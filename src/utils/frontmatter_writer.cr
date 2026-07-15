# Frontmatter Writer
#
# Shared serialization helpers for tools that WRITE frontmatter back to disk
# (`tool convert`, `tool export`, importers). Centralised here so the TOML
# emission rules — key quoting, string escaping, date formatting — stay
# identical across every tool that produces content files.

require "yaml"
require "toml"
require "time"

module Hwaro
  module Utils
    module FrontmatterWriter
      # Serialize a frontmatter date/time value without corrupting the
      # calendar day or the author's zone.
      #
      # Frontmatter dates are commonly written as TOML/YAML *local dates* such
      # as `2026-05-20`, which parse to midnight in the local time zone.
      # Rendering those through `to_rfc3339` (always UTC) rolls the day back
      # in any positive-offset zone — e.g. in KST `2026-05-20` becomes
      # `2026-05-19T15:00:00Z`. When the value carries no time-of-day we emit
      # a bare `YYYY-MM-DD`; genuine timestamps keep their own offset
      # (`to_rfc3339` would silently convert `08:00+09:00` to the previous
      # day's `23:00Z`).
      def self.serialize_time(time : Time) : String
        if time.hour == 0 && time.minute == 0 && time.second == 0 && time.nanosecond == 0
          time.to_s("%Y-%m-%d")
        elsif time.offset == 0
          time.to_rfc3339
        else
          time.to_s("%Y-%m-%dT%H:%M:%S%:z")
        end
      end

      # Escape a string for a double-quoted TOML basic string. Unlike Crystal's
      # `String#inspect`, this never emits TOML-invalid escapes (`\a`, `\e`,
      # `\v`) and leaves non-ASCII text raw — toml.cr's `\uXXXX` reader greedily
      # consumes a following hex digit, so escaping U+200B in "Auto​build" would
      # produce an unparseable file.
      def self.escape_toml_string(str : String) : String
        str
          .gsub("\\", "\\\\")
          .gsub("\"", "\\\"")
          .gsub("\n", "\\n")
          .gsub("\t", "\\t")
          .gsub("\r", "\\r")
          .gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/) { |s| "\\u%04X" % s[0].ord }
      end

      # Convert a parsed TOML value into the YAML::Any tree the emitters
      # consume. Time leaves become frontmatter date strings (see
      # `serialize_time`).
      def self.toml_to_yaml_any(value : TOML::Any) : YAML::Any
        raw = value.raw

        case raw
        when String
          YAML::Any.new(raw)
        when Int64
          YAML::Any.new(raw)
        when Float64
          YAML::Any.new(raw)
        when Bool
          YAML::Any.new(raw)
        when Time
          YAML::Any.new(serialize_time(raw))
        when Array
          arr = raw.map { |item|
            if item.is_a?(TOML::Any)
              toml_to_yaml_any(item)
            else
              YAML::Any.new(item.to_s)
            end
          }
          YAML::Any.new(arr)
        when Hash
          if raw.is_a?(Hash(String, TOML::Any))
            hash = {} of YAML::Any => YAML::Any
            raw.each do |k, v|
              hash[YAML::Any.new(k)] = toml_to_yaml_any(v)
            end
            YAML::Any.new(hash)
          else
            YAML::Any.new(raw.to_s)
          end
        else
          YAML::Any.new(raw.to_s)
        end
      end

      # YAML 1.1 words that reparse as booleans/null when left bare (Jekyll
      # runs on Psych). `y`/`n` included defensively.
      YAML_RESERVED_WORDS = %w[true false yes no on off null none y n ~]

      # Render a string as a YAML flow scalar, leaving simple values bare and
      # double-quoting anything YAML would reinterpret — `beta: gamma` parses
      # as a mapping, `NO` as false, `2024-01-15` as a date, `*x` as an alias.
      def self.yaml_scalar(str : String) : String
        bare_safe = str.matches?(/\A[A-Za-z_](?:[A-Za-z0-9 _.\/-]*[A-Za-z0-9_.\/-])?\z/) &&
                    !YAML_RESERVED_WORDS.includes?(str.downcase)
        bare_safe ? str : str.inspect
      end

      # Quote a frontmatter key that isn't a bare TOML key (spaces, dots,
      # non-ASCII — all valid in YAML/JSON source).
      def self.format_toml_key(key : String) : String
        if key =~ /^[A-Za-z0-9_-]+$/
          key
        else
          "\"#{escape_toml_string(key)}\""
        end
      end

      # Emits a TOML document body (no `+++` fences) from a parsed frontmatter
      # tree: scalars first, then `[table]` sections, then `[[array-of-table]]`
      # sections, preserving source key order within each group.
      class TomlBuilder
        def initialize
          @output = String::Builder.new
        end

        def build(yaml : YAML::Any) : String
          return "" unless yaml.as_h?
          process_table(yaml, [] of String, true)
          @output.to_s
        end

        # Convenience for callers holding a string-keyed field map (exporters).
        def build(fields : Hash(String, YAML::Any)) : String
          wrapped = {} of YAML::Any => YAML::Any
          fields.each { |k, v| wrapped[YAML::Any.new(k)] = v }
          build(YAML::Any.new(wrapped))
        end

        private def process_table(yaml : YAML::Any, path : Array(String), print_header : Bool)
          return unless hash = yaml.as_h?

          # An empty table (`extra: {}`) has no values to force a header out,
          # but dropping the key entirely would silently lose it.
          if hash.empty?
            if print_header && !path.empty?
              @output << "\n" unless @output.empty?
              @output << "[" << format_path(path) << "]\n"
            end
            return
          end

          simple_values = {} of String => YAML::Any
          tables = {} of String => YAML::Any
          array_tables = {} of String => YAML::Any

          hash.each do |key, value|
            key_str = key.as_s? || key.to_s

            if value.as_h?
              tables[key_str] = value
            elsif array_of_tables?(value)
              array_tables[key_str] = value
            else
              simple_values[key_str] = value
            end
          end

          if !simple_values.empty? && print_header && !path.empty?
            @output << "\n" unless @output.empty?
            @output << "[" << format_path(path) << "]\n"
          end

          simple_values.each do |k, v|
            @output << format_key(k) << " = " << to_toml_value(v) << "\n"
          end

          tables.each do |k, v|
            process_table(v, path + [k], true)
          end

          array_tables.each do |k, v|
            v.as_a.each do |item|
              new_path = path + [k]
              @output << "\n" unless @output.empty?
              @output << "[[" << format_path(new_path) << "]]\n"
              process_table(item, new_path, false)
            end
          end
        end

        private def array_of_tables?(value : YAML::Any) : Bool
          return false unless value.as_a?
          return false if value.as_a.empty?
          value.as_a.all?(&.as_h?)
        end

        private def format_path(path : Array(String)) : String
          path.map { |k| format_key(k) }.join(".")
        end

        private def format_key(key : String) : String
          FrontmatterWriter.format_toml_key(key)
        end

        # The TOML type family a value serializes to; toml.cr rejects arrays
        # that mix families, so array emission needs to know them.
        private def toml_kind(value : YAML::Any) : Symbol
          case value.raw
          when Bool             then :bool
          when Int32, Int64     then :int
          when Float32, Float64 then :float
          when Time             then :time
          when Array            then :array
          when Hash             then :table
          else                       :string
          end
        end

        private def to_toml_value(value : YAML::Any) : String
          raw = value.raw

          case raw
          when Bool
            raw.to_s
          when Int32, Int64
            raw.to_s
          when Float32, Float64
            # TOML spells non-finite floats `inf`/`nan`; Crystal's `to_s`
            # ("Infinity"/"NaN") doesn't reparse.
            if raw.nan?
              "nan"
            elsif raw.infinite?
              raw > 0 ? "inf" : "-inf"
            else
              raw.to_s
            end
          when Time
            FrontmatterWriter.serialize_time(raw)
          when Array
            "[#{array_items(value).join(", ")}]"
          when Hash
            # A hash reached from inside an array (mixed or nested) can't be
            # a `[table]` section; emit it as an inline table.
            pairs = value.as_h.map do |k, v|
              "#{format_key(k.as_s? || k.to_s)} = #{to_toml_value(v)}"
            end
            "{#{pairs.join(", ")}}"
          when String
            "\"#{FrontmatterWriter.escape_toml_string(raw)}\""
          when Nil
            "\"\""
          else
            "\"#{FrontmatterWriter.escape_toml_string(value.to_s)}\""
          end
        end

        # Serialize array elements, keeping the array homogeneous where
        # possible: toml.cr refuses `[1, "two"]`, so an int/float mix is
        # promoted to floats and any other scalar mix is coerced to strings
        # (structured members keep their shape).
        private def array_items(value : YAML::Any) : Array(String)
          items = value.as_a
          kinds = items.map { |v| toml_kind(v) }.uniq!

          if kinds.size <= 1
            items.map { |v| to_toml_value(v) }
          elsif kinds.sort == [:float, :int]
            items.map do |v|
              raw = v.raw
              raw.is_a?(Int) ? "#{raw}.0" : to_toml_value(v)
            end
          else
            items.map do |v|
              case toml_kind(v)
              when :array, :table, :string
                to_toml_value(v)
              when :time
                "\"#{FrontmatterWriter.escape_toml_string(FrontmatterWriter.serialize_time(v.raw.as(Time)))}\""
              else
                "\"#{FrontmatterWriter.escape_toml_string(v.raw.to_s)}\""
              end
            end
          end
        end
      end
    end
  end
end
