require "crinja"
require "json"

module Hwaro
  module Content
    module Processors
      module Filters
        module MiscFilters
          # Recursively serialize a Crinja value tree into a JSON::Builder.
          # Direct `target.to_json(io)` cannot be used here — Crinja::Value#to_json
          # opens its own document and raises inside an already-open builder.
          def self.build_json(json : JSON::Builder, value : Crinja::Value)
            build_json(json, value.raw)
          end

          def self.build_json(json : JSON::Builder, raw)
            case raw
            when Crinja::Value      then build_json(json, raw.raw)
            when Crinja::SafeString then json.string(raw.to_s)
            when Array              then json.array { raw.each { |v| build_json(json, v) } }
            when Hash               then json.object { raw.each { |k, v| json.field(k.to_s) { build_json(json, v) } } }
            when String, Int32, Int64, Float64, Bool, Nil
              raw.to_json(json)
            else
              json.string(raw.to_s)
            end
          end

          def self.register(env : Crinja)
            # JSON encode filter (escapes </ to prevent script-tag breakout in inline JS).
            # Serialize the actual value tree — `target.to_s.to_json` would stringify
            # the Crinja::Value first and emit broken JSON (e.g. "[Crinja::Value<...>]")
            # for arrays/hashes/numbers.
            env.filters["jsonify"] = Crinja.filter do
              JSON.build { |b| MiscFilters.build_json(b, target) }.gsub("</", "<\\/")
            end

            # Default filter — returns fallback when target is nil/undefined or empty string
            env.filters["default"] = Crinja.filter({value: ""}) do
              if target.raw.nil? || target.undefined?
                arguments["value"].to_s
              else
                val = target.to_s
                val.empty? ? arguments["value"].to_s : val
              end
            end

            # Inspect filter — outputs debug representation of a value
            env.filters["inspect"] = Crinja.filter do
              raw = target.raw
              case raw
              when Nil
                "nil"
              when String
                raw.inspect
              when Bool, Int32, Int64, Float64
                raw.to_s
              when Array
                String.build do |io|
                  io << "["
                  target.as_a.each_with_index do |v, i|
                    io << ", " if i > 0
                    io << v.to_s
                  end
                  io << "]"
                end
              when Hash
                pairs = [] of String
                target.as_h.each do |k, v|
                  pairs << "#{k}: #{v}"
                end
                "{#{pairs.join(", ")}}"
              else
                target.to_s.inspect
              end
            end
          end
        end
      end
    end
  end
end
