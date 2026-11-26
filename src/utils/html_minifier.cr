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
      # object — and `picture`, an inline wrapper around its `<img>`) are
      # deliberately NOT listed: whitespace adjacent to them renders as a
      # visible space and must be preserved.
      BLOCK_TAGS = Set{
        "address", "article", "aside", "blockquote", "body",
        "caption", "col", "colgroup", "dd", "details", "dialog",
        "div", "dl", "dt", "fieldset", "figcaption", "figure",
        "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
        "head", "header", "hgroup", "hr", "html",
        "li", "main", "menu", "nav", "noscript",
        "ol", "p", "pre", "script", "section",
        "style", "summary", "table", "tbody", "td",
        "tfoot", "th", "thead", "title", "tr", "ul",
      }

      # Void elements that render nothing (display:none). Like a hidden
      # placeholder (PROTECTED_HIDDEN) they are no block boundary: a
      # microdata `<meta itemprop>` between two inline siblings
      # (`<span>Jane</span> <meta …> <span>wrote</span>`), or the `<source>`
      # opening an inline `<picture>`, leaves the space around it visible,
      # and classing them as block deleted it ("Janewrote"). Between two
      # hidden neighbours — the run of `<meta>`/`<link>` tags in `<head>` —
      # the whitespace is still stripped.
      HIDDEN_TAGS = Set{"base", "link", "meta", "source", "track"}

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

      # Protected tags that render nothing (display:none; `noscript` while
      # scripting is on). They take no part in whitespace collapsing, so
      # the space beside one still separates the inline content around
      # it: `<b>a</b> <script>…</script> <b>c</b>` renders "a c", and
      # treating the script as block deleted that gap ("ac").
      PROTECTED_HIDDEN = Set{"script", "style", "noscript"}

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
        # start). The lowercase literal decides via `ByteScan`'s memchr scan
        # for the markdown-rendered common case; the case-insensitive probe
        # covers author-written uppercase tags.
         "<#{tag}",
         Regex.new("<#{tag}", Regex::Options::IGNORE_CASE),
         # `(?![\w-])`, not `\b`: a custom element such as `<pre-view>`
         # or `<math-field>` is not the protected tag, and `\b` matched it
         # and sealed everything up to the next real `</pre>` as one block.
         Regex.new(
           "<#{tag}(?![\\w-])[^>]*>.*?</#{tag}\\s*>",
           Regex::Options::IGNORE_CASE | Regex::Options::MULTILINE
         )}
      end

      # Every protected tag's probe in one caseless pass, one capture group
      # per tag in PROTECTED_TAGS order. Eight separate probes each walked
      # every `<` of the page; a tag this pass does not see cannot appear
      # later either (extraction only replaces text with `<`-free tokens).
      private PROTECTED_OPEN_ANY = Regex.new(
        "<(?:#{PROTECTED_TAGS.map { |tag| "(#{tag})" }.join('|')})",
        Regex::Options::IGNORE_CASE
      )

      # Only protected tag candidates inside removable HTML comments are
      # masked. Preserve the original bytes when a containing block is saved.
      private COMMENT_PROTECTED_TAG = Regex.new(
        "</?(?:#{PROTECTED_TAGS.join('|')})(?![\\w-])",
        Regex::Options::IGNORE_CASE
      )
      private COMMENT_TAG_LT = "\x00HW_HTML_COMMENT_LT\x00"

      # These bodies are opaque to the comment scan. In particular, SVG or
      # MathML can contain XML comments and CDATA, and a script string can
      # contain `<!--` without opening an HTML comment.
      private COMMENT_CONTEXT_CLOSERS = %w[script style textarea title iframe xmp noembed noframes noscript svg math].to_h do |name|
        {name, Regex.new("</#{name}\\s*>", Regex::Options::IGNORE_CASE)}
      end
      private COMMENT_CONTEXT_OPEN = Regex.new(
        "<(#{(COMMENT_CONTEXT_CLOSERS.keys + ["plaintext"]).join('|')})(?=[ \\t\\r\\n\\f/>])",
        Regex::Options::IGNORE_CASE
      )

      # Sentinel format for protected blocks. `\x00` is illegal in HTML,
      # so the placeholder cannot collide with author content. The
      # `B`/`I`/`H` suffix lets the whitespace collapser look up the
      # original element's display class without re-parsing the body.
      private PRESERVE_PREFIX_BLOCK  = "\x00HW_HTML_PB_"
      private PRESERVE_PREFIX_INLINE = "\x00HW_HTML_PI_"
      private PRESERVE_PREFIX_HIDDEN = "\x00HW_HTML_PH_"
      private PRESERVE_SUFFIX        = "\x00"
      # Common prefix of every placeholder form, for cheap presence probes.
      private PRESERVE_TOKEN_PROBE = "\x00HW_HTML_P"

      # Regex constants
      # The `<!-- more -->` summary marker, which the minifier keeps. Matched
      # against a comment's whole body (between `<!--` and `-->`).
      private REGEX_MORE_MARKER = /\A\s*more\s*\z/
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
      private REGEX_INTERTOKEN_WS  = /(<\/?[A-Za-z][\w-]*[^>]*>|\x00HW_HTML_P[BIH]_\d+\x00)([ \t\r\n\f]+)(?=(<\/?[A-Za-z][\w-]*[^>]*>|\x00HW_HTML_P[BIH]_\d+\x00))/
      private REGEX_TAG_NAME       = /^<\/?([A-Za-z][\w-]*)/
      private REGEX_PRESERVE_TOKEN = /\x00HW_HTML_P[BIH]_(\d{1,9})\x00/

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
        # memchr (via Slice#index), not `String#byte_index`, whose
        # byte-at-a-time loop is ~15x slower — this probe runs over every
        # rendered page.
        return html unless html.to_slice.index(0_u8)
        String.build(html.bytesize) do |io|
          html.each_byte { |b| io.write_byte(b) unless b == 0 }
        end
      end

      def minify(html : String) : String
        # Re-established here too, not only at the call site: this module's
        # placeholder scheme must not depend on a caller having scrubbed for
        # it. The probe is a single memchr on the common (clean) page.
        html = scrub_nul(html)
        # PCRE2 re-validates the UTF-8 of the rest of the page on every
        # match, so a gsub with many matches re-read the page per match.
        # Validate once; every pass below only edits ASCII between ASCII
        # delimiters, so what they hand on stays valid. Invalid input keeps
        # the checked matching (and its error) it always had.
        opts = utf8_opts(html)
        preserves = [] of String
        result = protect_sensitive_blocks(html, preserves, opts)
        result = strip_comments_and_trailing_space(result)
        result = collapse_intra_tag_whitespace(result)
        result = collapse_inter_token_whitespace(result)
        result = restore_sensitive_blocks(result, preserves)
        result.strip
      end

      # Extract whitespace-sensitive elements one tag at a time. A
      # single regex with alternation in the open/close tag (e.g.
      # `<(pre|script)>...</(pre|script)>`) does not enforce that both
      # sides reference the same tag, which let prior implementations
      # pair `<pre>` openers with `</script>` closers when the document
      # mixed both. One pass per tag avoids that whole class of bug.
      private def protect_sensitive_blocks(html : String, preserves : Array(String), opts : Regex::MatchOptions) : String
        result = mask_comment_tag_candidates(html, opts)
        masked = !result.same?(html)
        opened = Array.new(PROTECTED_TAGS.size, false)
        result.scan(PROTECTED_OPEN_ANY, options: opts) do |m|
          PROTECTED_TAGS.size.times { |i| opened[i] = true if m[i + 1]? }
        end
        PROTECTED_PATTERNS.each_with_index do |(tag, open_literal, probe, pattern), i|
          next unless opened[i]
          next unless ByteScan.includes?(result, open_literal) || result.matches?(probe, options: opts)
          prefix = if PROTECTED_INLINE.includes?(tag)
                     PRESERVE_PREFIX_INLINE
                   elsif PROTECTED_HIDDEN.includes?(tag)
                     PRESERVE_PREFIX_HIDDEN
                   else
                     PRESERVE_PREFIX_BLOCK
                   end
          result = result.gsub(pattern, options: opts) do |match|
            idx = preserves.size
            preserves << (masked ? match.gsub(COMMENT_TAG_LT, "<") : match)
            "#{prefix}#{idx}#{PRESERVE_SUFFIX}"
          end
        end
        masked ? result.gsub(COMMENT_TAG_LT, "<") : result
      end

      # A tag in a comment can pair with a real tag outside it. Mask only
      # those candidate delimiters before the existing block extraction, so a
      # later comment pass never sees a comment split across a placeholder.
      private def mask_comment_tag_candidates(html : String, opts : Regex::MatchOptions) : String
        bytes = html.to_slice
        return html unless possible_comment_tag_candidate?(html, bytes, opts)

        n = bytes.size
        anchored = opts | Regex::MatchOptions::ANCHORED
        cursor = 0
        copied = 0
        output : String::Builder? = nil
        while start = bytes.index('<'.ord.to_u8, cursor)
          cursor = start + 1
          if prefix_at?(bytes, start, "<!--")
            from = start + 4
            stop = comment_end(bytes, from, n)
            break if stop < 0
            cursor = stop
            body_end = stop - 3
            next if body_end <= from || kept_comment?(bytes, from, body_end)
            body = html.byte_slice(from, body_end - from)
            next unless body.matches?(COMMENT_PROTECTED_TAG, options: opts)

            stream = output ||= String::Builder.new(html.bytesize)
            stream.write(bytes[copied, from - copied])
            stream << body.gsub(COMMENT_PROTECTED_TAG, options: opts) { |tag| COMMENT_TAG_LT + tag.byte_slice(1) }
            copied = body_end
          elsif cursor < n && tag_start_byte?(bytes[cursor])
            tag_end = find_tag_end(bytes, start, n)
            break if tag_end < 0
            cursor = tag_end + 1
            if opener = COMMENT_CONTEXT_OPEN.match_at_byte_index(html, start, anchored)
              name = opener[1].downcase(:fold)
              break if name == "plaintext"
              if {"svg", "math"}.includes?(name) && bytes[tag_end - 1] == '/'.ord &&
                 foreign_self_closing?(bytes, opener.byte_end, tag_end - 1)
                next
              end
              closer = COMMENT_CONTEXT_CLOSERS[name].match_at_byte_index(html, cursor, opts)
              break unless closer
              cursor = closer.byte_end
            end
          end
        end
        return html unless output
        output.write(bytes[copied, n - copied])
        output.to_s
      end

      # A textual probe can overcount comment delimiters in raw text or
      # attributes. It avoids scanning markup on pages with plain comments.
      private def possible_comment_tag_candidate?(html : String, bytes : Bytes, opts : Regex::MatchOptions) : Bool
        cursor = 0
        while start = ByteScan.byte_index(html, "<!--", cursor)
          from = start + 4
          stop = comment_end(bytes, from, bytes.size)
          return false if stop < 0
          cursor = stop
          body_end = stop - 3
          if (left = bytes.index('<'.ord.to_u8, from)) && left < body_end
            return true if html.byte_slice(left, body_end - left).matches?(COMMENT_PROTECTED_TAG, options: opts)
          end
        end
        false
      end

      # A foreign start tag's final slash is part of the value if it comes
      # after `=` or an unquoted value. Whitespace after `=` is allowed.
      private def foreign_self_closing?(bytes : Bytes, cursor : Int32, slash : Int32) : Bool
        after_eq = false
        unquoted = false
        while cursor < slash
          byte = bytes[cursor]
          if intertoken_ws?(byte)
            unquoted = false
          elsif after_eq
            if byte == '"'.ord || byte == '\''.ord
              cursor = bytes.index(byte, cursor + 1) || slash
            else
              unquoted = true
            end
            after_eq = false
          elsif !unquoted && byte == '='.ord
            after_eq = true
          end
          cursor += 1
        end
        !after_eq && !unquoted
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
          break unless ByteScan.includes?(html, PRESERVE_TOKEN_PROBE)
          # Checked per pass: a caller's preserves need not be valid UTF-8.
          replaced = html.gsub(REGEX_PRESERVE_TOKEN, options: utf8_opts(html)) do
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

      private def utf8_opts(html : String) : Regex::MatchOptions
        html.valid_encoding? ? Regex::MatchOptions::NO_UTF_CHECK : Regex::MatchOptions::None
      end

      # Drop comments and the spaces/tabs that end a line — in TEXT only.
      # Tags are copied through verbatim (quote-aware, see find_tag_end): a
      # `<!-- … -->` or a line-final space inside an attribute value is part
      # of that value (`data-x="<!-- keep -->"`, a multi-line `content="…"`),
      # and the regex passes this replaces rewrote both.
      private def strip_comments_and_trailing_space(html : String) : String
        bytes = html.to_slice
        n = bytes.size
        String.build(n) do |io|
          # Spaces/tabs seen but not yet written. Kept as bytes, not as an
          # offset: a dropped comment can sit between two runs.
          pending = IO::Memory.new
          # Once a comment body starting at some offset has no `-->`, no later
          # one does either; remembering that keeps a run of unterminated
          # `<!--` linear instead of rescanning to the end for each.
          unterminated_from = n
          i = 0
          while i < n
            b = bytes[i]
            if b == ' '.ord || b == '\t'.ord
              pending.write_byte(b)
              i += 1
              next
            end
            if b == '\n'.ord
              pending.clear # line-final whitespace is dropped
              io.write_byte(b)
              i += 1
              next
            end
            if b == '<'.ord && i + 3 < n && bytes[i + 1] == '!'.ord && bytes[i + 2] == '-'.ord && bytes[i + 3] == '-'.ord
              close = i + 4 >= unterminated_from ? -1 : comment_end(bytes, i + 4, n)
              unterminated_from = i + 4 if close < 0 && i + 4 < unterminated_from
              if close >= 0
                unless kept_comment?(bytes, i + 4, close - 3)
                  i = close # dropped; pending whitespace stays pending
                  next
                end
                # A kept comment is copied whole. Re-scanning its body read
                # the `<!-->` that ends `<!--[if !IE]><!-->` as a new comment
                # and dropped everything up to the next `-->` — the content
                # every non-IE browser shows.
                unless pending.empty?
                  io.write(pending.to_slice)
                  pending.clear
                end
                io.write(bytes[i, close - i])
                i = close
                next
              end
            end
            unless pending.empty?
              io.write(pending.to_slice)
              pending.clear
            end
            if b == '<'.ord && i + 1 < n && tag_start_byte?(bytes[i + 1])
              tag_end = find_tag_end(bytes, i, n)
              if tag_end >= 0
                io.write(bytes[i, tag_end - i + 1])
                i = tag_end + 1
                next
              end
            end
            io.write_byte(b)
            i += 1
          end
          # Whitespace at the very end of the document is line-final too.
        end
      end

      # Index just past the `-->` closing a comment whose body starts at
      # `from`, or -1 when unterminated (left verbatim, like the old regex).
      private def comment_end(bytes : Bytes, from : Int32, n : Int32) : Int32
        # `<!-->` and `<!--->` are complete (empty) comments to an HTML parser.
        return from + 1 if from < n && bytes[from] == '>'.ord
        return from + 2 if from + 1 < n && bytes[from] == '-'.ord && bytes[from + 1] == '>'.ord
        i = from
        while i + 2 < n
          return i + 3 if bytes[i] == '-'.ord && bytes[i + 1] == '-'.ord && bytes[i + 2] == '>'.ord
          i += 1
        end
        -1
      end

      # True for a comment the minifier keeps: a conditional comment (`[if`),
      # an SSI directive (`#`) or the `<!-- more -->` summary marker. The
      # body is `bytes[from...body_end]`. The regex only ever sees that whole
      # body: both ends sit next to ASCII delimiters, so it is never a slice
      # cut through a multi-byte character (a fixed-size window was, and
      # PCRE2 raised "UTF-8 error", failing the whole `--minify` build).
      private def kept_comment?(bytes : Bytes, from : Int32, body_end : Int32) : Bool
        size = body_end - from
        return false if size <= 0
        first = bytes[from]
        return true if first == '#'.ord
        return true if first == '['.ord && size >= 3 && bytes[from + 1] == 'i'.ord && bytes[from + 2] == 'f'.ord
        # The `<!--<![endif]-->` closing a downlevel-revealed `<!--[if …]><!-->`.
        return true if size >= 7 && bytes[body_end - 7, 7] == "[endif]".to_slice
        # `more` plus any whitespace; skip the regex for anything shorter.
        return false if size < 4
        REGEX_MORE_MARKER.matches?(String.new(bytes[from, size]).scrub)
      end

      # Collapse whitespace between two structural tokens. The token
      # classification distinguishes block from inline so we can:
      #   * strip whitespace entirely when either neighbour is block
      #     (leading inside block / trailing inside block / between
      #     block siblings — all collapsed by browsers anyway), and
      #   * keep a single space only when both neighbours are inline,
      #     preserving the visible gap between adjacent inline elements
      #     like `<a>x</a> <a>y</a>`.
      # A hidden placeholder (script/style/noscript) is neither: next to
      # an inline neighbour its space is kept, between two hidden ones
      # (the usual run of tags in `<head>`) it is stripped.
      # ponytail: decided per pair, so `<b>a</b><script/> <script/><b>c</b>`
      # still loses its one space; look past hidden runs if that shows up.
      private def collapse_inter_token_whitespace(html : String) : String
        # A byte scan that makes REGEX_INTERTOKEN_WS's choices (same start
        # positions, same token extents, same retry on a failed start)
        # without a capture String per token. The regex stays the reference
        # and handles what the scan does not model: invalid UTF-8 (the
        # regex treats it differently) and non-ASCII where its UCP classes
        # look (`\w` in a tag name, `\d` in a placeholder).
        return collapse_inter_token_whitespace_regex(html) unless html.valid_encoding?
        bytes = html.to_slice
        n = bytes.size
        # Past the last `>` no tag can close: a run of unclosed `<` then
        # costs one probe each instead of a scan to the end.
        last_gt = bytes.rindex('>'.ord.to_u8) || -1
        values = tagged_value_spans(html)
        String.build(n) do |io|
          copied = 0
          i = 0
          while i < n
            b = bytes[i]
            unless b == '<'.ord || b == 0_u8
              i += 1
              next
            end
            prior_end = intertoken_end(bytes, i, n, last_gt)
            return collapse_inter_token_whitespace_regex(html) if prior_end == -2
            ws_end = prior_end
            while ws_end < n && intertoken_ws?(bytes[ws_end])
              ws_end += 1
            end
            if prior_end < 0 || ws_end == prior_end
              i += 1
              next
            end
            next_end = intertoken_end(bytes, ws_end, n, last_gt)
            return collapse_inter_token_whitespace_regex(html) if next_end == -2
            if next_end < 0
              i += 1
              next
            end
            # A match inside a quoted value is kept verbatim (see the regex
            # version); the scan resumes after its whitespace, as gsub does.
            if inside_span?(values, prior_end)
              i = ws_end
              next
            end
            prior_block = intertoken_block?(bytes, i, prior_end)
            next_block = intertoken_block?(bytes, ws_end, next_end)
            return collapse_inter_token_whitespace_regex(html) if prior_block.nil? || next_block.nil?
            io.write(bytes[copied, prior_end - copied])
            unless prior_block || next_block || (intertoken_hidden?(bytes, i, prior_end) && intertoken_hidden?(bytes, ws_end, next_end))
              io << ' '
            end
            copied = ws_end
            i = ws_end
          end
          io.write(bytes[copied, n - copied])
        end
      end

      # `[ \t\r\n\f]` — REGEX_INTERTOKEN_WS's whitespace class.
      private def intertoken_ws?(b : UInt8) : Bool
        b == ' '.ord || b == '\t'.ord || b == '\n'.ord || b == '\r'.ord || b == 0x0c
      end

      # End (exclusive) of a REGEX_INTERTOKEN_WS token starting at `i`, -1
      # when none starts there, -2 when only the regex can tell.
      #   tag:         `<` `/`? [A-Za-z] [^>]* `>`  (`[\w-]*[^>]*` matches
      #                exactly what `[^>]*` does)
      #   placeholder: `\0HW_HTML_P` [BIH] `_` \d+ `\0`
      private def intertoken_end(bytes : Bytes, i : Int32, n : Int32, last_gt : Int32) : Int32
        return -1 if i >= n
        if bytes[i] == '<'.ord
          j = i + 1
          j += 1 if j < n && bytes[j] == '/'.ord
          return -1 unless j < n && bytes[j].unsafe_chr.ascii_letter? && last_gt > j
          close = bytes[j + 1, n - j - 1].index('>'.ord.to_u8)
          return close ? j + 1 + close + 1 : -1
        end
        probe = PRESERVE_TOKEN_PROBE.bytesize
        return -1 unless n - i > probe + 3 && prefix_at?(bytes, i, PRESERVE_TOKEN_PROBE)
        j = i + probe
        return -1 unless {'B'.ord, 'I'.ord, 'H'.ord}.includes?(bytes[j]) && bytes[j + 1] == '_'.ord
        j += 2
        start = j
        while j < n && bytes[j].unsafe_chr.ascii_number?
          j += 1
        end
        return -2 if j < n && bytes[j] >= 0x80
        return -1 unless j > start && j < n && bytes[j] == 0_u8
        j + 1
      end

      # `block_token?` over `bytes[start...stop]` without building the
      # token; nil when a non-ASCII tag-name byte needs the Unicode rules
      # (`\w`, `downcase`) of the String version.
      private def intertoken_block?(bytes : Bytes, start : Int32, stop : Int32) : Bool?
        if bytes[start] == 0_u8
          return prefix_at?(bytes, start, PRESERVE_PREFIX_BLOCK)
        end
        return unless key = tag_name_key(bytes, start, stop)
        BLOCK_TAG_KEYS.includes?(key)
      end

      # The lowercased name of the tag at `bytes[start...stop]` packed into
      # an integer the way BLOCK_TAG_KEYS / HIDDEN_TAG_KEYS are (0 when it is
      # longer than any name in either set), or nil when a non-ASCII byte
      # ends the ASCII run of the name.
      private def tag_name_key(bytes : Bytes, start : Int32, stop : Int32) : UInt128?
        j = start + 1
        j += 1 if bytes[j] == '/'.ord
        name_start = j
        while j < stop
          b = bytes[j]
          break unless b.unsafe_chr.ascii_alphanumeric? || b == '_'.ord || b == '-'.ord
          j += 1
        end
        return if j < stop && bytes[j] >= 0x80
        return 0_u128 if j - name_start > BLOCK_TAG_MAX
        key = 0_u128
        (name_start...j).each { |k| key = (key << 8) | bytes[k].unsafe_chr.downcase.ord }
        key
      end

      # A hidden placeholder, or a HIDDEN_TAGS tag. Only asked once
      # `intertoken_block?` has classified the token, so a tag's name is
      # ASCII here.
      private def intertoken_hidden?(bytes : Bytes, start : Int32, stop : Int32) : Bool
        return prefix_at?(bytes, start, PRESERVE_PREFIX_HIDDEN) if bytes[start] == 0_u8
        HIDDEN_TAG_KEYS.includes?(tag_name_key(bytes, start, stop) || 0_u128)
      end

      private def prefix_at?(bytes : Bytes, start : Int32, prefix : String) : Bool
        bytes.size - start >= prefix.bytesize && bytes[start, prefix.bytesize] == prefix.to_slice
      end

      # BLOCK_TAGS names packed one byte each into an integer (they are at
      # most BLOCK_TAG_MAX ASCII bytes), so a token's name is looked up
      # without building a String.
      private BLOCK_TAG_MAX   = BLOCK_TAGS.max_of(&.bytesize)
      private BLOCK_TAG_KEYS  = BLOCK_TAGS.map { |tag| tag.each_byte.reduce(0_u128) { |key, b| (key << 8) | b } }.to_set
      private HIDDEN_TAG_KEYS = HIDDEN_TAGS.map { |tag| tag.each_byte.reduce(0_u128) { |key, b| (key << 8) | b } }.to_set

      private def collapse_inter_token_whitespace_regex(html : String) : String
        values = tagged_value_spans(html)
        html.gsub(REGEX_INTERTOKEN_WS) do
          # Tag-shaped text inside a quoted value (`data-x='<div>  <p>'`)
          # is the value's own bytes, not markup.
          next $0 if inside_span?(values, $~.byte_begin(2))
          prior = $1
          # $2 = whitespace run (discarded except when we re-emit one space)
          nxt = $3
          if block_token?(prior) || block_token?(nxt) || (hidden_token?(prior) && hidden_token?(nxt))
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
        if m = REGEX_TAG_NAME.match(token)
          BLOCK_TAGS.includes?(m[1].downcase)
        else
          false
        end
      end

      # Byte spans of the quoted attribute values that contain a `<` — the
      # only ones REGEX_INTERTOKEN_WS can match inside. As in HTML, a quote
      # opens a value only right after `=` (an apostrophe in `alt=Bob's` is
      # no value). Sorted and disjoint.
      private def tagged_value_spans(html : String) : Array({Int32, Int32})
        spans = [] of {Int32, Int32}
        bytes = html.to_slice
        n = bytes.size
        i = 0
        while lt = bytes.index('<'.ord.to_u8, i)
          i = lt + 1
          next unless i < n && tag_start_byte?(bytes[i])
          after_eq = false
          while i < n && bytes[i] != '>'.ord
            b = bytes[i]
            if after_eq && (b == '"'.ord || b == '\''.ord)
              close = bytes.index(b, i + 1)
              break unless close
              spans << {i + 1, close} if bytes[i + 1, close - i - 1].includes?('<'.ord.to_u8)
              i = close
              after_eq = false
            elsif b == '='.ord
              after_eq = true
            elsif !(b == ' '.ord || b == '\t'.ord || b == '\n'.ord || b == '\r'.ord || b == '\f'.ord)
              after_eq = false
            end
            i += 1
          end
        end
        spans
      end

      private def inside_span?(spans : Array({Int32, Int32}), pos : Int32) : Bool
        return false if spans.empty?
        idx = spans.bsearch_index { |(_, stop)| stop > pos }
        !idx.nil? && spans[idx][0] <= pos
      end

      private def hidden_token?(token : String) : Bool
        return true if token.starts_with?(PRESERVE_PREFIX_HIDDEN)
        if m = REGEX_TAG_NAME.match(token)
          HIDDEN_TAGS.includes?(m[1].downcase)
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
      #
      # Runs of blank lines in TEXT collapse to one newline here too. A
      # quoted value keeps its own: a whole-document `\n{2,}` pass rewrote
      # `data-copy="a\n\nb"` and multi-paragraph `content="…"` values.
      private def collapse_intra_tag_whitespace(html : String) : String
        return html if html.empty?
        bytes = html.to_slice
        n = bytes.size
        String.build(n) do |io|
          i = 0
          prev_newline = false
          while i < n
            b = bytes[i]
            if b == '<'.ord
              if i + 1 < n && tag_start_byte?(bytes[i + 1])
                tag_end = find_tag_end(bytes, i, n)
                if tag_end >= 0
                  emit_collapsed_tag(io, bytes, i, tag_end)
                  i = tag_end + 1
                  prev_newline = false
                  next
                end
              end
            end
            newline = b == '\n'.ord
            io.write_byte(b) unless newline && prev_newline
            prev_newline = newline
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

      # True when the attribute right before a trailing ` /` has an
      # UNQUOTED value (`<link href=/favicon.ico />`). There the space is what
      # ends the value: `href=/favicon.ico/` makes the slash part of the URL
      # (`/favicon.ico/`, a 404). A quoted value, a bare attribute name or the
      # tag name itself is ended by its own syntax, so `<br />` → `<br/>` and
      # `alt="x" />` → `alt="x"/>` stay safe.
      private def unquoted_value_before_slash?(body : String) : Bool
        rest = body.rchop(" /")
        last = rest.split(' ').last? || ""
        eq = last.index('=')
        return false unless eq
        value = last[(eq + 1)..]
        !value.empty? && !value.ends_with?('"') && !value.ends_with?('\'')
      end

      # True when `emit_collapsed_tag` would copy the tag unchanged, as most
      # tags (`<li>`, `</a>`, `<a href="x">`) are: outside quotes, only
      # single spaces (a tab/newline/CR becomes a space, a run collapses),
      # and an ASCII last byte that is neither whitespace nor `/` (nothing
      # for its trailing strip). Spares a String per tag.
      private def tag_verbatim?(bytes : Bytes, start : Int32, tag_end : Int32) : Bool
        last = bytes[tag_end - 1]
        return false if last >= 0x80 || last == '/'.ord || last.unsafe_chr.ascii_whitespace?
        quote = 0_u8
        i = start + 1
        while i < tag_end
          b = bytes[i]
          if quote != 0_u8
            quote = 0_u8 if b == quote
          elsif b == '"'.ord || b == '\''.ord
            quote = b
          elsif b == '\t'.ord || b == '\n'.ord || b == '\r'.ord || (b == ' '.ord && bytes[i - 1] == ' '.ord)
            return false
          end
          i += 1
        end
        true
      end

      # Write the tag at `bytes[start..tag_end]` to `io` with internal
      # whitespace collapsed. The tag-name run is copied verbatim;
      # then we collapse whitespace between attributes, preserve
      # quoted values, and strip any trailing whitespace before the
      # final `>` (or `/>` for self-closing).
      private def emit_collapsed_tag(io : IO, bytes : Bytes, start : Int32, tag_end : Int32) : Nil
        if tag_verbatim?(bytes, start, tag_end)
          io.write(bytes[start, tag_end - start + 1])
          return
        end
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
        if body.ends_with?(" /") && !unquoted_value_before_slash?(body)
          body = body.rchop(" /") + "/"
        end
        io << body
        io.write_byte('>'.ord.to_u8)
      end
    end
  end
end
