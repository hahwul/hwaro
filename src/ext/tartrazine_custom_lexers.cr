# Extension to Tartrazine's lexer lookup: user grammars from `[highlight]
# lexers_dir` (Chroma/Pygments XML, the format the bundled lexers use).
# Kept here so we don't fork the vendored library, like
# ext/tartrazine_mt_fix.cr.
#
# Upstream only knows the lexers baked into the binary (LexerFiles +
# LEXERS_BY_NAME). A parsed user grammar is stored in the same template
# cache under a key no bundled file can have (bundled keys never contain a
# `/`), so `create_from_template` — and with it the per-instance states
# copy from tartrazine_mt_fix.cr — serves custom and bundled lexers alike.
#
# Lookup precedence: a custom name or alias wins over a bundled one, so a
# site can replace a broken bundled grammar. This file is required after
# tartrazine_lexer_alias_fix.cr, so this `lexer_by_name` runs first and
# `cr`/`yml` can be taken over too.
#
# Thread-safety: registration happens once per build, before rendering
# (Initialize phase). It swaps in fresh lookup tables instead of mutating
# the ones parallel render fibers read, and edits the template cache under
# its own mutex.
#
# Remove when: upstream supports registering lexers at runtime.

require "tartrazine"

module Tartrazine
  HWARO_CUSTOM_KEY_PREFIX = "hwaro-custom/"

  # Lowercased name/alias → template-cache key. Replaced, never mutated.
  @@hwaro_custom_lexers = {} of String => String
  # Lowercased `<filename>` glob → lookup name, in registration order
  # (include_code's language detection). Replaced, never mutated.
  @@hwaro_custom_filenames = [] of {String, String}

  # Elements whose `state` attribute names a state of the same lexer.
  HWARO_STATE_REFS = {"push", "include", "combined"}

  # Parse one grammar file's XML. Returns the lowercased names it registers
  # under (`<name>` first, then each `<alias>`), its lowercased
  # `<filename>` globs, and its template. Raises with a readable message on
  # malformed XML, a missing `<name>` or `root` state, a `<push>`,
  # `<include>` or `<combined>` naming a state the grammar does not define
  # (stock Tartrazine only fails on those mid-tokenization), an unknown
  # action, or a regex PCRE2 refuses to compile.
  def self.hwaro_parse_custom_lexer(xml : String) : {Array(String), Array(String), LexerTemplate}
    doc = XML.parse(xml)
    # Chroma writes several states as repeated attributes
    # (`<push state="a" state="b"/>`): libxml2 reports each repeat but keeps
    # it in recovery mode, and Tartrazine reads them all. Every bundled
    # grammar that has any error has only that one.
    if error = doc.errors.try(&.find { |err| !err.message.to_s.matches?(/\AAttribute \S+ redefined/) })
      raise Exception.new("invalid XML (line #{error.line_number}): #{error.message.try(&.strip)}")
    end
    root = doc.first_element_child
    raise Exception.new("no <lexer> root element") unless root && root.name == "lexer"
    config = root.children.find { |node| node.name == "config" }
    names = [] of String
    filenames = [] of String
    if config
      primary = xml_to_s(config, name).try(&.strip)
      names << primary.downcase if primary && !primary.empty?
      xml_to_a(config, _alias).each do |value|
        value = value.strip.downcase
        names << value unless value.empty?
      end
      xml_to_a(config, filename).each do |value|
        value = value.strip.downcase
        filenames << value unless value.empty?
      end
    end
    raise Exception.new("missing <config><name>") if names.empty?

    template = parse_xml_to_template(xml)
    raise Exception.new(%(missing <state name="root">)) unless template.states.has_key?("root")
    root.xpath_nodes(".//*").each do |node|
      next unless HWARO_STATE_REFS.includes?(node.name)
      node.attributes.each do |attr|
        next unless attr.name == "state"
        state = attr.content
        next if state.starts_with?('#') || template.states.has_key?(state)
        raise Exception.new(%(<#{node.name}> names undefined state "#{state}"))
      end
    end
    {names.uniq, filenames.uniq, template}
  end

  # Replace every previously registered custom lexer with `entries`
  # (names, filename globs, template). Earlier entries win a name both
  # claim; the caller orders and reports those.
  def self.hwaro_register_custom_lexers(entries : Array({Array(String), Array(String), LexerTemplate})) : Nil
    lookup = {} of String => String
    by_filename = [] of {String, String}
    @@template_mutex.synchronize do
      @@hwaro_custom_lexers.each_value { |key| @@lexer_templates.delete(key) }
      entries.each_with_index do |(names, filenames, template), index|
        key = "#{HWARO_CUSTOM_KEY_PREFIX}#{index}"
        @@lexer_templates[key] = template
        names.each { |name| lookup[name] = key unless lookup.has_key?(name) }
        # A fence info string ends at whitespace, so a file maps to the
        # grammar's first space-free name.
        if fence_name = names.find { |name| !name.each_char.any?(&.whitespace?) }
          filenames.each { |glob| by_filename << {glob, fence_name} }
        end
      end
    end
    @@hwaro_custom_lexers = lookup
    @@hwaro_custom_filenames = by_filename
  end

  # The custom lexer for a lowercased file base name (an exact
  # `<filename>` entry or a glob), or nil.
  def self.hwaro_custom_language_for(basename : String) : String?
    @@hwaro_custom_filenames.each do |glob, name|
      return name if glob == basename || File.match?(glob, basename)
    end
    nil
  end

  def self.hwaro_custom_lexer?(name : String) : Bool
    @@hwaro_custom_lexers.has_key?(name.downcase)
  end

  private def self.lexer_by_name(name : String) : BaseLexer
    if key = @@hwaro_custom_lexers[name.downcase]?
      return create_from_template(key)
    end
    previous_def
  end
end
