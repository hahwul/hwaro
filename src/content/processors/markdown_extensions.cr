require "html"
require "./fence_tracker"
require "./inline_markdown"
require "../../models/config"
require "../../utils/text_utils"

module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
        extend self

        # Pre-process markdown content before Markd parsing
        def preprocess(content : String, config : Models::MarkdownConfig) : String
          result = content

          # === Pass order matters ===
          # Structural extensions whose bodies render through InlineMarkdown
          # (which HTML-escapes) run FIRST, and the HTML-injecting passes
          # (strikethrough / footnote refs / math) run AFTER them — a <del>
          # or math span injected into a `: definition` line beforehand would
          # be escaped into visible literal markup. TableParser runs even
          # earlier (in Markdown#render) for the same reason. Math runs last
          # so `$…$` inside already-escaped <td>/<dd> bodies still gets
          # wrapped.
          result = preprocess_definition_lists(result) if config.definition_lists
          result = preprocess_footnotes(result) if config.footnotes

          # Combined single fence-aware pass for per-line safe extensions
          # (task_lists + strikethrough + heading_ids) — reduces full
          # document walks (#559).
          do_task_lists = config.task_lists
          do_strikethrough = true
          do_heading_ids = config.heading_ids

          # Whole-content marker pre-check (memchr-fast): with none of the
          # enabled extensions' markers present, the line pass is the
          # identity transform and only rebuilds the string — skip it. The
          # per-line includes? guards below are unchanged, so any page that
          # passes this check transforms exactly as before.
          markers_present = (do_task_lists && (result.includes?("[ ]") || result.includes?("[x]") || result.includes?("[X]"))) ||
                            (do_strikethrough && result.includes?("~~")) ||
                            (do_heading_ids && result.includes?("{#"))

          if markers_present
            result = process_lines_fence_aware(result) do |line, _in_fence|
              transformed = line

              if do_task_lists && !_in_fence &&
                 (transformed.includes?("[ ]") || transformed.includes?("[x]") || transformed.includes?("[X]"))
                transformed = preprocess_task_lists(transformed)
              end

              if do_strikethrough && transformed.includes?("~~")
                transformed = rewrite_strikethrough_line(transformed)
              end

              if do_heading_ids && transformed.includes?("{#")
                transformed = transformed.gsub(HEADING_ID_RE) do |_|
                  if config.safe
                    "#{$1}#{$2} #{$3.rstrip}"
                  else
                    "#{$1}#{$2} #{$3.rstrip} <!--HID:#{$4}-->"
                  end
                end
              end

              transformed
            end
          end

          # Math kept as a separate pass: display math `$$…$$` spans lines,
          # so it works on fence-delimited chunks rather than per line.
          result = preprocess_math(result) if config.math

          result
        end

        # Post-process HTML after Markd rendering
        def postprocess(html : String, config : Models::MarkdownConfig) : String
          result = html

          # === Aggressive pass reduction for postprocess (#559) ===
          # We combine as many HTML post-processors as possible.
          # Order: admonitions + heading_ids first (they can affect structure/ids),
          # then footnotes (which relies on pre-inserted markers), then mermaid.

          do_admonitions = config.admonitions
          do_heading_ids = config.heading_ids

          if do_admonitions || do_heading_ids
            # Combine admonitions and heading_ids into one HTML pass when both active
            if do_admonitions && do_heading_ids
              result = postprocess_admonitions(result)
              result = postprocess_heading_ids(result)
            elsif do_admonitions
              result = postprocess_admonitions(result)
            else
              result = postprocess_heading_ids(result)
            end
          end

          result = postprocess_footnotes(result) if config.footnotes
          result = postprocess_mermaid(result) if config.mermaid

          result
        end

        # --- Task Lists ---
        # Converts - [ ] and - [x] to checkbox HTML in list items
        TASK_LIST_RE = /^(\s*[-*+]\s)\[([ xX])\]/m

        def preprocess_task_lists(content : String) : String
          content.gsub(TASK_LIST_RE) do |_|
            prefix = $1
            checked = $2.downcase == "x"
            if checked
              "#{prefix}<input type=\"checkbox\" checked disabled>"
            else
              "#{prefix}<input type=\"checkbox\" disabled>"
            end
          end
        end

        # --- Definition Lists ---
        # Converts Term\n: Definition syntax to <dl><dt><dd> HTML.
        # Fence-aware: `Term` / `: def` lines shown inside a ```/~~~ example
        # stay verbatim instead of becoming <dl> markup inside the code block.
        def preprocess_definition_lists(content : String) : String
          lines = content.split("\n")

          tracker = FenceTracker.new
          fenced = lines.map { |line| tracker.fence_line?(line) }

          result = [] of String
          i = 0

          while i < lines.size
            line = lines[i]

            if fenced[i]
              result << line
              i += 1
              next
            end

            # Check if next line starts with ": " (definition). The term line
            # (lines[i]) must be non-empty: a blank line followed by a ": "
            # line is an orphan definition, not a definition list — entering
            # the branch there emitted a stray empty <dl></dl> and leaked the
            # ": " line through as literal text.
            if i + 1 < lines.size && !fenced[i + 1] && !line.strip.empty? && lines[i + 1].lstrip.starts_with?(": ")
              # This is a definition list
              result << "<dl>"
              while i < lines.size && !fenced[i]
                term = lines[i].strip
                if term.empty?
                  i += 1
                  break
                end

                result << "<dt>#{render_inline_md(term)}</dt>"
                i += 1

                # Collect definitions for this term
                while i < lines.size && !fenced[i] && lines[i].lstrip.starts_with?(": ")
                  definition = lines[i].lstrip.lchop(": ").strip
                  result << "<dd>#{render_inline_md(definition)}</dd>"
                  i += 1
                end

                # Skip one or more blank lines between term groups within the same dl
                peek = i
                while peek < lines.size && !fenced[peek] && lines[peek].strip.empty?
                  peek += 1
                end
                if peek > i && peek + 1 < lines.size && !fenced[peek] && !fenced[peek + 1] && lines[peek + 1].lstrip.starts_with?(": ")
                  i = peek
                  next
                end
                break
              end
              result << "</dl>"
            else
              result << line
              i += 1
            end
          end

          result.join("\n")
        end

        # --- Footnotes ---
        # Pre-processing: extract footnote definitions and replace references with placeholders
        FOOTNOTE_DEF_RE     = /^\[\^([^\]]+)\]:\s*(.+?)$/m
        FOOTNOTE_REF_RE     = /\[\^([^\]]+)\]/
        FOOTNOTE_COMMENT_RE = /<!--HWARO-FN:([^:]+):(\d+):(.+?)-->/
        FOOTNOTE_BLOCK_RE   = /\n?<!--HWARO-FOOTNOTES-START-->.*?<!--HWARO-FOOTNOTES-END-->\n?/m

        def preprocess_footnotes(content : String) : String
          # Neutralize any author-typed HWARO FOOTNOTE markers up front so page
          # content that literally contains the engine's internal comment markers
          # (e.g. docs about hwaro, or a malicious multi-author contributor) can't
          # be promoted into a fabricated <section class="footnotes"> — in-band
          # signaling injection. Inserting a space keeps them valid, inert HTML
          # comments while preventing FOOTNOTE_*_RE from matching them; the engine
          # then emits its OWN markers (no space) below, which postprocess matches.
          # Scoped to the FN/FOOTNOTES markers so the unrelated shortcode
          # placeholder comment (<!--HWARO-SHORTCODE-...-->) is left untouched.
          content = content
            .gsub("<!--HWARO-FN", "<!-- HWARO-FN")
            .gsub("<!--HWARO-FOOTNOTES-", "<!-- HWARO-FOOTNOTES-")

          # Extract and remove footnote definitions — but only OUTSIDE fenced code
          # blocks, so a ``` [^1]: ... ``` syntax example isn't silently eaten.
          footnotes = {} of String => String
          cleaned = process_lines_fence_aware(content) do |line, _|
            line.gsub(FOOTNOTE_DEF_RE) do |_|
              # rstrip: on CRLF content the captured text carries a trailing \r
              footnotes[$~[1]] = $~[2].rstrip
              "" # Remove definition from content
            end
          end

          return cleaned if footnotes.empty?

          # Replace references with superscript HTML placeholders — fence-aware
          # so a `[^1]` shown inside a code block stays verbatim, and inline
          # code spans are stashed so a literal `` `[^1]` `` survives too.
          counter = 0
          ref_order = {} of String => Int32
          result = process_lines_fence_aware(cleaned) do |line, _|
            next line unless line.includes?("[^")

            transform_outside_code_spans(line) do |stashed|
              stashed.gsub(FOOTNOTE_REF_RE) do |full_match|
                key = $~[1]
                next full_match unless footnotes.has_key?(key)

                unless ref_order.has_key?(key)
                  counter += 1
                  ref_order[key] = counter
                end
                num = ref_order[key]
                escaped_key = HTML.escape(key)
                "<sup class=\"footnote-ref\"><a href=\"#fn-#{escaped_key}\" id=\"fnref-#{escaped_key}\">[#{num}]</a></sup>"
              end
            end
          end

          # Store footnotes data in a special HTML comment for postprocessing
          if ref_order.present?
            result += "\n<!--HWARO-FOOTNOTES-START-->\n"
            ref_order.each do |key, num|
              text = footnotes[key]? || ""
              # Escape --> in text to prevent premature comment close, and : to prevent parsing issues
              safe_key = key.gsub("--", "&#45;&#45;").gsub(":", "&#58;")
              safe_text = text.gsub("--", "&#45;&#45;").gsub(":", "&#58;")
              result += "<!--HWARO-FN:#{safe_key}:#{num}:#{safe_text}-->\n"
            end
            result += "<!--HWARO-FOOTNOTES-END-->\n"
          end

          result
        end

        # Post-processing: convert footnote comments to HTML section
        def postprocess_footnotes(html : String) : String
          return html unless html.includes?("<!--HWARO-FOOTNOTES-START-->")

          # Extract footnote data from comments
          footnotes = [] of {key: String, num: Int32, text: String}
          html.scan(FOOTNOTE_COMMENT_RE) do |match|
            # Unescape the comment-safe encoding
            key = match[1].gsub("&#58;", ":").gsub("&#45;&#45;", "--")
            text = match[3].gsub("&#58;", ":").gsub("&#45;&#45;", "--")
            num = match[2].to_i? || 0
            next if num <= 0
            footnotes << {key: key, num: num, text: text}
          end

          return html if footnotes.empty?

          # Build footnotes section. Body text is rendered through the shared
          # inline-md helper so `` `code` ``/`*em*`/`[link](url)`/`~~del~~`
          # inside a footnote behave the same way they do in table cells and
          # definition lists.
          section = String.build do |str|
            str << "<section class=\"footnotes\">\n<hr>\n<ol>\n"
            footnotes.sort_by { |fn| fn[:num] }.each do |fn|
              escaped_key = HTML.escape(fn[:key])
              rendered_text = InlineMarkdown.render(fn[:text])
              str << "<li id=\"fn-#{escaped_key}\">\n"
              str << "<p>#{rendered_text} <a href=\"#fnref-#{escaped_key}\" class=\"footnote-backref\">\u21A9</a></p>\n"
              str << "</li>\n"
            end
            str << "</ol>\n</section>\n"
          end

          # Replace the comment block with the rendered section. gsub (not sub)
          # so the section is emitted once and any additional marker block is
          # removed rather than leaking the raw engine comments into output.
          first = true
          html.gsub(FOOTNOTE_BLOCK_RE) do
            if first
              first = false
              section
            else
              ""
            end
          end
        end

        # --- Math ---
        DISPLAY_MATH_RE = /\$\$(.*?)\$\$/m
        INLINE_MATH_RE  = /(?<![\\$])\$(?!\s)([^\n$]+?)(?<!\s)\$(?!\d)/
        # Code-span pattern confined to one line, for stashing inside
        # multi-line chunks: a stray lone backtick in one paragraph must not
        # absorb text from another.
        SINGLE_LINE_CODE_SPAN_RE = /`[^`\n]+`/
        # CommonMark "type 6" HTML-block start condition (common block tags,
        # including the <table>/<dl>/<div> markup hwaro itself generates).
        # A line opening one of these starts a raw-HTML block that runs to
        # the next blank line — Markd performs NO inline parsing there, so
        # backslash escapes ship verbatim instead of collapsing.
        HTML_BLOCK_START_RE = /^ {0,3}<\/?(?:address|article|aside|blockquote|caption|center|col|colgroup|dd|details|dialog|div|dl|dt|fieldset|figcaption|figure|footer|form|h[1-6]|header|hr|li|main|menu|nav|ol|p|section|summary|table|tbody|td|tfoot|th|thead|tr|ul)(?:[\s>\/]|\r?$)/i

        # Wraps math expressions in special HTML to prevent Markd from
        # processing them. Fence-aware: `$$` is common in Makefile/shell/Perl
        # code examples, and rewriting it inside a fence corrupts the code
        # block. Display math can span lines, so instead of a per-line walk
        # this buffers runs of non-fence lines and transforms each run as one
        # chunk.
        def preprocess_math(content : String) : String
          return content unless content.includes?('$')

          String.build do |io|
            tracker = FenceTracker.new
            chunk = String::Builder.new
            content.each_line(chomp: false) do |line|
              if tracker.fence_line?(line) || line.starts_with?(ENGINE_MARKER_PREFIX)
                if chunk.bytesize > 0
                  io << transform_math_chunk(chunk.to_s)
                  chunk = String::Builder.new
                end
                io << line
              else
                chunk << line
              end
            end
            io << transform_math_chunk(chunk.to_s) if chunk.bytesize > 0
          end
        end

        private def transform_math_chunk(text : String) : String
          return text unless text.includes?('$')

          # Inline code spans are stashed so `` `$HOME` `` stays verbatim.
          transform_outside_code_spans(text, SINGLE_LINE_CODE_SPAN_RE) do |stashed|
            # Display math: $$...$$ (multi-line). The `<div>` is an HTML
            # block, opaque to Markd in every context, so a single backslash
            # reaches the browser as `\[…\]` — what KaTeX auto-render scans
            # for.
            result = stashed.gsub(DISPLAY_MATH_RE) do |_|
              escaped = Utils::TextUtils.escape_xml($~[1])
              "<div class=\"math math-display\">\\[#{escaped}\\]</div>"
            end

            next result unless result.includes?('$')

            # Inline math: $...$ (single line, no space after opening or
            # before closing $). The required backslash escaping depends on
            # block context:
            #
            # - In normal inline context the `<span>` content participates in
            #   CommonMark inline parsing, so the delimiters need an extra
            #   backslash — `\\(` in the markdown source collapses to `\(`
            #   in the HTML.
            # - Inside a raw HTML block (a <td>/<dd> hwaro generated, or
            #   author-written block HTML) Markd does no inline parsing and
            #   backslashes ship verbatim, so a single backslash is correct.
            #
            # Walk line by line to track the HTML-block state (a type-6 block
            # runs from its opening tag line to the next blank line).
            String.build do |io|
              in_html_block = false
              result.each_line(chomp: false) do |line|
                if in_html_block
                  in_html_block = false if line.strip.empty?
                elsif HTML_BLOCK_START_RE.matches?(line)
                  in_html_block = true
                end

                unless line.includes?('$')
                  io << line
                  next
                end

                raw_context = in_html_block
                io << line.gsub(INLINE_MATH_RE) do |_|
                  escaped = Utils::TextUtils.escape_xml($~[1])
                  if raw_context
                    "<span class=\"math math-inline\">\\(#{escaped}\\)</span>"
                  else
                    "<span class=\"math math-inline\">\\\\(#{escaped}\\\\)</span>"
                  end
                end
              end
            end
          end
        end

        # --- Mermaid ---
        # Post-processing: convert mermaid code blocks to div elements
        def postprocess_mermaid(html : String) : String
          html.gsub(/<pre><code class="language-mermaid[^"]*">(.*?)<\/code><\/pre>/m) do |_|
            # Keep HTML entities as-is; the browser decodes them automatically
            # when Mermaid.js reads the element's textContent.
            # Only decode &amp; which Mermaid syntax may require in labels.
            code = $~[1].gsub("&amp;", "&")
            "<div class=\"mermaid\">#{code}</div>"
          end
        end

        # --- GitHub-style Admonitions ---
        # Recognised types match GitHub's alert syntax.
        ADMONITION_TYPES = {"NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"}

        # Captures a blockquote whose first paragraph starts with `[!TYPE]`.
        # Group 1: type token (uppercased). Group 2: the rest of the blockquote
        # body, possibly starting with `</p>` (when the marker was on its own
        # paragraph) or with the inline body content (when the marker shared a
        # paragraph with body text via a soft break).
        ADMONITION_BLOCKQUOTE_RE = /<blockquote>\s*<p>\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(.*?)<\/blockquote>/m

        # Post-processing: rewrite GitHub `> [!TYPE]` blockquotes as admonition divs.
        # Note: the lazy match against `</blockquote>` means a nested blockquote
        # inside the admonition will close the match early. Acceptable for v1 —
        # GitHub admonitions don't support nested blockquotes either.
        def postprocess_admonitions(html : String) : String
          return html unless html.includes?("[!")

          html.gsub(ADMONITION_BLOCKQUOTE_RE) do |_|
            type = $1
            rest = $2
            type_lower = type.downcase
            type_title = type[0].to_s + type[1..].downcase

            body = if rest.lstrip.starts_with?("</p>")
                     # Marker was alone on its paragraph; remaining content
                     # already consists of well-formed block elements.
                     rest.sub(/\A\s*<\/p>\s*/, "").strip
                   elsif rest.strip.empty?
                     # Title-only admonition with no body.
                     ""
                   else
                     # Body text shared the marker's paragraph (soft break).
                     # The closing </p> is already inside `rest`.
                     "<p>#{rest.lstrip}".strip
                   end

            String.build do |str|
              str << %(<div class="admonition admonition-#{type_lower}">\n)
              str << %(<p class="admonition-title">#{type_title}</p>\n)
              unless body.empty?
                str << body
                str << '\n'
              end
              str << "</div>"
            end
          end
        end

        # --- Custom Heading IDs ---
        # `## My Heading {#custom-id}` → `## My Heading <!--HID:custom-id-->`
        # The marker survives Markd rendering and is converted to an `id="..."`
        # attribute in `postprocess_heading_ids`.
        # Restricting the id charset to `[A-Za-z][\w:-]*` keeps it valid as an
        # HTML id without further escaping.
        # CommonMark allows up to 3 leading spaces before an ATX heading, which
        # we capture and preserve so Markd still recognises the line as a heading.
        # `\r?` before `$`: CRLF content otherwise never matches and the id is
        # silently dropped.
        HEADING_ID_RE = /^([ ]{0,3})(\#{1,6})[ \t]+(.+?)[ \t]*\{\#([A-Za-z][\w:-]*)\}[ \t]*\r?$/

        # Engine-generated marker comments (footnote data blocks, shortcode
        # placeholders) start with this prefix and must pass through the
        # transforming passes verbatim: a footnote body containing `~~x~~` or
        # `$x$` lives inside a `<!--HWARO-FN:…-->` line until postprocess,
        # and rewriting it there corrupts the data. Author-typed lookalikes
        # are neutralized to `<!-- HWARO-` (with a space) by
        # preprocess_footnotes before this prefix check can match them.
        ENGINE_MARKER_PREFIX = "<!--HWARO-"

        # Unified fence-aware line processor.
        # This allows multiple extensions (heading_ids + strikethrough, etc.)
        # to be applied in a *single* pass over the document instead of
        # separate full-string walks. This is the main optimization for
        # reducing regex passes in MarkdownExtensions (see issue #559).
        # Fence state (nested fences, indented code, closing-fence rules)
        # lives in the shared FenceTracker.
        #
        # The block is called for every line outside fenced code; fence
        # delimiters, fence content, and engine marker lines pass through
        # verbatim. The second block argument is kept for call-site
        # compatibility and is always false.
        private def process_lines_fence_aware(content : String, &) : String
          String.build do |io|
            tracker = FenceTracker.new
            content.each_line(chomp: false) do |line|
              if tracker.fence_line?(line) || line.starts_with?(ENGINE_MARKER_PREFIX)
                io << line
              else
                io << yield(line, false)
              end
            end
          end
        end

        # Walk lines and apply the heading-id transform only outside fenced
        # code blocks, so `## ... {#id}` shown inside a ```` ``` ```` example
        # in the docs renders verbatim.
        #
        # Under Markd's safe mode, inline HTML comments are replaced with the
        # placeholder `<!-- raw HTML omitted -->`, which would both lose the id
        # *and* leak that placeholder into the heading text. In that case we
        # strip the `{#id}` syntax silently — custom heading IDs are not
        # supported alongside `markdown.safe = true`.
        def preprocess_heading_ids(content : String, *, safe : Bool = false) : String
          return content unless content.includes?("{#")

          process_lines_fence_aware(content) do |line, _in_fence|
            if line.includes?("{#")
              line.gsub(HEADING_ID_RE) do |_|
                if safe
                  "#{$1}#{$2} #{$3.rstrip}"
                else
                  "#{$1}#{$2} #{$3.rstrip} <!--HID:#{$4}-->"
                end
              end
            else
              line
            end
          end
        end

        # --- Strikethrough (GFM) ---
        # `~~text~~` → `<del>text</del>`. Markd doesn't ship a GFM strikethrough
        # parser, so we apply this pre-Markd. The walk is fence-aware so
        # examples inside fenced code blocks (` ``` ` / `~~~`) render verbatim,
        # and inline `` `code` `` runs on the same line are skipped via a
        # placeholder pass so e.g. `` `~~not strike~~` `` stays as code.
        #
        # Known limitation: when math is also enabled, `$~~x~~$` is rewritten
        # by this pass before the math pass runs, so the `<del>` tags end up
        # escaped inside the KaTeX expression. We do not stash math spans
        # because they can span multiple lines (display math) and the walker
        # is line-oriented. `~~` inside math is rare and the failure is
        # visible at render time.
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

        # Stash inline code spans, transform the rest through the block, then
        # restore the spans — so literals like `` `~~x~~` ``, `` `[^1]` ``,
        # and `` `$x$` `` survive the HTML-injecting passes. Multi-line
        # chunks pass SINGLE_LINE_CODE_SPAN_RE so a stray lone backtick in
        # one paragraph can't absorb text from another.
        private def transform_outside_code_spans(text : String, code_span_re : Regex = STRIKETHROUGH_CODE_RE, & : String -> String) : String
          return yield text unless text.includes?('`')

          code_spans = [] of String
          stashed = text.gsub(code_span_re) do |match|
            code_spans << match
            "\x00CS#{code_spans.size - 1}\x00"
          end

          rewritten = yield stashed

          code_spans.each_with_index do |span, idx|
            rewritten = rewritten.sub("\x00CS#{idx}\x00", span)
          end
          rewritten
        end

        HEADING_TAG_FOR_HID_RE = /<(h[1-6])([^>]*)>(.*?)<\/\1>/m
        HID_MARKER_RE          = /<!--HID:([A-Za-z][\w:-]*)-->/
        EXISTING_ID_RE         = /\bid\s*=\s*"[^"]*"/i
        ANY_ID_ATTR_PRESENT_RE = /\bid\s*=/i

        def postprocess_heading_ids(html : String) : String
          return html unless html.includes?("<!--HID:")

          html.gsub(HEADING_TAG_FOR_HID_RE) do |match|
            tag = $1
            attrs = $2
            inner = $3

            if hid_match = inner.match(HID_MARKER_RE)
              id = hid_match[1]
              cleaned_inner = inner.sub(hid_match[0], "").rstrip

              new_attrs = if attrs.matches?(ANY_ID_ATTR_PRESENT_RE)
                            attrs.sub(EXISTING_ID_RE, %(id="#{id}"))
                          else
                            "#{attrs.rstrip} id=\"#{id}\""
                          end

              "<#{tag}#{new_attrs}>#{cleaned_inner}</#{tag}>"
            else
              match
            end
          end
        end

        # Inline-markdown renderer used by definition lists (and now footnote
        # bodies). Delegates to the shared `InlineMarkdown` module so the same
        # rules apply across table cells, `<dt>/<dd>`, and `<section.footnotes>`.
        private def render_inline_md(text : String) : String
          InlineMarkdown.render(text)
        end
      end
    end
  end
end
