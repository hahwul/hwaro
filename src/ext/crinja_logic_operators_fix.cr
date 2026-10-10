# `and` / `or` return an operand, as in Jinja2 (and Python), not a Bool.
# Upstream collapsed both to true/false, so the fallback idiom
# `{{ page.description or site.description }}` printed "true" and
# `{% set x = a or "default" %}` stored a boolean. Truthiness — and so every
# `{% if %}` — is unchanged; the right operand is still evaluated lazily.
class Crinja::Operator::And
  def value(env : Crinja, op1 : Value, &op2 : -> Value) : Value
    op1.truthy? ? op2.call : op1
  end
end

class Crinja::Operator::Or
  def value(env : Crinja, op1 : Value, &op2 : -> Value) : Value
    op1.truthy? ? op1 : op2.call
  end
end
