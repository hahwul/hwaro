# Jinja's membership operators `in` / `not in`. Crinja ships neither, so the
# documented `{% if "tutorial" in page.tags %}` failed to parse. `in` lexes
# as a plain IDENTIFIER (the `for` tag matches it by value), so the
# comparison level of the expression parser recognises it here; `not in`
# is the `not` OPERATOR immediately followed by that identifier.
class Crinja::Operator
  # Jinja semantics: substring for strings, key lookup for mappings,
  # element equality for any other iterable.
  def self.member?(item : Value, container : Value) : Bool
    if container.string?
      container.to_s.includes?(item.to_s)
    elsif (raw = container.raw).is_a?(Hash)
      raw.has_key?(item)
    elsif container.iterable?
      container.each { |element| return true if element == item }
      false
    else
      raise TypeError.new(container, "argument of `in` is not iterable")
    end
  end

  class In < Operator
    include Binary
    name "in"

    def value(env : Crinja, op1 : Value, op2 : Value)
      Operator.member?(op1, op2)
    end
  end

  class NotIn < Operator
    include Binary
    name "not in"

    def value(env : Crinja, op1 : Value, op2 : Value)
      !Operator.member?(op1, op2)
    end
  end

  class Library
    register_default [In, NotIn]
  end
end

class Crinja::Parser::ExpressionParser
  # Replaces the `parse_operator :equal_not, ...` expansion. The upstream
  # list also accepted a bare binary `not` (`a not b`), which only ever
  # failed at render time with "unreachable: invalid operator".
  private def parse_equal_not
    left = parse_less_greater

    while operator = comparison_operator
      right = parse_less_greater
      left = AST::ComparisonExpression.new(operator, left, right).at(left, right)
    end

    left
  end

  # Consumes and returns the operator at the cursor, or nil.
  private def comparison_operator : String?
    token = current_token
    if token.kind == Kind::OPERATOR && (token.value == Symbol::OP_EQUAL || token.value == Symbol::OP_NOT_EQUAL)
      next_token
      token.value
    elsif token.kind == Kind::IDENTIFIER && token.value == "in"
      next_token
      "in"
    elsif token.kind == Kind::OPERATOR && token.value == Symbol::OP_NOT &&
          (following = peek_token?) && following.kind == Kind::IDENTIFIER && following.value == "in"
      next_token
      next_token
      "not in"
    end
  end
end
