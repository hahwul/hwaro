# CSS minification utilities
#
# Provides conservative CSS minification that removes unnecessary
# whitespace and comments while preserving functional correctness.
#
# Operations:
# - Remove CSS comments (/* ... */)
# - Collapse whitespace
# - Remove whitespace around structural characters
# - Strip trailing semicolons before }
# - Preserve url() contents and string literals
#
# Comments, string literals and `url(...)` values are recognised in a
# SINGLE left-to-right scan rather than by three ordered regex passes.
# Ordering separate passes cannot be made correct: a quote inside a
# comment (`/* don't */`) starts a bogus string literal that swallows
# real rules up to the next quote, while a comment marker inside a
# string (`content: "/* x */"`) must not be stripped. Only a scanner
# that consumes whichever construct opens first gets both right.
#
# All whitespace classes below are the five HTML/CSS space characters
# (`[ \t\r\n\f]`) rather than `\s`: Crystal compiles patterns with
# PCRE2's UCP flag, so `\s` would also match U+00A0/U+3000, which are
# not CSS whitespace.

module Hwaro
  module Utils
    module CssMinifier
      extend self

      # Sentinel wrapper for stashed strings/urls. `\x00` cannot appear in
      # a stylesheet, so the placeholder can't collide with author content.
      private PRESERVE_PREFIX = "\x00PRESERVE_"
      private PRESERVE_SUFFIX = "\x00"

      private WS_RUN        = /[ \t\r\n\f]+/
      private WS_STRUCTURAL = /[ \t\r\n\f]*([{};,])[ \t\r\n\f]*/
      private WS_COLON      = /[ \t\r\n\f]*:[ \t\r\n\f]*/
      private PAREN_GROUP   = /\(([^)]*)\)/
      private RESTORE_TOKEN = /\x00PRESERVE_(\d+)\x00/

      # Perform conservative CSS minification
      def minify(css : String) : String
        preserves = [] of String

        # ── Step 1: strip comments, stash strings and url() values ────────
        result = extract_tokens(css, preserves)

        # ── Step 2: Collapse whitespace ───────────────────────────────────
        result = result.gsub(WS_RUN, " ")

        # ── Step 3: Remove space around structural characters ─────────────
        # Single pass for `{`, `}`, `;`, `,` — these targets are disjoint
        # (none can appear inside another's match) so one scan is equivalent
        # to four sequential gsubs but allocates only one string.
        result = result.gsub(WS_STRUCTURAL) { $1 }

        # ── Step 4: Collapse `:` spacing, structurally ────────────────────
        result = collapse_colons(result)

        # ── Step 5: Strip trailing semicolons before } ────────────────────
        result = result.gsub(";}", "}")

        # ── Step 6: Restore preserved tokens (single-pass) ────────────────
        unless preserves.empty?
          result = result.gsub(RESTORE_TOKEN) do
            # to_i? guards against a counterfeit token whose index overflows
            # Int32 — return $0 unchanged rather than raising ArgumentError.
            idx = $1.to_i?
            idx && idx < preserves.size ? preserves[idx] : $0
          end
        end

        result.strip
      end

      # Single scan that drops comments and replaces string literals and
      # `url(...)` values with placeholders. Operates on the UTF-8 byte view:
      # every delimiter it looks for is 7-bit ASCII and a UTF-8 continuation
      # byte is always >= 0x80, so a byte scan can never mistake part of a
      # multi-byte character for a delimiter — and it avoids the O(n²) that
      # `String#[](Int32)` random access costs on non-ASCII input.
      private def extract_tokens(css : String, preserves : Array(String)) : String
        bytes = css.to_slice
        n = bytes.size
        String.build(css.bytesize) do |io|
          i = 0
          while i < n
            b = bytes[i]
            case b
            when '/'.ord
              if i + 1 < n && bytes[i + 1] == '*'.ord
                # Comment — dropped. An unterminated comment runs to EOF,
                # which is how browsers parse it too.
                i = skip_comment(bytes, i, n)
                next
              end
            when '"'.ord, '\''.ord
              if (stop = scan_string_end(bytes, i, n)) >= 0
                stash(io, preserves, String.new(bytes[i, stop - i]))
                i = stop
                next
              end
              # Unterminated literal: emit verbatim, like the old regex pass.
            when 'u'.ord, 'U'.ord
              if stop = scan_url(bytes, i, n, preserves, io)
                i = stop
                next
              end
            end
            io.write_byte(b)
            i += 1
          end
        end
      end

      # Append `text` to `preserves` and write its placeholder to `io`.
      private def stash(io : IO, preserves : Array(String), text : String) : Nil
        preserves << text
        io << PRESERVE_PREFIX << (preserves.size - 1) << PRESERVE_SUFFIX
      end

      # Index just past the closing `*/`, or `n` when the comment is
      # unterminated. `start` points at the opening `/`.
      private def skip_comment(bytes : Bytes, start : Int32, n : Int32) : Int32
        i = start + 2
        while i + 1 < n
          return i + 2 if bytes[i] == '*'.ord && bytes[i + 1] == '/'.ord
          i += 1
        end
        n
      end

      # Index just past the closing quote of the literal starting at
      # `start`, or -1 when unterminated.
      private def scan_string_end(bytes : Bytes, start : Int32, n : Int32) : Int32
        quote = bytes[start]
        i = start + 1
        while i < n
          b = bytes[i]
          if b == '\\'.ord
            i += 2
            next
          end
          return i + 1 if b == quote
          i += 1
        end
        -1
      end

      # Recognise `url( ... )` at `start` (case-insensitive, and only when
      # `url` is a standalone identifier). On success the normalised value —
      # inner whitespace trimmed, quoting preserved — is stashed and the
      # index just past the closing `)` is returned. Returns nil when this
      # is not a url token, so the caller falls back to copying bytes.
      private def scan_url(bytes : Bytes, start : Int32, n : Int32, preserves : Array(String), io : IO) : Int32?
        return unless start + 4 <= n
        return unless lower(bytes[start]) == 'u'.ord &&
                      lower(bytes[start + 1]) == 'r'.ord &&
                      lower(bytes[start + 2]) == 'l'.ord &&
                      bytes[start + 3] == '('.ord
        return if start > 0 && ident_byte?(bytes[start - 1])

        i = start + 4
        while i < n && space_byte?(bytes[i])
          i += 1
        end

        quote = 0_u8
        if i < n && (bytes[i] == '"'.ord || bytes[i] == '\''.ord)
          stop = scan_string_end(bytes, i, n)
          return if stop < 0
          quote = bytes[i]
          inner = String.new(bytes[i + 1, stop - i - 2])
          i = stop
        else
          j = i
          while j < n && bytes[j] != ')'.ord
            j += 1
          end
          return if j >= n
          inner = String.new(bytes[i, j - i]).rstrip(" \t\r\n\f")
          i = j
        end

        while i < n && space_byte?(bytes[i])
          i += 1
        end
        return unless i < n && bytes[i] == ')'.ord
        return if inner.empty?

        q = quote == 0_u8 ? "" : quote.unsafe_chr.to_s
        # Keep the author's casing of the function name (`URL(` stays `URL(`).
        stash(io, preserves, "#{String.new(bytes[start, 3])}(#{q}#{inner}#{q})")
        i + 1
      end

      private def lower(b : UInt8) : Int32
        (b | 0x20).to_i
      end

      private def space_byte?(b : UInt8) : Bool
        b == ' '.ord || b == '\t'.ord || b == '\r'.ord || b == '\n'.ord || b == '\f'.ord
      end

      private def ident_byte?(b : UInt8) : Bool
        (b >= 'a'.ord && b <= 'z'.ord) || (b >= 'A'.ord && b <= 'Z'.ord) ||
          (b >= '0'.ord && b <= '9'.ord) || b == '-'.ord || b == '_'.ord || b >= 0x80
      end

      # Collapse whitespace around `:` — but only where a `:` separates a
      # property from its value, never where it introduces a pseudo-class.
      #
      # The stylesheet is split into runs delimited by `{`, `}` and `;`,
      # and each run is classified by its terminator and brace depth:
      #
      #   * terminated by `{`  → a prelude (selector or at-rule condition)
      #   * `;`/`}` at depth 0 → a top-level at-rule statement (`@import …;`)
      #   * `;`/`}` deeper     → a declaration
      #
      # Only declarations get their colons tightened. Preludes keep theirs,
      # so the descendant combinator in `.card :hover` survives; the sole
      # exception is an at-rule prelude, where a colon inside parentheses is
      # a media/supports feature test (`@media (max-width: 600px)`).
      #
      # A depth-blind regex over `\{([^}]*)\}` cannot make this distinction:
      # inside `@media screen{.card :hover{…}}` the first `{`…`}` span
      # reaches into the *nested* selector, and `.card :hover` was being
      # rewritten to the (differently-matching) compound `.card:hover`.
      private def collapse_colons(css : String) : String
        return css unless css.includes?(':')
        String.build(css.bytesize) do |io|
          run = String::Builder.new
          depth = 0
          css.each_char do |ch|
            case ch
            when '{'
              io << collapse_prelude(run.to_s)
              io << ch
              run = String::Builder.new
              depth += 1
            when '}', ';'
              io << (depth > 0 ? collapse_declaration(run.to_s) : collapse_prelude(run.to_s))
              io << ch
              run = String::Builder.new
              depth -= 1 if ch == '}' && depth > 0
            else
              run << ch
            end
          end
          io << collapse_prelude(run.to_s)
        end
      end

      # Selector / at-rule condition: only an at-rule's parenthesised
      # feature tests get their colons tightened.
      private def collapse_prelude(run : String) : String
        return run unless run.includes?(':')
        return run unless run.lstrip(" \t\r\n\f").starts_with?('@')
        run.gsub(PAREN_GROUP) { "(" + $1.gsub(WS_COLON, ":") + ")" }
      end

      # Declaration: every `:` is a property/value separator.
      private def collapse_declaration(run : String) : String
        return run unless run.includes?(':')
        run.gsub(WS_COLON, ":")
      end
    end
  end
end
