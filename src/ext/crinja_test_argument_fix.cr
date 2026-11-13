# A test's argument written without parentheses is one value, as in Jinja2:
# `loop.index is divisibleby 3 and not loop.last` is
# `(loop.index is divisibleby 3) and not loop.last`.
#
# Upstream parsed the whole rest of the expression as the argument, so the
# test above was `divisibleby(3 and not loop.last)`, and
# `x is sameas true or y` / `n is eq 2 and m` silently gave the wrong
# answer. Jinja2 reads a literal, a name or a parenthesized expression plus
# any `.attr` / `[index]` / `(call)` after it (`parse_primary` +
# `parse_postfix`), and no argument at all when the next token is not one
# of those (or is `else` / `or` / `and`). Filters are unchanged.
class Crinja::Parser::ExpressionParser
  private def parse_filter
    left = parse_unary_expression

    loop do
      case current_token.kind
      when Kind::PIPE, Kind::TEST
        is_test = current_token.kind == Kind::TEST

        next_token

        not_location = nil
        if is_test
          if_token Kind::OPERATOR, "not" do
            not_location = current_token.location

            next_token
          end
        end

        identifier = if_token(Kind::NONE) do
          AST::IdentifierLiteral.new(current_token.value).at(current_token.location)
        end || assert_token(Kind::IDENTIFIER) do
          AST::IdentifierLiteral.new(current_token.value).at(current_token.location)
        end

        identifier.location_end = next_token.location

        if is_test
          call = __parse_test_call(identifier)
          left = AST::TestExpression.new(left, identifier, call.argumentlist, call.keyword_arguments).at(left, call)

          if not_location
            left = AST::UnaryExpression.new("not", left).at(not_location)
          end
        else
          with_parenthesis = false
          if current_token.kind == Kind::LEFT_PAREN
            next_token
            with_parenthesis = true
          elsif config.liquid_compatibility_mode && current_token.kind == Kind::DICT_ASSIGN
            # django/liquid style format `val | filter: arg, arg`
            next_token
          end

          call = parse_call_expression identifier, with_parenthesis: with_parenthesis
          left = AST::FilterExpression.new(left, identifier, call.argumentlist, call.keyword_arguments).at(left, call)
        end
      else
        return left
      end
    end
  end

  private def __parse_test_call(identifier) : AST::CallExpression
    takes_argument = case current_token.kind
                     when Kind::STRING, Kind::INTEGER, Kind::FLOAT, Kind::BOOL, Kind::NONE,
                          Kind::LEFT_PAREN, Kind::LEFT_BRACKET, Kind::LEFT_CURLY
                       true
                     when Kind::IDENTIFIER
                       !current_token.value.in?("else", "or", "and", "if", "in", "is", "not")
                     else
                       false
                     end
    args = [] of AST::ExpressionNode
    args << parse_parenthesis_expression if takes_argument
    AST::CallExpression.new(identifier, AST::ExpressionList.new(args),
      Hash(AST::IdentifierLiteral, AST::ExpressionNode).new).at(identifier.location_start, current_token.location)
  end
end
