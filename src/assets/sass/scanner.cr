# Low-level character scanner for the SCSS parser.
#
# Tracks 1-based line/column positions and provides the small set of
# lexical primitives the parser is built on (identifiers, quoted strings,
# comments). Values and selectors are kept as verbatim text runs rather
# than a token stream — SCSS is CSS token soup, and preserving the source
# text exactly (minus comments) is what makes plain-CSS passthrough safe.
#
# Uses an Array(Char) for O(1) indexing; SCSS sources are small enough
# that the copy is irrelevant next to positional correctness.

require "./errors"

module Hwaro
  module Assets
    module Sass
      class Scanner
        getter path : String
        getter line : Int32
        getter column : Int32

        def initialize(source : String, @path : String)
          # A UTF-8 BOM is not content (dart-sass strips it too). Without
          # this, U+FEFF falls into the `ord > 0x7F` ident charset below and
          # a BOM'd partial embeds an invisible char into the first selector
          # it contributes mid-sheet.
          @chars = source.lchop('\u{FEFF}').chars
          @pos = 0
          @line = 1
          @column = 1
        end

        def eof? : Bool
          @pos >= @chars.size
        end

        def peek(offset : Int32 = 0) : Char?
          idx = @pos + offset
          idx < @chars.size ? @chars[idx] : nil
        end

        def advance : Char
          c = @chars[@pos]
          @pos += 1
          if c == '\n'
            @line += 1
            @column = 1
          else
            @column += 1
          end
          c
        end

        def error(message : String, line : Int32 = @line, column : Int32 = @column) : NoReturn
          raise SyntaxError.new(message, @path, line, column)
        end

        def ident_start?(c : Char?) : Bool
          return false unless c
          c.ascii_letter? || c == '_' || c == '-' || c.ord > 0x7F
        end

        def ident_char?(c : Char?) : Bool
          return false unless c
          c.ascii_alphanumeric? || c == '_' || c == '-' || c.ord > 0x7F
        end

        # Reads an identifier (CSS ident charset; no escape support).
        def read_ident : String
          String.build do |io|
            while ident_char?(peek)
              io << advance
            end
          end
        end

        # Skips whitespace and comments. Loud (/* */) comments are returned
        # to the caller one at a time when `yield_comments` is true so the
        # parser can preserve them as statement-level nodes; silent (//)
        # comments are always dropped.
        def skip_ws(& : String, Int32, Int32 -> Nil) : Nil
          loop do
            c = peek
            if c && c.ascii_whitespace?
              advance
            elsif c == '/' && peek(1) == '/'
              advance
              advance
              until eof? || peek == '\n'
                advance
              end
            elsif c == '/' && peek(1) == '*'
              start_line = @line
              start_col = @column
              text = read_loud_comment
              yield text, start_line, start_col
            else
              break
            end
          end
        end

        def skip_ws : Nil
          skip_ws { |_text, _line, _col| nil }
        end

        # Consumes "/* ... */" (cursor on the leading '/') and returns it
        # verbatim including delimiters.
        def read_loud_comment : String
          start_line = @line
          start_col = @column
          String.build do |io|
            io << advance # '/'
            io << advance # '*'
            loop do
              error("unterminated comment", start_line, start_col) if eof?
              c = advance
              io << c
              if c == '*' && peek == '/'
                io << advance
                break
              end
            end
          end
        end

        # Consumes a quoted string (cursor on the opening quote) and returns
        # it verbatim including quotes and escapes. Stops the scan at `#{`
        # boundaries only when the caller handles interpolation itself —
        # this primitive is interpolation-blind and used where a literal
        # string is required (e.g. @use/@import urls).
        def read_quoted : String
          quote = peek
          start_line = @line
          start_col = @column
          String.build do |io|
            io << advance # opening quote
            loop do
              error("unterminated string", start_line, start_col) if eof?
              c = advance
              io << c
              if c == '\\' && !eof?
                io << advance
              elsif c == quote
                break
              end
            end
          end
        end
      end
    end
  end
end
