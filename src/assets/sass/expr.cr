# SassScript expression layer: lexer, Pratt parser, and evaluator.
#
# Expressions are parsed from the same `TextTemplate`s the statement
# parser already produces, so one machinery serves both worlds:
#
# - Lenient contexts (declaration/variable values, mixin arguments,
#   interpolation) call `Expr.parse` and only *use* the result when the
#   tree actually computes something (`Expr.computes?`) — otherwise the
#   legacy verbatim-text path runs and existing output stays
#   byte-identical. Parse or evaluation failures also fall back.
# - Strict contexts (@if/@while conditions, @each/@for headers, @return,
#   @use ... with) parse with `Expr.parse!` and surface every failure as
#   a located SyntaxError.
#
# `/` follows the classic Sass division rule (dart-sass 1.x semantics):
# it divides when either operand is "computed" (a variable, a known
# function call, parenthesized) or when the slash itself sits in a
# computing context (an operand of other arithmetic, a Sass function
# argument, a variable declaration, interpolation, control flow).
# Otherwise the operands render joined by a literal `/`, which is what
# keeps CSS shorthands like `font: 12px/1.5` and `grid-area: 1 / 2` safe.
#
# CSS-owned function spans (`url(...)`, `calc(...)`, `var(...)`, ...)
# lex as verbatim raw tokens and are never evaluated.

require "./ast"
require "./value"

