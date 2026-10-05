require "crinja"

module Hwaro
  module Content
    module Processors
      module Filters
        module DateFilters
          # `Time#to_s(format)` raises a bare Crystal `IndexError` on a
          # malformed format string (a trailing `%`, e.g. `date("%")`) — not a
          # `Crinja::Error`, so it escapes the render phase's rescue and
          # aborts the whole build with `Index out of bounds` and no template
          # file:line. Re-raise as a Crinja error so the failure names the bad
          # format AND points at the template line that wrote it.
          def self.format_time(time : Time, format : String) : String
            time.to_s(format)
          rescue ex : IndexError | ArgumentError
            raise Crinja::TypeError.new("invalid date format #{format.inspect}: #{ex.message}")
          end

          # Zoned forms come first: `Time.parse` ignores trailing input, so a
          # zone-less format would accept "10:30:00-03:30" and drop the offset.
          # The space-separated forms include `Time#to_s` output
          # ("2024-03-05 08:00:00 UTC"), which is how front matter and data
          # file datetimes reach templates.
          T_ZONED     = {"%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S.%N%z", "%Y-%m-%dT%H:%M%z"}
          T_LOCAL     = {"%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M"}
          SPACE_ZONED = {"%Y-%m-%d %H:%M:%S %z", "%Y-%m-%d %H:%M:%S%z", "%Y-%m-%d %H:%M:%S.%N %z", "%Y-%m-%d %H:%M %z", "%Y-%m-%d %H:%M%z"}
          SPACE_LOCAL = {"%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"}

          # No date-only fallback for longer strings: `%Y-%m-%d` consumes only
          # the first 10 chars, which would silently reformat garbage like
          # "2024-01-15xxx" instead of passing it through unchanged.
          def self.parse_string(value : String) : Time?
            return try_parse(value, "%Y-%m-%d") if value.size <= 10
            zoned, local = value[10] == 'T' ? {T_ZONED, T_LOCAL} : {SPACE_ZONED, SPACE_LOCAL}
            # Longer than the zone-less minute form ("2024-01-15T10:30").
            if value.size > 16
              zoned.each { |fmt| try_parse(value, fmt).try { |time| return time } }
            end
            local.each { |fmt| try_parse(value, fmt).try { |time| return time } }
            nil
          end

          private def self.try_parse(value : String, format : String) : Time?
            Time.parse(value, format, Time::Location::UTC)
          rescue Time::Format::Error | ArgumentError
            nil
          end

          def self.register(env : Crinja)
            # Date formatting filter
            env.filters["date"] = Crinja.filter({format: "%Y-%m-%d"}) do
              value = target.raw
              format = arguments["format"].to_s

              case value
              when Time
                DateFilters.format_time(value, format)
              when String
                parsed = DateFilters.parse_string(value)
                parsed ? DateFilters.format_time(parsed, format) : value
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
