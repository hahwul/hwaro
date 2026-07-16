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

        INLINE_CODE_SPAN_RE = /`([^`]+)`/
        INLINE_IMAGE_RE     = /!\[([^\]]*)\]\(([^)]*)\)/
        INLINE_LINK_RE      = /\[([^\]]+)\]\(([^)]*)\)/
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
        INLINE_STRIKETHROUGH_RE     = /~~(?=\S)(.+?)(?<=\S)~~/

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
        SCPH_TOKEN_RE            = /\x00SCPH(\d+)\x00/

        # Render a small inline-markdown subset over already-HTML-escaped or
        # raw text. Code spans are extracted first so their content survives
        # the other passes verbatim.
        #
        # With `math: true`, `$…$`/`$$…$$` spans are stashed too and restored
        # UNtransformed: emphasis/strikethrough/link passes must not rewrite
        # formula internals (`$~~x~~$`, `$f([x])(y)$`), and the math
        # preprocess wraps the still-raw span afterwards.
        #
        # `flags` controls the F10 opt-in inline markup (ins/mark/sub/sup)
        # in addition to math — see `render(text, *, math:)` below, which is
        # the pre-F10 signature every existing caller/spec still uses.
        def render(text : String, *, flags : Flags) : String
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
            code_spans << $1
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

          result = result.gsub(INLINE_IMAGE_RE) do
            # Placeholder tokens landing in ATTRIBUTE values are restored in
            # escaped form: substituting rendered shortcode HTML into an
            # attribute after Markdown would break out of it (the same
            # in-band channel the HID/footnote neutralization defends), and
            # the escaped comment matches the pre-stash rendering here.
            # Link TEXT below keeps raw restore — it's element content,
            # consistent with paragraph text.
            alt = escape_placeholder_tokens($1, placeholders)
            url = escape_placeholder_tokens($2, placeholders)
            # `result` was already HTML.escaped at the top, so `url`/`alt` are
            # captured in their escaped form — emit them as-is (re-escaping here
            # would double-encode `&` into `&amp;amp;`). Matches the link branch
            # below, which already inserts `link_text` without re-escaping.
            if safe_url?(url)
              %(<img src="#{url}" alt="#{alt}">)
            else
              "![#{alt}](#{url})"
            end
          end

          result = result.gsub(INLINE_LINK_RE) do
            link_text = $1
            url = escape_placeholder_tokens($2, placeholders)
            if safe_url?(url)
              %(<a href="#{url}">#{link_text}</a>)
            else
              "[#{link_text}](#{url})"
            end
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

          math_spans.each_with_index do |span, idx|
            result = result.sub("\x00MATHSPAN#{idx}\x00", span)
          end

          code_spans.each_with_index do |content, idx|
            # Tokens inside code spans restore ESCAPED, so a backticked
            # placeholder displays literally instead of being substituted —
            # the same thing Markd's own code-span escaping guarantees for
            # paragraph text.
            restored = escape_placeholder_tokens(content, placeholders)
            result = result.gsub("\x00CODESPAN#{idx}\x00", "<code>#{restored}</code>")
          end

          # Remaining tokens sit in element-content positions: restore the
          # raw comment so the post-Markdown replacement pass resolves it
          # (consistent with paragraph text, where the comment also rides
          # through Markd verbatim).
          placeholders.each_with_index do |comment, idx|
            result = result.sub("\x00SCPH#{idx}\x00", comment)
          end

          result
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

        # Pre-F10 signature — delegates to the `Flags` overload with every
        # new transform off, so every existing caller/spec keeps compiling
        # and rendering exactly as before.
        def render(text : String, *, math : Bool = false) : String
          render(text, flags: Flags.new(math: math))
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
          decoded = URI.decode(url.strip).gsub(/[\x00-\x20\x7f]/, "")
          return true if UNSAFE_DATA_PROTOCOL_RE.matches?(decoded)
          !UNSAFE_PROTOCOL_RE.matches?(decoded)
        end
      end
    end
  end
end
