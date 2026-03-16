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
              format = arguments["format"].to_s

              case value
              when Time
                value.to_s(format)
              when String
                # Try to parse the string as a date using multiple common formats
                parsed = nil
                ["%Y-%m-%dT%H:%M:%S%:z", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"].each do |fmt|
                  begin
                    parsed = Time.parse(value, fmt, Time::Location::UTC)
                    break
                  rescue
                  end
                end
                if parsed.nil?
                  begin
                    parsed = Time.parse_rfc3339(value)
                  rescue
                  end
                end
                parsed ? parsed.to_s(format) : value
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
