require "html"
require "./fence_tracker"
require "./inline_markdown"
require "./markdown_attributes"
require "../../models/config"
require "../../utils/text_utils"

require "./markdown_extensions/external_links"
require "./markdown_extensions/task_lists"
require "./markdown_extensions/containers"
require "./markdown_extensions/definition_lists"
require "./markdown_extensions/footnotes"
require "./markdown_extensions/math"
require "./markdown_extensions/mermaid"
require "./markdown_extensions/admonitions"
require "./markdown_extensions/custom_heading_ids"
require "./markdown_extensions/strikethrough"
require "./markdown_extensions/attributes"

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
          # earlier (in Markdown#render) for the same reason. Math is split
          # into a stash phase before the combined pass and an expand phase
          # after it, so `$…$` inside already-escaped <td>/<dd> bodies still
          # gets wrapped while `~~`/`[ ]` inside formulas stays verbatim.
          # Containers run FIRST: their ::: marker lines become raw-HTML
          # wrapper lines, and everything between stays untouched for the
          # passes below (and Markd) to parse as ordinary markdown. Not
          # supported under safe mode — markd would strip the raw <div>
          # wrappers (same class of limitation as custom heading ids).
          result = preprocess_containers(result) if config.containers && !config.safe
          result = preprocess_definition_lists(result, flags: inline_flags(config)) if config.definition_lists
          result = preprocess_footnotes(result) if config.footnotes

          # Math spans become opaque placeholders before the combined pass —
          # `$~~x~~$` must reach KaTeX verbatim, not as `$<del>x</del>$`.
          math_store = nil
          if config.math
            result, math_store = stash_math(result)
          end

          # Combined single fence-aware pass for per-line safe extensions
          # (task_lists + strikethrough + heading_ids + F10 inline markup) —
          # reduces full document walks (#559).
          do_task_lists = config.task_lists
          do_strikethrough = true
          do_heading_ids = config.heading_ids
          do_ins = config.ins
          do_mark = config.mark
          do_sub = config.sub
          do_sup = config.sup

          # Whole-content marker pre-check (memchr-fast): with none of the
          # enabled extensions' markers present, the line pass is the
          # identity transform and only rebuilds the string — skip it. The
          # per-line includes? guards below are unchanged, so any page that
          # passes this check transforms exactly as before.
          markers_present = (do_task_lists && (result.includes?("[ ]") || result.includes?("[x]") || result.includes?("[X]"))) ||
                            (do_strikethrough && result.includes?("~~")) ||
                            (do_heading_ids && (result.includes?("{#") || result.includes?("<!--HID:"))) ||
                            (do_ins && result.includes?("++")) || (do_mark && result.includes?("==")) ||
                            (do_sub && result.includes?('~')) || (do_sup && result.includes?('^')) ||
                            (config.attributes && (result.includes?('{') || result.includes?("<!--HATTR:")))

          if markers_present
            result = process_lines_fence_aware(result) do |line, _in_fence|
              transformed = line

              # Author-typed engine markers are neutralized before the
              # branches below inject the real ones — same in-band-signaling
              # protection footnotes get (see preprocess_footnotes), but
              # per-line and code-span-safe: a literal `<!--HID:x-->` in
              # inline code or a fenced example stays byte-identical (it's
              # inert there — Markd entity-escapes it), while one typed in
              # prose can no longer smuggle an id or attributes onto a
              # heading.
              if do_heading_ids && transformed.includes?("<!--HID:")
                transformed = transform_outside_code_spans(transformed) do |stashed|
                  stashed.gsub("<!--HID:", "<!-- HID:")
                end
              end

              if config.attributes && transformed.includes?("<!--HATTR:")
                transformed = transform_outside_code_spans(transformed) do |stashed|
                  stashed.gsub("<!--HATTR:", "<!-- HATTR:")
                end
              end

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

              # F9 opt-in `{#id .class key=val}` attribute blocks. Runs
              # AFTER heading_ids above: HEADING_ID_RE already consumed (and
              # rewrote/removed) a pure `{#id}` block, so on a line where
              # that happened `transformed` no longer contains it — the two
              # regexes are disjoint on any single line, which is what keeps
              # `## H {#id}` byte-identical when heading_ids=true regardless
              # of this flag.
              if config.attributes && transformed.includes?('{')
                transformed = transformed.gsub(HEADING_ATTR_RE) do |full_match|
                  if MarkdownAttributes.parse($4)
                    if config.safe
                      "#{$1}#{$2} #{$3.rstrip}"
                    else
                      "#{$1}#{$2} #{$3.rstrip} <!--HATTR:#{MarkdownAttributes.encode($4)}-->"
                    end
                  else
                    full_match
                  end
                end
              end

              if config.attributes && transformed.includes?("![") && transformed.includes?('{')
                transformed = transform_outside_code_spans(transformed) do |stashed|
                  stashed.gsub(IMAGE_ATTR_RE) do |full_match|
                    if MarkdownAttributes.parse($2)
                      if config.safe
                        $1
                      else
                        "#{$1}<!--HATTR:#{MarkdownAttributes.encode($2)}-->"
                      end
                    else
                      full_match
                    end
                  end
                end
              end

              # F10 opt-in inline markup — each flag gets its own guarded
              # branch (not merged with strikethrough's) so the flags-off
              # byte path above stays the untouched pre-F10 code exactly.
              # Fixed order: ins, mark, sub, sup.
              if do_ins && transformed.includes?("++")
                transformed = transform_outside_code_spans(transformed) do |stashed|
                  stashed.gsub(InlineMarkdown::INLINE_INS_RE) { "<ins>#{$1}</ins>" }
                end
              end

              if do_mark && transformed.includes?("==")
                transformed = transform_outside_code_spans(transformed) do |stashed|
                  stashed.gsub(InlineMarkdown::INLINE_MARK_RE) { "<mark>#{$1}</mark>" }
                end
              end

              if do_sub && transformed.includes?('~')
                transformed = transform_outside_code_spans(transformed) do |stashed|
                  stashed.gsub(InlineMarkdown::INLINE_SUB_RE) { "<sub>#{$1}</sub>" }
                end
              end

              if do_sup && transformed.includes?('^')
                transformed = transform_outside_code_spans(transformed) do |stashed|
                  stashed.gsub(InlineMarkdown::INLINE_SUP_RE) { "<sup>#{$1}</sup>" }
                end
              end

              transformed
            end
          end

          # Expand the stashed math spans into final HTML now that the
          # transforming passes are done.
          result = expand_math(result, math_store) if math_store

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

          result = postprocess_attributes(result) if config.attributes
          result = postprocess_footnotes(result, flags: inline_flags(config)) if config.footnotes
          result = postprocess_mermaid(result) if config.mermaid
          result = postprocess_task_list_classes(result) if config.task_lists && config.task_list_classes
          # Last, so anchors from every producer above (markd, table cells,
          # footnote sections) get the site's external-link policy.
          result = postprocess_external_links(result, config)

          result
        end

        # Inline-markdown renderer used by definition lists (and now footnote
        # bodies). Delegates to the shared `InlineMarkdown` module so the same
        # rules apply across table cells, `<dt>/<dd>`, and `<section.footnotes>`.
        private def render_inline_md(text : String, math : Bool = false) : String
          InlineMarkdown.render(text, math: math)
        end

        private def render_inline_md(text : String, flags : InlineMarkdown::Flags) : String
          InlineMarkdown.render(text, flags: flags)
        end

        # Builds the shared `InlineMarkdown::Flags` for a markdown config —
        # math plus the F10 opt-in inline markup — so table cells,
        # definition lists, and footnote bodies all see the same set of
        # enabled transforms as the main per-line pass above.
        def inline_flags(config : Models::MarkdownConfig) : InlineMarkdown::Flags
          InlineMarkdown::Flags.new(
            math: config.math,
            ins: config.ins,
            mark: config.mark,
            sub: config.sub,
            sup: config.sup,
          )
        end
      end
    end
  end
end
