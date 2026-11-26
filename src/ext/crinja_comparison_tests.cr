# Jinja2's comparison tests: `eq`/`==`/`equalto`, `ne`/`!=`, `lt`/`<`/
# `lessthan`, `le`/`<=`, `gt`/`>`/`greaterthan`, `ge`/`>=`.
#
# Upstream had only `equalto`, `lessthan` and `greaterthan`, and the latter
# two compared `to_i` of both sides, so `2.5 is greaterthan 2` was false and
# strings always compared equal. `selectattr("year", ">=", 2020)` — the
# documented Jinja2 form — failed with "no test with name". Each test now
# applies the template operator of the same meaning.
{% for name, operator in {
                           "eq" => "==", "==" => "==", "equalto" => "==",
                           "ne" => "!=", "!=" => "!=",
                           "lt" => "<", "<" => "<", "lessthan" => "<",
                           "le" => "<=", "<=" => "<=",
                           "gt" => ">", ">" => ">", "greaterthan" => ">",
                           "ge" => ">=", ">=" => ">=",
                         } %}
  Crinja.test({other: Crinja::UNDEFINED}, {{ name.id.symbolize }}) do
    env.operators[{{ operator }}].as(Crinja::Operator::Binary).value(env, target, arguments["other"])
  end
{% end %}

# `Value#<=>` (behind `<`, `>`, `sort`, `min`, `max`) compares a string with
# anything as strings, but upstream tested the left operand twice
# (`a.is_a?(String) || a.is_a?(String)`), so `"a" > 1` and `[1, "a"] | max`
# worked while `1 < "a"` and `["a", 1] | max` raised: the answer depended on
# operand order. Both orders now compare as strings (an array too, unless
# both sides are arrays).
struct Crinja::Value
  private def compare(a, b)
    if a.is_a?(Array) && b.is_a?(Array)
      compare_array(a, b)
    elsif a.is_a?(Bool) || b.is_a?(Bool)
      raise TypeError.new "Cannot compare Bool value"
    elsif a.is_a?(Number) && b.is_a?(Number)
      a <=> b
    elsif a.is_a?(String | SafeString) || b.is_a?(String | SafeString)
      a.to_s <=> b.to_s
    else
      raise TypeError.new("cannot compare #{a.class} with #{b.class}")
    end
  end
end

# Jinja2's number tests, `value % 2 == 0` (`even`), `value % 2 == 1` (`odd`)
# and `value % num == 0` (`divisibleby`), in the value's own type. Upstream
# converted both sides to Int32 first, so any integer past 2**31 (a
# timestamp, an ID from a data file) failed the build with "Arithmetic
# overflow", and a float was truncated: `2.5 is even` and
# `3.5 is divisibleby 3` were true. A numeric string is still read as an
# integer (a CSV field), as before.
module Crinja::Test
  def self.__number(value : Crinja::Value) : Int64 | Float64
    case raw = value.raw
    when Float                      then raw.to_f64
    when Int                        then raw.to_i64
    when String, Crinja::SafeString then raw.to_s.to_i64
    else                                 value.to_i.to_i64
    end
  end

  # Python's `%`: the result takes the divisor's sign.
  def self.__modulo(value : Int64 | Float64, divisor : Int64 | Float64) : Int64 | Float64
    raise DivisionByZeroError.new if divisor == 0
    return 0_i64 if divisor == -1 && value.is_a?(Int64) # Int64::MIN % -1 overflows
    value.is_a?(Int64) && divisor.is_a?(Int64) ? value % divisor : value.to_f64 % divisor.to_f64
  end
end

Crinja.test(:even) { Crinja::Test.__modulo(Crinja::Test.__number(target), 2_i64) == 0 }
Crinja.test(:odd) { Crinja::Test.__modulo(Crinja::Test.__number(target), 2_i64) == 1 }
Crinja.test({num: Crinja::UNDEFINED}, :divisibleby) do
  Crinja::Test.__modulo(Crinja::Test.__number(target), Crinja::Test.__number(arguments["num"])) == 0
end

# `lower` / `upper` are Python's `str.islower()` / `str.isupper()`: at least
# one cased character, and none of the other case. Upstream required EVERY
# character to be a lowercase (uppercase) letter, so a space, digit or
# punctuation mark made `"hello world" is lower` false, and the empty
# string was both lower and upper.
module Crinja::Test
  def self.__cased?(text : String, upper : Bool) : Bool
    cased = false
    text.each_char do |char|
      if upper ? char.uppercase? : char.lowercase?
        cased = true
      elsif char.titlecase? || (upper ? char.lowercase? : char.uppercase?)
        return false
      end
    end
    cased
  end
end

Crinja.test(:lower) { Crinja::Test.__cased?(target.to_s, upper: false) }
Crinja.test(:upper) { Crinja::Test.__cased?(target.to_s, upper: true) }
