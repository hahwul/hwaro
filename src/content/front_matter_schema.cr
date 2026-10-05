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
      # an unknown top-level key under.
      def check(rule : Models::ContentSchemaConfig, file : String, source : String,
                extra : Hash(String, Models::ExtraValue), cascade : Hash(String, Models::ExtraValue),
                locate : Bool = true) : Result
        source = Utils::TextUtils.strip_bom(source)
        top, own_extra = own_front_matter(source)
        cascade_extra = cascade["extra"]?.as?(Hash(String, Models::ExtraValue)) || {} of String => Models::ExtraValue
        line_for = ->(key : String) { locate ? line_of(source, key) : nil }

        violations = [] of Violation
        defaults = {} of String => Models::SchemaValue
        rule.fields.each do |field|
          value = if (key = field.extra_key) || !KNOWN_KEYS.includes?(field.name)
                    key ||= field.name
                    own_extra[key]? || extra[key]? || cascade_extra[key]?
                  else
                    # `build_cascade_map` already dropped non-cascadable keys.
                    top[field.name]? || cascade[field.name]? || taxonomy_terms(top, field.name)
                  end
          if value.nil?
            if default = field.default
              defaults[field.name] = default
            elsif field.required
              violations << Violation.new(file, nil, field.name, "required but missing")
            end
          elsif problem = field.problem(value)
            violations << Violation.new(file, line_for.call(field.extra_key || field.name), field.name, problem)
          end
        end

        if rule.strict
          declared = rule.fields.map { |f| f.extra_key || f.name }
          candidates = KNOWN_KEYS.to_a + declared
          top.each_key do |key|
            next if key == "extra" || KNOWN_KEYS.includes?(key) || declared.includes?(key)
            hint = Processor::Markdown.typo_suggestion(key, candidates)
            message = hint ? "unknown front-matter key — did you mean \"#{hint}\"?" : "unknown front-matter key (declare it in the schema or move it under [extra])"
            violations << Violation.new(file, line_for.call(key), key, message)
          end
        end

        Result.new(violations, defaults)
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

      # `tags`/`authors` may also be given as a `[taxonomies]` entry.
      private def taxonomy_terms(top : Hash(String, Models::SchemaValue), name : String) : Models::SchemaValue?
        return unless name.in?("tags", "authors")
        top["taxonomies"]?.as?(Hash(String, Models::ExtraValue)).try(&.[name]?)
      end

      private def value_of(any : TOML::Any | YAML::Any | JSON::Any) : Models::SchemaValue
        raw = any.raw
        raw.is_a?(Time) ? raw : Processor::Markdown.extra_value(any)
      end

      # 1-based line of `key` (as `key =`, `key:` or `"key":`) inside the
      # front-matter block; nil when it is not written there.
      private def line_of(source : String, key : String) : Int32?
        return unless fm = Utils::FrontmatterScanner.detect(source)
        block = fm[1]
        first = source[0, source.index(block) || 0].count('\n') + 1
        pattern = /^\s*["']?#{Regex.escape(key)}["']?\s*[=:]/
        block.each_line.with_index do |line, i|
          return first + i if line.matches?(pattern)
        end
        nil
      end
    end
  end
end
