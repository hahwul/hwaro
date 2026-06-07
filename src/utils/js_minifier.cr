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
        protected_spans = [] of String
        result = String.build do |io|
          i = 0
          len = js.size
          chars = js

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
              next
            end

            # Slash: could be comment (//, /*) or regex literal (/.../)
            if c == '/' && i + 1 < len
              next_c = chars[i + 1]

              if next_c == '/'
                # Single-line comment — skip until end of line
                i += 2
                while i < len && chars[i] != '\n'
                  i += 1
                end
                next
              end

              if next_c == '*'
                # Multi-line comment
                i += 2
                while i + 1 < len
                  if chars[i] == '*' && chars[i + 1] == '/'
                    i += 2
                    break
                  end
                  i += 1
                end
                next
              end

              # Check if this slash starts a regex literal.
              # A `/` is a regex when preceded by a token that expects an expression:
              # operators, punctuation, or keywords like return/typeof/in/etc.
              if regex_context?(chars, i)
                # Regex literal — pass through unchanged
                io << c
                i += 1
                while i < len
                  rc = chars[i]
                  io << rc
                  if rc == '\\' && i + 1 < len
                    i += 1
                    io << chars[i]
                  elsif rc == '/'
                    # Consume regex flags (g, i, m, s, u, y)
                    i += 1
                    while i < len && chars[i].ascii_letter?
                      io << chars[i]
                      i += 1
                    end
                    break
                  end
                  i += 1
                end
                next
              end
            end

            io << c
            i += 1
          end
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
        cleaned.gsub(/\x00JSPL(\d+)\x00/) do
          idx = $1.to_i
          idx < protected_spans.size ? protected_spans[idx] : $0
        end
      end

      # Determine whether a `/` at position `pos` in `chars` is likely a regex
      # literal rather than a division operator. We look at the last
      # non-whitespace character before the slash: if it could end an
      # expression (identifier char, digit, `)`, `]`), it's division;
      # otherwise (operator, `(`, `[`, `{`, `,`, `;`, `!`, line start) it's regex.
      #
      # Known limitation: keywords that end with an alphanumeric char and precede
      # a regex literal (e.g. `return /foo/`, `typeof /re/`, `void /re/`,
      # `case /re/`, `throw /re/`) are misclassified as division because
      # full keyword-aware tokenization is not performed.
      private def regex_context?(chars : String, pos : Int32) : Bool
        j = pos - 1
        while j >= 0 && (chars[j] == ' ' || chars[j] == '\t')
          j -= 1
        end
        return true if j < 0 # start of input

        prev = chars[j]
        # These characters can end an expression value — `/` after them is division
        return false if prev.alphanumeric? || prev == '_' || prev == '$' ||
                        prev == ')' || prev == ']'
        # Everything else (operators, punctuation, keywords ending with these) → regex
        true
      end

      # Scan a template literal beginning at chars[i] == '`'. Appends the whole
      # literal — including every nested `${...}` interpolation — to `lb` and
      # returns the index just past the closing backtick. Correctly handles
      # strings, balanced braces, and nested template literals inside an
      # interpolation, so a `}`/backtick that belongs to the interpolation can
      # never be mistaken for the outer literal's terminator.
      private def scan_template_literal(chars : String, i : Int32, len : Int32, lb : String::Builder) : Int32
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
      private def scan_interpolation(chars : String, i : Int32, len : Int32, lb : String::Builder) : Int32
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
            while i < len && chars[i] != '\n'
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
          elsif c == '/' && regex_context?(chars, i)
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

      # Scan a quoted string beginning at chars[i] (a `"` or `'`). Appends it
      # verbatim (honoring backslash escapes) and returns the index just past
      # the closing quote.
      private def scan_quoted(chars : String, i : Int32, len : Int32, lb : String::Builder) : Int32
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
      # flags) verbatim and returns the index just past the literal. Mirrors the
      # main loop's regex handling, including its limitation of not modelling
      # `[...]` character classes (an unescaped `/` inside a class still ends the
      # literal) — kept identical so behaviour matches the top-level scanner.
      private def scan_regex(chars : String, i : Int32, len : Int32, lb : String::Builder) : Int32
        lb << chars[i] # opening /
        i += 1
        while i < len
          c = chars[i]
          lb << c
          if c == '\\' && i + 1 < len
            i += 1
            lb << chars[i]
          elsif c == '/'
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
