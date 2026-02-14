require "crinja"
require "json"

module Hwaro
  module Content
    module Processors
      module Filters
        module MiscFilters
          def self.register(env : Crinja)
            # JSON encode filter
            env.filters["jsonify"] = Crinja.filter do
              target.to_s.to_json
            end

            # Default filter
            env.filters["default"] = Crinja.filter({value: ""}) do
              val = target.to_s
              if val.empty?
                arguments["value"].to_s
              else
                val
              end
            end
          end
        end
      end
    end
  end
end
