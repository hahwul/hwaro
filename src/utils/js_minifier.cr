# JS minification utilities
#
# Provides conservative JS minification that removes comments and
# unnecessary whitespace. Does NOT rename variables or perform
# AST-level optimization.
#
# Operations:
# - Remove single-line comments (// ...) outside strings
# - Remove multi-line comments (/* ... */)
# - Collapse excessive whitespace
# - Remove leading/trailing whitespace on lines

module Hwaro
  module Utils
    module JsMinifier
      extend self

      # Perform conservative JS minification
      def minify(js : String) : String
        # Multi-line template literals are stashed as NUL-delimited placeholders
        # so the final per-line rstrip / blank-line pass can't mutate bytes that
        # are part of a string value (a blank line or significant trailing
        # whitespace inside a `...` literal). Restored verbatim at the end.
        # (Plain "" / '' strings and /regex/ literals can't contain raw newlines,
        # so the line pass never touches them.)
        #
        # The scanner indexes by char position. `String#[](Int32)` is O(1)
        # only on ascii-only strings — on any non-ASCII string it is
        # O(position), which made this loop O(n²) (measured: 0.2ms ASCII vs
        # 3+ seconds with CJK comments on an ~80KB input). Scan the String
        # directly for the common all-ASCII bundle (no copy), and materialize
        # an Array(Char) for O(1) access otherwise. `scan_source` is generic
        # over both, so neither path pays a union dispatch.
        protected_spans = [] of String
        result = if js.ascii_only?
                   scan_source(js, protected_spans)
                 else
                   scan_source(js.chars, protected_spans)
                 end

        # Collapse multiple blank lines (placeholders survive: they contain no
        # trailing whitespace and are never empty).
        lines = result.lines.map(&.rstrip)
        lines.reject!(&.empty?)
        cleaned = lines.join("\n").strip

        # Restore protected template literals verbatim. Bounds-guard the index
        # so an adversarial literal `\x00JSPLn\x00` sequence in the source (NUL
        # is not valid JS) can't raise IndexError — emit it unchanged instead.
        return cleaned if protected_spans.empty?
        cleaned.gsub(/\x00JSPL(\d{1,9})\x00/) do
          # to_i? guards against a counterfeit token whose index overflows
          # Int32 — return $0 unchanged rather than raising ArgumentError.
          idx = $1.to_i?
          idx && idx < protected_spans.size ? protected_spans[idx] : $0
        end
      end

      # Single scanning pass over `chars` — a String when the input is
      # ascii-only, an Array(Char) otherwise. Untyped parameter so each
      # concrete type gets its own instantiation (no union dispatch in the
      # hot loop). Emits minified source; template literals are stashed
      # verbatim into `protected_spans` behind NUL placeholders.
      private def scan_source(chars, protected_spans : Array(String)) : String
        String.build do |io|
          i = 0
          len = chars.size
          # The last significant source character before `i` — whitespace
          # and comments skipped — and whether it closed a string, template
          # or regex literal. What precedes a `/` tells a regex literal from
          # a division (see regex_context?); looking back from the slash
          # over spaces alone misread `n\n  / 2`, `8 /* half */ / 2` and
          # `'6' / 2` as a regex, and that "regex" could end inside a later
          # string, which then opened where it closed and stripped its
          # `//` text (`'http://x'`) as a comment.
          last_sig = -1
          after_value = false
          # One entry per open `(`: whether it opens the head of an `if`,
          # `while`, `for` or `with` statement. A `)` closing such a head
          # ends no expression, so a `/` after it starts a regex literal
          # (`if (x) /re/.test(y)`); after any other `)` it is a division.
          parens = [] of Bool
          after_head = false

          while i < len
            c = chars[i]

            # String literals — pass through unchanged
            if c == '"' || c == '\''
              quote = c
              io << c
              i += 1
              while i < len
                sc = chars[i]
                io << sc
                if sc == '\\' && i + 1 < len
                  i += 1
                  io << chars[i]
                elsif sc == quote
                  break
                end
                i += 1
              end
              last_sig = i
              after_value = true
              after_head = false
              i += 1
              next
            end

            # Template literals — captured verbatim into a placeholder so the
            # trailing line-cleanup pass can't alter newlines/whitespace that
            # belong to the literal's value. The scan must track string state,
            # balanced braces, and nested template literals inside `${...}`
            # interpolations (see scan_template_literal); a naive single-depth
            # counter terminated the literal early on `${ '}' }`, `${ {a:1} }`,
            # or nested templates and stripped the rest as comments.
            if c == '`'
              lit = String.build do |lb|
                i = scan_template_literal(chars, i, len, lb)
              end
              protected_spans << lit
              io << "\x00JSPL#{protected_spans.size - 1}\x00"
              last_sig = i - 1
              after_value = true
              after_head = false
              next
            end

            # Slash: could be comment (//, /*) or regex literal (/.../)
            if c == '/' && i + 1 < len
              next_c = chars[i + 1]

              if next_c == '/'
                # Single-line comment — skip until the line terminator (a
                # lone CR or U+2028/U+2029 ends it too; stopping only at LF
                # deleted the rest of a CR-only file)
                i += 2
                while i < len && !line_terminator?(chars[i])
                  i += 1
                end
                next
              end

              if next_c == '*'
                # Multi-line comment. Removing it must leave a separator
                # behind: a comment is a token boundary (`return/*x*/g`
                # must not fuse into `returng`), and a comment containing
                # a line terminator counts as one for automatic semicolon
                # insertion (`return /*\n*/ 42` must keep the line break).
                prev_char = i > 0 ? chars[i - 1] : nil
                i += 2
                had_newline = false
                while i + 1 < len
                  if chars[i] == '*' && chars[i + 1] == '/'
                    i += 2
                    break
                  end
                  had_newline = true if line_terminator?(chars[i])
                  i += 1
                end
                if had_newline
                  # Always re-emit the line break: adjacent spaces do not
                  # preserve ASI semantics. The later per-line cleanup
                  # rstrips and drops blank lines but never joins lines,
                  # so the separation survives.
                  io << '\n'
                else
                  # A single space, and only when both neighbours are
                  # non-whitespace tokens that would otherwise fuse — this
                  # keeps output byte-identical for the common
                  # `a = /* c */ 1` shape where separation already exists.
                  next_char = i < len ? chars[i] : nil
                  if prev_char && next_char && !prev_char.whitespace? && !next_char.whitespace?
                    io << ' '
                  end
                end
                next
              end

              # Check if this slash starts a regex literal.
              # A `/` is a regex when preceded by a token that expects an expression:
              # operators, punctuation, or keywords like return/typeof/in/etc.
              if after_head || regex_context?(chars, last_sig, after_value)
                # Regex literal — pass through unchanged
                i = scan_regex(chars, i, len, io)
                last_sig = i - 1
                after_value = true
                after_head = false
                next
              end
            end

            io << c
            unless c.whitespace?
              after_head = false
              if c == '('
                parens << statement_head?(chars, last_sig)
              elsif c == ')'
                after_head = parens.pop? || false
              end
              last_sig = i
              after_value = false
            end
            i += 1
          end
        end
      end

      # Determine whether a `/` is likely a regex literal rather than a
      # division operator, from the last significant character before it
      # (`last`, -1 at the start of input) and whether that character closed
      # a string, template or regex literal (`after_value`). A literal, or a
      # token that can end an expression (identifier char, digit, `)`,
      # `]`), means division; otherwise (operator, `(`, `[`, `{`, `,`, `;`,
      # `!`, start of input) it's a regex.
      #
      # A word ending right before the slash is normally an identifier (so
      # division), except for the keywords after which an expression — and so
      # a regex literal — starts: `return /\/*$/.test(u)` must not read the
      # regex body's `/*` as a comment opener, which dropped everything after
      # it (the rest of the file and every later bundle entry). A keyword used
      # as a property name (`obj.return / 2`) is still division.
      #
      # A `)` reads as the end of an expression here; the scanner itself
      # tells a statement head's `)` (`if (x) /re/`) from a call's.
      private def regex_context?(chars, last : Int32, after_value : Bool) : Bool
        return true if last < 0 # start of input
        return false if after_value

        prev = chars[last]
        return false if prev == ')' || prev == ']'
        # A postfix `i++ / 2` ends an expression; `++` can never precede a
        # regex literal (a literal is not incrementable). Read as a regex,
        # the "literal" swallowed a template's opening backtick on the same
        # line and the template body was then stripped as code.
        return false if (prev == '+' || prev == '-') && last > 0 && chars[last - 1] == prev
        if prev.alphanumeric? || prev == '_' || prev == '$'
          return regex_keyword_before?(chars, last)
        end
        # Everything else (operators, punctuation) → regex
        true
      end

      # `regex_context?` for a `/` at `pos` inside a template interpolation,
      # where the scan copies strings and nested templates verbatim instead
      # of tracking them: the last significant character is found by
      # looking back over whitespace, and a quote or backtick there can only
      # be the end of a literal.
      private def interpolation_regex_context?(chars, pos : Int32) : Bool
        j = pos - 1
        while j >= 0 && chars[j].whitespace?
          j -= 1
        end
        regex_context?(chars, j, j >= 0 && (chars[j] == '"' || chars[j] == '\'' || chars[j] == '`'))
      end

      # `of` is a valid identifier outside `for … of`, so `of / 2` must stay
      # a division. `yield` and `await` are too, but only in sloppy code
      # outside a generator / async function, where nobody names a variable
      # after them; inside one (and anywhere in a module) a regex follows
      # them (`yield /a'/`), and reading that as division let the quote in
      # its body open a string that ran on through the file.
      REGEX_PRECEDING_KEYWORDS = Set{
        "return", "typeof", "instanceof", "in", "new", "delete", "void",
        "throw", "case", "do", "else", "yield", "await",
      }

      # Keywords whose parenthesised head is followed by a statement.
      STATEMENT_HEAD_KEYWORDS = Set{"if", "while", "for", "with"}

      # True when the `(` after chars[last] opens a statement head.
      private def statement_head?(chars, last : Int32) : Bool
        return false if last < 0
        prev = chars[last]
        # The last letters of `if`, `while`, `for`, `with`: most calls
        # (`f(`, `log(`) stop here without walking back over their name.
        return false unless prev == 'f' || prev == 'e' || prev == 'r' || prev == 'h'
        keyword_before?(chars, last, STATEMENT_HEAD_KEYWORDS)
      end

      # True when the identifier-like word ending at chars[last] is one of
      # REGEX_PRECEDING_KEYWORDS and not a member name (`a.return`) or a
      # private class member (`this.#in`, `#new`).
      private def regex_keyword_before?(chars, last : Int32) : Bool
        keyword_before?(chars, last, REGEX_PRECEDING_KEYWORDS)
      end

      # True when the identifier-like word ending at chars[last] is one of
      # `keywords` and not a member name or a private class member. The word
      # is compared in place: this runs for every `(` after an identifier
      # (every call), so building a String per lookup was measurable.
      private def keyword_before?(chars, last : Int32, keywords : Set(String)) : Bool
        start = last
        while start > 0 && (chars[start - 1].alphanumeric? || chars[start - 1] == '_' || chars[start - 1] == '$')
          start -= 1
        end
        return false if start > 0 && chars[start - 1] == '#'
        size = last - start + 1
        return false if size > 10 # longer than any keyword above
        return false unless keywords.any? { |kw| word_at?(chars, start, size, kw) }
        k = start - 1
        while k >= 0 && chars[k].whitespace?
          k -= 1
        end
        !(k >= 0 && chars[k] == '.')
      end

      # True when chars[start, size] spells the ASCII word `kw`.
      private def word_at?(chars, start : Int32, size : Int32, kw : String) : Bool
        return false unless kw.bytesize == size
        size.times do |k|
          return false unless chars[start + k].ord == kw.byte_at(k)
        end
        true
      end

      # Scan a template literal beginning at chars[i] == '`'. Appends the whole
      # literal — including every nested `${...}` interpolation — to `lb` and
      # returns the index just past the closing backtick. Correctly handles
      # strings, balanced braces, and nested template literals inside an
      # interpolation, so a `}`/backtick that belongs to the interpolation can
      # never be mistaken for the outer literal's terminator.
      private def scan_template_literal(chars, i : Int32, len : Int32, lb : String::Builder) : Int32
        lb << chars[i] # opening backtick
        i += 1
        while i < len
          c = chars[i]
          if c == '\\' && i + 1 < len
            lb << c << chars[i + 1]
            i += 2
          elsif c == '`'
            lb << c
            return i + 1 # closing backtick
          elsif c == '$' && i + 1 < len && chars[i + 1] == '{'
            lb << '$' << '{'
            i = scan_interpolation(chars, i + 2, len, lb)
          else
            lb << c
            i += 1
          end
        end
        i
      end

      # Scan the body of a `${ ... }` interpolation; the opening `{` is already
      # emitted and `i` points just past it. Tracks nested braces, string
      # literals, comments, regex literals, and nested template literals so the
      # matching `}` is found correctly. Returns the index just past that `}`.
      # Comments and regex bodies are skipped verbatim because a `}`, backtick,
      # or quote inside them is content, not structure — interpreting it (e.g.
      # treating a comment's backtick as a nested template) misaligns the scan
      # and corrupts the literal's boundary.
      private def scan_interpolation(chars, i : Int32, len : Int32, lb : String::Builder) : Int32
        depth = 1
        while i < len
          c = chars[i]
          if c == '\\' && i + 1 < len
            lb << c << chars[i + 1]
            i += 2
          elsif c == '"' || c == '\''
            i = scan_quoted(chars, i, len, lb)
          elsif c == '`'
            i = scan_template_literal(chars, i, len, lb)
          elsif c == '/' && i + 1 < len && chars[i + 1] == '/'
            # Line comment (only reachable in a multiline template, where the
            # closing `}` sits on a later line) — copy verbatim to end of line.
            while i < len && !line_terminator?(chars[i])
              lb << chars[i]
              i += 1
            end
          elsif c == '/' && i + 1 < len && chars[i + 1] == '*'
            # Block comment — copy verbatim through the closing `*/`.
            lb << '/' << '*'
            i += 2
            while i < len
              if chars[i] == '*' && i + 1 < len && chars[i + 1] == '/'
                lb << '*' << '/'
                i += 2
                break
              end
              lb << chars[i]
              i += 1
            end
          elsif c == '/' && interpolation_regex_context?(chars, i)
            i = scan_regex(chars, i, len, lb)
          elsif c == '{'
            depth += 1
            lb << c
            i += 1
          elsif c == '}'
            depth -= 1
            lb << c
            i += 1
            return i if depth == 0
          else
            lb << c
            i += 1
          end
        end
        i
      end

      # ECMAScript LineTerminator: LF, CR, LS, PS.
      private def line_terminator?(c : Char) : Bool
        c == '\n' || c == '\r' || c == '\u2028' || c == '\u2029'
      end

      # Scan a quoted string beginning at chars[i] (a `"` or `'`). Appends it
      # verbatim (honoring backslash escapes) and returns the index just past
      # the closing quote.
      private def scan_quoted(chars, i : Int32, len : Int32, lb : String::Builder) : Int32
        quote = chars[i]
        lb << quote
        i += 1
        while i < len
          c = chars[i]
          lb << c
          if c == '\\' && i + 1 < len
            i += 1
            lb << chars[i]
          elsif c == quote
            return i + 1
          end
          i += 1
        end
        i
      end

      # Scan a regex literal beginning at chars[i] == '/'. Appends it (and its
      # flags) verbatim and returns the index just past the literal. Used by
      # the main loop and inside `${...}` interpolations alike.
      #
      # An unescaped `/` inside a `[...]` character class does not end the
      # literal (`/[^\\/]*\//`): ending it there left the class's tail to the
      # main loop, where the literal's closing `\//` read as a `//` comment and
      # swallowed the rest of the line. A line break always ends the scan — a
      # regex literal cannot contain one — so a misclassified division can
      # never run on past its own line.
      private def scan_regex(chars, i : Int32, len : Int32, lb : String::Builder) : Int32
        lb << chars[i] # opening /
        i += 1
        in_class = false
        while i < len
          c = chars[i]
          break if c == '\n' || c == '\r'
          lb << c
          if c == '\\' && i + 1 < len
            i += 1
            lb << chars[i]
          elsif c == '['
            in_class = true
          elsif c == ']'
            in_class = false
          elsif c == '/' && !in_class
            i += 1
            while i < len && chars[i].ascii_letter?
              lb << chars[i]
              i += 1
            end
            return i
          end
          i += 1
        end
        i
      end
    end
  end
end
