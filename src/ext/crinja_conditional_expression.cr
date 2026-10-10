# Jinja2's conditional expression: `{{ "active" if current else "" }}`,
# `{% set label = page.title if page.title else "Untitled" %}`.
#
# Upstream rejected it ("expression was not fully parsed"), one of the most
# common Jinja2 idioms. Semantics follow Jinja2: only the chosen branch is
# evaluated, a missing `else` yields undefined (renders empty), and
# `a if x else b if y else c` nests to the right. The collection of a
# `{% for x in xs if cond %}` loop keeps reading `if` as the loop filter.
module Crinja::AST
  expression_node ConditionalExpression,
    test : ExpressionNode,
    if_true : ExpressionNode,
    if_false : ExpressionNode?
end

class Crinja::Parser::ExpressionParser
  # Set by the `for` tag around its collection expression, where `if`
  # starts the loop filter instead.
  property __no_condexpr = false

  def parse_expression
    allow_condexpr = !@__no_condexpr
    @__no_condexpr = false

    expression = parse_logical_or
    while allow_condexpr && current_token.kind == Kind::IDENTIFIER && current_token.value == "if"
      next_token
      test = parse_logical_or
      if_false = nil
      if current_token.kind == Kind::IDENTIFIER && current_token.value == "else"
        next_token
        if_false = parse_expression
      end
      expression = AST::ConditionalExpression.new(test, expression, if_false).at(expression, if_false || test)
    end

    expression.location_end = current_token.location
    expression
  end

  # A filter or test written without parentheses swallowed a following
  # `if` / `else` as its argument (`x | lower if x else ""`,
  # `x is defined else ""`); those keywords end the call instead. A bare
  # argument is no conditional either: `n is divisibleby 2 if c else d` is
  # `(n is divisibleby 2) if c else d`, as in Jinja2.
  private def parse_call_expression(identifier, with_parenthesis = true)
    return previous_def if with_parenthesis
    if current_token.kind == Kind::IDENTIFIER && current_token.value.in?("if", "else")
      return AST::CallExpression.new(identifier, AST::ExpressionList.new([] of AST::ExpressionNode),
        Hash(AST::IdentifierLiteral, AST::ExpressionNode).new).at(identifier.location_start, current_token.location)
    end

    begin
      @__no_condexpr = true
      previous_def
    ensure
      # No argument at all leaves the flag unread; don't let it reach the
      # next expression.
      @__no_condexpr = false
    end
  end
end

class Crinja::Evaluator
  def evaluate(expression : AST::ConditionalExpression)
    if value(expression.test).truthy?
      evaluate expression.if_true
    elsif if_false = expression.if_false
      evaluate if_false
    else
      Undefined.new
    end
  rescue ex : Crinja::Error
    ex.at(expression) unless ex.has_location?
    raise ex
  end
end

class Crinja::Tag::For
  private class Parser < ArgumentsParser
    # Upstream `parse_for_tag`, with the collection parsed without the
    # conditional expression (Jinja2's `with_condexpr=False`).
    def parse_for_tag
      item_vars = parse_identifier_list.map do |identifier|
        if identifier.name == LOOP_VARIABLE
          raise TemplateSyntaxError.new(identifier, "cannot use reserved name `loop` as item variable in for loop")
        end
        identifier.name
      end

      expect Kind::IDENTIFIER, "in"

      self.__no_condexpr = true
      collection_expr = parse_expression

      if_expr : AST::ExpressionNode? = nil
      if_token Kind::IDENTIFIER, "if" do
        next_token
        if_expr = parse_expression
      end

      recursive = false
      if_token Kind::IDENTIFIER, "recursive" do
        recursive = true
      end

      close

      return {item_vars, collection_expr, if_expr, recursive}
    end
  end
end
