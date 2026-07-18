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
# `/` is never division (dart-sass 2.0 semantics): it builds a
# slash-separated list, which is what keeps CSS shorthands like
# `font: 12px/1.5` and `grid-area: 1 / 2` safe. Division is `math.div`.
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
          getter op : Symbol # :or, :and, :eq, :neq, :lt, :gt, :le, :ge, :plus, :minus, :times, :mod
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
          Raw # hex colors, u+ranges, url(...)/calc(...) spans
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

        # ---------------------------------------------------------------
        # Lexer: TextTemplate pieces -> token list
        # ---------------------------------------------------------------

        # Function names whose parenthesized span belongs to CSS and must
        # pass through verbatim, never parsed as Sass arguments.
        RAW_SPAN_FNS = %w[url var env attr counter counters expression format local]

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
                # The string continues past this piece: an Interp piece
                # follows, then a String piece with the rest.
                parts << buf.to_s
                buf = String::Builder.new
                nxt = @pieces[@piece_i + 1]?
                fail unless nxt.is_a?(Ast::Interp)
                parts << nxt.inner
                @piece_i += 2
                @char_i = 0
                fail unless current_piece.is_a?(String)
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
          # the opening paren). Interpolation inside would have split the
          # piece — that shape is unlexable and falls back.
          private def lex_raw_span(start : Int32) : Nil
            depth = 0
            loop do
              fail if eop?
              c = advance
              if c == '"' || c == '\''
                quote = c
                loop do
                  fail if eop?
                  sc = advance
                  if sc == '\\'
                    advance unless eop?
                  elsif sc == quote
                    break
                  end
                end
              elsif c == '('
                depth += 1
              elsif c == ')'
                depth -= 1
                break if depth == 0
              end
            end
            push(Tok.new(TokKind::Raw, text[start...@char_i], @space))
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
            when '='
              advance
              fail unless peek == '='
              advance
              push(Tok.new(TokKind::EqEq, "==", @space))
            when '!'
              advance
              fail unless peek == '='
              advance
              push(Tok.new(TokKind::NotEq, "!=", @space))
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

          private def prev_operand? : Bool
            last = @toks.last?
            return false unless last
            case last.kind
            when TokKind::Number, TokKind::Ident, TokKind::Str, TokKind::Var,
                 TokKind::Interp, TokKind::Raw, TokKind::RParen, TokKind::RBracket
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
        #   comma-list > slash-list > space-list > or > and > not >
        #   equality > relational > additive > multiplicative > unary >
        #   concat/primary
        # :nodoc:
        class Parser
          def initialize(@toks : Array(Tok))
            @pos = 0
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
            first = parse_slash
            return first unless match?(TokKind::Comma)
            items = [first]
            while accept(TokKind::Comma)
              break if eof? # trailing comma
              items << parse_slash
            end
            ListE.new(items, ListV::Sep::Comma)
          end

          private def parse_slash : Node
            first = parse_space
            return first unless match?(TokKind::Slash)
            items = [first]
            while accept(TokKind::Slash)
              items << parse_space
            end
            ListE.new(items, ListV::Sep::Slash)
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
                 TokKind::Var, TokKind::Interp, TokKind::Raw, TokKind::LParen,
                 TokKind::LBracket
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
            left = parse_not
            while (tok = peek) && tok.kind.ident? && tok.text == "and"
              @pos += 1
              left = Binary.new(:and, left, parse_not)
            end
            left
          end

          private def parse_not : Node
            if (tok = peek) && tok.kind.ident? && tok.text == "not"
              @pos += 1
              Unary.new(:not, parse_not)
            else
              parse_equality
            end
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
              elsif (tok = peek) && tok.kind.percent?
                @pos += 1
                left = Binary.new(:mod, left, parse_unary)
              else
                break
              end
            end
            left
          end

          private def parse_unary : Node
            if accept(TokKind::Minus)
              Unary.new(:minus, parse_unary)
            elsif accept(TokKind::Plus)
              Unary.new(:plus, parse_unary)
            else
              parse_concat
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
            when TokKind::Number, TokKind::Ident, TokKind::Str, TokKind::Var, TokKind::Raw
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
                kwargs << KwargE.new(kw, parse_slash)
              else
                value = parse_slash
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

            first = parse_slash
            if accept(TokKind::Colon)
              first_val = parse_slash
              pairs = Array(MapPair).new
              pairs << MapPair.new(first, first_val)
              while accept(TokKind::Comma)
                break if match?(TokKind::RParen) # trailing comma
                key = parse_slash
                fail unless accept(TokKind::Colon)
                pairs << MapPair.new(key, parse_slash)
              end
              fail unless accept(TokKind::RParen)
              return MapE.new(pairs)
            end

            if match?(TokKind::Comma)
              items = [first]
              while accept(TokKind::Comma)
                break if match?(TokKind::RParen) # trailing comma
                items << parse_slash
              end
              fail unless accept(TokKind::RParen)
              return ListE.new(items, ListV::Sep::Comma)
            end

            fail unless accept(TokKind::RParen)
            ParenE.new(first)
          end

          private def parse_bracket : Node
            advance # '['
            items = [] of Node
            sep = ListV::Sep::Space
            unless match?(TokKind::RBracket)
              first = parse_slash
              items << first
              if match?(TokKind::Comma)
                sep = ListV::Sep::Comma
                while accept(TokKind::Comma)
                  break if match?(TokKind::RBracket)
                  items << parse_slash
                end
              else
                while !match?(TokKind::RBracket) && !eof?
                  items << parse_slash
                end
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
        rescue ParseFailure
          nil
        end

        # Strict parse for control-flow contexts.
        def self.parse!(template : Ast::TextTemplate) : Node
          toks = Lexer.new(template).lex
          raise SoftEvalError.new("expected expression") if toks.empty?
          begin
            Parser.new(toks).parse
          rescue ParseFailure
            raise SoftEvalError.new("invalid expression")
          end
        end

        # True when evaluating the tree would do real work: any operator,
        # `not`, or a call that resolves to a known (user or built-in)
        # function. Bare literals/variables/lists resolve identically via
        # the legacy path, so they don't count — that is what keeps
        # existing output byte-identical.
        def self.computes?(node : Node, host : Host) : Bool
          case node
          when Binary
            true
          when Unary
            node.op == :not || computes?(node.operand, host)
          when CallE
            return true if host.expr_known_fn?(node.ns, node.name)
            node.args.any? { |a| computes?(a, host) } ||
              node.kwargs.any? { |kw| computes?(kw.value, host) } ||
              node.spread.try { |s| computes?(s, host) } || false
          when ListE
            node.items.any? { |i| computes?(i, host) }
          when MapE
            node.pairs.any? { |pair| computes?(pair.key, host) || computes?(pair.value, host) }
          when ParenE
            computes?(node.inner, host)
          when ConcatE
            node.parts.any? { |p| computes?(p, host) }
          else
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
          Evaluator.new(CoerceHost.new).eval(node)
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
          def initialize(@host : Host, @strict : Bool = false)
          end

          def eval(node : Node) : Value
            case node
            when Lit     then node.value
            when VarE    then Expr.coerce(@host.expr_var(node.name, node.ns))
            when InterpE then Expr.coerce(@host.expr_interp(node.template))
            when StrE    then eval_str(node)
            when ConcatE then Raw.new(node.parts.map { |p| eval(p).to_css }.join)
            when ParenE  then eval(node.inner)
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
            node.pairs.each { |pair| entries << MapEntry.new(eval(pair.key), eval(pair.value)) }
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
              BoolV.new(eval(node.left).eq?(eval(node.right)))
            when :neq
              BoolV.new(!eval(node.left).eq?(eval(node.right)))
            when :lt, :gt, :le, :ge
              compare(node.op, eval(node.left), eval(node.right))
            when :plus
              add(eval(node.left), eval(node.right))
            when :minus
              arith(:minus, eval(node.left), eval(node.right))
            when :times
              multiply(eval(node.left), eval(node.right))
            when :mod
              arith(:mod, eval(node.left), eval(node.right))
            else
              raise SoftEvalError.new("unsupported operator")
            end
          end

          private def compare(op : Symbol, left : Value, right : Value) : Value
            ln = number!(left, "comparison")
            rn = number!(right, "comparison")
            unless ln.compatible_unit?(rn)
              raise SoftEvalError.new("can't compare #{ln.to_css} with #{rn.to_css} (incompatible units)")
            end
            result =
              case op
              when :lt then ln.value < rn.value
              when :gt then ln.value > rn.value
              when :le then ln.value <= rn.value
              else          ln.value >= rn.value
              end
            BoolV.new(result)
          end

          private def add(left : Value, right : Value) : Value
            if (ln = as_number?(left)) && (rn = as_number?(right))
              return arith_numbers(:plus, ln, rn)
            end
            # String concatenation; quotedness follows the left operand
            # (dart-sass semantics).
            if left.is_a?(Str) || right.is_a?(Str)
              lt = left.is_a?(Str) ? left.text : left.to_css
              rt = right.is_a?(Str) ? right.text : right.to_css
              quoted = left.is_a?(Str) && left.quoted
              quote = left.is_a?(Str) ? left.quote_char : '"'
              return Str.new(lt + rt, quoted: quoted, quote_char: quote)
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
            value =
              case op
              when :plus  then ln.value + rn.value
              when :minus then ln.value - rn.value
              when :mod
                raise SoftEvalError.new("modulo by zero") if rn.value == 0
                ln.value % rn.value
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

          private def eval_call(node : CallE) : Value
            args = node.args.map { |a| eval(a) }
            if spread = node.spread
              spread_val = eval(spread)
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
              kwargs[key] = eval(kw.value)
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
