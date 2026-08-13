# HTML minification utilities
#
# Aggressively shrinks rendered HTML while staying visually equivalent
# to the input. The contract:
#
#   1. Whitespace-sensitive elements (<pre>, <textarea>, <script>,
#      <style>, <code>, <svg>, <math>, <noscript>) are extracted as
#      opaque, typed placeholders before any whitespace pass touches
#      the document and restored verbatim at the end. Each tag is
#      handled in its own pass so a stray alternation in non-greedy
#      matching can't pair an open <pre> with a close </script>.
#      Placeholders carry the element's default display classification
#      (block or inline) so the whitespace collapse can treat the
#      sealed block as if it were still its original tag for the
#      purpose of deciding whether neighbouring whitespace is visible.
#
#   2. Inter-token whitespace is collapsed by classifying both
#      neighbours (tags or placeholders) by HTML default display.
#      If either neighbour is a block-level tag the whitespace is
#      stripped entirely (browsers collapse whitespace at the start,
#      end, or between block siblings). Only when both neighbours are
#      inline do we keep a single space so adjacent inline siblings
#      like `<a>x</a> <a>y</a>` keep their visible gap.
#
#   3. Whitespace *inside* tag openings is collapsed with a
#      quote-aware scan: runs of whitespace between attributes
#      shrink to a single space and trailing whitespace before the
#      closing `>` is stripped. Quoted attribute values are passed
#      through untouched so `title="x  y"` retains its inner spacing.
#
# What is NOT done: variable renaming, attribute-value rewriting,
# or entity collapsing. For more aggressive output shrinking,
# post-process with a dedicated tool (`html-minifier-terser`,
# `minify-html`).

