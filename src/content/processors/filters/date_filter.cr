require "crinja"

module Hwaro
  module Content
    module Processors
      module Filters
        module DateFilters
          def self.register(env : Crinja)
            # Date formatting filter
            env.filters["date"] = Crinja.filter({format: "%Y-%m-%d"}) do
              value = target.raw
              format = arguments["format"].as_s

              case value
              when Time
                value.to_s(format)
              when String
                # Try to parse the string as a date
                begin
                  Time.parse(value, "%Y-%m-%d", Time::Location::UTC).to_s(format)
                rescue
                  value
                end
              else
                value.to_s
              end
            end
          end
        end
      end
    end
  end
end
