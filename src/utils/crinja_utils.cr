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

      # Convert a YAML::Any value to Crinja::Value
      def from_yaml(value : YAML::Any) : Crinja::Value
        if arr = value.as_a?
          Crinja::Value.new(arr.map { |v| from_yaml(v) })
        elsif h = value.as_h?
          converted = {} of String => Crinja::Value
          h.each do |k, v|
            converted[k.to_s] = from_yaml(v)
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
        else
          NIL_VALUE
        end
      end

      # Convert a Hash(String, TOML::Any) to Crinja::Value
      def from_toml(value : Hash(String, TOML::Any)) : Crinja::Value
        converted = {} of String => Crinja::Value
        value.each do |k, v|
          converted[k] = from_toml(v)
        end
        Crinja::Value.new(converted)
      end

      # Convert a TOML::Any value to Crinja::Value
      def from_toml(value : TOML::Any) : Crinja::Value
        if arr = value.as_a?
          Crinja::Value.new(arr.map { |v| from_toml(v) })
        elsif h = value.as_h?
          converted = {} of String => Crinja::Value
          h.each do |k, v|
            converted[k] = from_toml(v)
          end
          Crinja::Value.new(converted)
        elsif s = value.as_s?
          Crinja::Value.new(s)
        elsif i = value.as_i?
          Crinja::Value.new(i.to_i64)
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
      def from_extra(value : Hwaro::Models::ExtraValue) : Crinja::Value
        case value
        when Hash
          converted = {} of String => Crinja::Value
          value.each { |k, v| converted[k] = from_extra(v) }
          Crinja::Value.new(converted)
        when Array(String)
          Crinja::Value.new(value.map { |s| Crinja::Value.new(s) })
        when Array
          Crinja::Value.new(value.map { |v| from_extra(v) })
        else
          Crinja::Value.new(value)
        end
      end

      # Convert a JSON::Any value to Crinja::Value
      def from_json(value : JSON::Any) : Crinja::Value
        case value.raw
        when Hash
          hash = {} of String => Crinja::Value
          value.as_h.each { |k, v| hash[k] = from_json(v) }
          Crinja::Value.new(hash)
        when Array
          arr = value.as_a.map { |v| from_json(v) }
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
    end
  end
end
