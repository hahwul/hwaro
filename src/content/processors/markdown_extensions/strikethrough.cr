# Markdown extensions — GFM strikethrough.
#
# One file per `# --- X ---` pass of the pre/post-processing pipeline; the
# pass ORDER is fixed in ../markdown_extensions.cr (`preprocess` /
# `postprocess`). Parts only reopen the module: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
        # --- Strikethrough (GFM) ---
        # `~~text~~` → `<del>text</del>`. Markd doesn't ship a GFM strikethrough
        # parser, so we apply this pre-Markd. The walk is fence-aware so
        # examples inside fenced code blocks (` ``` ` / `~~~`) render verbatim,
        # and inline `` `code` `` runs on the same line are skipped via a
        # placeholder pass so e.g. `` `~~not strike~~` `` stays as code.
        #
        # When math is also enabled, `preprocess` stashes `$…$`/`$$…$$`
        # spans into opaque placeholders before this pass runs, so `$~~x~~$`
        # reaches KaTeX verbatim instead of being rewritten here.
        STRIKETHROUGH_RE      = InlineMarkdown::INLINE_STRIKETHROUGH_RE
        STRIKETHROUGH_CODE_RE = /`[^`]+`/

        def preprocess_strikethrough(content : String) : String
          return content unless content.includes?("~~")

          process_lines_fence_aware(content) do |line, _in_fence|
            if line.includes?("~~")
              rewrite_strikethrough_line(line)
            else
              line
            end
          end
        end

        private def rewrite_strikethrough_line(line : String) : String
          # Stash inline code spans so a `~~` inside backticks is not rewritten.
          transform_outside_code_spans(line) do |stashed|
            stashed.gsub(STRIKETHROUGH_RE) { "<del>#{$1}</del>" }
          end
        end

        # Stash inline code spans — backtick spans AND `<code>` HTML spans —
        # transform the rest through the block, then restore the spans: so
        # literals like `` `~~x~~` ``, `` `[^1]` ``, and `` `$x$` `` survive
        # the HTML-injecting passes, including after a table cell or
        # definition body has already been rendered to `<code>…</code>`.
        # Multi-line chunks pass SINGLE_LINE_CODE_SPAN_RE so a stray lone
        # backtick in one paragraph can't absorb text from another.
        private def transform_outside_code_spans(text : String, code_span_re : Regex = STRIKETHROUGH_CODE_RE, & : String -> String) : String
          has_backticks = text.includes?('`')
          has_html_code = text.includes?("<code")
          return yield text unless has_backticks || has_html_code

          code_spans = [] of String
          stashed = text
          if has_backticks
            stashed = stashed.gsub(code_span_re) do |match|
              code_spans << match
              "\x00CS#{code_spans.size - 1}\x00"
            end
          end
          if has_html_code
            stashed = stashed.gsub(HTML_CODE_SPAN_RE) do |match|
              code_spans << match
              "\x00CS#{code_spans.size - 1}\x00"
            end
          end

          rewritten = yield stashed

          # Single-pass restore per nesting level (the per-index `sub` loop
          # rescanned the line once per span). An HTML code span stashed
          # second can contain a backtick-span placeholder stashed first
          # (`<code>` + "`x`" on one line); gsub does not rescan injected
          # content, so a second pass picks those up. The pass count is a
          # HARD cap of 2, matching the two stash passes above — a span
          # whose own content forges a valid token (raw NULs in the source
          # file) would otherwise re-expand itself every pass and hang the
          # build. An out-of-range counterfeit restores nothing and exits
          # via the no-change check.
          2.times do
            break unless rewritten.includes?("\x00CS")
            replaced = rewritten.gsub(CODE_SPAN_TOKEN_RE) do |match|
              idx = $1.to_i?
              idx && idx < code_spans.size ? code_spans[idx] : match
            end
            break if replaced == rewritten
            rewritten = replaced
          end
          rewritten
        end
      end
    end
  end
end