module Hwaro
  module Utils
    module HtmlMinifier
      extend self

      # HTML block-level elements. Whitespace adjacent to a block-level
      # neighbour has no visual effect:
      #   * between two block siblings the user agent renders them on
      #     separate lines anyway,
      #   * leading whitespace inside a block parent is collapsed by
      #     the browser before the first inline child,
      #   * trailing whitespace before a block close is collapsed
      #     after the last inline child.
      # Anything not listed here is treated as inline, where whitespace
      # between siblings collapses to a single rendered space and must
      # therefore be kept as one literal space. Replaced elements that
      # default to display:inline (iframe, video, audio, canvas, embed,
      # object) are deliberately NOT listed: whitespace adjacent to them
      # renders as a visible space and must be preserved.
      BLOCK_TAGS = Set{
        "address", "article", "aside", "base", "blockquote", "body",
        "caption", "col", "colgroup", "dd", "details", "dialog",
        "div", "dl", "dt", "fieldset", "figcaption", "figure",
        "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
        "head", "header", "hgroup", "hr", "html",
        "li", "link", "main", "menu", "meta", "nav", "noscript",
        "ol", "p", "picture", "pre", "script", "section",
        "source", "style", "summary", "table", "tbody", "td",
        "tfoot", "th", "thead", "title", "tr", "track", "ul",
      }

      # Tags whose content must be preserved verbatim. Extracted into
      # placeholders before any whitespace pass and restored afterward.
      # `code` is included because inline-code snippets often carry
      # whitespace that authors expect to ship unchanged.
      #
      # Order matters: a `<style>` body may legitimately contain the
      # literal string `<script>` (e.g. `content: "<script>"`), so
      # `style` is extracted first to remove that text from view
      # before the `script` pass runs.
      PROTECTED_TAGS = %w[pre textarea style script code svg math noscript]

      # Classification of protected tags by default HTML display so
      # the inter-token whitespace pass can treat sealed blocks as if
      # they were their original tag.
      PROTECTED_INLINE = Set{"code", "svg", "math", "textarea"}

      # Per-tag extraction patterns, compiled once at load time. minify()
      # runs once per rendered page, so building these eight Regex objects
      # inside protect_sensitive_blocks paid a PCRE2 compile per tag per
      # page. Array (not Hash) to preserve PROTECTED_TAGS order — `style`
      # must be extracted before `script` (see comment above).
      private PROTECTED_PATTERNS = PROTECTED_TAGS.map do |tag|
        {tag,
        # Cheap presence probe: most pages carry no <textarea>, <math>,
        # <noscript>, …, and the heavy `.*?` extraction pattern below has
        # no fast no-match path (every '<' in the document is a candidate
        # start). The lowercase literal decides via memchr for the
        # markdown-rendered common case; the case-insensitive probe covers
        # author-written uppercase tags.
         "<#{tag}",
         Regex.new("<#{tag}", Regex::Options::IGNORE_CASE),
         Regex.new(
           "<#{tag}\\b[^>]*>.*?</#{tag}\\s*>",
           Regex::Options::IGNORE_CASE | Regex::Options::MULTILINE
         )}
      end

      # Sentinel format for protected blocks. `\x00` is illegal in HTML,
      # so the placeholder cannot collide with author content. The
      # `B`/`I` suffix lets the whitespace collapser look up the
      # original element's display class without re-parsing the body.
      private PRESERVE_PREFIX_BLOCK  = "\x00HW_HTML_PB_"
      private PRESERVE_PREFIX_INLINE = "\x00HW_HTML_PI_"
      private PRESERVE_SUFFIX        = "\x00"
      # Common prefix of both placeholder forms, for cheap presence probes.
      private PRESERVE_TOKEN_PROBE = "\x00HW_HTML_P"

      # Regex constants
      private REGEX_COMMENTS       = /<!--(?!\[if|#|\s*more\s*-->).*?-->/m
      private REGEX_TRAILING_SPACE = /[ \t]+$/m
      # Match a structural token immediately followed by whitespace and
      # lookahead at the next structural token. A "token" here is
      # either a regular tag or one of our protected-block
      # placeholders. Captures:
      #   $1 = prior token (full text)
      #   $2 = whitespace run
      #   $3 = next token (full text, via lookahead)
      #
      # Known limitation: `[^>]*` does not understand quoted attribute
      # values, so a literal `>` inside an attribute (`title="x > y"`)
      # is treated as the tag's end. The intra-tag pass is quote-aware
      # and runs first, but it cannot rewrite the value text itself —
      # in those rare cases this pass simply leaves the surrounding
      # whitespace untouched (the prior conservative behaviour).
      #
      # The whitespace run is `[ \t\r\n\f]+`, NOT `\s+`. Crystal compiles
      # patterns with PCRE2's UCP flag, so `\s` also matches U+00A0
      # (NBSP), U+3000 and the other Unicode space separators — none of
      # which are HTML "space characters". Those are *content*: an
      # `&nbsp;` written between two tags decodes to a literal U+00A0 in
      # the rendered HTML, and collapsing it either downgraded it to a
      # breakable space (inline neighbours) or deleted it outright
      # (block neighbours), silently changing the rendered page.
      private REGEX_INTERTOKEN_WS  = /(<\/?[A-Za-z][\w-]*[^>]*>|\x00HW_HTML_P[BI]_\d+\x00)([ \t\r\n\f]+)(?=(<\/?[A-Za-z][\w-]*[^>]*>|\x00HW_HTML_P[BI]_\d+\x00))/
      private REGEX_TAG_NAME       = /^<\/?([A-Za-z][\w-]*)/
      private REGEX_BLANK_LINES    = /\n{2,}/
      private REGEX_PRESERVE_TOKEN = /\x00HW_HTML_P[BI]_(\d+)\x00/

      # Minify the given HTML.
      #
      # Example:
      #   minify("<div>\n  <p>Hello</p>\n</div>")
      #   # => "<div><p>Hello</p></div>"
      #
      #   minify("<span>x</span>\n<span>y</span>")
      #   # => "<span>x</span> <span>y</span>"
      # Drop every NUL byte from a rendered document.
      #
      # NUL is not valid in HTML text (parsers replace it with U+FFFD), and it
      # never appears in author input — but it does reach the rendered page
      # through a data-file value (data/x.json, data/x.yml), and its absence is
      # the ONLY thing that makes the `\x00`-delimited sentinels below
      # collision-proof: a forged `\x00HW_HTML_PB_0\x00` arriving that way made
      # restore_sensitive_blocks substitute a preserved block into itself, the
      # string grew by one copy per pass, and the fixed point never converged —
      # `hwaro build --minify` hung forever.
      #
      # Applied by the RENDER phase to every page, minified or not, so the two
      # build modes cannot disagree on page bytes: scrubbing only inside
      # `minify` made an optional whitespace pass silently delete a byte of
      # author-controlled content that a plain build emitted. Dropping (rather
      # than substituting U+FFFD) is deliberate — the byte carries no meaning
      # here and a replacement character in the page would be a worse surprise
      # than its absence.
      #
      # Filtered byte-wise rather than with `String#delete` so that invalid
      # UTF-8 elsewhere in the page survives verbatim instead of being folded
      # to U+FFFD; NUL never appears inside a multi-byte sequence, so this is
      # safe.
      def scrub_nul(html : String) : String
        return html unless html.byte_index(0)
        String.build(html.bytesize) do |io|
          html.each_byte { |b| io.write_byte(b) unless b == 0 }
        end
      end

      def minify(html : String) : String
        # Re-established here too, not only at the call site: this module's
        # placeholder scheme must not depend on a caller having scrubbed for
        # it. The probe is a single memchr on the common (clean) page.
        html = scrub_nul(html)
        preserves = [] of String
        result = protect_sensitive_blocks(html, preserves)
        result = result.gsub(REGEX_COMMENTS, "")
        result = result.gsub(REGEX_TRAILING_SPACE, "")
        result = collapse_intra_tag_whitespace(result)
        result = collapse_inter_token_whitespace(result)
        result = result.gsub(REGEX_BLANK_LINES, "\n")
        result = restore_sensitive_blocks(result, preserves)
        result.strip
      end

      # Extract whitespace-sensitive elements one tag at a time. A
      # single regex with alternation in the open/close tag (e.g.
      # `<(pre|script)>...</(pre|script)>`) does not enforce that both
      # sides reference the same tag, which let prior implementations
      # pair `<pre>` openers with `</script>` closers when the document
      # mixed both. One pass per tag avoids that whole class of bug.
      private def protect_sensitive_blocks(html : String, preserves : Array(String)) : String
        result = html
        PROTECTED_PATTERNS.each do |(tag, open_literal, probe, pattern)|
          next unless result.includes?(open_literal) || result.matches?(probe)
          prefix = PROTECTED_INLINE.includes?(tag) ? PRESERVE_PREFIX_INLINE : PRESERVE_PREFIX_BLOCK
          result = result.gsub(pattern) do |match|
            idx = preserves.size
            preserves << match
            "#{prefix}#{idx}#{PRESERVE_SUFFIX}"
          end
        end
        result
      end

      # Restore in a fixed-point loop: a protected block (e.g. a `<style>`
      # extracted before `<script>`) can be captured *inside* a later block, so
      # the first restore leaves an inner placeholder behind. Re-scan until no
      # token remains; a dangling index returns $0 unchanged. The original
      # termination argument — "restored content is author HTML, which cannot
      # contain a valid \x00-delimited token because NUL is illegal in author
      # input" — turned out to be false (NUL reaches the rendered page through
      # data-file values), so termination now rests on minify()'s NUL scrub
      # plus the hard pass cap below rather than on that invariant alone.
      #
      # Public (not private) so the counterfeit-token guards below stay
      # testable: with `minify`'s NUL scrub in front of it, no forged token can
      # reach this method through the public entry point any more, and a spec
      # that goes through `minify` therefore exercises neither guard — a
      # mutation that deletes both still passes. They are defence-in-depth for
      # any future caller, and dead guards nobody can test are how they rot.
      def restore_sensitive_blocks(html : String, preserves : Array(String)) : String
        return html if preserves.empty?
        # Hard bound on the fixed point, belt-and-braces behind the NUL
        # scrub in minify(). Legitimate re-expansion only ever chains
        # "outer block hands back an inner placeholder", and extraction
        # hands out strictly increasing indices, so a nesting chain is at
        # most `preserves.size` links long and that many passes always
        # suffice. Anything still substituting past it is a self-referential
        # token (a caller that reached this module with NUL still in the
        # document), which would otherwise grow the page by one copy per
        # pass forever — the same hazard the placeholder restore in
        # src/content/processors/markdown_extensions.cr caps at 2 passes.
        preserves.size.times do
          # memchr probe: once the last token is restored the loop used to
          # pay one full confirming regex pass over the document.
          break unless html.includes?(PRESERVE_TOKEN_PROBE)
          replaced = html.gsub(REGEX_PRESERVE_TOKEN) do
            # to_i? (not to_i) so a counterfeit token whose digits overflow
            # Int32 (e.g. \x00HW_HTML_PB_99999999999999999999\x00 forged in
            # author input) returns nil → emit $0 unchanged instead of raising
            # ArgumentError and aborting minification of the whole page.
            idx = $1.to_i?
            idx && idx < preserves.size ? preserves[idx] : $0
          end
          break if replaced == html
          html = replaced
        end
        html
      end

      # Collapse whitespace between two structural tokens. The token
      # classification distinguishes block from inline so we can:
      #   * strip whitespace entirely when either neighbour is block
      #     (leading inside block / trailing inside block / between
      #     block siblings — all collapsed by browsers anyway), and
      #   * keep a single space only when both neighbours are inline,
      #     preserving the visible gap between adjacent inline elements
      #     like `<a>x</a> <a>y</a>`.
      private def collapse_inter_token_whitespace(html : String) : String
        html.gsub(REGEX_INTERTOKEN_WS) do
          prior = $1
          # $2 = whitespace run (discarded except when we re-emit one space)
          nxt = $3
          if block_token?(prior) || block_token?(nxt)
            prior
          else
            "#{prior} "
          end
        end
      end

      # True if the structural token is a block-level tag (or a
      # placeholder for a protected element whose default display is
      # block).
      private def block_token?(token : String) : Bool
        return true if token.starts_with?(PRESERVE_PREFIX_BLOCK)
        return false if token.starts_with?(PRESERVE_PREFIX_INLINE)
        if m = REGEX_TAG_NAME.match(token)
          BLOCK_TAGS.includes?(m[1].downcase)
        else
          false
        end
      end

      # Collapse whitespace runs *inside* tag openings to a single
      # space, and strip whitespace immediately before the closing
      # `>` or `/>`. The scan is quote-aware so attribute values
      # like `title="x  y"` survive unchanged. Comments, DOCTYPEs
      # (`<!...>`) and processing instructions (`<?...?>`) are
      # ignored. Protected-block placeholders are also ignored
      # (their bodies are already opaque).
      private def collapse_intra_tag_whitespace(html : String) : String
        return html if html.empty?
        bytes = html.to_slice
        n = bytes.size
        String.build(n) do |io|
          i = 0
          while i < n
            b = bytes[i]
            if b == '<'.ord
              if i + 1 < n && tag_start_byte?(bytes[i + 1])
                tag_end = find_tag_end(bytes, i, n)
                if tag_end >= 0
                  emit_collapsed_tag(io, bytes, i, tag_end)
                  i = tag_end + 1
                  next
                end
              end
            end
            io.write_byte(b)
            i += 1
          end
        end
      end

      # The byte immediately following `<` must look like the start of
      # a real tag name or a closing tag. We deliberately exclude `!`
      # (DOCTYPE / declarations) and `?` (processing instructions).
      private def tag_start_byte?(b : UInt8) : Bool
        return true if (b >= 'a'.ord && b <= 'z'.ord) || (b >= 'A'.ord && b <= 'Z'.ord)
        b == '/'.ord
      end

      # Scan forward from `start` (pointing at `<`) to the matching
      # `>` while respecting single- and double-quoted attribute
      # values. Returns the index of the closing `>` or -1 if the
      # tag is unterminated (in which case the caller falls back to
      # emitting the byte literally and continues).
      private def find_tag_end(bytes : Bytes, start : Int32, n : Int32) : Int32
        i = start + 1
        quote = 0_u8
        while i < n
          b = bytes[i]
          if quote != 0_u8
            quote = 0_u8 if b == quote
          else
            return i if b == '>'.ord
            quote = b if b == '"'.ord || b == '\''.ord
          end
          i += 1
        end
        -1
      end

      # Write the tag at `bytes[start..tag_end]` to `io` with internal
      # whitespace collapsed. The tag-name run is copied verbatim;
      # then we collapse whitespace between attributes, preserve
      # quoted values, and strip any trailing whitespace before the
      # final `>` (or `/>` for self-closing).
      private def emit_collapsed_tag(io : IO, bytes : Bytes, start : Int32, tag_end : Int32) : Nil
        # Buffer the tag body (minus the closing `>`) into a slice so
        # we can collapse and trim, then emit `>` at the end.
        # We can't easily trim trailing whitespace from an already-
        # written IO, so do it in a local buffer.
        body = String.build(tag_end - start + 1) do |buf|
          i = start
          # Copy `<` (and optional `/`)
          buf.write_byte(bytes[i])
          i += 1
          if i < tag_end && bytes[i] == '/'.ord
            buf.write_byte(bytes[i])
            i += 1
          end
          # Copy the tag name run.
          while i < tag_end && (
                  (bytes[i] >= 'a'.ord && bytes[i] <= 'z'.ord) ||
                  (bytes[i] >= 'A'.ord && bytes[i] <= 'Z'.ord) ||
                  (bytes[i] >= '0'.ord && bytes[i] <= '9'.ord) ||
                  bytes[i] == '-'.ord || bytes[i] == ':'.ord
                )
            buf.write_byte(bytes[i])
            i += 1
          end
          # Walk the attribute area collapsing whitespace and
          # respecting quotes.
          last_was_space = false
          quote = 0_u8
          while i < tag_end
            b = bytes[i]
            if quote != 0_u8
              buf.write_byte(b)
              quote = 0_u8 if b == quote
              last_was_space = false
            elsif b == ' '.ord || b == '\t'.ord || b == '\n'.ord || b == '\r'.ord
              unless last_was_space
                buf.write_byte(' '.ord.to_u8)
                last_was_space = true
              end
            else
              buf.write_byte(b)
              quote = b if b == '"'.ord || b == '\''.ord
              last_was_space = false
            end
            i += 1
          end
        end
        # Drop trailing whitespace before the `>`. For self-closing
        # tags `<br />` the `/` is the last byte of `body`; we then
        # also strip the single space we inserted between the
        # attributes and the `/` so the output is `<br/>`. `rchop`
        # is suffix-equality (byte-safe), so it works even when
        # the byte preceding the `" /"` is part of a multi-byte
        # UTF-8 sequence inside a quoted attribute value.
        body = body.rstrip
        body = body.rchop(" /") + "/" if body.ends_with?(" /")
        io << body
        io.write_byte('>'.ord.to_u8)
      end
    end
  end
end
