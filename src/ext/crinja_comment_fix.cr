# A `{# … #}` comment ends at its first `#}` (or `-#}`), as in Jinja2,
# whatever it contains.
#
# Upstream's comment scanner stopped at every `}}` and `%}` too and raised
# "Terminated <State:note> with '}}'", so commenting out template code
# (`{# {{ page.title }} #}`, `{# {% include "x.html" %} #}`) failed the
# build.
class Crinja::Parser::TemplateLexer
  def consume_note
    String.build do |io|
      io << current_char # = '{'
      io << next_char    # = '#'
      next_char

      if current_char == Symbol::TRIM_WHITESPACE
        @token.trim_left = true
      end

      loop do
        # check_for_end raises "Unterminated note" at the end of input.
        if (current_char == Char::ZERO || note_end_ahead?) && check_for_end(@stack.last)
          @stack.pop
          break
        end

        io << current_char
        next_char
      end
    end
  end

  # Is the cursor at `#}` / `-#}`, after optional whitespace?
  private def note_end_ahead? : Bool
    offset = peek_for_whitespace_offset(0)
    offset += 1 if peek_char(offset) == Symbol::TRIM_WHITESPACE
    peek_char(offset) == Symbol::NOTE && peek_char(offset + 1) == Symbol::POSTFIX
  end
end
