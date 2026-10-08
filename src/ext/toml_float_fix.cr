# Monkey-patch for the vendored toml shard's number lexing — kept here so we
# don't fork the library, like ext/toml_datetime_fix.cr.
#
# `TOML::Lexer#consume_number` / `#consume_float` / `#consume_exponent` (toml
# 0.8.1, src/toml/lexer.cr:350-500) accumulated every digit into an Int64 and a
# UInt64 divisor (`divisor *= 10`), then computed `int.to_f64 / divisor` and
# `* 10_f64 ** exp`:
#
#   * 20+ fractional digits (`pi = 3.14159265358979323846264338327950288`,
#     `1e-21` written out) or 19+ integer digits overflowed and raised a bare
#     OverflowError — not a TOML::ParseException, so it was not reported as a
#     front-matter / config error at all;
#   * shorter literals were rounded twice (`1.1e2` -> 110.00000000000001,
#     `6.022e23` -> 6.0219999999999996e+23) and `1.7976931348623157e308` -> inf.
#
# The digits are now collected as text and the float is `String#to_f64` of the
# literal (correctly rounded). An integer that does not fit in 64 bits is a
# TOML parse error instead of an OverflowError. The error messages, the
# underscore rules and the leading-zero check are unchanged.
#
# Remove when: upstream parses floats without intermediate integers.

require "toml"

# Replaces the upstream methods wholesale (no `previous_def`), so pin the
# version they were copied from — see toml_nesting_limit_fix.cr.
{% if (shard_yml = read_file?("lib/toml/shard.yml")) && !shard_yml.includes?("version: 0.8.1") %}
  {% raise "src/ext/toml_float_fix.cr replaces TOML::Lexer#consume_number/#consume_float/#consume_exponent from toml 0.8.1, but a different toml version is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

class TOML::Lexer
  private def consume_number(negative = false, leading_zero = false)
    # Wrapping arithmetic: `num` is only trusted for the 2/4-digit time and
    # date prefixes; INT values are re-parsed from `text` below.
    num = current_char.to_i.to_i64
    digits = String::Builder.new
    digits << current_char
    count = 1
    last_is_underscore = false
    has_underscore = false

    loop do
      case next_char
      when '0'..'9'
        num = num &* 10 &+ current_char.to_i
        digits << current_char
        last_is_underscore = false
        count += 1
      when '_'
        if last_is_underscore
          raise "double underscores in a number are now allowed"
        else
          last_is_underscore = true
          has_underscore = true
        end
      else
        break
      end
    end
    text = digits.to_s

    unless @before_eq_symbol
      case current_char
      when '-'
        if count == 4 && !has_underscore && !negative
          return consume_datetime num
        else
          unexpected_char
        end
      when '.'
        return hwaro_consume_float(negative, text)
      when ':'
        if count == 2 && !has_underscore && !negative
          return consume_time num
        else
          unexpected_char
        end
      when 'e', 'E'
        return hwaro_consume_exponent(negative, text)
      end
    end

    if leading_zero && text.each_char.any? { |c| c != '0' }
      raise "numbers with leading zero are not allowed"
    end

    value = (negative ? "-#{text}" : text).to_i64? || raise("integer out of range")

    @token.type = :INT
    @token.int_value = value
  end

  # *integer_text* is the literal's integer digits; `current_char` is the `.`.
  private def hwaro_consume_float(negative, integer_text : String)
    text = String::Builder.new
    text << integer_text << '.'
    fraction_digits = 0
    last_is_underscore = false
    next_char
    loop do
      case current_char
      when '0'..'9'
        text << current_char
        fraction_digits += 1
        next_char
        last_is_underscore = false
      when '_'
        if last_is_underscore
          raise "double underscores in a number are now allowed"
        else
          last_is_underscore = true
          next_char
        end
      else
        break
      end
    end

    if fraction_digits == 0
      raise "expecting float decimal digit"
    end

    case current_char
    when 'e', 'E'
      hwaro_consume_exponent(negative, text.to_s)
    else
      hwaro_finish_float(negative, text.to_s)
    end
  end

  # *mantissa_text* is everything before the `e`; `current_char` is the `e`.
  private def hwaro_consume_exponent(negative, mantissa_text : String)
    text = String::Builder.new
    text << mantissa_text << 'e'
    last_is_underscore = false

    case next_char
    when '+'
      next_char
    when '-'
      text << '-'
      next_char
    end

    if '0' <= current_char <= '9'
      loop do
        case current_char
        when '0'..'9'
          text << current_char
          next_char
          last_is_underscore = false
        when '_'
          if last_is_underscore
            raise "double underscores in a number are now allowed"
          else
            last_is_underscore = true
            next_char
          end
        else
          break
        end
      end
    else
      unexpected_char
    end

    hwaro_finish_float(negative, text.to_s)
  end

  private def hwaro_finish_float(negative, literal : String)
    # `to_f64?` is nil past the double range; an underflow (`1e-400`) is 0.0
    # like every other TOML parser, an overflow is an error.
    float = literal.to_f64? || (literal.includes?("e-") ? 0.0 : raise("float out of range"))
    @token.type = :FLOAT
    @token.float_value = negative ? -float : float
  end
end
