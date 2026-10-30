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
