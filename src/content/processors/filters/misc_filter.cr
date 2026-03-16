require "crinja"
require "json"

module Hwaro
  module Content
    module Processors
      module Filters
        module MiscFilters
          def self.register(env : Crinja)
            # JSON encode filter (escapes </ to prevent script-tag breakout in inline JS)
            env.filters["jsonify"] = Crinja.filter do
              target.to_s.to_json.gsub("</", "<\\/")
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
                "[#{target.as_a.map(&.to_s).join(", ")}]"
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
