# Attribute, subscript and call access after a parenthesized expression, as
# in Jinja2: `{{ (section.pages | first).title }}`, `{{ (a + b)[0] }}`.
#
# Upstream returned the parenthesized expression without reading what
# follows it, so the `.title` failed the template with "expression was not
# fully parsed". A parenthesis is now parsed as the head of the variable
# expression, whose loop reads the trailing `.x` / `[i]` / `(…)`; the head
# itself (including a tuple, `(1, 2)`) is still parsed by the upstream rule.
class Crinja::Parser::ExpressionParser
  # Set by `parse_literal` for the one nested call that must run the
  # upstream rule; consumed on entry, so inner parentheses start clean.
  @__paren_head = false

  private def parse_parenthesis_expression
    if current_token.kind == Kind::LEFT_PAREN && !@__paren_head
      return parse_variable_expression
    end
    @__paren_head = false
    previous_def
  end

  private def parse_literal
    if current_token.kind == Kind::LEFT_PAREN
      @__paren_head = true
      return parse_parenthesis_expression
    end
    previous_def
  end
end
