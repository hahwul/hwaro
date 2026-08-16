# Frontmatter Writer
#
# Shared serialization helpers for tools that WRITE frontmatter back to disk
# (`tool convert`, `tool export`, importers). Centralised here so the TOML
# emission rules — key quoting, string escaping, date formatting — stay
# identical across every tool that produces content files.

require "yaml"
require "json"
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
      def self.toml_to_yaml_any(value : TOML::Any, depth : Int32 = 0) : YAML::Any
        Nesting.check!(depth)
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
              toml_to_yaml_any(item, depth + 1)
            else
              YAML::Any.new(item.to_s)
            end
          }
          YAML::Any.new(arr)
        when Hash
          if raw.is_a?(Hash(String, TOML::Any))
            hash = {} of YAML::Any => YAML::Any
            raw.each do |k, v|
              hash[YAML::Any.new(k)] = toml_to_yaml_any(v, depth + 1)
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
        return str if bare_safe

        # Not `String#inspect`: Crystal escapes unprintable codepoints with the
        # brace form (`\u{E0001}`), which YAML rejects — it only accepts the
        # fixed-width `\xXX` / `\uXXXX` / `\UXXXXXXXX` forms.
        String.build do |io|
          io << '"'
          str.each_char do |ch|
            case ch
            when '"'  then io << "\\\""
            when '\\' then io << "\\\\"
            when '\n' then io << "\\n"
            when '\t' then io << "\\t"
            when '\r' then io << "\\r"
            else
              if ch.printable?
                io << ch
              elsif ch.ord <= 0xFF
                io << "\\x" << ch.ord.to_s(16, upcase: true).rjust(2, '0')
              elsif ch.ord <= 0xFFFF
                io << "\\u" << ch.ord.to_s(16, upcase: true).rjust(4, '0')
              else
                io << "\\U" << ch.ord.to_s(16, upcase: true).rjust(8, '0')
              end
            end
          end
          io << '"'
        end
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
          process_table(yaml, [] of String, true, 0)
          @output.to_s
        end

        # Convenience for callers holding a string-keyed field map (exporters).
        def build(fields : Hash(String, YAML::Any)) : String
          wrapped = {} of YAML::Any => YAML::Any
          fields.each { |k, v| wrapped[YAML::Any.new(k)] = v }
          build(YAML::Any.new(wrapped))
        end

        # `depth` guards a cyclic YAML::Any (self-referencing anchor); see
        # `Utils::Nesting`. Callers already rescue conversion failures.
        private def process_table(yaml : YAML::Any, path : Array(String), print_header : Bool, depth : Int32 = 0)
          Nesting.check!(depth)
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
            @output << format_key(k) << " = " << to_toml_value(v, depth + 1) << "\n"
          end

          tables.each do |k, v|
            process_table(v, path + [k], true, depth + 1)
          end

          array_tables.each do |k, v|
            v.as_a.each do |item|
              new_path = path + [k]
              @output << "\n" unless @output.empty?
              @output << "[[" << format_path(new_path) << "]]\n"
              process_table(item, new_path, false, depth + 1)
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
          case raw = value.raw
          when Bool then :bool
          when Int32, Int64
            # Int64::MIN is the one integer `to_toml_value` cannot spell as a
            # TOML integer the reader accepts, so it serializes as a quoted
            # string (see `toml_int_literal`) and belongs to the STRING family
            # here. Calling it an :int would emit `["-9223372036854775808", 1]`
            # for an all-integer array — precisely the mixed array toml.cr
            # refuses, reintroducing the unreadable file this guard prevents.
            raw == Int64::MIN ? :string : :int
          when Float32, Float64 then :float
          when Time             then :time
          when Array            then :array
          when Hash             then :table
          else                       :string
          end
        end

        # Decimal literal for an integer, in a spelling this codebase's TOML
        # reader can read back.
        #
        # TOML's integer range is exactly Int64's, but toml.cr accumulates the
        # digits POSITIVELY and only applies the sign afterwards
        # (`num = num * 10 + digit`, lib/toml/src/toml/lexer.cr:374), so the
        # one in-range value it cannot reparse is Int64::MIN — reading back
        # `-9223372036854775808` raises OverflowError. Emitting it verbatim
        # turned a document hwaro had just parsed into one it can no longer
        # parse: `tool convert to-toml` rewrote the file in place, reported
        # success, and the next build died on its own output. (Before the front
        # matter extractors were hardened the failure was silent and worse —
        # the whole block was discarded, so a `draft = true` page shipped.)
        # Keep the exact digits as a quoted string instead: lossy in type, but
        # the document stays loadable, the same trade `array_items` already
        # makes for structured members of a mixed array.
        private def toml_int_literal(int : Int) : String
          return "\"#{int}\"" if int == Int64::MIN
          int.to_s
        end

        # `N.0` form of an integer being promoted into a float array (see
        # `array_items`), likewise in a spelling toml.cr can read back: its
        # float reader keeps accumulating into the same Int64 integer part,
        # one `integer *= 10` per fractional digit
        # (lib/toml/src/toml/lexer.cr:427), so `[9223372036854775807, 1.5]`
        # was emitted as `9223372036854775807.0` and overflowed on the way in.
        # Past a tenth of Int64::MAX — the point where appending `.0` no
        # longer survives that multiplication — emit the shortest round-trip
        # float instead (`9.223372036854776e+18`), which the reader takes
        # through its exponent path. Everything below keeps the `N.0` spelling
        # it has always had.
        private def toml_promoted_float_literal(int : Int) : String
          limit = Int64::MAX // 10
          return "#{int}.0" if int >= -limit && int <= limit
          int.to_f64.to_s
        end

        private def to_toml_value(value : YAML::Any, depth : Int32 = 0) : String
          Nesting.check!(depth)
          raw = value.raw

          case raw
          when Bool
            raw.to_s
          when Int32, Int64
            toml_int_literal(raw)
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
            "[#{array_items(value, depth).join(", ")}]"
          when Hash
            # A hash reached from inside an array (mixed or nested) can't be
            # a `[table]` section; emit it as an inline table.
            pairs = value.as_h.map do |k, v|
              "#{format_key(k.as_s? || k.to_s)} = #{to_toml_value(v, depth + 1)}"
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
        private def array_items(value : YAML::Any, depth : Int32 = 0) : Array(String)
          items = value.as_a
          kinds = items.map { |v| toml_kind(v) }.uniq!

          if kinds.size <= 1
            items.map { |v| to_toml_value(v, depth + 1) }
          elsif kinds.sort == [:float, :int]
            items.map do |v|
              raw = v.raw
              raw.is_a?(Int) ? toml_promoted_float_literal(raw) : to_toml_value(v, depth + 1)
            end
          else
            items.map do |v|
              case toml_kind(v)
              when :string
                to_toml_value(v, depth + 1)
              when :array, :table
                # A structured member inside an otherwise-scalar array cannot
                # keep its TOML shape: `["plain", {k = "v"}]` is precisely the
                # mixed array toml.cr refuses, so `tool convert to-toml` wrote
                # a file the very next `hwaro build` failed to parse. Emit it
                # as JSON text — lossy for the reader, but the document stays
                # loadable instead of corrupting the round-trip.
                # `to_json` recurses the raw graph with no depth of its own,
                # so a cyclic value would blow the stack here even though
                # every other path is guarded. Bound it first.
                Nesting.validate!(v, depth + 1)
                "\"#{FrontmatterWriter.escape_toml_string(v.to_json)}\""
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
