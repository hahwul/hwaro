# `[[content.schema]]` front-matter validation, shared by the build
# (Phases::ParseContent) and the tools (`hwaro doctor`, `tool validate`), so
# all three report the same violations for the same page.

require "json"
require "toml"
require "yaml"
require "../models/config"
require "../utils/errors"
require "../utils/frontmatter_scanner"
require "../utils/text_utils"
require "./processors/markdown"

module Hwaro
  module Content
    module FrontMatterSchema
      extend self

      KNOWN_KEYS = Processors::Markdown::KNOWN_FRONT_MATTER_KEYS

      TOML_MULTILINE_DELIMITERS = {"\"" * 3, "'" * 3}

      # One problem with one field of one page. `line` is the key's line in
      # the file when it is there to point at (nil for a missing field, or a
      # `[[content.generate]]` page, which has no file).
      record Violation, file : String, line : Int32?, field : String, message : String do
        def to_s(io : IO) : Nil
          io << file
          io << ':' << line if line
          io << ": field " << field.inspect << ": " << message
        end
      end

      # The page's violations, and the defaults its missing fields take.
      record Result, violations : Array(Violation), defaults : Hash(String, Models::SchemaValue)

      # The first schema (config order) whose `sections` match, like
      # `[permalinks]`; nil when the page is not validated.
      def rule_for(config : Models::Config, section : String) : Models::ContentSchemaConfig?
        config.content_schema.find(&.matches?(section))
      end

      # Check one regular page. `source` is the page's whole source text
      # (front matter + body); `extra` the page's `extra` (with or without
      # cascaded keys — `cascade`, the merged ancestor cascade, fills in
      # whatever it lacks). A field name without the `extra.` prefix names a
      # known front-matter field, or else the `extra` key the parser stores
      # an unknown top-level key under. `taxonomies` are the configured
      # taxonomy names, which `strict` accepts as top-level keys.
      #
      # Lookups test presence (`fetch`), never truthiness: an explicit
      # `false` is a value, so it meets `required` and keeps its default out.
      def check(rule : Models::ContentSchemaConfig, file : String, source : String,
                extra : Hash(String, Models::ExtraValue), cascade : Hash(String, Models::ExtraValue),
                locate : Bool = true, taxonomies : Array(String) = [] of String) : Result
        source = Utils::TextUtils.strip_bom(source)
        top, own_extra = own_front_matter(source)
        cascade_extra = cascade["extra"]?.as?(Hash(String, Models::ExtraValue)) || {} of String => Models::ExtraValue
        line_for = ->(key : String, extra_first : Bool?) { locate ? line_of(source, key, extra_first) : nil }

        violations = [] of Violation
        defaults = {} of String => Models::SchemaValue
        rule.fields.each do |field|
          known = field.extra_key.nil? && KNOWN_KEYS.includes?(field.name)
          value = if known
                    # `build_cascade_map` already dropped non-cascadable keys.
                    top.fetch(field.name) { cascade.fetch(field.name) { taxonomy_terms(top, cascade, field.name) } }
                  else
                    key = field.extra_key || field.name
                    own_extra.fetch(key) { extra.fetch(key) { cascade_extra.fetch(key) { field.extra_key ? nil : taxonomy_terms(top, cascade, key) } } }
                  end
          if value.nil?
            # `nil`, not truthiness: a `false` default is a value too.
            if (default = field.default).nil?
              violations << Violation.new(file, nil, field.name, "required but missing") if field.required
            else
              defaults[field.name] = default
            end
          elsif problem = field.problem(value)
            # extra.<key> looks in [extra] first; a bare unknown name at the
            # top level first; a known field only at the top level.
            extra_first = known ? nil : !field.extra_key.nil?
            violations << Violation.new(file, line_for.call(field.extra_key || field.name, extra_first), field.name, problem)
          end
        end

        if rule.strict
          declared = rule.fields.map { |f| f.extra_key || f.name }
          candidates = KNOWN_KEYS.to_a + declared + taxonomies
          top.each_key do |key|
            next if key == "extra" || KNOWN_KEYS.includes?(key) || declared.includes?(key) || taxonomies.includes?(key)
            hint = Processor::Markdown.typo_suggestion(key, candidates)
            message = hint ? "unknown front-matter key — did you mean \"#{hint}\"?" : "unknown front-matter key (declare it in the schema or move it under [extra])"
            violations << Violation.new(file, line_for.call(key, nil), key, message)
          end
        end

        Result.new(violations, defaults)
      end

      # Every taxonomy name the site configures, any language.
      def taxonomy_names(config : Models::Config) : Array(String)
        names = config.taxonomies.map(&.name)
        config.languages.each_value { |lang| names.concat(lang.taxonomies) }
        names.uniq
      end

      # Fail the build (HWARO_E_CONTENT) with every violation, sorted by file.
      def raise_if_any!(violations : Array(Violation)) : Nil
        return if violations.empty?
        lines = violations.sort_by { |v| {v.file, v.line || 0, v.field} }.map(&.to_s)
        label = lines.size == 1 ? "1 front-matter schema violation" : "#{lines.size} front-matter schema violations"
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONTENT,
          message: "#{label}:\n  #{lines.join("\n  ")}",
          hint: "Fix the front matter above, or adjust [[content.schema]] in config.toml.",
        )
      end

      # The file's own front matter as {top-level keys, extra keys} — extra
      # keys are the `[extra]` table's plus unknown top-level keys, in
      # document order (later wins), the way the parser fills `page.extra`.
      # Native datetimes stay `Time` (page.extra stringifies them). Empty on
      # no or unparseable front matter: the parser reports that itself.
      private def own_front_matter(source : String) : {Hash(String, Models::SchemaValue), Hash(String, Models::SchemaValue)}
        top = {} of String => Models::SchemaValue
        own_extra = {} of String => Models::SchemaValue
        return {top, own_extra} unless fm = Utils::FrontmatterScanner.detect(source)

        dialect, block = fm
        root = case dialect
               when :toml then TOML::Any.new(TOML.parse(block))
               when :yaml then YAML.parse(block)
               else            JSON.parse(block)
               end
        root.as_h?.try do |h|
          h.each do |k, v|
            key = k.is_a?(String) ? k : k.as_s?
            next if key.nil? || v.raw.nil?
            if key == "extra" && (inner = v.as_h?)
              inner.each do |ik, iv|
                inner_key = ik.is_a?(String) ? ik : (ik.as_s? || ik.to_s)
                own_extra[inner_key] = value_of(iv) unless iv.raw.nil?
              end
              next
            end
            top[key] = value_of(v)
            own_extra[key] = top[key] unless KNOWN_KEYS.includes?(key)
          end
        end
        {top, own_extra}
      rescue
        {({} of String => Models::SchemaValue), ({} of String => Models::SchemaValue)}
      end

      # A taxonomy's terms may also be given as a `[taxonomies]` entry (the
      # parser accepts any taxonomy name there), the page's own or a cascaded
      # `[cascade.taxonomies]` one.
      private def taxonomy_terms(top : Hash(String, Models::SchemaValue), cascade : Hash(String, Models::ExtraValue), name : String) : Models::SchemaValue?
        own = top["taxonomies"]?.as?(Hash(String, Models::ExtraValue))
        cascaded = cascade["taxonomies"]?.as?(Hash(String, Models::ExtraValue))
        own.try(&.[name]?) || cascaded.try(&.[name]?)
      end

      private def value_of(any : TOML::Any | YAML::Any | JSON::Any) : Models::SchemaValue
        raw = any.raw
        raw.is_a?(Time) ? raw : Processor::Markdown.extra_value(any)
      end

      # 1-based line of `key` in the front matter: written at the top level,
      # or inside the `extra` table. `extra_first` picks which wins (nil:
      # top level only). Bare, quoted and escaped (`"q\"k"`) spellings are
      # recognised; nil when the key is not on a line of its own (an inline
      # table, a dotted key).
      private def line_of(source : String, key : String, extra_first : Bool?) : Int32?
        return unless fm = Utils::FrontmatterScanner.detect(source)
        dialect, block = fm
        first = source[0, source.index(block) || 0].count('\n') + 1
        quoted = Regex.escape(key)
        key_re = /\A(?:#{quoted}|"#{quoted}"|'#{quoted}'|#{Regex.escape(key.to_json)})\s*[=:]/
        top_line = extra_line = nil
        scope = ""         # "" top level, "extra", or another table
        top_indent = nil   # YAML/JSON: the top-level keys' indentation
        extra_indent = nil # YAML/JSON: the `extra` table's keys' indentation
        ml_delim = nil     # TOML: the open multi-line string's delimiter
        block.each_line.with_index do |line, i|
          if delim = ml_delim
            ml_delim = nil if line.includes?(delim)
            next
          end
          stripped = line.lstrip
          next if stripped.empty? || stripped.starts_with?('#')
          if dialect == :toml
            # A multi-line string opened (and not closed) on this line hides
            # the lines up to its closing delimiter.
            ml_delim = TOML_MULTILINE_DELIMITERS.find { |d| line.split(d).size.even? }
            # A `[table]` header switches scope until the next one.
            if stripped.starts_with?('[')
              scope = stripped.starts_with?("[[") ? "[[" : stripped.lchop('[').split(']', 2).first.strip.strip('"')
              next
            end
          else
            indent = line.size - stripped.size
            next if stripped.starts_with?('{') # JSON's opening brace
            top_indent ||= indent
            if indent <= top_indent
              scope = ""
              extra_indent = nil
            elsif scope == "open-extra"
              scope = "extra"
              extra_indent = indent
            else
              # Only the extra table's own keys are "extra"; deeper is not.
              scope = indent == extra_indent ? "extra" : "nested"
            end
          end
          if key_re.matches?(stripped)
            top_line ||= first + i if scope.empty?
            extra_line ||= first + i if scope == "extra"
          end
          scope = "open-extra" if dialect != :toml && scope.empty? && stripped.matches?(/\A["']?extra["']?\s*:/)
        end
        case extra_first
        when nil  then top_line
        when true then extra_line || top_line
        else           top_line || extra_line
        end
      end
    end
  end
end
