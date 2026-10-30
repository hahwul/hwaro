require "big"
require "crinja"
require "../../../utils/crinja_utils"

module Hwaro
  module Content
    module Processors
      module Filters
        module MathFilters
          PLAIN_NUMBER_RE = /\A[+-]?\d+(?:\.\d+)?\z/

          # The exact decimal value of a number, or of a string holding a
          # plain decimal (`"1234.5"`); nil for anything else, including
          # NaN/Infinity and booleans.
          def self.to_decimal(value : Crinja::Value) : BigDecimal?
            case raw = value.raw
            when Int   then BigDecimal.new(raw)
            when Float then BigDecimal.new(raw) if raw.finite?
            when String, Crinja::SafeString
              text = raw.to_s.strip
              BigDecimal.new(text) if text.matches?(PLAIN_NUMBER_RE)
            end
          end

          # `number` with its integer digits grouped in threes, rounded
          # half away from zero to `decimals` places (nil keeps the
          # number's own decimals).
          def self.num_format(number : BigDecimal, decimals : Int32?, separator : String, decimal_point : String) : String
            number = number.round(decimals, mode: :ties_away) if decimals
            scale = number.scale.to_i
            digits = number.value.abs.to_s.rjust(scale + 1, '0')
            integer = digits[0, digits.size - scale]
            fraction = digits[digits.size - scale, scale]
            fraction = fraction.ljust(decimals, '0') if decimals
            String.build do |io|
              io << '-' if number.value < 0
              integer.each_char_with_index do |char, i|
                io << separator if i > 0 && (integer.size - i) % 3 == 0
                io << char
              end
              io << decimal_point << fraction unless fraction.empty?
            end
          end

          def self.register(env : Crinja)
            # `num_format` — `1234567 | num_format` → `1,234,567`;
            # `decimals=` fixes the decimal places, `separator=` and
            # `decimal_point=` pick the marks (`num_format(separator=".",
            # decimal_point=",")` → `1.234.567,5`). A value that is not a
            # number (or a numeric string) is returned unchanged, like
            # `ceil` / `floor`.
            env.filters["num_format"] = Crinja.filter({decimals: nil, separator: ",", decimal_point: "."}) do
              if number = MathFilters.to_decimal(target)
                decimals = arguments["decimals"]
                decimals = decimals.none? || decimals.undefined? ? nil : Utils::CrinjaUtils.to_count(decimals, max: 20)
                MathFilters.num_format(number, decimals, arguments["separator"].to_s, arguments["decimal_point"].to_s)
              else
                target
              end
            end

            # Ceil filter — rounds up to the nearest integer
            env.filters["ceil"] = Crinja.filter do
              num = target.as_number
              if num.is_a?(Float64)
                if num.nan? || num.infinite? || num > Int64::MAX.to_f || num < Int64::MIN.to_f
                  target
                else
                  Crinja::Value.new(num.ceil.to_i64)
                end
              else
                Crinja::Value.new(num.to_i64)
              end
            rescue Exception
              target
            end

            # Floor filter — rounds down to the nearest integer
            env.filters["floor"] = Crinja.filter do
              num = target.as_number
              if num.is_a?(Float64)
                if num.nan? || num.infinite? || num > Int64::MAX.to_f || num < Int64::MIN.to_f
                  target
                else
                  Crinja::Value.new(num.floor.to_i64)
                end
              else
                Crinja::Value.new(num.to_i64)
              end
            rescue Exception
              target
            end
          end
        end
      end
    end
  end
end
