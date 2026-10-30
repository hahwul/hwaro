require "crinja"

module Hwaro
  module Content
    module Processors
      module Filters
        module MathFilters
          # ASCII digits only: `\d` also matches Arabic-Indic or fullwidth
          # digits under UCP.
          PLAIN_NUMBER_RE = /\A[+-]?[0-9]+(?:\.[0-9]+)?\z/

          # An exact decimal as digit strings: sign, integer digits (no
          # leading zeros) and fraction digits. Kept as text, not BigDecimal,
          # so hwaro does not link libgmp for one filter.
          alias Decimal = {Bool, String, String}

          # The exact decimal of a number, or of a string holding a plain
          # decimal (`"1234.5"`); nil for anything else, including
          # NaN/Infinity and booleans. A float gives its shortest round-trip
          # digits (`0.1 + 0.2` is `0.30000000000000004`, `1e-7` is
          # `0.0000001`).
          def self.to_decimal(value : Crinja::Value) : Decimal?
            case raw = value.raw
            when Int   then split_decimal(raw.to_s)
            when Float then float_decimal(raw) if raw.finite?
            when String, Crinja::SafeString
              text = raw.to_s.strip
              split_decimal(text) if text.matches?(PLAIN_NUMBER_RE)
            end
          end

          # Splits `[+-]digits[.digits]`; the fraction keeps its digits as
          # written.
          private def self.split_decimal(text : String) : Decimal
            negative = text.starts_with?('-')
            text = text.lchop('-').lchop('+')
            integer, _, fraction = text.partition('.')
            {negative, integer.lstrip('0').presence || "0", fraction}
          end

          # `Float#to_s` is the shortest round-trip form, possibly in
          # exponent notation (`1.5e-7`, `1.0e+20`); shift its digits into
          # plain notation and drop the padding zero of `1234.0` / `1.0e-7`.
          private def self.float_decimal(float : Float) : Decimal
            mantissa, _, exponent = float.abs.to_s.partition('e')
            point = mantissa.index!('.') + (exponent.empty? ? 0 : exponent.to_i)
            digits = mantissa.delete('.')
            integer, fraction = if point <= 0
                                  {"0", "0" * -point + digits}
                                elsif point >= digits.size
                                  {digits + "0" * (point - digits.size), ""}
                                else
                                  {digits[0, point], digits[point..]}
                                end
            {float < 0, integer.lstrip('0').presence || "0", fraction.rstrip('0')}
          end

          # `decimal` rounded half away from zero to `places` fraction
          # digits (padded with zeros when it has fewer).
          def self.round_decimal(decimal : Decimal, places : Int32) : Decimal
            negative, integer, fraction = decimal
            return {negative, integer, fraction.ljust(places, '0')} if fraction.size <= places
            digits = (integer + fraction[0, places]).chars
            if fraction[places] >= '5'
              i = digits.size - 1
              while i >= 0 && digits[i] == '9'
                digits[i] = '0'
                i -= 1
              end
              if i >= 0
                digits[i] = digits[i].succ
              else
                digits.unshift('1')
              end
            end
            joined = digits.join
            integer = joined[0, joined.size - places].lstrip('0').presence || "0"
            {negative, integer, joined[joined.size - places, places]}
          end

          # `decimals=` as a place count clamped to 0..20: an integer, or an
          # integral float or string. Anything else means "not given".
          def self.decimal_places(value : Crinja::Value) : Int32?
            case raw = value.raw
            when Int   then raw.clamp(0, 20).to_i32
            when Float then raw.clamp(0.0, 20.0).to_i32 if raw.finite? && raw == raw.trunc
            when String, Crinja::SafeString
              raw.to_s.strip.to_i64?.try(&.clamp(0, 20).to_i32)
            end
          end

          # `number` with its integer digits grouped in threes, rounded
          # half away from zero to `decimals` places (nil keeps the
          # number's own decimals).
          def self.num_format(number : Decimal, decimals : Int32?, separator : String, decimal_point : String) : String
            number = round_decimal(number, decimals) if decimals
            negative, integer, fraction = number
            # No `-0`: a value that is (or rounds to) zero has no sign.
            negative &&= integer != "0" || fraction.each_char.any? { |char| char != '0' }
            String.build do |io|
              io << '-' if negative
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
                decimals = MathFilters.decimal_places(arguments["decimals"])
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
