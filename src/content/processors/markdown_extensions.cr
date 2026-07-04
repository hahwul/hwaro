require "html"
require "./fence_tracker"
require "./inline_markdown"
require "./markdown_attributes"
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
          # earlier (in Markdown#render) for the same reason. Math is split
          # into a stash phase before the combined pass and an expand phase
          # after it, so `$…$` inside already-escaped <td>/<dd> bodies still
          # gets wrapped while `~~`/`[ ]` inside formulas stays verbatim.
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
                            (do_heading_ids && result.includes?("{#")) ||
                            (do_ins && result.includes?("++")) || (do_mark && result.includes?("==")) ||
                            (do_sub && result.includes?('~')) || (do_sup && result.includes?('^')) ||
                            (config.attributes && result.includes?('{'))

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
        # `math: true` keeps `$…$` spans in <dt>/<dd> bodies untransformed
        # for the later math pass (see InlineMarkdown.render). Pre-F10
        # signature — delegates to the `flags` overload (existing
        # callers/specs keep calling this one directly).
        def preprocess_definition_lists(content : String, *, math : Bool = false) : String
          preprocess_definition_lists(content, flags: InlineMarkdown::Flags.new(math: math))
        end

        # `flags` also threads the F10 opt-in inline markup (ins/mark/sub/
        # sup) into term/definition bodies, alongside the math flag.
        def preprocess_definition_lists(content : String, *, flags : InlineMarkdown::Flags) : String
          # Whole-content marker pre-check (memchr-fast): every definition line
          # must lstrip-start with ": " (see the loop conditions below), so a
          # content without ": " anywhere cannot contain a definition list and
          # the walk is the identity transform — skip it.
          return content unless content.includes?(": ")

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

                result << "<dt>#{render_inline_md(term, flags)}</dt>"
                i += 1

                # Collect definitions for this term
                while i < lines.size && !fenced[i] && lines[i].lstrip.starts_with?(": ")
                  definition = lines[i].lstrip.lchop(": ").strip
                  result << "<dd>#{render_inline_md(definition, flags)}</dd>"
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
        FOOTNOTE_DEF_RE = /^\[\^([^\]]+)\]:\s*(.+?)$/m
        FOOTNOTE_REF_RE = /\[\^([^\]]+)\]/
        # Occurrence count rides on the number field as `NUM.OCC` (e.g. `1.3`).
        # The `.` separator can't appear in the legacy 3-field `NUM:` form, so a
        # 3-field comment whose text starts with digits+colon is never misread
        # as a count.
        FOOTNOTE_COMMENT_RE = /<!--HWARO-FN:([^:]+):(\d+)(?:\.(\d+))?:(.+?)-->/
        FOOTNOTE_BLOCK_RE   = /\n?<!--HWARO-FOOTNOTES-START-->.*?<!--HWARO-FOOTNOTES-END-->\n?/m

        # Derive an id-safe token from a footnote key. The key can contain ASCII
        # whitespace (`[^my note]`), which is invalid in an `id`/fragment, so
        # collapse runs of whitespace to a single `-` before HTML-escaping the
        # rest. Must be applied identically on the reference side and the
        # li/backref side so forward and backward anchors still match.
        def footnote_id_token(key : String) : String
          HTML.escape(key.gsub(/\s+/, "-"))
        end

        def preprocess_footnotes(content : String) : String
          # Whole-content marker pre-check (memchr-fast): without `[^` there is
          # no footnote definition or reference to process, and without the
          # HWARO comment markers the neutralization gsubs below are identity —
          # skipping keeps both the output AND the in-band-injection defense
          # exactly as before. Any page passing this check transforms as today.
          unless content.includes?("[^") ||
                 content.includes?("<!--HWARO-FN") ||
                 content.includes?("<!--HWARO-FOOTNOTES-")
            return content
          end

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
          # Per-key occurrence counter so repeated references of the same
          # footnote get unique ids (fnref-KEY, fnref-KEY-2, …) instead of
          # emitting duplicate `id` attributes (invalid HTML, ambiguous backref).
          ref_occurrences = Hash(String, Int32).new(0)
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
                ref_occurrences[key] += 1
                occ = ref_occurrences[key]
                escaped_key = footnote_id_token(key)
                ref_id = occ == 1 ? "fnref-#{escaped_key}" : "fnref-#{escaped_key}-#{occ}"
                "<sup class=\"footnote-ref\"><a href=\"#fn-#{escaped_key}\" id=\"#{ref_id}\">[#{num}]</a></sup>"
              end
            end
          end

          # Store footnotes data in a special HTML comment for postprocessing
          if ref_order.present?
            result += "\n<!--HWARO-FOOTNOTES-START-->\n"
            ref_order.each do |key, num|
              text = footnotes[key]? || ""
              occ = ref_occurrences[key]? || 1
              # Escape --> in text to prevent premature comment close, and : to prevent parsing issues
              safe_key = key.gsub("--", "&#45;&#45;").gsub(":", "&#58;")
              safe_text = text.gsub("--", "&#45;&#45;").gsub(":", "&#58;")
              result += "<!--HWARO-FN:#{safe_key}:#{num}.#{occ}:#{safe_text}-->\n"
            end
            result += "<!--HWARO-FOOTNOTES-END-->\n"
          end

          result
        end

        # Post-processing: convert footnote comments to HTML section.
        # `math: true` keeps `$…$` spans in footnote bodies untransformed
        # (math is not rendered in footnotes, but its internals must not be
        # rewritten by emphasis/strikethrough either). Pre-F10 signature —
        # delegates to the `flags` overload (existing callers/specs keep
        # calling this one directly).
        def postprocess_footnotes(html : String, *, math : Bool = false) : String
          postprocess_footnotes(html, flags: InlineMarkdown::Flags.new(math: math))
        end

        # `flags` also threads the F10 opt-in inline markup (ins/mark/sub/
        # sup) into footnote bodies, alongside the math flag.
        def postprocess_footnotes(html : String, *, flags : InlineMarkdown::Flags) : String
          return html unless html.includes?("<!--HWARO-FOOTNOTES-START-->")

          # Extract footnote data from comments
          footnotes = [] of {key: String, num: Int32, occ: Int32, text: String}
          html.scan(FOOTNOTE_COMMENT_RE) do |match|
            # Unescape the comment-safe encoding
            key = match[1].gsub("&#58;", ":").gsub("&#45;&#45;", "--")
            text = match[4].gsub("&#58;", ":").gsub("&#45;&#45;", "--")
            num = match[2].to_i? || 0
            # Occurrence count is optional: older/hand-written 3-field comments
            # (no count) fall back to a single backref.
            occ = match[3]?.try(&.to_i?) || 1
            next if num <= 0
            footnotes << {key: key, num: num, occ: occ, text: text}
          end

          return html if footnotes.empty?

          # Build footnotes section. Body text is rendered through the shared
          # inline-md helper so `` `code` ``/`*em*`/`[link](url)`/`~~del~~`
          # inside a footnote behave the same way they do in table cells and
          # definition lists.
          section = String.build do |str|
            str << "<section class=\"footnotes\">\n<hr>\n<ol>\n"
            footnotes.sort_by { |fn| fn[:num] }.each do |fn|
              escaped_key = footnote_id_token(fn[:key])
              rendered_text = InlineMarkdown.render(fn[:text], flags: flags)
              str << "<li id=\"fn-#{escaped_key}\">\n"
              # One backref per reference occurrence so every `fnref-\u2026` id is
              # reachable (cmark-gfm/pandoc behavior): \u21A9, \u21A92, \u21A93, \u2026
              backrefs = String.build do |b|
                (1..fn[:occ]).each do |i|
                  target = i == 1 ? "fnref-#{escaped_key}" : "fnref-#{escaped_key}-#{i}"
                  label = i == 1 ? "\u21A9" : "\u21A9#{i}"
                  b << ' ' if i > 1
                  b << "<a href=\"##{target}\" class=\"footnote-backref\">#{label}</a>"
                end
              end
              str << "<p>#{rendered_text} #{backrefs}</p>\n"
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
        DISPLAY_MATH_RE = InlineMarkdown::DISPLAY_MATH_RE
        INLINE_MATH_RE  = InlineMarkdown::INLINE_MATH_RE
        # Code-span pattern confined to one line, for stashing inside
        # multi-line chunks: a stray lone backtick in one paragraph must not
        # absorb text from another.
        SINGLE_LINE_CODE_SPAN_RE = /`[^`\n]+`/
        # Inline `<code>…</code>` HTML spans — generated by InlineMarkdown
        # for table cells / definition bodies (where the original backticks
        # are already consumed), or author-written raw HTML. Their content
        # is code: the strikethrough/footnote/math passes must treat it as
        # opaque, exactly like backtick spans. `[^<]*` keeps the match to a
        # flat element (generated spans never contain tags).
        HTML_CODE_SPAN_RE = /<code(?:\s[^>]*)?>[^<]*<\/code>/
        # CommonMark "type 6" HTML-block start condition (common block tags,
        # including the <table>/<dl>/<div> markup hwaro itself generates).
        # A line opening one of these starts a raw-HTML block that runs to
        # the next blank line — Markd performs NO inline parsing there, so
        # backslash escapes ship verbatim instead of collapsing.
        HTML_BLOCK_START_RE = /^ {0,3}<\/?(?:address|article|aside|blockquote|caption|center|col|colgroup|dd|details|dialog|div|dl|dt|fieldset|figcaption|figure|footer|form|h[1-6]|header|hr|li|main|menu|nav|ol|p|section|summary|table|tbody|td|tfoot|th|thead|tr|ul)(?:[\s>\/]|\r?$)/i

        # A math span captured by `stash_math`, awaiting `expand_math`.
        record MathSpan, display : Bool, body : String

        MATH_PLACEHOLDER_RE = /\x00MATH(\d+)\x00/

        # One-shot math transform (stash + immediate expand). `preprocess`
        # itself uses the two phases separately so the combined pass runs in
        # between — see the ordering comment there.
        def preprocess_math(content : String) : String
          stashed, store = stash_math(content)
          expand_math(stashed, store)
        end

        # Phase 1: replace `$$…$$` / `$…$` spans with opaque placeholders so
        # the passes running in between can't rewrite formula internals
        # (`$~~x~~$` must reach KaTeX verbatim, not as `$<del>x</del>$`).
        #
        # Fence-aware: `$$` is common in Makefile/shell/Perl code examples,
        # and rewriting it inside a fence corrupts the code block. Display
        # math can span lines, so instead of a per-line walk this buffers
        # runs of non-fence lines and stashes each run as one chunk.
        private def stash_math(content : String) : Tuple(String, Array(MathSpan))
          store = [] of MathSpan
          return {content, store} unless content.includes?('$')

          result = String.build do |io|
            tracker = FenceTracker.new
            chunk = String::Builder.new
            content.each_line(chomp: false) do |line|
              if tracker.fence_line?(line) || line.starts_with?(ENGINE_MARKER_PREFIX)
                if chunk.bytesize > 0
                  io << stash_math_chunk(chunk.to_s, store)
                  chunk = String::Builder.new
                end
                io << line
              else
                chunk << line
              end
            end
            io << stash_math_chunk(chunk.to_s, store) if chunk.bytesize > 0
          end

          {result, store}
        end

        private def stash_math_chunk(text : String, store : Array(MathSpan)) : String
          return text unless text.includes?('$')

          # Code spans — backtick AND `<code>` HTML (a `` `$x$` `` table cell
          # is already `<code>$x$</code>` by now) — are stashed first so
          # their `$…$` stays verbatim. Not via transform_outside_code_spans:
          # a code span captured INSIDE a math body would leave its `\x00CS…`
          # token in the store where the helper's restore step can't see it,
          # so each body is restored explicitly at capture time.
          code_spans = [] of String
          stashed = text
          if text.includes?('`')
            stashed = stashed.gsub(SINGLE_LINE_CODE_SPAN_RE) do |match|
              code_spans << match
              "\x00CS#{code_spans.size - 1}\x00"
            end
          end
          if stashed.includes?("<code")
            stashed = stashed.gsub(HTML_CODE_SPAN_RE) do |match|
              code_spans << match
              "\x00CS#{code_spans.size - 1}\x00"
            end
          end

          result = stashed.gsub(DISPLAY_MATH_RE) do |_|
            store << MathSpan.new(display: true, body: restore_code_spans($~[1], code_spans))
            "\x00MATH#{store.size - 1}\x00"
          end

          if result.includes?('$')
            result = result.gsub(INLINE_MATH_RE) do |_|
              store << MathSpan.new(display: false, body: restore_code_spans($~[1], code_spans))
              "\x00MATH#{store.size - 1}\x00"
            end
          end

          restore_code_spans(result, code_spans)
        end

        private def restore_code_spans(text : String, code_spans : Array(String)) : String
          return text if code_spans.empty? || !text.includes?('\0')
          # Reverse order: an HTML code span stashed second can contain a
          # backtick-span placeholder stashed first.
          (code_spans.size - 1).downto(0) do |idx|
            text = text.sub("\x00CS#{idx}\x00", code_spans[idx])
          end
          text
        end

        # Phase 2: expand stashed math spans into final HTML.
        #
        # Display math always emits single-backslash `\[…\]`: its `<div>` is
        # an HTML block, opaque to Markd in every context. Inline math
        # delimiter escaping depends on block context:
        #
        # - In normal inline context the `<span>` content participates in
        #   CommonMark inline parsing, so the delimiters need an extra
        #   backslash — `\\(` in the markdown source collapses to `\(` in
        #   the HTML.
        # - Inside a raw HTML block (a <td>/<dd> hwaro generated, or
        #   author-written block HTML) Markd does no inline parsing and
        #   backslashes ship verbatim, so a single backslash is correct.
        #
        # Walk line by line to track the HTML-block state (a type-6 block
        # runs from its opening tag line to the next blank line).
        private def expand_math(content : String, store : Array(MathSpan)) : String
          return content if store.empty?

          String.build do |io|
            tracker = FenceTracker.new
            in_html_block = false
            content.each_line(chomp: false) do |line|
              if tracker.fence_line?(line) || line.starts_with?(ENGINE_MARKER_PREFIX)
                # Mirrors stash_math's chunk boundaries: block state resets.
                in_html_block = false
                io << line
                next
              end

              if in_html_block
                in_html_block = false if line.strip.empty?
              elsif HTML_BLOCK_START_RE.matches?(line)
                in_html_block = true
              end

              unless line.includes?('\0')
                io << line
                next
              end

              raw_context = in_html_block
              io << line.gsub(MATH_PLACEHOLDER_RE) do |match|
                span = $~[1].to_i?.try { |idx| store[idx]? }
                next match unless span

                escaped = Utils::TextUtils.escape_xml(span.body)
                if span.display
                  "<div class=\"math math-display\">\\[#{escaped}\\]</div>"
                elsif raw_context
                  "<span class=\"math math-inline\">\\(#{escaped}\\)</span>"
                else
                  # Normal inline context: the body still flows through Markd's
                  # CommonMark inline parser, which would (a) read `*`/`_` as
                  # emphasis and pair them across math spans, (b) start code
                  # spans on backticks, (c) form links on `[`/`]`, and (d)
                  # CONSUME a backslash before any ASCII punctuation — stripping
                  # the LaTeX escapes in e.g. `$\{x\}$` or `$a \& b$`. Backslash-
                  # escape each of those active chars (backslash itself FIRST, so
                  # `\{` survives as `\{` rather than being eaten) so Markd ships
                  # the formula body verbatim to KaTeX/MathJax. (`~` is left
                  # alone: GFM strikethrough is handled by hwaro's own
                  # preprocessor, which already skips math spans.)
                  inline_escaped = escaped.gsub(/[\\`*_\[\]]/) { |c| "\\#{c}" }
                  "<span class=\"math math-inline\">\\\\(#{inline_escaped}\\\\)</span>"
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

        # --- Custom Attributes (F9) ---
        # Generalized `{#id .class key=val}` attribute blocks — headings and
        # inline images. See `markdown_attributes.cr` for the token grammar.
        # Deliberately broader than HEADING_ID_RE's brace group
        # (`[^{}]+` vs `\#[A-Za-z][\w:-]*`): this is what makes the two
        # regexes disjoint on `## H {#id}` (HEADING_ID_RE wins) while still
        # catching `## H {#id .class}` (falls through to this one, since
        # HEADING_ID_RE requires the braces to contain ONLY `#id`).
        HEADING_ATTR_RE = /^([ ]{0,3})(\#{1,6})[ \t]+(.+?)[ \t]*\{([^{}]+)\}[ \t]*\r?$/
        # `![alt](url){.class key=val}` — an attribute block immediately
        # following an inline image's closing `)`. Matched inside
        # `transform_outside_code_spans` so a literal example in a code span
        # isn't rewritten.
        IMAGE_ATTR_RE = /(!\[[^\]]*\]\([^)]*\))\{([^{}]+)\}/

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

          # Reverse order: an HTML code span stashed second can contain a
          # backtick-span placeholder stashed first (`<code>` + "`x`" on one
          # line); restoring highest-index first re-exposes the inner
          # placeholder for its own restore.
          (code_spans.size - 1).downto(0) do |idx|
            rewritten = rewritten.sub("\x00CS#{idx}\x00", code_spans[idx])
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

        # --- Custom Attributes (F9) postprocess ---
        # Resolves `<!--HATTR:HEXPAYLOAD-->` markers (left by the preprocess
        # branches above) into real `id`/`class`/other attributes on the
        # heading tag or `<img>` tag they trail. Runs BEFORE footnotes (an
        # attribute block is only ever on a heading/image line, never inside
        # footnote marker comments) and AFTER heading_ids (so a heading that
        # got a `<!--HID:...-->` marker instead — the pure `{#id}` case — is
        # already resolved and simply won't match `HATTR_MARKER_RE` here).
        HATTR_MARKER_RE = /<!--HATTR:([0-9a-f]+)-->/
        # `<img ...>` opening portion (quote-aware, so a `>` inside an
        # attribute value like `alt="Home > Docs"` isn't mistaken for the
        # tag end), its closer (`>` or `/>`, with any whitespace before it),
        # and the trailing marker comment this preprocess pass appended.
        IMG_HATTR_RE = /(<img\b(?:[^>"']|"[^"]*"|'[^']*')*?)(\s*\/?>)\s*<!--HATTR:([0-9a-f]+)-->/

        def postprocess_attributes(html : String) : String
          return html unless html.includes?("<!--HATTR:")

          result = html.gsub(HEADING_TAG_FOR_HID_RE) do |match|
            tag = $1
            attrs = $2
            inner = $3

            if hattr_match = inner.match(HATTR_MARKER_RE)
              parsed = decode_and_parse_hattr(hattr_match[1])
              if parsed
                cleaned_inner = inner.sub(hattr_match[0], "").rstrip
                new_attrs = MarkdownAttributes.apply_to_tag_attrs(attrs, parsed)
                "<#{tag}#{new_attrs}>#{cleaned_inner}</#{tag}>"
              else
                match
              end
            else
              match
            end
          end

          result = result.gsub(IMG_HATTR_RE) do |match|
            img_open = $1
            closer = $2
            parsed = decode_and_parse_hattr($3)
            if parsed
              "#{MarkdownAttributes.apply_to_img(img_open, parsed)}#{closer}"
            else
              match
            end
          end

          # No marker may leak into published output, even a malformed one
          # (defensive — the capture regexes above require 1+ hex chars, so
          # an empty payload should never occur via the normal preprocess
          # path, but this keeps the invariant regardless).
          result.gsub(/<!--HATTR:[0-9a-f]*-->/, "")
        end

        private def decode_and_parse_hattr(payload : String) : MarkdownAttributes::Parsed?
          decoded = MarkdownAttributes.decode(payload)
          return unless decoded
          MarkdownAttributes.parse(decoded)
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