module Hwaro
  module Assets
    module Sass
      module Expr
        # ---------------------------------------------------------------
        # Expression AST
        # ---------------------------------------------------------------

        abstract class Node
        end

        class Lit < Node
          getter value : Value

          def initialize(@value : Value)
          end
        end

        class VarE < Node
          getter name : String
          getter ns : String?

          def initialize(@name, @ns)
          end
        end

        class InterpE < Node
          getter template : Ast::TextTemplate

          def initialize(@template)
          end
        end

        # Quoted string; parts are raw text runs and interpolation
        # templates.
        class StrE < Node
          getter parts : Array(String | Ast::TextTemplate)
          getter quote : Char

          def initialize(@parts, @quote)
          end
        end

        # Adjacent atoms with no whitespace between them (`10px#{$u}`,
        # `-#{$a}x`). Evaluates to the concatenated text.
        class ConcatE < Node
          getter parts : Array(Node)

          def initialize(@parts)
          end
        end

        class ListE < Node
          getter items : Array(Node)
          getter sep : ListV::Sep
          getter bracketed : Bool

          def initialize(@items, @sep, @bracketed = false)
          end
        end

        # Key/value expression pair (a record — tuples of abstract class
        # elements crash Crystal's codegen).
        record MapPair, key : Node, value : Node

        class MapE < Node
          getter pairs : Array(MapPair)

          def initialize(@pairs)
          end
        end

        record KwargE, name : String, value : Node

        class ParenE < Node
          getter inner : Node

          def initialize(@inner)
          end
        end

        class Unary < Node
          getter op : Symbol # :minus, :plus, :not
          getter operand : Node

          def initialize(@op, @operand)
          end
        end

        class Binary < Node
          getter op : Symbol # :or, :and, :eq, :neq, :lt, :gt, :le, :ge, :plus, :minus, :times, :div, :mod
          getter left : Node
          getter right : Node

          def initialize(@op, @left, @right)
          end
        end

        class CallE < Node
          getter ns : String?
          getter name : String
          getter args : Array(Node)
          getter kwargs : Array(KwargE)
          getter spread : Node?

          def initialize(@ns, @name, @args, @kwargs, @spread)
          end
        end

        # A CSS-owned function span (`calc(...)`, `var(...)`, `url(...)`)
        # whose argument text is interrupted by interpolation or `$var`
        # pieces: `calc(#{$a} + 2px)`, `var(--#{$prefix}x)`. The span is
        # never evaluated as Sass — the dynamic pieces resolve to text and
        # splice back into the verbatim span (dart-sass treats these spans
        # as unparsed too). Templates in `parts` are either a real `#{...}`
        # body or a synthesized single-`$var` template.
        class RawSpanE < Node
          getter parts : Array(String | Ast::TextTemplate)

          def initialize(@parts)
          end
        end

        # `&` as a SassScript value: the parent selector as a comma list,
        # or null at the root (dart-sass semantics). What makes the
        # `#{if(&, "&", "")}` mixin idiom work.
        class AmpE < Node
        end

        # ---------------------------------------------------------------
        # Tokens
        # ---------------------------------------------------------------

        # :nodoc:
        enum TokKind
          Number
          Ident     # includes and/or/not/true/false/null (parser decides)
          QualIdent # ns.name (only meaningful before a call paren)
          Str
          Var
          Interp
          Raw     # hex colors, u+ranges, url(...)/calc(...) spans
          RawSpan # url(...)/calc(...) span with interpolation/$var pieces
          Amp     # `&` parent-selector reference
          LParen
          RParen
          LBracket
          RBracket
          Comma
          Colon
          Slash
          Plus
          Minus
          Star
          Percent
          EqEq
          NotEq
          Lt
          Gt
          Le
          Ge
          Ellipsis
        end

        # :nodoc:
        class Tok
          getter kind : TokKind
          getter text : String
          getter space_before : Bool
          # Number payload
          getter num_value : Float64
          getter num_unit : String
          # Var payload
          getter ns : String?
          # Str payload
          getter str_parts : Array(String | Ast::TextTemplate)?
          getter quote : Char
          # Interp payload
          getter template : Ast::TextTemplate?

          def initialize(@kind, @text, @space_before,
                         @num_value = 0.0, @num_unit = "", @ns = nil,
                         @str_parts = nil, @quote = '"', @template = nil)
          end
        end

        class ParseFailure < Exception
        end

        # A ParseFailure raised specifically by the MAX_DEPTH guard.
        #
        # Distinguished from an ordinary unparsable expression because the two
        # deserve different handling in lenient contexts: an unparsable value
        # falls back to verbatim text on purpose (that fallback is what keeps
        # hwaro's Sass output byte-compatible), whereas hitting the depth cap
        # means the declaration ships literally — `a{width:((((…}` — which is
        # not valid CSS. The build must not do that silently just because it no
        # longer crashes.
        class DepthExceeded < ParseFailure
        end

        # ---------------------------------------------------------------
        # Lexer: TextTemplate pieces -> token list
        # ---------------------------------------------------------------

        # Function names whose parenthesized span belongs to CSS and must
        # pass through verbatim, never parsed as Sass arguments. `var()` is
        # deliberately NOT here: dart-sass parses its fallback argument as
        # SassScript (`var(--x, escape-svg($d))` must call the function),
        # and the computes? gate still passes plain `var(--x, 10px)`
        # through verbatim.
        RAW_SPAN_FNS = %w[url env attr counter counters expression format local]

        # :nodoc:
        class Lexer
          def initialize(template : Ast::TextTemplate)
            @pieces = template.pieces
            @piece_i = 0
            @char_i = 0
            @toks = [] of Tok
            @space = false
          end

          def lex : Array(Tok)
            loop do
              piece = current_piece
              break unless piece
              case piece
              in String
                lex_string_piece
              in Ast::VarRef
                push(Tok.new(TokKind::Var, piece.name, @space, ns: piece.namespace))
                next_piece
              in Ast::Interp
                push(Tok.new(TokKind::Interp, "", @space, template: piece.inner))
                next_piece
              end
            end
            @toks
          end

          private def current_piece
            @piece_i < @pieces.size ? @pieces[@piece_i] : nil
          end

          private def next_piece
            @piece_i += 1
            @char_i = 0
          end

          private def push(tok : Tok)
            @toks << tok
            @space = false
          end

          private def text : String
            @pieces[@piece_i].as(String)
          end

          private def peek(offset = 0) : Char?
            t = text
            idx = @char_i + offset
            idx < t.size ? t[idx] : nil
          end

          private def advance : Char
            c = text[@char_i]
            @char_i += 1
            c
          end

          private def eop? : Bool
            @char_i >= text.size
          end

          private def fail : NoReturn
            raise ParseFailure.new("unlexable")
          end

          private def lex_string_piece : Nil
            while c = peek
              if c.ascii_whitespace?
                advance
                @space = true
              elsif c.ascii_number? || (c == '.' && peek(1).try(&.ascii_number?))
                lex_number
              elsif c == '"' || c == '\''
                lex_quoted(c)
              elsif c == '#'
                lex_hash
              elsif ident_start?(c)
                lex_ident
              else
                lex_operator(c)
              end
            end
            # Whitespace does not exist at piece boundaries: `10#{$u}` is
            # adjacent, `10 #{$u}` had its space inside the string piece.
            next_piece
          end

          private def ident_start?(c : Char) : Bool
            return true if c.ascii_letter? || c == '_' || c.ord > 0x7F
            return false unless c == '-'
            n = peek(1)
            !n.nil? && (n.ascii_letter? || n == '_' || n == '-' || n.ord > 0x7F)
          end

          private def ident_char?(c : Char?) : Bool
            return false unless c
            c.ascii_alphanumeric? || c == '_' || c == '-' || c.ord > 0x7F
          end

          private def lex_number : Nil
            start = @char_i
            while (c = peek) && c.ascii_number?
              advance
            end
            if peek == '.' && peek(1).try(&.ascii_number?)
              advance
              while (c = peek) && c.ascii_number?
                advance
              end
            end
            # Scientific notation (2e3, 1.5e-2).
            if (c = peek) && (c == 'e' || c == 'E')
              off = (peek(1) == '+' || peek(1) == '-') ? 2 : 1
              if peek(off).try(&.ascii_number?)
                advance
                advance if peek == '+' || peek == '-'
                while (c2 = peek) && c2.ascii_number?
                  advance
                end
              end
            end
            num_end = @char_i
            # Unit: letters only (px, em, dvh, ...) or a single %. `-`
            # after a number is an operator or sign, never a unit char.
            if peek == '%'
              advance
            else
              while (c = peek) && (c.ascii_letter? || c.ord > 0x7F)
                advance
              end
            end
            lexeme = text[start...@char_i]
            unit = text[num_end...@char_i]
            value = text[start...num_end].to_f64? || fail
            push(Tok.new(TokKind::Number, lexeme, @space, num_value: value, num_unit: unit))
          end

          # Quoted string; may span pieces when interpolation splits it.
          private def lex_quoted(quote : Char) : Nil
            space = @space
            advance # opening quote
            parts = [] of String | Ast::TextTemplate
            buf = String::Builder.new
            loop do
              if eop?
                # The string continues past this piece: one or more Interp
                # pieces follow (`"--#{$a}#{$b}rest"`), then a String piece
                # with the rest.
                parts << buf.to_s
                buf = String::Builder.new
                loop do
                  @piece_i += 1
                  @char_i = 0
                  nxt = current_piece
                  fail unless nxt
                  case nxt
                  in String
                    break
                  in Ast::Interp
                    parts << nxt.inner
                  in Ast::VarRef
                    fail # `$var` is literal inside strings; never a piece here
                  end
                end
                next
              end
              c = advance
              if c == '\\'
                buf << c
                buf << advance unless eop?
              elsif c == quote
                break
              else
                buf << c
              end
            end
            tail = buf.to_s
            parts << tail if !tail.empty? || parts.empty?
            @toks << Tok.new(TokKind::Str, "", space, str_parts: parts, quote: quote)
            @space = false
          end

          # `#hex` colors pass through as raw tokens; anything else after
          # `#` is unlexable (`#{` never appears inside String pieces).
          private def lex_hash : Nil
            start = @char_i
            advance # '#'
            fail unless peek.try(&.ascii_alphanumeric?)
            while peek.try(&.ascii_alphanumeric?)
              advance
            end
            push(Tok.new(TokKind::Raw, text[start...@char_i], @space))
          end

          private def lex_ident : Nil
            start = @char_i
            advance
            while ident_char?(peek)
              advance
            end
            name = text[start...@char_i]

            # `U+0025-00FF` unicode-range tokens.
            if (name == "u" || name == "U") && peek == '+' && (n = peek(1)) &&
               (n.ascii_alphanumeric? || n == '?')
              advance # '+'
              while (c = peek) && (c.ascii_alphanumeric? || c == '?' || c == '-')
                advance
              end
              push(Tok.new(TokKind::Raw, text[start...@char_i], @space))
              return
            end

            # CSS-owned spans: consume the balanced parens verbatim.
            if peek == '(' && raw_span_fn?(name)
              lex_raw_span(start)
              return
            end

            # `ns.name` qualified identifier (function calls).
            if peek == '.' && (n = peek(1)) && (n.ascii_letter? || n == '_' || n.ord > 0x7F)
              advance # '.'
              while ident_char?(peek)
                advance
              end
              push(Tok.new(TokKind::QualIdent, text[start...@char_i], @space))
              return
            end

            push(Tok.new(TokKind::Ident, name, @space))
          end

          private def raw_span_fn?(name : String) : Bool
            down = name.downcase
            RAW_SPAN_FNS.includes?(down) || down.ends_with?("calc")
          end

          # Balanced-paren verbatim span starting at `start` (cursor on
          # the opening paren). Interpolation or `$var` pieces inside the
          # span (`calc(#{$a} + 2px)`, `var(--#{$p}x)`) split the String
          # piece; the span then continues across those pieces and lexes
          # as a RawSpan token whose dynamic parts resolve at eval time.
          private def lex_raw_span(start : Int32) : Nil
            space = @space
            parts = [] of String | Ast::TextTemplate
            buf = String::Builder.new
            buf << text[start...@char_i] # function name (cursor on '(')
            depth = 0
            done = false
            until done
              if eop?
                # The span continues in the next piece(s): flush the text
                # run and absorb dynamic pieces until text resumes.
                flushed = buf.to_s
                parts << flushed unless flushed.empty?
                buf = String::Builder.new
                loop do
                  @piece_i += 1
                  @char_i = 0
                  piece = current_piece
                  fail unless piece # unterminated span at template end
                  case piece
                  in String
                    break
                  in Ast::Interp
                    parts << piece.inner
                  in Ast::VarRef
                    parts << Ast::TextTemplate.new(
                      Array(Ast::Piece){piece}, piece.line, piece.column)
                  end
                end
                next
              end
              c = advance
              buf << c
              case c
              when '"', '\''
                quote = c
                loop do
                  fail if eop? # interpolation inside a quoted span string
                  sc = advance
                  buf << sc
                  if sc == '\\'
                    buf << advance unless eop?
                  elsif sc == quote
                    break
                  end
                end
              when '('
                depth += 1
              when ')'
                depth -= 1
                done = true if depth == 0
              end
            end
            tail = buf.to_s
            parts << tail unless tail.empty?
            if parts.size == 1 && (only = parts[0]).is_a?(String)
              @toks << Tok.new(TokKind::Raw, only, space)
            else
              @toks << Tok.new(TokKind::RawSpan, "", space, str_parts: parts)
            end
            @space = false
          end

          private def lex_operator(c : Char) : Nil
            case c
            when '('
              advance
              push(Tok.new(TokKind::LParen, "(", @space))
            when ')'
              advance
              push(Tok.new(TokKind::RParen, ")", @space))
            when '['
              advance
              push(Tok.new(TokKind::LBracket, "[", @space))
            when ']'
              advance
              push(Tok.new(TokKind::RBracket, "]", @space))
            when ','
              advance
              push(Tok.new(TokKind::Comma, ",", @space))
            when ':'
              advance
              push(Tok.new(TokKind::Colon, ":", @space))
            when '/'
              advance
              push(Tok.new(TokKind::Slash, "/", @space))
            when '+'
              advance
              push(Tok.new(TokKind::Plus, "+", @space))
            when '-'
              lex_minus
            when '*'
              advance
              push(Tok.new(TokKind::Star, "*", @space))
            when '%'
              advance
              push(Tok.new(TokKind::Percent, "%", @space))
            when '&'
              advance
              push(Tok.new(TokKind::Amp, "&", @space))
            when '='
              advance
              fail unless peek == '='
              advance
              push(Tok.new(TokKind::EqEq, "==", @space))
            when '!'
              advance
              if peek == '='
                advance
                push(Tok.new(TokKind::NotEq, "!=", @space))
              else
                # `!important` as a SassScript value (dart-sass
                # ImportantExpression) — the utilities-API idiom
                # `$value if($enable-important, !important, null)`.
                # (A trailing `!important` flag never reaches this lexer;
                # the statement parser strips it first.)
                off = 0
                while peek(off).try(&.ascii_whitespace?)
                  off += 1
                end
                fail unless word_at?(off, "important")
                (off + 9).times { advance }
                push(Tok.new(TokKind::Ident, "!important", @space))
              end
            when '<'
              advance
              if peek == '='
                advance
                push(Tok.new(TokKind::Le, "<=", @space))
              else
                push(Tok.new(TokKind::Lt, "<", @space))
              end
            when '>'
              advance
              if peek == '='
                advance
                push(Tok.new(TokKind::Ge, ">=", @space))
              else
                push(Tok.new(TokKind::Gt, ">", @space))
              end
            when '.'
              if peek(1) == '.' && peek(2) == '.'
                advance
                advance
                advance
                push(Tok.new(TokKind::Ellipsis, "...", @space))
              else
                fail
              end
            else
              fail
            end
          end

          # `-` disambiguation: a sign when it starts a number and the
          # previous token can't end an operand (`(-5px`, `, -5px`); a
          # minus operator when a number follows an operand directly
          # (`10px-5px`). `-ident` always lexes as an identifier.
          private def lex_minus : Nil
            n = peek(1)
            if n && (n.ascii_number? || (n == '.' && peek(2).try(&.ascii_number?)))
              if prev_operand? && !@space
                advance
                push(Tok.new(TokKind::Minus, "-", false))
              else
                start = @char_i
                advance
                lex_number_after_sign(start)
              end
            elsif n && (n.ascii_letter? || n == '_' || n == '-' || n.ord > 0x7F)
              lex_ident
            else
              advance
              push(Tok.new(TokKind::Minus, "-", @space))
            end
          end

          private def lex_number_after_sign(start : Int32) : Nil
            space = @space
            lex_number
            last = @toks.pop
            lexeme = text[start...@char_i]
            @toks << Tok.new(TokKind::Number, lexeme, space,
              num_value: -last.num_value, num_unit: last.num_unit)
            @space = false
          end

          # Case-insensitive keyword match at `offset` chars ahead, ending
          # at a non-ident boundary.
          private def word_at?(offset : Int32, word : String) : Bool
            word.each_char_with_index do |wc, i|
              c = peek(offset + i)
              return false unless c && c.downcase == wc
            end
            !ident_char?(peek(offset + word.size))
          end

          private def prev_operand? : Bool
            last = @toks.last?
            return false unless last
            case last.kind
            when TokKind::Number, TokKind::Ident, TokKind::Str, TokKind::Var,
                 TokKind::Interp, TokKind::Raw, TokKind::RawSpan, TokKind::Amp,
                 TokKind::RParen, TokKind::RBracket
              true
            else
              false
            end
          end
        end

        # ---------------------------------------------------------------
        # Parser (precedence climbing)
        # ---------------------------------------------------------------

        # Grammar, loosest first:
        #   comma-list > space-list > or > and >
        #   equality > relational > additive > multiplicative (*, /, %) >
        #   unary (-, +, not) > concat/primary
        # `/` parses at multiplicative precedence (dart-sass): whether it
        # divides or renders as a literal slash is decided at eval time.
        # :nodoc:
        class Parser
          # Cap on expression nesting depth. This is a recursive-descent
          # parser, so every level of `(`, `[`, call argument or unary
          # operator in the source maps 1:1 onto native stack frames — a
          # stylesheet with a few thousand nested parens
          # (`width: ((((…1…))))`) exhausted the stack and killed the whole
          # build with SIGSEGV, where every other Sass limit
          # (MAX_INCLUDE_DEPTH, MAX_CALL_DEPTH, MAX_WHILE_ITERATIONS in the
          # evaluator) reports a clean located error. Counted in parse_unary
          # because every path from parse_comma down to a primary passes
          # through it exactly once per nesting level, so one counter bounds
          # parens, brackets, call arguments and unary chains alike. 512 is
          # far past anything a hand-written or generated stylesheet nests,
          # and exceeding it degrades to the same outcome as any other
          # unparsable expression: verbatim text in lenient value contexts,
          # a located error where `parse!` is used.
          MAX_DEPTH = 512

          def initialize(@toks : Array(Tok))
            @pos = 0
            @depth = 0
          end

          def parse : Node
            node = parse_comma
            fail unless eof?
            node
          end

          private def fail : NoReturn
            raise ParseFailure.new("unparsable")
          end

          private def eof? : Bool
            @pos >= @toks.size
          end

          private def peek : Tok?
            @toks[@pos]?
          end

          private def advance : Tok
            tok = @toks[@pos]
            @pos += 1
            tok
          end

          private def match?(kind : TokKind) : Bool
            peek.try(&.kind) == kind
          end

          private def accept(kind : TokKind) : Bool
            if match?(kind)
              @pos += 1
              true
            else
              false
            end
          end

          private def parse_comma : Node
            first = parse_space
            return first unless match?(TokKind::Comma)
            items = [first]
            while accept(TokKind::Comma)
              break if eof? # trailing comma
              items << parse_space
            end
            ListE.new(items, ListV::Sep::Comma)
          end

          private def parse_space : Node
            first = parse_or
            return first unless operand_start?
            items = [first]
            while operand_start?
              items << parse_or
            end
            ListE.new(items, ListV::Sep::Space)
          end

          # True when the current token can begin a new space-list item.
          private def operand_start? : Bool
            tok = peek
            return false unless tok
            case tok.kind
            when TokKind::Number, TokKind::Ident, TokKind::QualIdent, TokKind::Str,
                 TokKind::Var, TokKind::Interp, TokKind::Raw, TokKind::RawSpan,
                 TokKind::Amp, TokKind::LParen, TokKind::LBracket
              true
            when TokKind::Minus, TokKind::Plus
              # `a -b` starts a new item; `a - b` is subtraction and was
              # consumed by parse_additive before we got here.
              tok.space_before && !next_space?
            else
              false
            end
          end

          private def next_space? : Bool
            nxt = @toks[@pos + 1]?
            nxt.nil? || nxt.space_before
          end

          private def parse_or : Node
            left = parse_and
            while (tok = peek) && tok.kind.ident? && tok.text == "or"
              @pos += 1
              left = Binary.new(:or, left, parse_and)
            end
            left
          end

          private def parse_and : Node
            left = parse_equality
            while (tok = peek) && tok.kind.ident? && tok.text == "and"
              @pos += 1
              left = Binary.new(:and, left, parse_equality)
            end
            left
          end

          private def parse_equality : Node
            left = parse_relational
            loop do
              if accept(TokKind::EqEq)
                left = Binary.new(:eq, left, parse_relational)
              elsif accept(TokKind::NotEq)
                left = Binary.new(:neq, left, parse_relational)
              else
                break
              end
            end
            left
          end

          private def parse_relational : Node
            left = parse_additive
            loop do
              if accept(TokKind::Lt)
                left = Binary.new(:lt, left, parse_additive)
              elsif accept(TokKind::Gt)
                left = Binary.new(:gt, left, parse_additive)
              elsif accept(TokKind::Le)
                left = Binary.new(:le, left, parse_additive)
              elsif accept(TokKind::Ge)
                left = Binary.new(:ge, left, parse_additive)
              else
                break
              end
            end
            left
          end

          private def parse_additive : Node
            left = parse_multiplicative
            loop do
              tok = peek
              break unless tok
              if tok.kind.plus? && binary_shape?(tok)
                @pos += 1
                left = Binary.new(:plus, left, parse_multiplicative)
              elsif tok.kind.minus? && binary_shape?(tok)
                @pos += 1
                left = Binary.new(:minus, left, parse_multiplicative)
              else
                break
              end
            end
            left
          end

          # `a - b` and `a- b` and `10px-5px` (no space either side) are
          # binary; `a -b` is not (it starts a new space-list item).
          private def binary_shape?(tok : Tok) : Bool
            !(tok.space_before && !next_space?)
          end

          private def parse_multiplicative : Node
            left = parse_unary
            loop do
              if accept(TokKind::Star)
                left = Binary.new(:times, left, parse_unary)
              elsif accept(TokKind::Slash)
                left = Binary.new(:div, left, parse_unary)
              elsif (tok = peek) && tok.kind.percent?
                @pos += 1
                left = Binary.new(:mod, left, parse_unary)
              else
                break
              end
            end
            left
          end

          # `not` is a unary operator binding tighter than every binary
          # operator except concatenation — `not 1 == 2` is `(not 1) == 2`,
          # not `not (1 == 2)`. Parsing it between `and` and `==` inverted
          # the result of any `not` applied to a comparison.
          private def parse_unary : Node
            # Sole recursion choke point — see MAX_DEPTH.
            @depth += 1
            begin
              raise DepthExceeded.new("expression nesting exceeds #{MAX_DEPTH}") if @depth > MAX_DEPTH
              if (tok = peek) && tok.kind.ident? && tok.text == "not"
                @pos += 1
                Unary.new(:not, parse_unary)
              elsif accept(TokKind::Minus)
                Unary.new(:minus, parse_unary)
              elsif accept(TokKind::Plus)
                Unary.new(:plus, parse_unary)
              else
                parse_concat
              end
            ensure
              @depth -= 1
            end
          end

          # Adjacent primaries with no whitespace merge into a concat
          # atom (`10#{$u}`, `#{$a}-suffix`). A lone primary stays itself.
          private def parse_concat : Node
            first = parse_primary
            parts = [first]
            while (tok = peek) && !tok.space_before && concat_continuer?(tok)
              parts << parse_primary
            end
            parts.size == 1 ? first : ConcatE.new(parts)
          end

          private def concat_continuer?(tok : Tok) : Bool
            case tok.kind
            when TokKind::Interp
              true
            when TokKind::Number, TokKind::Ident, TokKind::Str, TokKind::Var,
                 TokKind::Raw, TokKind::RawSpan
              # Only join runs that involve interpolation; `10px 5px`
              # spacing errors and the like should fail-fast instead.
              @toks[@pos - 1].kind.interp?
            else
              false
            end
          end

          private def parse_primary : Node
            tok = peek || fail
            case tok.kind
            when TokKind::Number
              @pos += 1
              Lit.new(Number.new(tok.num_value, tok.num_unit, tok.text))
            when TokKind::Str
              @pos += 1
              parts = tok.str_parts || fail
              StrE.new(parts, tok.quote)
            when TokKind::Var
              @pos += 1
              VarE.new(tok.text, tok.ns)
            when TokKind::Interp
              @pos += 1
              template = tok.template || fail
              InterpE.new(template)
            when TokKind::Raw
              @pos += 1
              Lit.new(Raw.new(tok.text))
            when TokKind::RawSpan
              @pos += 1
              parts = tok.str_parts || fail
              RawSpanE.new(parts)
            when TokKind::Amp
              @pos += 1
              AmpE.new
            when TokKind::Ident, TokKind::QualIdent
              parse_ident_primary
            when TokKind::LParen
              parse_paren
            when TokKind::LBracket
              parse_bracket
            else
              fail
            end
          end

          private def parse_ident_primary : Node
            tok = advance
            if (nxt = peek) && nxt.kind.l_paren? && !nxt.space_before
              return parse_call(tok)
            end
            fail if tok.kind.qual_ident? # bare ns.name without a call
            case tok.text
            when "true"  then Lit.new(BoolV.new(true))
            when "false" then Lit.new(BoolV.new(false))
            when "null"  then Lit.new(NullV.new)
            else              Lit.new(Str.new(tok.text, quoted: false))
            end
          end

          private def parse_call(name_tok : Tok) : Node
            ns = nil
            name = name_tok.text
            if name_tok.kind.qual_ident?
              ns, _, name = name.rpartition('.')
            end
            advance # '('
            args = [] of Node
            kwargs = [] of KwargE
            spread : Node? = nil
            loop do
              break if accept(TokKind::RParen)
              fail if eof?
              fail if spread # arguments after a spread
              if (v = peek) && v.kind.var? && @toks[@pos + 1]?.try(&.kind.colon?)
                kw = advance.text
                advance # ':'
                kwargs << KwargE.new(kw, parse_space)
              else
                value = parse_space
                if accept(TokKind::Ellipsis)
                  fail unless kwargs.empty?
                  spread = value
                else
                  fail unless kwargs.empty? # positional after keyword
                  args << value
                end
              end
              break if accept(TokKind::RParen)
              fail unless accept(TokKind::Comma)
            end
            CallE.new(ns, name, args, kwargs, spread)
          end

          # `(...)`: empty list, map literal, or grouping parens.
          private def parse_paren : Node
            advance # '('
            return Lit.new(ListV.new(Array(Value).new, ListV::Sep::Space)) if accept(TokKind::RParen)

            first = parse_space
            if accept(TokKind::Colon)
              first_val = parse_space
              pairs = Array(MapPair).new
              pairs << MapPair.new(first, first_val)
              while accept(TokKind::Comma)
                break if match?(TokKind::RParen) # trailing comma
                key = parse_space
                fail unless accept(TokKind::Colon)
                pairs << MapPair.new(key, parse_space)
              end
              fail unless accept(TokKind::RParen)
              return MapE.new(pairs)
            end

            if match?(TokKind::Comma)
              items = [first]
              while accept(TokKind::Comma)
                break if match?(TokKind::RParen) # trailing comma
                items << parse_space
              end
              fail unless accept(TokKind::RParen)
              # Wrapped in ParenE so the parens count as work (`computes?`):
              # `(1, 2)` is Sass-only syntax — the verbatim path would ship
              # the parens into CSS, and `#{(1, 2)}` must interpolate as
              # `1, 2` (dart-sass parity).
              return ParenE.new(ListE.new(items, ListV::Sep::Comma))
            end

            fail unless accept(TokKind::RParen)
            ParenE.new(first)
          end

          private def parse_bracket : Node
            advance # '['
            items = [] of Node
            sep = ListV::Sep::Space
            unless match?(TokKind::RBracket)
              first = parse_space
              if match?(TokKind::Comma)
                items << first
                sep = ListV::Sep::Comma
                while accept(TokKind::Comma)
                  break if match?(TokKind::RBracket)
                  items << parse_space
                end
              elsif first.is_a?(ListE) && !first.bracketed
                # parse_space already consumed the whole space run as
                # one inner list — its items ARE the bracketed list's items
                # (`[1 2 3]` is a 3-element bracketed space list, not a
                # 1-element list holding `(1 2 3)`).
                items = first.items
                sep = first.sep
              else
                items << first
              end
            end
            fail unless accept(TokKind::RBracket)
            ListE.new(items, sep, bracketed: true)
          end
        end

        # ---------------------------------------------------------------
        # Public API
        # ---------------------------------------------------------------

        # Parses a template into an expression tree; nil when the text is
        # outside the expression grammar (lenient callers then use the
        # legacy verbatim path).
        def self.parse(template : Ast::TextTemplate) : Node?
          toks = Lexer.new(template).lex
          return if toks.empty?
          Parser.new(toks).parse
        rescue DepthExceeded
          # The lenient fallback ships the value's raw lexeme, which for a
          # deeply nested expression is `((((…1…))))` — syntactically invalid
          # CSS. Silence here is how an author deploys a broken stylesheet
          # after a build that exited 0 with no diagnostic at all.
          Logger.warn "Sass expression nesting exceeds #{Parser::MAX_DEPTH} levels; the value is emitted verbatim and may not be valid CSS. Simplify the nested parentheses/calls in this declaration."
          nil
        rescue ParseFailure
          nil
        end

        # Strict parse for control-flow contexts. Every ParseFailure —
        # the lexer's included — must convert to SoftEvalError here: a raw
        # ParseFailure escaping the compiler bypasses error classification
        # entirely and surfaces as an unlocated crash.
        def self.parse!(template : Ast::TextTemplate) : Node
          toks = begin
            Lexer.new(template).lex
          rescue ParseFailure
            raise SoftEvalError.new("invalid expression")
          end
          raise SoftEvalError.new("expected expression") if toks.empty?
          begin
            Parser.new(toks).parse
          rescue ex : DepthExceeded
            raise SoftEvalError.new(ex.message || "invalid expression")
          rescue ParseFailure
            raise SoftEvalError.new("invalid expression")
          end
        end

        # True when this node, used as a `/` operand, forces the slash to
        # divide (the classic Sass rule): a variable reference, a function
        # call, or grouping parens. Unary wrappers force iff their operand
        # does (`-1/2` stays literal, `-$a/2` divides — dart-sass parity).
        def self.div_operand_forces?(node : Node) : Bool
          case node
          when VarE, CallE, ParenE
            true
          when Unary
            div_operand_forces?(node.operand)
          when Binary
            # A nested arithmetic result is a computed value.
            node.op != :div || div_operand_forces?(node.left) || div_operand_forces?(node.right)
          else
            false
          end
        end

        # Division with the math.div unit rules plus convertible-group
        # cancelling: same units (or convertible ones) cancel, a unitless
        # divisor keeps the numerator's unit.
        # Folds a verbatim `calc(...)` span to the single number dart-sass
        # would emit (`calc(10px + 5px * 2)` → `20px`, `calc(9 / 21 * 100%)`
        # → `42.8571428571%`). nil when the contents aren't statically
        # foldable — unknown functions (`var()`, `env()`), incompatible or
        # unitless↔united addition, keywords — in which case the span
        # passes through verbatim as before (valid CSS the browser
        # computes itself; a partial rewrite of working CSS buys nothing).
        def self.fold_calc(text : String) : Number?
          stripped = text.strip
          return unless stripped.ends_with?(')')
          paren = stripped.index('(')
          return unless paren
          return unless stripped[0...paren].compare("calc", case_insensitive: true) == 0
          inner = stripped[(paren + 1)...-1]
          template = Ast::TextTemplate.new([inner.as(Ast::Piece)], 1, 1)
          node = parse(template)
          return unless node
          result = fold_calc_node(node)
          return unless result && result.value.finite?
          # A fresh Number: a lone literal keeps its lexeme (`calc(1e3px)`
          # must print `1000px`, not the lexeme).
          Number.new(result.value, result.unit)
        rescue SoftEvalError
          nil
        end

        private def self.fold_calc_node(node : Node) : Number?
          case node
          when Lit
            case value = node.value
            when Number then value
            when Raw    then fold_calc(value.text) # a nested `calc(...)` span
            end
          when ParenE
            fold_calc_node(node.inner)
          when Unary
            operand = fold_calc_node(node.operand)
            return unless operand
            case node.op
            when :minus then Number.new(-operand.value, operand.unit)
            when :plus  then operand
            end
          when Binary
            left = fold_calc_node(node.left)
            right = left ? fold_calc_node(node.right) : nil
            return unless left && right
            case node.op
            when :plus, :minus
              # CSS calc rejects unitless↔united addition (dart-sass
              # errors there); decline the fold, keep the span verbatim.
              return if left.unit.empty? != right.unit.empty?
              return unless left.compatible_unit?(right)
              rv = left.unit.empty? ? right.value : left.coerce_value(right)
              Number.new(node.op == :plus ? left.value + rv : left.value - rv,
                left.result_unit(right))
            when :times
              return if !left.unit.empty? && !right.unit.empty?
              Number.new(left.value * right.value, left.unit.empty? ? right.unit : left.unit)
            when :div
              # Zero divides to Infinity (CSS calc semantics); the final
              # finite check in fold_calc declines the whole fold then,
              # but an infinite INTERMEDIATE may still lose a min/max.
              value, unit = divide_numbers(left, right)
              Number.new(value, unit)
            end
          when CallE
            fold_calc_call(node)
          end
        end

        # `min`/`max`/`clamp` nested in (or wrapping) a foldable
        # calculation: fold when every argument folds and the units agree
        # (identical, all-unitless, or convertible).
        private def self.fold_calc_call(node : CallE) : Number?
          return unless node.ns.nil? && node.kwargs.empty? && node.spread.nil?
          name = node.name.downcase
          return unless name == "min" || name == "max" || name == "clamp"
          return if node.args.empty?
          return if name == "clamp" && node.args.size != 3
          args = [] of Number
          node.args.each do |arg|
            folded = fold_calc_node(arg)
            return unless folded
            args << folded
          end
          basis = args.find { |n| !n.unit.empty? }
          values = [] of Float64
          args.each do |n|
            if (b = basis) && !n.unit.empty?
              values << (n.unit == b.unit ? n.value : b.coerce_value(n))
            else
              # Unitless compares by raw value even against united
              # operands (dart folds `calc(min(5, 2px))` to `2px`).
              values << n.value
            end
          end
          case name
          when "min"
            best = 0
            values.each_with_index { |v, i| best = i if v < values[best] }
            args[best]
          when "max"
            best = 0
            values.each_with_index { |v, i| best = i if v > values[best] }
            args[best]
          else
            values[1] < values[0] ? args[0] : (values[1] > values[2] ? args[2] : args[1])
          end
        end

        # A slash run that was PARSED as `a / b` but never forced to
        # divide (`min(10 / 2, 8)`) folds to its division when every
        # element is a plain number — dart-sass's lazy-slash numbers
        # divide the moment a numeric context coerces them. nil for
        # constructed slash lists (`list.slash`; only lazy_slash pairs
        # divide — dart errors on math over a real slash list) and when
        # any element isn't a number. A zero divisor folds to Infinity,
        # exactly as dart's lazy division does (`min(10 / 0, 8)` is `8`).
        def self.slash_division?(list : ListV) : Number?
          return unless list.lazy_slash?
          return if list.bracketed || list.items.size < 2
          return unless list.sep == ListV::Sep::Slash
          result : Number? = nil
          list.items.each do |item|
            n = item.as?(Number)
            return unless n
            if prev = result
              value, unit = divide_numbers(prev, n)
              result = Number.new(value, unit)
            else
              result = n
            end
          end
          result
        rescue SoftEvalError
          nil
        end

        def self.divide_numbers(ln : Number, rn : Number) : {Float64, String}
          if ln.unit == rn.unit
            {ln.value / rn.value, ""}
          elsif rn.unit.empty?
            {ln.value / rn.value, ln.unit}
          elsif ln.unit.empty?
            raise SoftEvalError.new("can't divide unitless by #{rn.to_css}")
          elsif factor = Number.conversion_factor(rn.unit, ln.unit)
            {ln.value / (rn.value * factor), ""}
          else
            raise SoftEvalError.new("incompatible units: #{ln.to_css} and #{rn.to_css}")
          end
        end

        # True when evaluating the tree would do real work: any operator,
        # `not`, or a call that resolves to a known (user or built-in)
        # function. Bare literals/variables/lists resolve identically via
        # the legacy path, so they don't count — that is what keeps
        # existing output byte-identical.
        #
        # `force_div` marks a division-forcing context (variable values,
        # interpolation): there a literal-operand `/` counts as work too.
        def self.computes?(node : Node, host : Host, force_div : Bool = false) : Bool
          case node
          when Binary
            return true unless node.op == :div
            force_div || div_operand_forces?(node.left) || div_operand_forces?(node.right) ||
              computes?(node.left, host, force_div) || computes?(node.right, host, force_div)
          when Unary
            # Even a plain `-$a` / `+$a` counts: the verbatim path renders
            # `+5` for `+$a` where dart-sass emits the evaluated `5`.
            true
          when CallE
            return true if host.expr_known_fn?(node.ns, node.name)
            node.args.any? { |a| computes?(a, host, force_div) } ||
              node.kwargs.any? { |kw| computes?(kw.value, host, force_div) } ||
              node.spread.try { |s| computes?(s, host, force_div) } || false
          when ListE
            node.items.any? { |i| computes?(i, host, force_div) }
          when MapE
            # Map literals ALWAYS count as work, same rationale as ParenE:
            # `(a: b)` is Sass-only syntax with no CSS meaning. The verbatim
            # path also corrupts them — substituting a comma-list variable
            # into the map's text splices the list into the map's own comma
            # structure, and the storage round-trip no longer parses.
            true
          when ParenE
            # Grouping parens ALWAYS count as work, even around a bare literal
            # or a slash/space list: they are Sass syntax with no meaning in
            # CSS, so the legacy verbatim path emitted them into the stylesheet
            # (`width: (10px / 2)`, `margin: (1px 2px)`) — invalid declaration
            # values that no browser accepts. Evaluating consumes them.
            true
          when ConcatE
            node.parts.any? { |p| computes?(p, host) }
          when Lit
            # Two literals count as real work: a static `calc(...)` that
            # folds to a number (dart-sass emits `20px` for
            # `calc(10px + 5px * 2)`), and a literal `null` — the verbatim
            # path ships the four letters where dart elides the value
            # (`#{null 1px}` is `1px`, `x: null 1px` emits `x: 1px`).
            # Every other literal resolves identically via verbatim.
            case value = node.value
            when NullV then true
            when Raw   then !Expr.fold_calc(value.text).nil?
            else            false
            end
          else
            # RawSpanE and AmpE deliberately don't compute: interpolated
            # `calc(#{$a})` spans and a bare `&` resolve identically via
            # the verbatim path, which keeps existing output
            # byte-identical.
            false
          end
        end

        # Host services the evaluator needs from the statement evaluator.
        module Host
          # Variable value as stored text; raises SoftEvalError when
          # undefined.
          abstract def expr_var(name : String, ns : String?) : String
          # Calls a known function; nil when no such function exists (the
          # call then reconstructs as verbatim CSS).
          abstract def expr_call(ns : String?, name : String, args : Array(Value),
                                 kwargs : Hash(String, Value)) : Value?
          abstract def expr_known_fn?(ns : String?, name : String) : Bool
          # Resolves an interpolation template to (unquoted) text.
          abstract def expr_interp(template : Ast::TextTemplate) : String
          # Enclosing rule's resolved selectors for `&` (nil at root).
          abstract def expr_parent_selectors : Array(String)?

          # `meta.keywords($args)` — the keyword arguments captured by the
          # variadic parameter `$name`, as a map; nil when the call does
          # not resolve to the built-in (the normal call path then runs).
          def expr_keywords(name : String, var_ns : String?, call_ns : String?) : Value?
            nil
          end
        end

        # Coerces stored text back into a typed value ("1px" -> Number,
        # "(a: 1)" -> Map). Unparseable text stays Raw — lazily typed
        # strings are the storage model.
        def self.coerce(text : String) : Value
          stripped = text.strip
          return Raw.new(text) if stripped.empty?
          template = Ast::TextTemplate.new([stripped.as(Ast::Piece)], 1, 1)
          node = parse(template)
          return Raw.new(stripped) unless node
          # coercing: true — slash text arriving through storage is always
          # a CONSTRUCTED list (a literal lazy pair would have divided at
          # its force_div declaration), so it must not re-acquire lazy
          # division here. dart-sass errors on math over such a list.
          Evaluator.new(CoerceHost.new, coercing: true).eval(node)
        rescue SoftEvalError
          Raw.new(text.strip)
        end

        # :nodoc:
        class CoerceHost
          include Host

          def expr_var(name : String, ns : String?) : String
            raise SoftEvalError.new("no variables in stored values")
          end

          def expr_call(ns : String?, name : String, args : Array(Value),
                        kwargs : Hash(String, Value)) : Value?
            nil
          end

          def expr_known_fn?(ns : String?, name : String) : Bool
            false
          end

          def expr_interp(template : Ast::TextTemplate) : String
            raise SoftEvalError.new("no interpolation in stored values")
          end

          def expr_parent_selectors : Array(String)?
            nil
          end
        end

        # ---------------------------------------------------------------
        # Evaluator
        # ---------------------------------------------------------------

        class Evaluator
          # In lenient (value) contexts, `and`/`or` only operate on real
          # booleans/null: unquoted CSS idents like a hypothetical
          # `Franklin and Marshall` font stack must fall back to verbatim
          # text, never evaluate to one operand. Strict contexts
          # (@if/@while conditions) keep full Sass truthiness.
          #
          # `force_div` starts the evaluation in a division-forcing context
          # (variable declarations, interpolation, strict contexts): every
          # `/` in the tree divides. When it starts false (declaration
          # values), a `/` divides only when an operand is computed or the
          # slash sits under other arithmetic / a Sass function call — the
          # classic Sass division rule.
          def initialize(@host : Host, @strict : Bool = false, @force_div : Bool = false,
                         @coercing : Bool = false)
          end

          def eval(node : Node) : Value
            case node
            when Lit
              # A static `calc(...)` span folds to its number (dart-sass
              # simplification: `calc(10px + 5px * 2)` is `20px`).
              value = node.value
              if value.is_a?(Raw) && (folded = Expr.fold_calc(value.text))
                folded
              else
                value
              end
            when VarE    then Expr.coerce(@host.expr_var(node.name, node.ns))
            when InterpE then Expr.coerce(@host.expr_interp(node.template))
            when StrE    then eval_str(node)
            when RawSpanE
              # Interpolated spans stay opaque text — dart-sass doesn't
              # simplify `calc(#{$w} * 2)` either.
              Raw.new(node.parts.join { |p| p.is_a?(String) ? p : @host.expr_interp(p) })
            when AmpE
              if parents = @host.expr_parent_selectors
                ListV.new(parents.map { |p| Str.new(p, quoted: false).as(Value) }, ListV::Sep::Comma)
              else
                NullV.new
              end
            when ConcatE then Raw.new(node.parts.map { |p| eval(p).to_css }.join)
            when ParenE  then eval_forced(node.inner) # parens force `/` division (Sass rule)
            when ListE   then ListV.new(node.items.map { |i| eval(i).as(Value) }, node.sep, node.bracketed)
            when MapE    then eval_map(node)
            when Unary   then eval_unary(node)
            when Binary  then eval_binary(node)
            when CallE   then eval_call(node)
            else
              raise SoftEvalError.new("unsupported expression")
            end
          end

          private def eval_map(node : MapE) : Value
            entries = Array(MapEntry).new
            node.pairs.each do |pair|
              key = eval(pair.key)
              if entries.any?(&.key.eq?(key))
                raise DuplicateKeyError.new("Duplicate key")
              end
              entries << MapEntry.new(key, eval(pair.value))
            end
            MapV.new(entries)
          end

          private def eval_str(node : StrE) : Value
            text = String.build do |io|
              node.parts.each do |part|
                case part
                in String
                  io << part
                in Ast::TextTemplate
                  io << @host.expr_interp(part)
                end
              end
            end
            Str.new(text, quoted: true, quote_char: node.quote)
          end

          private def eval_unary(node : Unary) : Value
            operand = eval(node.operand)
            case node.op
            when :not
              BoolV.new(!operand.truthy?)
            when :minus
              if n = as_number?(operand)
                Number.new(-n.value, n.unit)
              else
                Raw.new("-" + operand.to_css)
              end
            when :plus
              if n = as_number?(operand)
                n
              else
                Raw.new("+" + operand.to_css)
              end
            else
              raise SoftEvalError.new("unsupported unary operator")
            end
          end

          private def eval_binary(node : Binary) : Value
            case node.op
            when :or
              left = eval(node.left)
              boolish!(left)
              left.truthy? ? left : eval(node.right)
            when :and
              left = eval(node.left)
              boolish!(left)
              left.truthy? ? eval(node.right) : left
            when :eq
              BoolV.new(loose_eq(eval_forced(node.left), eval_forced(node.right)))
            when :neq
              BoolV.new(!loose_eq(eval_forced(node.left), eval_forced(node.right)))
            when :lt, :gt, :le, :ge
              compare(node.op, eval_forced(node.left), eval_forced(node.right))
            when :plus
              add(eval_forced(node.left), eval_forced(node.right))
            when :minus
              arith(:minus, eval_forced(node.left), eval_forced(node.right))
            when :times
              multiply(eval_forced(node.left), eval_forced(node.right))
            when :div
              eval_div(node)
            when :mod
              arith(:mod, eval_forced(node.left), eval_forced(node.right))
            else
              raise SoftEvalError.new("unsupported operator")
            end
          end

          # Evaluates a subexpression in division-forcing position (an
          # arithmetic/comparison operand or a Sass function argument).
          private def eval_forced(node : Node) : Value
            saved = @force_div
            @force_div = true
            begin
              eval(node)
            ensure
              @force_div = saved
            end
          end

          # The classic Sass `/` rule: divide when forced by context or by
          # a computed operand; otherwise the slash is a list separator
          # (`list.slash` round-trips through variable storage as
          # `4 / 5 / 6`). Literal CSS slashes (`font: 12px/30px`) never
          # reach here — `computes?` is false, so they stay verbatim.
          private def eval_div(node : Binary) : Value
            if @force_div || Expr.div_operand_forces?(node.left) || Expr.div_operand_forces?(node.right)
              ln = number!(eval_forced(node.left), "division")
              rn = number!(eval_forced(node.right), "division")
              raise SoftEvalError.new("division by zero") if rn.value == 0
              value, unit = Expr.divide_numbers(ln, rn)
              Number.new(value, unit)
            else
              slash_list(eval(node.left), eval(node.right))
            end
          end

          # Flattens adjacent unbracketed slash lists so `1 / 2 / 3`
          # round-trips as one 3-element slash list, not a nested pair.
          private def slash_list(left : Value, right : Value) : ListV
            items = [] of Value
            append_slash_items(items, left)
            append_slash_items(items, right)
            ListV.new(items, ListV::Sep::Slash, lazy_slash: !@coercing)
          end

          private def append_slash_items(items : Array(Value), value : Value) : Nil
            if value.is_a?(ListV) && value.sep == ListV::Sep::Slash && !value.bracketed
              items.concat(value.items)
            else
              items << value
            end
          end

          # `==` with Raw normalization: a value that reaches comparison as
          # unmodeled text (a function's raw return, a concat result) still
          # compares equal to its typed twin — `1rem == 1rem` must not
          # depend on which evaluation path each side took.
          private def loose_eq(left : Value, right : Value) : Bool
            return true if left.eq?(right)
            l = left.is_a?(Raw) ? Expr.coerce(left.text) : left
            r = right.is_a?(Raw) ? Expr.coerce(right.text) : right
            return true if l.eq?(r)
            # Colors compare by channel across spellings: `red == #f00`.
            # Neither side coerces to ColorV via Expr.coerce (colors are
            # only produced on demand), so ask the color parser directly.
            if (lc = ColorV.coerce?(l)) && (rc = ColorV.coerce?(r))
              return lc.eq?(rc)
            end
            false
          end

          private def compare(op : Symbol, left : Value, right : Value) : Value
            ln = number!(left, "comparison")
            rn = number!(right, "comparison")
            unless ln.compatible_unit?(rn)
              raise SoftEvalError.new("can't compare #{ln.to_css} with #{rn.to_css} (incompatible units)")
            end
            rv = ln.unit.empty? ? rn.value : ln.coerce_value(rn)
            result =
              case op
              when :lt then ln.value < rv
              when :gt then ln.value > rv
              when :le then ln.value <= rv
              else          ln.value >= rv
              end
            BoolV.new(result)
          end

          private def add(left : Value, right : Value) : Value
            if (ln = as_number?(left)) && (rn = as_number?(right))
              return arith_numbers(:plus, ln, rn)
            end
            # String concatenation; quotedness follows the left operand
            # when it IS a string, otherwise the right one (dart-sass:
            # `"a" + b` is quoted, `a + "b"` is not, `1 + "a"` is).
            if left.is_a?(Str) || right.is_a?(Str)
              lt = left.is_a?(Str) ? left.text : left.to_css
              rt = right.is_a?(Str) ? right.text : right.to_css
              lead = left.is_a?(Str) ? left : right.as(Str)
              return Str.new(lt + rt, quoted: lead.quoted, quote_char: lead.quote_char)
            end
            raise SoftEvalError.new("can't add #{left.to_css} and #{right.to_css}")
          end

          private def arith(op : Symbol, left : Value, right : Value) : Value
            ln = number!(left, "arithmetic")
            rn = number!(right, "arithmetic")
            arith_numbers(op, ln, rn)
          end

          private def arith_numbers(op : Symbol, ln : Number, rn : Number) : Value
            unless ln.compatible_unit?(rn)
              raise SoftEvalError.new("incompatible units: #{ln.to_css} and #{rn.to_css}")
            end
            unit = ln.result_unit(rn)
            # The left operand's unit wins; a convertible right operand is
            # re-expressed in it (`1in + 72pt` is `2in`, dart-sass parity).
            rv = ln.unit.empty? ? rn.value : ln.coerce_value(rn)
            value =
              case op
              when :plus  then ln.value + rv
              when :minus then ln.value - rv
              when :mod
                raise SoftEvalError.new("modulo by zero") if rv == 0
                ln.value % rv
              else
                raise SoftEvalError.new("unsupported arithmetic")
              end
            Number.new(value, unit)
          end

          private def multiply(left : Value, right : Value) : Value
            ln = number!(left, "multiplication")
            rn = number!(right, "multiplication")
            if !ln.unit.empty? && !rn.unit.empty?
              raise SoftEvalError.new("can't multiply #{ln.to_css} by #{rn.to_css} (two units)")
            end
            Number.new(ln.value * rn.value, ln.unit.empty? ? rn.unit : ln.unit)
          end

          # Built-ins that shadow real CSS functions. Their argument lists
          # may be plain CSS (`rgb(255 0 0 / 0.5)`, `min(10px, 5%/2)`), so
          # a `/` inside must stay literal — forcing division there would
          # corrupt the reconstructed passthrough.
          SHADOWED_CSS_FNS = %w[rgb rgba hsl hsla hwb min max clamp round abs
            invert grayscale greyscale opacity saturate]

          private def eval_call(node : CallE) : Value
            if node.ns.nil? && node.spread.nil? && node.kwargs.empty? &&
               node.args.size == 3 && Sass.normalize_ident(node.name) == "if"
              return eval_forced(node.args[0]).truthy? ? eval_forced(node.args[1]) : eval_forced(node.args[2])
            end
            # `meta.keywords($args)` needs the VARIABLE, not its value —
            # the keyword store is a side channel of the variadic binding
            # that doesn't survive evaluation of `$args` into a list.
            if Sass.normalize_ident(node.name) == "keywords" && node.kwargs.empty? &&
               node.spread.nil? && node.args.size == 1 && (ref = node.args[0]).is_a?(VarE)
              begin
                if result = @host.expr_keywords(ref.name, ref.ns, node.ns)
                  return result
                end
              rescue ex : NamespacedEvalError
                raise ex
              rescue ex : SoftEvalError
                # Same policy as expr_call: a namespaced `meta.keywords`
                # failure must not fall back to verbatim CSS.
                raise NamespacedEvalError.new(ex.message || "keywords() failed") if node.ns
                raise ex
              end
            end
            # Arguments of a known Sass function are a SassScript context:
            # `/` divides there (`percentage(1/4)` is `25%`). Unknown-
            # function arguments are CSS and keep the literal slash.
            force_args = @host.expr_known_fn?(node.ns, node.name) &&
                         !(node.ns.nil? && SHADOWED_CSS_FNS.includes?(Sass.normalize_ident(node.name)))
            args = node.args.map { |a| force_args ? eval_forced(a) : eval(a) }
            if spread = node.spread
              spread_val = force_args ? eval_forced(spread) : eval(spread)
              case spread_val
              when ListV
                args.concat(spread_val.items)
              else
                args << spread_val
              end
            end
            kwargs = {} of String => Value
            node.kwargs.each do |kw|
              key = Sass.normalize_ident(kw.name)
              raise SoftEvalError.new("duplicate argument $#{kw.name}") if kwargs.has_key?(key)
              kwargs[key] = force_args ? eval_forced(kw.value) : eval(kw.value)
            end
            if result = @host.expr_call(node.ns, node.name, args, kwargs)
              result
            else
              reconstruct_call(node.ns, node.name, args, kwargs)
            end
          end

          private def reconstruct_call(ns : String?, name : String, args : Array(Value),
                                       kwargs : Hash(String, Value)) : Value
            pieces = args.map(&.to_css)
            kwargs.each { |n, v| pieces << "$#{n}: #{v.to_css}" }
            prefix = ns ? "#{ns}.#{name}" : name
            Raw.new("#{prefix}(#{pieces.join(", ")})")
          end

          private def boolish!(value : Value) : Nil
            return if @strict
            return if value.is_a?(BoolV) || value.is_a?(NullV)
            raise SoftEvalError.new("and/or on non-boolean values")
          end

          private def as_number?(value : Value) : Number?
            case value
            when Number
              value
            when Raw
              Expr.coerce(value.text).as?(Number)
            when Str
              value.quoted ? nil : Expr.coerce(value.text).as?(Number)
            when ListV
              Expr.slash_division?(value)
            end
          end

          private def number!(value : Value, context : String) : Number
            as_number?(value) ||
              raise SoftEvalError.new("#{context} requires numbers, got #{value.to_css.inspect}")
          end
        end
      end
    end
  end
end
