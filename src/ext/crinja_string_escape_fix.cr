# String-literal escapes as Jinja2 reads them (Python's unicode-escape).
#
# Upstream knew only `\n`, `\\`, `\'` and `\"`, and silently DROPPED any
# other backslash together with the character after it: `'\t'` became an
# empty string, `'é'` became "00e9", and a regex literal such as
# `matching('\.png$')` lost its `\.` and matched something else. Now `\t`,
# `\r`, `\a`, `\b`, `\f`, `\v`, octal, `\xhh`, `\uXXXX` and `\UXXXXXXXX` decode, a
# backslash-newline is a line continuation, and an unknown escape keeps its
# backslash (`'\d'` stays `\d`), all as in Jinja2. A malformed `\x` / `\u`
# escape (an error in Jinja2) is kept literally.
abstract class Crinja::Parser::BaseLexer
  def consume_string
    @buffer.clear
    delimiter = current_char

    loop do
      char = next_char
      raise "Unterminated string literal" if char == Char::ZERO

      if char == delimiter
        next_char
        break
      elsif char == Symbol::STRING_ESCAPE
        consume_string_escape
      else
        @buffer << char
      end
    end

    @buffer.to_s
  end

  # Called with the cursor on the backslash.
  private def consume_string_escape
    char = next_char
    raise "Unterminated string literal" if char == Char::ZERO

    case char
    when 'n'  then @buffer << '\n'
    when 't'  then @buffer << '\t'
    when 'r'  then @buffer << '\r'
    when 'a'  then @buffer << '\a'
    when 'b'  then @buffer << '\b'
    when 'f'  then @buffer << '\f'
    when 'v'  then @buffer << '\v'
    when '\n' then nil # line continuation
    when '"', '\'', Symbol::STRING_ESCAPE
      @buffer << char
    when '0'..'7'
      code = char.to_i
      2.times do
        break unless peek_char.in?('0'..'7')
        code = code * 8 + next_char.to_i
      end
      @buffer << code.chr
    when 'x' then consume_hex_escape(char, 2)
    when 'u' then consume_hex_escape(char, 4)
    when 'U' then consume_hex_escape(char, 8)
    else
      @buffer << Symbol::STRING_ESCAPE << char
    end
  end

  private def consume_hex_escape(kind : Char, digits : Int32)
    hex = String.build do |io|
      digits.times do
        break unless peek_char.hex?
        io << next_char
      end
    end

    code = hex.size == digits ? hex.to_i?(16) : nil
    if code && code <= Char::MAX_CODEPOINT && !(0xD800..0xDFFF).includes?(code)
      @buffer << code.unsafe_chr
    else
      @buffer << Symbol::STRING_ESCAPE << kind << hex
    end
  end
end
