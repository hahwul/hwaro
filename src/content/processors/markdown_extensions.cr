require "html"
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

          # === Aggressive pass reduction for #559 ===
          # We aggressively combine as many simple regex-based extensions
          # as possible into a *single* fence-aware line pass.
          #
          # Order preserved from original (important for correctness):
          # task_lists → math → strikethrough → heading_ids
          #
          # Complex/structural ones (definition_lists, footnotes) are left
          # as separate passes because they have multi-line state and
          # different requirements.

          # Combined single fence-aware pass for per-line safe extensions
          # (task_lists + strikethrough + heading_ids). This is the aggressive
          # optimization for #559 — reduces full document walks.
          do_task_lists = config.task_lists
          do_strikethrough = true
          do_heading_ids = config.heading_ids

          if do_task_lists || do_strikethrough || do_heading_ids
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

          # Math kept as separate pass (multi-line $$ + known strikethrough interaction)
          result = preprocess_math(result) if config.math

          # Structural extensions kept separate
          result = preprocess_definition_lists(result) if config.definition_lists
          result = preprocess_footnotes(result) if config.footnotes

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
        # Converts Term\n: Definition syntax to <dl><dt><dd> HTML
        def preprocess_definition_lists(content : String) : String
          lines = content.split("\n")
          result = [] of String
          i = 0

          while i < lines.size
            line = lines[i]

            # Check if next line starts with ": " (definition)
            if i + 1 < lines.size && lines[i + 1].lstrip.starts_with?(": ")
              # This is a definition list
              result << "<dl>"
              while i < lines.size
                term = lines[i].strip
                if term.empty?
                  i += 1
                  break
                end

                result << "<dt>#{render_inline_md(term)}</dt>"
                i += 1

                # Collect definitions for this term
                while i < lines.size && lines[i].lstrip.starts_with?(": ")
                  definition = lines[i].lstrip.lchop(": ").strip
                  result << "<dd>#{render_inline_md(definition)}</dd>"
                  i += 1
                end

                # Skip one or more blank lines between term groups within the same dl
                peek = i
                while peek < lines.size && lines[peek].strip.empty?
                  peek += 1
                end
                if peek > i && peek + 1 < lines.size && lines[peek + 1].lstrip.starts_with?(": ")
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
          # Extract and remove footnote definitions
          footnotes = {} of String => String
          cleaned = content.gsub(FOOTNOTE_DEF_RE) do |_|
            footnotes[$~[1]] = $~[2]
            "" # Remove definition from content
          end

          return cleaned if footnotes.empty?

          # Replace references with superscript HTML placeholders
          counter = 0
          ref_order = {} of String => Int32
          result = cleaned.gsub(FOOTNOTE_REF_RE) do |full_match|
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

          # Replace the comment block with the rendered section
          html.sub(FOOTNOTE_BLOCK_RE, section)
        end

        # --- Math ---
        # Wraps math expressions in special HTML to prevent Markd from processing them
        def preprocess_math(content : String) : String
          # Display math: $$...$$ (multi-line)
          result = content.gsub(/\$\$(.*?)\$\$/m) do |_|
            escaped = Utils::TextUtils.escape_xml($~[1])
            "<div class=\"math math-display\">\\[#{escaped}\\]</div>"
          end

          # Inline math: $...$ (single line, no space after opening or before closing $)
          # NOTE: Inline `<span>` content participates in CommonMark inline parsing,
          # so the KaTeX delimiters need an extra backslash to survive — `\\(` in
          # the markdown source renders to `\(` in HTML, which KaTeX auto-render
          # expects. Display math uses `<div>` (HTML block, opaque to Markd) and
          # therefore keeps a single backslash.
          result = result.gsub(/(?<![\\$])\$(?!\s)([^\n$]+?)(?<!\s)\$(?!\d)/) do |_|
            escaped = Utils::TextUtils.escape_xml($~[1])
            "<span class=\"math math-inline\">\\\\(#{escaped}\\\\)</span>"
          end

          result
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
        HEADING_ID_RE = /^([ ]{0,3})(\#{1,6})[ \t]+(.+?)[ \t]*\{\#([A-Za-z][\w:-]*)\}[ \t]*$/

        FENCE_BACKTICKS = "```"
        FENCE_TILDES    = "~~~"

        # Unified fence-aware line processor.
        # This allows multiple extensions (heading_ids + strikethrough, etc.)
        # to be applied in a *single* pass over the document instead of
        # separate full-string walks. This is the main optimization for
        # reducing regex passes in MarkdownExtensions (see issue #559).
        #
        # The block is called for every line. It receives the original line
        # and whether we are currently inside a fenced code block.
        # The block should return the (possibly transformed) line.
        private def process_lines_fence_aware(content : String, &) : String
          String.build do |io|
            in_fence = false
            fence_marker = FENCE_BACKTICKS

            content.each_line(chomp: false) do |line|
              stripped = line.lstrip

              if in_fence
                if stripped.starts_with?(fence_marker)
                  in_fence = false
                end
                io << line
              elsif stripped.starts_with?(FENCE_BACKTICKS)
                in_fence = true
                fence_marker = FENCE_BACKTICKS
                io << line
              elsif stripped.starts_with?(FENCE_TILDES)
                in_fence = true
                fence_marker = FENCE_TILDES
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
        # Known limitation: when math is also enabled, `$~~x~~$` runs the math
        # preprocess first and the `~~` chars end up inside a math span,
        # then this pass rewrites them — corrupting the KaTeX expression. We
        # do not stash math spans because they can span multiple lines (display
        # math) and the walker is line-oriented. `~~` inside math is rare and
        # the failure is visible at render time.
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
          code_spans = [] of String
          stashed = line.gsub(STRIKETHROUGH_CODE_RE) do |match|
            code_spans << match
            "\x00CS#{code_spans.size - 1}\x00"
          end

          rewritten = stashed.gsub(STRIKETHROUGH_RE) { "<del>#{$1}</del>" }

          code_spans.each_with_index do |span, idx|
            rewritten = rewritten.gsub("\x00CS#{idx}\x00", span)
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
