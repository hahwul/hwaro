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
                # Detect format heuristically to avoid exception-based control flow
                parsed = if value.includes?('T')
                           if value.size > 19 && (value.includes?('+') || value.includes?('Z') || value.ends_with?("00"))
                             Time.parse_rfc3339(value) rescue Time.parse(value, "%Y-%m-%dT%H:%M:%S", Time::Location::UTC) rescue nil
                           else
                             # Fall back to minute precision (no seconds), e.g. "2024-01-15T10:30".
                             Time.parse(value, "%Y-%m-%dT%H:%M:%S", Time::Location::UTC) rescue Time.parse(value, "%Y-%m-%dT%H:%M", Time::Location::UTC) rescue nil
                           end
                         elsif value.size > 10
                           # Try seconds, then minute precision, then date-only so
                           # space-separated datetimes without seconds still parse.
                           Time.parse(value, "%Y-%m-%d %H:%M:%S", Time::Location::UTC) rescue Time.parse(value, "%Y-%m-%d %H:%M", Time::Location::UTC) rescue Time.parse(value, "%Y-%m-%d", Time::Location::UTC) rescue nil
                         else
                           Time.parse(value, "%Y-%m-%d", Time::Location::UTC) rescue nil
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
