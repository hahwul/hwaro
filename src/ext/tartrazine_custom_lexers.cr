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
# (Initialize phase). It swaps in a fresh lookup Hash instead of mutating
# the one parallel render fibers read, and edits the template cache under
# its own mutex.
#
# Remove when: upstream supports registering lexers at runtime.

require "tartrazine"

module Tartrazine
  HWARO_CUSTOM_KEY_PREFIX = "hwaro-custom/"

  # Lowercased name/alias → template-cache key. Replaced, never mutated.
  @@hwaro_custom_lexers = {} of String => String

  # Parse one grammar file's XML. Returns the lowercased names it registers
  # under (`<name>` first, then each `<alias>`) and its template. Raises
  # with a readable message on malformed XML, a missing `<name>` or `root`
  # state, an unknown action, or a regex PCRE2 refuses to compile.
  def self.hwaro_parse_custom_lexer(xml : String) : {Array(String), LexerTemplate}
    doc = XML.parse(xml)
    if error = doc.errors.try(&.first?)
      raise Exception.new("invalid XML (line #{error.line_number}): #{error.message.try(&.strip)}")
    end
    root = doc.first_element_child
    raise Exception.new("no <lexer> root element") unless root && root.name == "lexer"
    config = root.children.find { |node| node.name == "config" }
    names = [] of String
    if config
      primary = xml_to_s(config, name).try(&.strip)
      names << primary.downcase if primary && !primary.empty?
      xml_to_a(config, _alias).each do |value|
        value = value.strip.downcase
        names << value unless value.empty?
      end
    end
    raise Exception.new("missing <config><name>") if names.empty?

    template = parse_xml_to_template(xml)
    raise Exception.new(%(missing <state name="root">)) unless template.states.has_key?("root")
    {names.uniq, template}
  end

  # Replace every previously registered custom lexer with `entries`
  # (names, template). Earlier entries win a name both claim; the caller
  # orders and reports those.
  def self.hwaro_register_custom_lexers(entries : Array({Array(String), LexerTemplate})) : Nil
    lookup = {} of String => String
    @@template_mutex.synchronize do
      @@hwaro_custom_lexers.each_value { |key| @@lexer_templates.delete(key) }
      entries.each_with_index do |(names, template), index|
        key = "#{HWARO_CUSTOM_KEY_PREFIX}#{index}"
        @@lexer_templates[key] = template
        names.each { |name| lookup[name] = key unless lookup.has_key?(name) }
      end
    end
    @@hwaro_custom_lexers = lookup
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
