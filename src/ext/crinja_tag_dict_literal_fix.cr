# A nested dict literal inside a `{% … %}` tag, as in Jinja2:
# `{% set nav = {"home": {"url": "/"}} %}`.
#
# Inside a tag the template lexer read every `}}` as the end of an
# `{{ … }}` expression and failed with "Terminated <State:tag> with '}}'",
# although the expression lexer still had a `{` open. Output expressions
# already defer to that bracket stack; a tag now does the same for a `}`
# that closes a literal. `%}` is still recognised as the tag end as before.
class Crinja::Parser::TemplateLexer
  def next_token : Token
    if @stack.last == State::TAG && !expression_lexer.stack_closed? &&
       peek_char(peek_for_whitespace_offset(0)) == Symbol::RIGHT_CURLY
      @token = expression_lexer.next_token
      return @token.dup
    end
    previous_def
  end
end
