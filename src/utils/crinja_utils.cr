# Shared utility module for converting YAML, TOML, and JSON values to Crinja::Value
#
# This consolidates the duplicated conversion logic that previously existed
# in both Builder (src/core/build/builder.cr) and TemplateEngine
# (src/content/processors/template.cr).

require "yaml"
require "json"
require "toml"
require "crinja"

module Hwaro
  module Utils
    module CrinjaUtils
      extend self

      # Pre-allocated nil value to avoid repeated allocations in hot paths
      NIL_VALUE = Crinja::Value.new(nil)

      # Convert a YAML::Any value to Crinja::Value.
      #
      # `depth` guards against a self-referencing YAML anchor, whose parsed
      # graph is cyclic and would otherwise recurse until the stack dies
      # (see `Utils::Nesting`). Both call sites — `Initialize#parse_data_file`
      # and the `load_data` template function — already rescue and degrade, so
      # the raise surfaces as "data file skipped" rather than a crash.
      def from_yaml(value : YAML::Any, depth : Int32 = 0) : Crinja::Value
        Nesting.check!(depth)
        if arr = value.as_a?
          Crinja::Value.new(arr.map { |v| from_yaml(v, depth + 1) })
        elsif h = value.as_h?
          converted = {} of String => Crinja::Value
          h.each do |k, v|
            converted[k.to_s] = from_yaml(v, depth + 1)
          end
          Crinja::Value.new(converted)
        elsif s = value.as_s?
          Crinja::Value.new(s)
        elsif i = value.as_i64?
          Crinja::Value.new(i)
        elsif f = value.as_f?
          Crinja::Value.new(f)
        elsif b = value.as_bool?
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
        elsif b = value.as_bool?
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
