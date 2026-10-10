# Shared inline-markdown renderer.
#
# Used by table cells (`table_parser.cr`), definition lists, and footnote bodies
# (`markdown_extensions.cr`) — places where Markd's block parser doesn't run but
# we still want `**bold**`/`*em*`/`` `code` ``/`[link](url)`/`![alt](url)`/`~~del~~`.
# Keeping the renderer in one module prevents the implementations from drifting
# apart (e.g. one supporting strikethrough, another not).
#
# `safe_url?` is also the single source of truth for URL-scheme sanitization
# used in markdown-generated `<a>`/`<img>` tags.

require "html"
require "uri"

module Hwaro
  module Content
    module Processors
      module InlineMarkdown
        extend self

        # Schemes that must be blocked in `<a href="…">` / `<img src="…">` even
        # when Markd's `safe` option is off. `data:` is allowed only for image
        # MIME types (matching Markd's own `UNSAFE_DATA_PROTOCOL`).
        UNSAFE_PROTOCOL_RE      = /^\s*(javascript|vbscript|file|data):/i
        UNSAFE_DATA_PROTOCOL_RE = /^\s*data:image\/(?:png|gif|jpeg|webp)/i

        # CommonMark code spans: a run of N backticks opens, and the next run
        # of EXACTLY N backticks closes. The single-backtick-only form this
        # replaced could not see `` `tick` `` or ``a`b`` at all — it matched
        # the inner backticks instead, shredding the span into stray `<code>`
        # tags and literal delimiters inside table cells, footnote bodies, and
        # definition lists (the three callers of `render`).
        #
        # The opening run is POSSESSIVE (`` `++ ``) and BOTH delimiters are
        # fenced by `(?<!`)`/`(?!`)` so each is a whole run: without those,
        # `\1` would happily match two of a three-backtick run and pair
        # mismatched delimiters. The opener's lookbehind matters twice over:
        #   * correctness — without it, an unmatched longer run bleeds into a
        #     later shorter one: `` `` `a` `` became `` `<code> </code>a` ``
        #     (the scan restarted on the SECOND backtick of the ``), where
        #     CommonMark gives `` `` <code>a</code> ``;
        #   * cost — without it, every backtick of a run is a fresh start
        #     position that possessively re-consumes the rest of the run, so
        #     an unclosed run of N backticks cost O(N²): a 200 KB cell of
        #     backticks did not finish in ten minutes. With it, positions
        #     inside a run are rejected in O(1) and the scan is linear again.
        # `[\s\S]` (not `.`) because a footnote or definition body may still
        # carry a newline at this point.
        INLINE_CODE_SPAN_RE = /(?<!`)(`++)([\s\S]+?)(?<!`)\1(?!`)/
        # Link/image openers up to and including `(`; the destination and
        # optional title are read by `scan_link_tail`.
        INLINE_IMAGE_OPEN_RE = /!\[([^\]]*)\]\(/
        INLINE_LINK_OPEN_RE  = /\[([^\]]+)\]\(/
        # A backslash before ASCII punctuation (shown HTML-escaped, so `\"`
        # is `\&quot;`) is a CommonMark escape: the character is literal.
        ESCAPE_RE       = /\\(&(?:amp|lt|gt|quot|#39);|[!#$%()*+,\-.\/:;=?@\[\\\]^_`{|}~])/
        ESCAPE_TOKEN_RE = /\x00ESC(\d{1,9})\x00/
        # CommonMark allows 32 levels of balanced parentheses in a destination.
        MAX_DEST_PAREN_DEPTH = 32
        # ponytail: a title longer than this is not read (keeps a run of
        # unterminated `[a](x "` openers linear); such a link keeps the
        # first-`)` fallback.
        MAX_TITLE_BYTES = 2000
        # `{width=300}` / `{width=300 height=200}` right after an image is its
        # size, the attribute block `![[pic.png|300]]` is rewritten to.
        IMAGE_SIZE_RE = /(<img\b[^>]*)>\{width=(\d+)(?: height=(\d+))?\}/
        # Flanking guards (`(?=\S)` … `(?<=\S)`): a delimiter run that touches
        # whitespace on the inside must NOT open/close emphasis, so literal
        # `2 * 3 and 4 * 5` (arithmetic in a table cell or footnote) is left
        # alone instead of becoming `2 <em> 3 and 4 </em> 5`. This approximates
        # CommonMark's left/right-flanking rule that the body markd uses.
        INLINE_BOLD_ASTERISK_RE   = /\*\*(?=\S)(.+?)(?<=\S)\*\*/
        INLINE_BOLD_UNDERSCORE_RE = /__(?=\S)(.+?)(?<=\S)__/
        # The italic delimiter must be a LONE `*`/`_` (not part of a `**`/`__`
        # run) — `(?<!\*)…(?!\*)` and `[^\s*]` neighbours — otherwise a spaced
        # `2 ** 3 and 4 ** 5` (which the bold regex correctly declines) would be
        # re-matched across the two `**` runs into `<em>* 3 and 4 *</em>`.
        INLINE_ITALIC_ASTERISK_RE   = /(?<!\*)\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?!\*)/
        INLINE_ITALIC_UNDERSCORE_RE = /(?<![a-zA-Z0-9_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![a-zA-Z0-9_])/
        # A `~~` right after an unescaped backslash is literal (`\~~not\~~`):
        # rewriting it would leave `\<del>`, which Markd escapes into visible
        # `&lt;del&gt;` text. `\\~~x~~` (escaped backslash) still strikes.
        INLINE_STRIKETHROUGH_RE = /(?<!(?<!\\)\\)~~(?=\S)(.+?)(?<=\S)(?<!(?<!\\)\\)~~/

        # Opt-in inline markup (F10) — all gated behind their own
        # `[markdown]` flags (see `Flags`), so with every flag off these
        # patterns are never even consulted.
        #
        # `++ins++`: same flanking-guard shape as strikethrough. A lone
        # `++` (as in `C++`) never gets a second delimiter to pair with, so
        # it's left alone without any special-casing.
        INLINE_INS_RE = /\+\+(?=\S)(.+?)(?<=\S)\+\+/
        # `==mark==`: the `(?<!=)`/`(?!=)` outer guards and the
        # `[^\s=]` inner guards keep a run of `=` (a setext heading
        # underline, a `====` divider) from ever matching — there's no
        # non-`=` character for the inner lookaround to anchor on.
        INLINE_MARK_RE = /(?<!=)==(?=[^\s=])(.+?)(?<=[^\s=])==(?!=)/
        # `~sub~`: single tilde, deliberately disjoint from the double-tilde
        # strikethrough delimiter (which always runs first and consumes any
        # `~~...~~` pair before this pattern gets a chance to see it).
        INLINE_SUB_RE = /(?<!~)~([^~\s]+)~(?!~)/
        # `^sup^`: the `(?<![\^\[])` guard specifically excludes a `^` that
        # immediately follows `[` — i.e. a footnote reference's `[^key]` —
        # so `sup` and `footnotes` can both be enabled without sup mangling
        # a footnote marker before the footnotes pass gets to it.
        INLINE_SUP_RE = /(?<![\^\[])\^([^\^\s]+)\^(?!\^)/

        # Per-call feature flags for `render`. `math` already existed as a
        # positional keyword arg; F10 adds four more opt-in transforms that
        # default OFF, so every existing call site (`Flags.new` == all
        # false except math defaults false too) renders identically.
        record Flags, math : Bool = false, ins : Bool = false, mark : Bool = false, sub : Bool = false, sup : Bool = false

        # Math span patterns — canonical home for the whole pipeline
        # (MarkdownExtensions aliases these, mirroring INLINE_STRIKETHROUGH_RE).
        #
        # Display math must not cross a blank line (the tempered dot refuses
        # to consume a newline that starts one, whitespace-only lines
        # included): a stray unmatched `$$` would otherwise pair with a
        # legitimate `$$` several paragraphs later and swallow all the prose
        # in between. Blank lines are invalid inside LaTeX display math
        # anyway, so no real formula is lost.
        #
        # Inline math admits backslash escapes in the body (`$x = \$5$`) and
        # requires an unescaped, non-space-preceded closer. A body *ending*
        # in a literal `\` won't close — meaningless in LaTeX at the end of
        # a formula.
        DISPLAY_MATH_RE = /\$\$((?:(?!\n[ \t\r]*\n).)*?)\$\$/m
        INLINE_MATH_RE  = /(?<![\\$])\$(?!\s)((?:[^\n$\\]|\\[^\n])+?)(?<![\s\\])\$(?!\d)/

        # Placeholder comments left by `Core::Build::ShortcodeProcessor` for
        # already-rendered shortcodes (canonical home here, next to the other
        # inline patterns; the shortcode processor aliases it and emits the
        # matching text). They must ride through `render` untouched: the
        # HTML.escape at the top would otherwise turn them into
        # `&lt;!--…--&gt;`, which the post-Markdown replacement pass cannot
        # find — leaking the escaped comment into table cells, definition
        # bodies, and footnotes.
        SHORTCODE_PLACEHOLDER_RE = /<!--HWARO-SHORTCODE-PLACEHOLDER-\d+-->/
        SCPH_TOKEN_RE            = /\x00SCPH(\d{1,9})\x00/
        MATHSPAN_TOKEN_RE        = /\x00MATHSPAN(\d{1,9})\x00/
        CODESPAN_TOKEN_RE        = /\x00CODESPAN(\d{1,9})\x00/
        LINK_TAG_TOKEN_RE        = /\x00IMTAG(\d{1,9})\x00/

        # Render a small inline-markdown subset over already-HTML-escaped or
        # raw text. Code spans are extracted first so their content survives
        # the other passes verbatim.
        #
        # With `flags.math`, `$…$`/`$$…$$` spans are stashed too and restored
        # UNtransformed: emphasis/strikethrough/link passes must not rewrite
        # formula internals (`$~~x~~$`, `$f([x])(y)$`), and the math
        # preprocess wraps the still-raw span afterwards.
        #
        # `flags` also controls the F10 opt-in inline markup (ins/mark/sub/sup).
        def render(text : String, *, flags : Flags = Flags.new) : String
          placeholders = [] of String
          if text.includes?("<!--HWARO-SHORTCODE-PLACEHOLDER-")
            text = text.gsub(SHORTCODE_PLACEHOLDER_RE) do |comment|
              placeholders << comment
              "\x00SCPH#{placeholders.size - 1}\x00"
            end
          end

          result = HTML.escape(text)

          code_spans = [] of String
          result = result.gsub(INLINE_CODE_SPAN_RE) do
            code_spans << strip_code_span_padding($2)
            "\x00CODESPAN#{code_spans.size - 1}\x00"
          end

          math_spans = [] of String
          if flags.math && result.includes?('$')
            result = result.gsub(DISPLAY_MATH_RE) do |match|
              math_spans << match
              "\x00MATHSPAN#{math_spans.size - 1}\x00"
            end
            result = result.gsub(INLINE_MATH_RE) do |match|
              math_spans << match
              "\x00MATHSPAN#{math_spans.size - 1}\x00"
            end
          end

          escapes = [] of String
          if result.includes?('\\')
            result = result.gsub(ESCAPE_RE) do
              escapes << $1
              "\x00ESC#{escapes.size - 1}\x00"
            end
          end

          # Placeholder tokens landing in ATTRIBUTE values are restored in
          # escaped form: substituting rendered shortcode HTML into an
          # attribute after Markdown would break out of it (the same
          # in-band channel the HID/footnote neutralization defends), and
          # the escaped comment matches the pre-stash rendering here.
          # Link TEXT keeps raw restore — it's element content,
          # consistent with paragraph text.
          # `result` was already HTML.escaped at the top, so label/url/title
          # are captured in their escaped form — emit them as-is (re-escaping
          # would double-encode `&` into `&amp;amp;`). Escape tokens are
          # restored in the URL/title BEFORE the scheme check, so
          # `javascript\:` cannot hide its colon from `safe_url?`.
          result = replace_links(result, INLINE_IMAGE_OPEN_RE) do |alt, url, title, rest|
            alt = escape_placeholder_tokens(alt, placeholders)
            url = restore_escapes(escape_placeholder_tokens(url, placeholders), escapes)
            if safe_url?(url)
              %(<img src="#{url}" alt="#{alt}"#{title_attribute(title, placeholders, escapes)}>)
            else
              "![#{alt}](#{escape_placeholder_tokens(rest, placeholders)})"
            end
          end
          # Every `<img` in `result` is one generated above (the text was
          # HTML-escaped first), so the size block can be read off the tag.
          if result.includes?("{width=")
            result = result.gsub(IMAGE_SIZE_RE) { %(#{$1} width="#{$2}"#{$3? ? %( height="#{$3}") : ""}>) }
          end

          result = replace_links(result, INLINE_LINK_OPEN_RE) do |link_text, url, title, rest|
            url = restore_escapes(escape_placeholder_tokens(url, placeholders), escapes)
            if safe_url?(url)
              %(<a href="#{url}"#{title_attribute(title, placeholders, escapes)}>#{link_text}</a>)
            else
              "[#{link_text}](#{escape_placeholder_tokens(rest, placeholders)})"
            end
          end

          # The emphasis-like passes below run over rendered inline HTML so
          # link text gets formatting too. Keep generated <a>/<img> opening
          # tags opaque during those passes; otherwise delimiters in a valid
          # URL are inserted into an href/src attribute.
          link_tags = [] of String
          result = result.gsub(/<(?:a|img)\b[^>]*>/i) do |tag|
            link_tags << tag
            "\x00IMTAG#{link_tags.size - 1}\x00"
          end

          result = result.gsub(INLINE_BOLD_ASTERISK_RE) { "<strong>#{$1}</strong>" }
          result = result.gsub(INLINE_BOLD_UNDERSCORE_RE) { "<strong>#{$1}</strong>" }
          result = result.gsub(INLINE_ITALIC_ASTERISK_RE) { "<em>#{$1}</em>" }
          result = result.gsub(INLINE_ITALIC_UNDERSCORE_RE) { "<em>#{$1}</em>" }
          result = result.gsub(INLINE_STRIKETHROUGH_RE) { "<del>#{$1}</del>" }

          result = result.gsub(INLINE_INS_RE) { "<ins>#{$1}</ins>" } if flags.ins
          result = result.gsub(INLINE_MARK_RE) { "<mark>#{$1}</mark>" } if flags.mark
          result = result.gsub(INLINE_SUB_RE) { "<sub>#{$1}</sub>" } if flags.sub
          result = result.gsub(INLINE_SUP_RE) { "<sup>#{$1}</sup>" } if flags.sup

          unless link_tags.empty?
            result = result.gsub(LINK_TAG_TOKEN_RE) { link_tags[$1.to_i]?.try(&.itself) || $0 }
          end

          result = restore_escapes(result, escapes)

          # One pass per token kind, not one `gsub` per span: the per-span
          # loop rescanned the whole string for every span, so a cell or
          # footnote with N code spans cost O(N²) — 20k spans took 10 s and
          # the 200 KB `` `a`a`a… `` pattern minutes, after #779 had made the
          # code-span REGEX itself linear.
          unless math_spans.empty?
            result = result.gsub(MATHSPAN_TOKEN_RE) { math_spans[$1.to_i]? || $0 }
          end

          unless code_spans.empty?
            # Tokens inside code spans restore ESCAPED, so a backticked
            # placeholder displays literally instead of being substituted —
            # the same thing Markd's own code-span escaping guarantees for
            # paragraph text.
            result = result.gsub(CODESPAN_TOKEN_RE) do
              if content = code_spans[$1.to_i]?
                "<code>#{escape_placeholder_tokens(content, placeholders)}</code>"
              else
                $0
              end
            end
          end

          # Remaining tokens sit in element-content positions: restore the
          # raw comment so the post-Markdown replacement pass resolves it
          # (consistent with paragraph text, where the comment also rides
          # through Markd verbatim).
          unless placeholders.empty?
            result = result.gsub(SCPH_TOKEN_RE) { placeholders[$1.to_i]? || $0 }
          end

          result
        end

        # Rewrites every `[label](destination "title")` match of `open_re`.
        # The block gets the label, destination, title (nil when absent) and
        # the raw text after `](` up to the closing `)`, and returns the
        # replacement. A tail that is not a well-formed destination falls
        # back to everything up to the first `)`, as before.
        private def replace_links(text : String, open_re : Regex, & : String, String, String?, String -> String) : String
          return text unless text.includes?("](")
          bytes = text.to_slice
          String.build do |io|
            pos = 0
            while m = open_re.match_at_byte_index(text, pos)
              from = m.byte_begin(0)
              tail_start = m.byte_end(0)
              io.write bytes[pos, from - pos]
              if tail = scan_link_tail(bytes, tail_start)
                dest, title, finish = tail
              elsif close = text.byte_index(')', tail_start)
                dest = String.new(bytes[tail_start, close - tail_start])
                title = nil
                finish = close + 1
              else
                pos = from
                break
              end
              io << yield(m[1], dest, title, String.new(bytes[tail_start, finish - 1 - tail_start]))
              pos = finish
            end
            io.write bytes[pos, bytes.size - pos]
          end
        end

        # Reads `destination "title")` from `start` (just past `](`):
        # a `<…>` destination or bare text with balanced parentheses, then an
        # optional title in `"…"`, `'…'` or `(…)`. Returns the destination,
        # the title and the byte offset just past the closing `)`, or nil.
        # `bytes` is HTML-escaped, so `<`, `"` and `'` read `&lt;`, `&quot;`
        # and `&#39;`.
        private def scan_link_tail(bytes : Bytes, start : Int32) : {String, String?, Int32}?
          i = skip_space(bytes, start)
          if bytes_at?(bytes, i, "&lt;")
            j = i + 4
            close = nil
            while j < bytes.size
              return if bytes[j] === '\n' || bytes_at?(bytes, j, "&lt;")
              if bytes_at?(bytes, j, "&gt;")
                close = j
                break
              end
              j += 1
            end
            return unless close
            dest = String.new(bytes[i + 4, close - i - 4]).gsub(' ', "%20")
            i = close + 4
          else
            depth = 0
            j = i
            while j < bytes.size
              byte = bytes[j]
              break if space?(byte)
              if byte === '('
                depth += 1
                return if depth > MAX_DEST_PAREN_DEPTH
              elsif byte === ')'
                break if depth.zero?
                depth -= 1
              end
              j += 1
            end
            return unless depth.zero?
            dest = String.new(bytes[i, j - i])
            i = j
          end

          k = skip_space(bytes, i)
          return {dest, nil, k + 1} if bytes[k]? === ')'
          return if k == i # a title needs whitespace before it

          opener, closer = if bytes_at?(bytes, k, "&quot;")
                             {"&quot;", "&quot;"}
                           elsif bytes_at?(bytes, k, "&#39;")
                             {"&#39;", "&#39;"}
                           elsif bytes[k]? === '('
                             {"(", ")"}
                           else
                             return
                           end
          title_start = k + opener.bytesize
          stop = Math.min(bytes.size, title_start + MAX_TITLE_BYTES)
          j = title_start
          while j < stop && !bytes_at?(bytes, j, closer)
            j += 1
          end
          return unless j < stop
          m = skip_space(bytes, j + closer.bytesize)
          return unless bytes[m]? === ')'
          {dest, String.new(bytes[title_start, j - title_start]), m + 1}
        end

        private def space?(byte : UInt8) : Bool
          byte === ' ' || byte === '\t' || byte === '\n' || byte === '\r'
        end

        private def skip_space(bytes : Bytes, i : Int32) : Int32
          while i < bytes.size && space?(bytes[i])
            i += 1
          end
          i
        end

        private def bytes_at?(bytes : Bytes, i : Int32, needle : String) : Bool
          return false if i + needle.bytesize > bytes.size
          needle.to_slice == bytes[i, needle.bytesize]
        end

        private def title_attribute(title : String?, placeholders : Array(String), escapes : Array(String)) : String
          return "" unless title
          %( title="#{restore_escapes(escape_placeholder_tokens(title, placeholders), escapes)}")
        end

        private def restore_escapes(text : String, escapes : Array(String)) : String
          return text if escapes.empty? || !text.includes?('\u{0}')
          text.gsub(ESCAPE_TOKEN_RE) { escapes[$1.to_i]? || $0 }
        end

        # CommonMark strips ONE leading and ONE trailing space from a code
        # span when both are present and the content isn't all spaces — that's
        # what makes `` `tick` `` render as `` `tick` `` rather than
        # `` ` tick ` ``. Markd already does this on the paragraph path; doing
        # it here keeps the two paths agreeing.
        private def strip_code_span_padding(content : String) : String
          return content unless content.starts_with?(' ') && content.ends_with?(' ')
          return content if content.each_char.all? { |c| c == ' ' }
          content[1...-1]
        end

        # Replaces stashed placeholder tokens with the HTML-escaped comment
        # text — for positions (attribute values, code spans) where the raw
        # comment must NOT survive to the post-Markdown replacement pass.
        private def escape_placeholder_tokens(text : String, placeholders : Array(String)) : String
          return text if placeholders.empty? || !text.includes?('\u{0}')
          text.gsub(SCPH_TOKEN_RE) do |token|
            comment = $1.to_i?.try { |idx| placeholders[idx]? }
            comment ? HTML.escape(comment) : token
          end
        end

        # Returns true for URLs we're willing to emit in a generated `href`/`src`.
        # Reject `javascript:`, `vbscript:`, `file:`, and non-image `data:` URIs.
        # Percent-decode first so encodings like `java%73cript:` don't slip past.
        # Also strip ASCII control/whitespace bytes (NUL–space and DEL) anywhere
        # in the decoded value: browsers ignore tabs/newlines/NULs inside a URL
        # scheme, so `java%09script:` would otherwise execute as `javascript:`.
        # The unsafe regexes are anchored at `^`, so stripping these from the
        # whole string only affects scheme detection, never legitimate URLs.
        def safe_url?(url : String) : Bool
          # `URI.decode` turns every `%XX` into a raw byte, so a legacy latin-1
          # escape (`/caf%E9.html`, exactly what an old CMS or an importer
          # emits) or a truncated `%FF` yields an invalid-UTF-8 String. Crystal's
          # PCRE2 runs in UTF mode and RAISES `ArgumentError: Regex match error`
          # the moment such a subject reaches a regex — which would abort the
          # whole build from a single table cell, footnote body, or `redirect_to`
          # front-matter value. Scrub first (a no-op that returns `self` for
          # valid UTF-8, so existing output stays byte-identical); U+FFFD can
          # never spell `javascript:`/`vbscript:`/`file:`/`data:`, so no
          # sanitization strength is lost. Same guard, same reason, as
          # `PathUtils.split_safe_segments`.
          decoded = URI.decode(url.strip).scrub.gsub(/[\x00-\x20\x7f]/, "")
          return true if UNSAFE_DATA_PROTOCOL_RE.matches?(decoded)
          !UNSAFE_PROTOCOL_RE.matches?(decoded)
        end
      end
    end
  end
end
