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
