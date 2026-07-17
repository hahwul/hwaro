# Recursive-descent parser for the SCSS subset.
#
# Statement-level constructs ($var decls, @mixin/@include/@use/@import,
# rules, declarations, at-rules) are parsed structurally; selectors,
# property names, values, and at-rule preludes are captured as
# `TextTemplate`s — verbatim text with `#{...}` / `$var` pieces — so that
# any CSS we don't model passes through untouched.
#
# The classic SCSS ambiguity (declaration vs nested rule) is resolved by
# scanning the prelude to its terminator: `{` starts a rule, `;`/`}` ends
# a declaration split at its first top-level colon. A colon immediately
# followed by an identifier (`a:hover`) is treated as a pseudo-selector
# colon for the nested-property check only.

require "./scanner"
require "./ast"

module Hwaro
  module Assets
    module Sass
      class Parser
        # Sass directives outside the supported subset. Rejected loudly with
        # a located error — never silently emitted as broken CSS. Each of
        # these becomes a real AST node + evaluator arm when implemented.
        UNSUPPORTED_DIRECTIVES = %w[if else each for while function return extend forward at-root debug warn error]

        private record TemplateScan,
          template : Ast::TextTemplate,
          terminator : Char?,
          first_colon : {Int32, Int32}?,
          first_decl_colon : {Int32, Int32}?

        # Mutable text accumulator shared between the template scanner and
        # its string/url sub-scanners. A plain String::Builder can't be
        # passed around because flushing replaces the builder instance.
        private class Buf
          getter size : Int32

          def initialize
            @io = String::Builder.new
            @size = 0
          end

          def <<(c : Char) : self
            @io << c
            @size += 1
            self
          end

          def append(s : String) : self
            @io << s
            @size += s.size
            self
          end

          def flush_into(pieces : Array(Ast::Piece)) : Nil
            return if @size == 0
            pieces << @io.to_s
            @io = String::Builder.new
            @size = 0
          end
        end

        def initialize(source : String, path : String)
          @s = Scanner.new(source, path)
        end

        def self.parse(source : String, path : String) : Ast::Stylesheet
          new(source, path).parse
        end

        def parse : Ast::Stylesheet
          children = parse_statements(top_level: true)
          Ast::Stylesheet.new(children)
        end

        # Splits selector-ish text on commas outside strings/brackets/parens.
        # Shared with the evaluator's selector resolution.
        def self.split_top_level_commas(text : String) : Array(String)
          parts = [] of String
          depth = 0
          current = String::Builder.new
          chars = text.chars
          i = 0
          while i < chars.size
            c = chars[i]
            case c
            when '(', '['
              depth += 1
              current << c
            when ')', ']'
              depth -= 1
              current << c
            when '"', '\''
              quote = c
              current << c
              i += 1
              while i < chars.size
                sc = chars[i]
                current << sc
                if sc == '\\' && i + 1 < chars.size
                  i += 1
                  current << chars[i]
                elsif sc == quote
                  break
                end
                i += 1
              end
            when ','
              if depth == 0
                parts << current.to_s
                current = String::Builder.new
              else
                current << c
              end
            else
              current << c
            end
            i += 1
          end
          parts << current.to_s
          parts
        end

        private def parse_statements(top_level : Bool) : Array(Ast::Node)
          nodes = [] of Ast::Node
          loop do
            @s.skip_ws { |text, line, col| nodes << Ast::CommentNode.new(text, line, col) }
            break if @s.eof?
            case @s.peek
            when '}'
              @s.error("unmatched \"}\"") if top_level
              break
            when ';'
              @s.advance
            when '$'
              nodes << parse_var_decl
            when '@'
              parse_at_rule(nodes)
            else
              nodes << parse_rule_or_declaration
            end
          end
          nodes
        end

        # Consumes "{ ... }" (cursor on the opening brace).
        private def parse_block : Array(Ast::Node)
          open_line = @s.line
          open_col = @s.column
          @s.advance # '{'
          nodes = parse_statements(top_level: false)
          @s.error("unterminated block", open_line, open_col) if @s.eof?
          @s.advance # '}'
          nodes
        end

        private def parse_var_decl : Ast::Node
          line = @s.line
          column = @s.column
          @s.advance # '$'
          name = @s.read_ident
          @s.error("expected variable name after \"$\"", line, column) if name.empty?
          @s.skip_ws
          @s.error("expected \":\" after $#{name}") unless @s.peek == ':'
          @s.advance
          scan = read_template(stops: ";}", value_vars: true)
          template, flags = strip_flags(scan.template, {"default", "global"})
          template = trim_template(template)
          @s.error("expected value for $#{name}", line, column) if template.empty?
          @s.advance if scan.terminator == ';'
          Ast::VarDeclNode.new(name, template, flags.includes?("default"), flags.includes?("global"), line, column)
        end

        private def parse_at_rule(nodes : Array(Ast::Node)) : Nil
          line = @s.line
          column = @s.column
          @s.advance # '@'
          name = @s.read_ident
          @s.error("expected at-rule name after \"@\"", line, column) if name.empty?

          if UNSUPPORTED_DIRECTIVES.includes?(name)
            @s.error("@#{name} is not supported by hwaro's Sass subset (yet)", line, column)
          end

          case name
          when "use"
            nodes << parse_use(line, column)
          when "import"
            parse_import(nodes, line, column)
          when "mixin"
            nodes << parse_mixin(line, column)
          when "include"
            nodes << parse_include(line, column)
          when "content"
            @s.skip_ws
            if @s.peek == '('
              @s.error("@content arguments are not supported", line, column)
            end
            @s.advance if @s.peek == ';'
            nodes << Ast::ContentNode.new(line, column)
          else
            nodes << parse_raw_at_rule(name, line, column)
          end
        end

        private def parse_use(line : Int32, column : Int32) : Ast::Node
          @s.skip_ws
          unless @s.peek == '"' || @s.peek == '\''
            @s.error("expected quoted url after @use", line, column)
          end
          url = unquote(@s.read_quoted)
          namespace = nil
          loop do
            @s.skip_ws
            break unless @s.ident_start?(@s.peek)
            word_line = @s.line
            word_col = @s.column
            word = @s.read_ident
            case word
            when "as"
              @s.skip_ws
              if @s.peek == '*'
                @s.advance
                namespace = "*"
              else
                ns = @s.read_ident
                @s.error("expected namespace after \"as\"", word_line, word_col) if ns.empty?
                namespace = ns
              end
            when "with"
              @s.error("@use ... with (...) configuration is not supported", word_line, word_col)
            else
              @s.error("unexpected \"#{word}\" in @use", word_line, word_col)
            end
          end
          @s.error("expected \";\" after @use") unless @s.peek == ';'
          @s.advance
          Ast::UseNode.new(url, namespace, line, column)
        end

        # Sass imports of local files become ImportNodes; plain-CSS forms
        # (url(...), remote urls, ".css", media-query suffixes) pass through
        # as raw statement at-rules.
        private def parse_import(nodes : Array(Ast::Node), line : Int32, column : Int32) : Nil
          scan = read_template(stops: ";}", value_vars: false)
          @s.advance if scan.terminator == ';'
          template = trim_template(scan.template)

          if template.pieces.size == 1 && (text = template.pieces[0].as?(String))
            parts = Parser.split_top_level_commas(text)
            if parts.all? { |p| quoted_string?(p.strip) }
              parts.each do |part|
                url = unquote(part.strip)
                if plain_css_import?(url)
                  prelude = Ast::TextTemplate.new([part.strip.as(Ast::Piece)], line, column)
                  nodes << Ast::RawAtRuleNode.new("import", prelude, nil, line, column)
                else
                  nodes << Ast::ImportNode.new(url, line, column)
                end
              end
              return
            end
          end
          # url(...), media-query suffixes, interpolation: plain CSS passthrough.
          nodes << Ast::RawAtRuleNode.new("import", template, nil, line, column)
        end

        private def plain_css_import?(url : String) : Bool
          url.starts_with?("http://") || url.starts_with?("https://") ||
            url.starts_with?("//") || url.ends_with?(".css")
        end

        # True only for a single closed string literal — `"a" + "b"` has
        # matching first/last quotes but is NOT one string and must fall
        # through to plain-CSS passthrough instead of being mis-unquoted.
        private def quoted_string?(text : String) : Bool
          return false if text.size < 2
          quote = text[0]
          return false unless quote == '"' || quote == '\''
          chars = text.chars
          i = 1
          while i < chars.size
            case chars[i]
            when '\\'
              i += 2
            when quote
              # The first unescaped closing quote must be the final char.
              return i == chars.size - 1
            else
              i += 1
            end
          end
          false
        end

        private def parse_mixin(line : Int32, column : Int32) : Ast::Node
          @s.skip_ws
          name = @s.read_ident
          @s.error("expected mixin name after @mixin", line, column) if name.empty?
          @s.skip_ws
          params = @s.peek == '(' ? parse_params : [] of Ast::Param
          @s.skip_ws
          @s.error("expected \"{\" for @mixin #{name}", line, column) unless @s.peek == '{'
          body = parse_block
          Ast::MixinDefNode.new(name, params, body, line, column)
        end

        private def parse_params : Array(Ast::Param)
          params = [] of Ast::Param
          @s.advance # '('
          loop do
            @s.skip_ws
            break if @s.peek == ')'
            @s.error("unterminated parameter list") if @s.eof?
            @s.error("expected \"$\" in mixin parameter list") unless @s.peek == '$'
            @s.advance
            name = @s.read_ident
            @s.error("expected parameter name after \"$\"") if name.empty?
            @s.skip_ws
            if @s.peek == '.' && @s.peek(1) == '.' && @s.peek(2) == '.'
              @s.error("variadic parameters ($#{name}...) are not supported")
            end
            default = nil
            if @s.peek == ':'
              @s.advance
              scan = read_template(stops: ",)", value_vars: true, depth_relative_stops: true)
              default = trim_template(scan.template)
            end
            params << Ast::Param.new(name, default)
            @s.skip_ws
            @s.advance if @s.peek == ','
          end
          @s.error("unterminated parameter list") if @s.eof?
          @s.advance # ')'
          params
        end

        private def parse_include(line : Int32, column : Int32) : Ast::Node
          @s.skip_ws
          first = @s.read_ident
          @s.error("expected mixin name after @include", line, column) if first.empty?
          namespace = nil
          name = first
          if @s.peek == '.'
            @s.advance
            namespace = first
            name = @s.read_ident
            @s.error("expected mixin name after \"#{first}.\"", line, column) if name.empty?
          end
          @s.skip_ws
          args = @s.peek == '(' ? parse_args : [] of Ast::Arg
          @s.skip_ws
          body = nil
          if @s.ident_start?(@s.peek)
            word_line = @s.line
            word_col = @s.column
            word = @s.read_ident
            if word == "using"
              @s.error("@include ... using (...) is not supported", word_line, word_col)
            else
              @s.error("unexpected \"#{word}\" after @include #{name}", word_line, word_col)
            end
          end
          if @s.peek == '{'
            body = parse_block
          elsif @s.peek == ';'
            @s.advance
          end
          Ast::IncludeNode.new(name, namespace, args, body, line, column)
        end

        private def parse_args : Array(Ast::Arg)
          args = [] of Ast::Arg
          @s.advance # '('
          loop do
            @s.skip_ws
            break if @s.peek == ')'
            @s.error("unterminated argument list") if @s.eof?
            kwarg = nil
            if @s.peek == '$'
              # `$name: value` is a keyword argument; a bare `$var` is a
              # positional value. Peek past the identifier for the colon.
              offset = 1
              while @s.ident_char?(@s.peek(offset))
                offset += 1
              end
              while @s.peek(offset).try(&.ascii_whitespace?)
                offset += 1
              end
              if @s.peek(offset) == ':' && @s.peek(offset + 1) != ':'
                @s.advance # '$'
                kwarg = @s.read_ident
                @s.skip_ws
                @s.advance # ':'
              end
            end
            scan = read_template(stops: ",)", value_vars: true, depth_relative_stops: true)
            value = trim_template(scan.template)
            @s.error("expected argument value") if value.empty?
            args << Ast::Arg.new(kwarg, value)
            @s.skip_ws
            @s.advance if @s.peek == ','
          end
          @s.error("unterminated argument list") if @s.eof?
          @s.advance # ')'
          args
        end

        private def parse_raw_at_rule(name : String, line : Int32, column : Int32) : Ast::Node
          # Preludes get variable substitution too: `@media (min-width: $bp)`
          # is the standard breakpoint-mixin pattern (dart-sass parity).
          scan = read_template(stops: "{;}", value_vars: true)
          prelude = trim_template(scan.template)
          if scan.terminator == '{'
            children = parse_block
            Ast::RawAtRuleNode.new(name, prelude, children, line, column)
          else
            @s.advance if scan.terminator == ';'
            Ast::RawAtRuleNode.new(name, prelude, nil, line, column)
          end
        end

        private def parse_rule_or_declaration : Ast::Node
          line = @s.line
          column = @s.column
          scan = read_template(stops: "{;}", value_vars: true)

          if scan.terminator == '{'
            if (colon = scan.first_decl_colon) && blank_after?(scan.template, colon)
              @s.error("nested properties are not supported", line, column)
            end
            selector = trim_template(scan.template)
            @s.error("expected selector", line, column) if selector.empty?
            children = parse_block
            return Ast::RuleNode.new(selector, children, line, column)
          end

          # Declaration: split at the first top-level colon.
          colon = scan.first_colon
          @s.error("expected \"{\"", line, column) unless colon
          @s.advance if scan.terminator == ';'
          name_t, value_t = split_at(scan.template, colon)
          name_t = trim_template(name_t)
          @s.error("expected property name", line, column) if name_t.empty?
          custom = name_t.pieces[0].as?(String).try(&.starts_with?("--")) || false
          important = false
          if custom
            # Custom property values are verbatim: `$var` stays literal,
            # only `#{...}` interpolates (dart-sass semantics).
            value_t = literalize_vars(value_t)
          else
            value_t, flags = strip_flags(value_t, {"important"})
            important = flags.includes?("important")
            value_t = trim_template(value_t)
            @s.error("expected value for property", line, column) if value_t.empty? && !important
          end
          Ast::DeclarationNode.new(name_t, value_t, important, custom, line, column)
        end

        # ---------------------------------------------------------------
        # Template scanning
        # ---------------------------------------------------------------

        # Reads verbatim text until one of `stops` at nesting depth 0 (the
        # terminator is not consumed; nil terminator = EOF). Handles quoted
        # strings, url(...) spans, comments (dropped, replaced by a space),
        # `#{...}` interpolation, and — when `value_vars` — `$var` and
        # `ns.$var` references. With `depth_relative_stops` the caller has
        # already consumed an opening paren, so a `)` stop is expected at
        # depth 0 rather than being an unmatched-paren error.
        private def read_template(stops : String, value_vars : Bool, depth_relative_stops : Bool = false) : TemplateScan
          start_line = @s.line
          start_col = @s.column
          pieces = [] of Ast::Piece
          buf = Buf.new
          depth = 0
          terminator = nil
          first_colon = nil
          first_decl_colon = nil

          while c = @s.peek
            if depth == 0 && stops.includes?(c)
              terminator = c
              break
            end

            case c
            when '"', '\''
              read_string_into(buf, pieces)
            when '/'
              if @s.peek(1) == '*'
                @s.read_loud_comment
                buf << ' '
              elsif @s.peek(1) == '/'
                @s.advance
                @s.advance
                until @s.eof? || @s.peek == '\n'
                  @s.advance
                end
              else
                buf << @s.advance
              end
            when '#'
              if @s.peek(1) == '{'
                buf.flush_into(pieces)
                pieces << parse_interp
              else
                buf << @s.advance
              end
            when '$'
              if value_vars
                var_line = @s.line
                var_col = @s.column
                @s.advance
                name = @s.read_ident
                @s.error("expected identifier after \"$\"", var_line, var_col) if name.empty?
                buf.flush_into(pieces)
                pieces << Ast::VarRef.new(name, nil, var_line, var_col)
              else
                buf << @s.advance
              end
            when '(', '['
              depth += 1
              buf << @s.advance
            when ')'
              @s.error("unmatched \")\"") if depth == 0
              depth -= 1
              buf << @s.advance
            when ']'
              @s.error("unmatched \"]\"") if depth == 0
              depth -= 1
              buf << @s.advance
            when ':'
              if depth == 0
                first_colon ||= {pieces.size, buf.size}
                nxt = @s.peek(1)
                pseudo_like = @s.ident_start?(nxt) || nxt == ':'
                first_decl_colon ||= {pieces.size, buf.size} unless pseudo_like
              end
              buf << @s.advance
            else
              if value_vars && @s.ident_start?(c)
                ident = @s.read_ident
                if @s.peek == '.' && @s.peek(1) == '$'
                  # `ns.$var` — namespaced variable reference.
                  var_line = @s.line
                  var_col = @s.column
                  @s.advance # '.'
                  @s.advance # '$'
                  name = @s.read_ident
                  @s.error("expected identifier after \"#{ident}.$\"", var_line, var_col) if name.empty?
                  buf.flush_into(pieces)
                  pieces << Ast::VarRef.new(name, ident, var_line, var_col)
                elsif ident.compare("url", case_insensitive: true) == 0 && @s.peek == '('
                  buf.append(ident)
                  read_url_span(buf, pieces)
                else
                  buf.append(ident)
                end
              else
                buf << @s.advance
              end
            end
          end

          buf.flush_into(pieces)
          template = Ast::TextTemplate.new(pieces, start_line, start_col)
          TemplateScan.new(template, terminator, first_colon, first_decl_colon)
        end

        # Quoted string with `#{...}` support (cursor on the opening quote).
        private def read_string_into(buf : Buf, pieces : Array(Ast::Piece)) : Nil
          start_line = @s.line
          start_col = @s.column
          quote = @s.peek || @s.error("expected string", start_line, start_col)
          buf << @s.advance
          loop do
            c = @s.peek || @s.error("unterminated string", start_line, start_col)
            if c == '\\'
              buf << @s.advance
              buf << @s.advance unless @s.eof?
            elsif c == '#' && @s.peek(1) == '{'
              buf.flush_into(pieces)
              pieces << parse_interp
            elsif c == quote
              buf << @s.advance
              break
            else
              buf << @s.advance
            end
          end
        end

        # Raw `url(...)` span (cursor on '('): unquoted url contents are
        # token soup (data URIs contain `;` and `,`), so everything up to
        # the closing paren is verbatim except quoted strings and `#{...}`.
        private def read_url_span(buf : Buf, pieces : Array(Ast::Piece)) : Nil
          start_line = @s.line
          start_col = @s.column
          buf << @s.advance # '('
          loop do
            c = @s.peek || @s.error("unterminated url(", start_line, start_col)
            case c
            when ')'
              buf << @s.advance
              break
            when '"', '\''
              read_string_into(buf, pieces)
            when '#'
              if @s.peek(1) == '{'
                buf.flush_into(pieces)
                pieces << parse_interp
              else
                buf << @s.advance
              end
            else
              buf << @s.advance
            end
          end
        end

        # `#{ ... }` (cursor on '#').
        private def parse_interp : Ast::Interp
          line = @s.line
          column = @s.column
          @s.advance # '#'
          @s.advance # '{'
          scan = read_template(stops: "}", value_vars: true)
          @s.error("unterminated \"\#{\"", line, column) unless scan.terminator == '}'
          @s.advance # '}'
          inner = trim_template(scan.template)
          @s.error("empty \"\#{}\"", line, column) if inner.empty?
          Ast::Interp.new(inner, line, column)
        end

        # ---------------------------------------------------------------
        # Template helpers
        # ---------------------------------------------------------------

        private def unquote(text : String) : String
          text[1...-1]
        end

        private def split_at(template : Ast::TextTemplate, colon : {Int32, Int32}) : {Ast::TextTemplate, Ast::TextTemplate}
          piece_idx, offset = colon
          left = [] of Ast::Piece
          right = [] of Ast::Piece
          template.pieces.each_with_index do |piece, i|
            if i < piece_idx
              left << piece
            elsif i == piece_idx
              text = piece.as(String)
              head = text[0, offset]
              tail = text[offset + 1..]
              left << head unless head.empty?
              right << tail unless tail.empty?
            else
              right << piece
            end
          end
          {Ast::TextTemplate.new(left, template.line, template.column),
           Ast::TextTemplate.new(right, template.line, template.column)}
        end

        private def trim_template(template : Ast::TextTemplate) : Ast::TextTemplate
          pieces = template.pieces.dup
          if (first = pieces.first?) && first.is_a?(String)
            stripped = first.lstrip
            if stripped.empty?
              pieces.shift
            else
              pieces[0] = stripped
            end
          end
          if (last = pieces.last?) && last.is_a?(String)
            stripped = last.rstrip
            if stripped.empty?
              pieces.pop
            else
              pieces[-1] = stripped
            end
          end
          Ast::TextTemplate.new(pieces, template.line, template.column)
        end

        # Strips trailing `!flag` markers (!default, !global, !important)
        # off a value template.
        private def strip_flags(template : Ast::TextTemplate, allowed : Tuple) : {Ast::TextTemplate, Set(String)}
          flags = Set(String).new
          pieces = template.pieces.dup
          loop do
            last = pieces.last?
            break unless last.is_a?(String)
            stripped = last.rstrip
            matched = false
            allowed.each do |flag|
              marker = "!#{flag}"
              next unless stripped.downcase.ends_with?(marker)
              flags << flag
              stripped = stripped[0, stripped.size - marker.size].rstrip
              matched = true
              break
            end
            break unless matched
            if stripped.empty?
              pieces.pop
            else
              pieces[-1] = stripped
            end
          end
          {Ast::TextTemplate.new(pieces, template.line, template.column), flags}
        end

        # Converts VarRef pieces back into literal `$name` text (custom
        # property values must not substitute variables).
        private def literalize_vars(template : Ast::TextTemplate) : Ast::TextTemplate
          pieces = [] of Ast::Piece
          template.pieces.each do |piece|
            if piece.is_a?(Ast::VarRef)
              if (last = pieces.last?) && last.is_a?(String)
                pieces[-1] = last + piece.lexeme
              else
                pieces << piece.lexeme
              end
            else
              pieces << piece
            end
          end
          Ast::TextTemplate.new(pieces, template.line, template.column)
        end

        # True when nothing but whitespace follows the given colon position
        # (the `font: { ... }` nested-property shape).
        private def blank_after?(template : Ast::TextTemplate, colon : {Int32, Int32}) : Bool
          piece_idx, offset = colon
          template.pieces.each_with_index do |piece, i|
            next if i < piece_idx
            if i == piece_idx
              tail = piece.as(String)[offset + 1..]
              return false unless tail.blank?
            else
              return false unless piece.is_a?(String) && piece.blank?
            end
          end
          true
        end
      end
    end
  end
end
