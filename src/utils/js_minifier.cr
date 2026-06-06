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

            # Template literals — track ${...} nesting depth. Captured into a
            # placeholder so the trailing line-cleanup pass can't alter newlines
            # or whitespace that are part of the literal's value.
            if c == '`'
              lit = String.build do |lb|
                lb << c
                i += 1
                depth = 0
                while i < len
                  sc = chars[i]
                  lb << sc
                  if sc == '\\' && i + 1 < len
                    i += 1
                    lb << chars[i]
                  elsif sc == '$' && i + 1 < len && chars[i + 1] == '{'
                    lb << chars[i + 1]
                    i += 1
                    depth += 1
                  elsif sc == '{' && depth > 0
                    # Nested brace inside ${...}
                  elsif sc == '}' && depth > 0
                    depth -= 1
                  elsif sc == '`' && depth == 0
                    break
                  end
                  i += 1
                end
                i += 1
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

        # Restore protected template literals verbatim.
        return cleaned if protected_spans.empty?
        cleaned.gsub(/\x00JSPL(\d+)\x00/) { protected_spans[$1.to_i] }
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
    end
  end
end
