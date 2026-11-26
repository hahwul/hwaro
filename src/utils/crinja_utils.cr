# Shared utility module for converting YAML, TOML, and JSON values to Crinja::Value
#
# This consolidates the duplicated conversion logic that previously existed
# in both Builder (src/core/build/builder.cr) and TemplateEngine
# (src/content/processors/template.cr).

require "csv"
require "yaml"
require "json"
require "toml"
require "crinja"
require "./frontmatter_writer"

module Hwaro
  module Utils
    module CrinjaUtils
      extend self

      # Pre-allocated nil value to avoid repeated allocations in hot paths
      NIL_VALUE = Crinja::Value.new(nil)

      # A string hwaro built as HTML, or text it already escaped, as a
      # template value: safe (printed as is) under `[templates] autoescape`,
      # a plain string — exactly what templates always got — without it.
      # Marked as rendered HTML, so `| e` still escapes it (see
      # ext/crinja_autoescape.cr).
      def html_value(html : String, autoescape : Bool) : Crinja::Value
        Crinja::Value.new(autoescape ? Crinja::SafeString.new(html, false, true) : html)
      end

      # A TEXT value that is usually already escaped for an HTML attribute or
      # text node (markd's escaper: `& < > "` but NOT `'`), but not always —
      # a raw-HTML heading's TOC title/id or an image alt holding inline HTML
      # carries raw `"`/`<`/`&`. Under autoescape it is marked safe, so first
      # normalise it to fully escaped text in one pass: a character reference
      # (`&amp;`, `&#39;`, `&copy;`, …) is kept as written, and every other
      # `& < > " '` is escaped. Already-escaped input keeps its bytes (and so
      # its meaning, in text and attribute alike); raw specials can no longer
      # leave a quoted attribute. Off the switch it stays the plain string it
      # was, byte-identical.
      def preescaped_value(text : String, autoescape : Bool) : Crinja::Value
        return Crinja::Value.new(text) unless autoescape
        Crinja::Value.new(Crinja::SafeString.new(escape_text(text)))
      end

      # `text` with every `& < > " '` escaped except a terminated character
      # reference's `&`, which is kept with the reference. The same String
      # when there is nothing to escape. A byte scan, not a regex `gsub`:
      # it runs on every hook value and TOC field.
      private def escape_text(text : String) : String
        bytes = text.to_slice
        first = bytes.index { |byte| Crinja::Markup::SPECIAL.unsafe_fetch(byte) }
        return text unless first
        String.build(text.bytesize + 16) do |io|
          io.write bytes[0, first]
          i = run = first
          while i < bytes.size
            byte = bytes[i]
            unless Crinja::Markup::SPECIAL.unsafe_fetch(byte)
              i += 1
              next
            end
            if byte === '&' && (ref = reference_length(bytes, i)) > 0
              i += ref
              next
            end
            io.write bytes[run, i - run]
            io << (case byte
            when '&' then "&amp;"
            when '<' then "&lt;"
            when '>' then "&gt;"
            when '"' then "&quot;"
            else          "&#39;"
            end)
            i += 1
            run = i
          end
          io.write bytes[run, bytes.size - run]
        end
      end

      # Byte length of the terminated reference (`&amp;`, `&#39;`, `&#x27;`,
      # `&copy;`) starting at the `&` at `at`, or 0 when there is none.
      private def reference_length(bytes : Bytes, at : Int32) : Int32
        i = at + 1
        if i < bytes.size && bytes[i] === '#'
          i += 1
          hex = i < bytes.size && (bytes[i] === 'x' || bytes[i] === 'X')
          i += 1 if hex
          start = i
          while i < bytes.size && (hex ? bytes[i].unsafe_chr.hex? : bytes[i].unsafe_chr.ascii_number?)
            i += 1
          end
        else
          start = i
          return 0 unless i < bytes.size && bytes[i].unsafe_chr.ascii_letter?
          while i < bytes.size && bytes[i].unsafe_chr.ascii_alphanumeric?
            i += 1
          end
        end
        i > start && i < bytes.size && bytes[i] === ';' ? i - at + 1 : 0
      end

      # Convert a YAML::Any value to Crinja::Value.
      #
      # `depth` guards against a self-referencing YAML anchor, whose parsed
      # graph is cyclic and would otherwise recurse until the stack dies
      # (see `Utils::Nesting`). Both call sites — `DataDisk.parse_file`
      # and the `load_data` template function — already rescue and degrade, so
      # the raise surfaces as "data file skipped" rather than a crash.
      def from_yaml(value : YAML::Any, depth : Int32 = 0) : Crinja::Value
        Nesting.check!(depth)
        if arr = value.as_a?
          Crinja::Value.new(arr.map { |v| from_yaml(v, depth + 1) })
        elsif h = value.as_h?
          converted = {} of String => Crinja::Value
          h.each do |k, v|
            # `key_string`, not `to_s`: an unquoted `2024-01-15:` key is a
            # timestamp to the YAML reader, and its `to_s` named the entry
            # "2024-01-15 00:00:00 +09:00" — a different key in every
            # machine zone, and never the "2024-01-15" the same data in TOML
            # or JSON is keyed by.
            converted[FrontmatterWriter.key_string(k)] = from_yaml(v, depth + 1)
          end
          Crinja::Value.new(converted)
        elsif s = value.as_s?
          Crinja::Value.new(s)
        elsif i = value.as_i64?
          Crinja::Value.new(i)
        elsif f = value.as_f?
          Crinja::Value.new(f)
        elsif !(b = value.as_bool?).nil?
          Crinja::Value.new(b)
        elsif (t = value.raw).is_a?(Time)
          # Crystal's YAML core-schema resolver turns an unquoted ISO date
          # (`released: 2021-01-02`) into a `Time` node, which matches none of
          # the accessors above — without this branch the value fell through to
          # NIL_VALUE and the template rendered `none` while the identical TOML
          # data file rendered the date. Mirrors `from_toml` below.
          Crinja::Value.new(t.to_s)
        else
          NIL_VALUE
        end
      end

      # Convert a Hash(String, TOML::Any) to Crinja::Value
      def from_toml(value : Hash(String, TOML::Any), depth : Int32 = 0) : Crinja::Value
        Nesting.check!(depth)
        converted = {} of String => Crinja::Value
        value.each do |k, v|
          converted[k] = from_toml(v, depth + 1)
        end
        Crinja::Value.new(converted)
      end

      # Convert a TOML::Any value to Crinja::Value
      def from_toml(value : TOML::Any, depth : Int32 = 0) : Crinja::Value
        Nesting.check!(depth)
        if arr = value.as_a?
          Crinja::Value.new(arr.map { |v| from_toml(v, depth + 1) })
        elsif h = value.as_h?
          converted = {} of String => Crinja::Value
          h.each do |k, v|
            converted[k] = from_toml(v, depth + 1)
          end
          Crinja::Value.new(converted)
        elsif s = value.as_s?
          Crinja::Value.new(s)
        elsif i = value.as_i64?
          # TOML integers are 64-bit. `as_i?` is a TYPE guard with no RANGE
          # guard (`@raw.as(Int).to_i`), so `downloads = 4200000000` raised
          # OverflowError out of a nil-safe accessor; the caller's blanket
          # rescue then dropped the WHOLE data file from site.data and blamed
          # a parse error that never happened. The Int32 hop was pure loss
          # anyway — the value was widened straight back to Int64.
          Crinja::Value.new(i)
        elsif f = value.as_f?
          Crinja::Value.new(f)
        elsif !(b = value.as_bool?).nil?
          Crinja::Value.new(b)
        elsif (t = value.raw).is_a?(Time)
          Crinja::Value.new(t.to_s)
        else
          NIL_VALUE
        end
      end

      # Convert an extra field value (from front matter) to Crinja::Value.
      # Recursive so nested `[extra.*]` hashes and arrays-of-hashes
      # traverse via `{{ page.extra.a.b }}` in templates.
      def from_extra(value : Hwaro::Models::ExtraValue, depth : Int32 = 0) : Crinja::Value
        Nesting.check!(depth)
        case value
        when Hash
          converted = {} of String => Crinja::Value
          value.each { |k, v| converted[k] = from_extra(v, depth + 1) }
          Crinja::Value.new(converted)
        when Array(String)
          Crinja::Value.new(value.map { |s| Crinja::Value.new(s) })
        when Array
          Crinja::Value.new(value.map { |v| from_extra(v, depth + 1) })
        else
          Crinja::Value.new(value)
        end
      end

      # Convert a JSON::Any value to Crinja::Value
      def from_json(value : JSON::Any, depth : Int32 = 0) : Crinja::Value
        Nesting.check!(depth)
        case value.raw
        when Hash
          hash = {} of String => Crinja::Value
          value.as_h.each { |k, v| hash[k] = from_json(v, depth + 1) }
          Crinja::Value.new(hash)
        when Array
          arr = value.as_a.map { |v| from_json(v, depth + 1) }
          Crinja::Value.new(arr)
        when String
          Crinja::Value.new(value.as_s)
        when Int64
          Crinja::Value.new(value.as_i64)
        when Float64
          Crinja::Value.new(value.as_f)
        when Bool
          Crinja::Value.new(value.as_bool)
        when Nil
          NIL_VALUE
        else
          Crinja::Value.new(value.to_s)
        end
      end

      # Parse a data payload into the `Crinja::Value` templates see, dispatching
      # on a bare format name ("json", "toml", "yaml"/"yml", "csv"). This is the
      # one place that mapping lives: `data/` files (DataDisk.parse_file),
      # the `load_data()` template function, and `[[data.remote]]` payloads
      # (RemoteData#parse_body) all route through it, so a key can move between
      # a disk file, a template call and a remote source and parse identically.
      # CSV matches the long-standing `load_data()` shape: an array of rows,
      # each an array of stripped string cells.
      #
      # Returns nil for an unrecognized format — every caller owns its own error
      # policy (warn and drop the key, debug-log and return none, or raise a
      # classified fetch error), and no two of them agree, so this helper
      # neither logs nor raises. Parse exceptions propagate to the caller for
      # the same reason.
      #
      # BOM stripping is the caller's call too: the `data/` and remote paths
      # strip it (JSON and TOML both reject a leading BOM outright), while
      # `load_data()` deliberately never has — see its call site.
      def parse_data_string(content : String, format : String) : Crinja::Value?
        # The JSON and CSV parsers accept invalid UTF-8 inside strings, and the
        # first regex any consumer then runs on such a value (TOML escaping
        # for `[[content.generate]]`, a template filter) raised "UTF-8 error:
        # illegal byte" and aborted the build. Scrub once, for every source.
        content = content.scrub unless content.valid_encoding?
        case format
        when "json"        then from_json(JSON.parse(content))
        when "toml"        then from_toml(TOML.parse(content))
        when "yaml", "yml" then from_yaml(YAML.parse(content))
        when "csv"
          rows = CSV.parse(content).map do |row|
            Crinja::Value.new(row.map { |cell| Crinja::Value.new(cell.strip) })
          end
          Crinja::Value.new(rows)
        end
      end

      # Coerce a template/filter argument to an Int32 count, clamped to
      # [min, max], with `default` for anything that isn't a number at all.
      #
      # Numeric arguments reach templates as strings far more often than not:
      # `parse_shortcode_args_jinja` produces a `Hash(String, String)`, so every
      # value a shortcode forwards is a String. `Crinja::Value#as_number` raises
      # `Crinja::TypeError` on those, and the raise propagated out of the filter
      # and aborted the whole page render — `resize_image(width="800")` killed
      # the page instead of resizing. Out-of-range and NaN values clamp here too
      # rather than raising OverflowError from `Float64#to_i`.
      def to_count(value : Crinja::Value, default : Int32 = 0, min : Int32 = 0, max : Int32 = Int32::MAX) : Int32
        num = begin
          value.as_number.to_f
        rescue Exception
          value.to_s.strip.to_f?
        end
        return default unless num
        return default if num.nan?
        return min if num <= min.to_f
        return max if num >= max.to_f
        num.to_i32
      end
    end
  end
end
