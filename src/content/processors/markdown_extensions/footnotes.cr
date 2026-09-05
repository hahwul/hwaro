# Markdown extensions — footnotes.
#
# One file per `# --- X ---` pass of the pre/post-processing pipeline; the
# pass ORDER is fixed in ../markdown_extensions.cr (`preprocess` /
# `postprocess`). Parts only reopen the module: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
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
          # A definition collects 4-space/tab-indented continuation lines
          # (GFM/pandoc style), including blank-line-separated paragraphs:
          # soft-wrapped lines join with "\n", a held blank line becomes a
          # "\n\n" paragraph break when (and only when) the next non-blank
          # line is indented too. Lazy (unindented) continuation is NOT
          # supported — it would eat the regular paragraph after a
          # definition. Consumed lines are replaced with bare "\n" so the
          # surrounding CommonMark block structure is unchanged.
          footnotes = {} of String => String
          pending_key = nil.as(String?)
          pending_blank = false
          cleaned = String.build do |io|
            tracker = FenceTracker.new
            content.each_line(chomp: false) do |line|
              # Collection takes precedence over fence tracking: an indented
              # continuation after a held blank would otherwise read as an
              # indented-code run opener. Consumed lines are not fed to the
              # tracker — they are all blank or indented, so at worst its
              # blank/list state is stale-conservative (under-protective,
              # matching pre-collection behavior) for the line that ends
              # the collection.
              if key = pending_key
                if line.strip.empty?
                  pending_blank = true
                  io << line
                  next
                elsif line.starts_with?("    ") || line.starts_with?('\t')
                  footnotes[key] += pending_blank ? "\n\n" : "\n"
                  footnotes[key] += line.strip
                  pending_blank = false
                  io << "\n"
                  next
                end
                pending_key = nil
                pending_blank = false
              end

              if tracker.fence_line?(line)
                io << line
                next
              end

              if m = line.match(FOOTNOTE_DEF_RE)
                # rstrip: on CRLF content the captured text carries a trailing \r
                footnotes[m[1]] = m[2].rstrip
                pending_key = m[1]
                io << "\n"
              else
                io << line
              end
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
              # Escape --> in text to prevent premature comment close, : to
              # prevent parsing issues, and newlines (multi-line bodies) so
              # the comment stays single-line for FOOTNOTE_COMMENT_RE.
              safe_key = key.gsub("--", "&#45;&#45;").gsub(":", "&#58;")
              safe_text = text.gsub("--", "&#45;&#45;").gsub(":", "&#58;").gsub("\n", "&#10;")
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
            text = match[4].gsub("&#58;", ":").gsub("&#45;&#45;", "--").gsub("&#10;", "\n")
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
              # Multi-paragraph bodies (blank-line-separated in the source)
              # render one <p> each, backrefs inside the LAST one (GFM
              # placement). A single-paragraph body produces exactly the
              # pre-multi-line output.
              paragraphs = fn[:text].split(/\n{2,}/)
              paragraphs.each_with_index do |para, idx|
                rendered_text = InlineMarkdown.render(para, flags: flags)
                if idx == paragraphs.size - 1
                  str << "<p>#{rendered_text} #{backrefs}</p>\n"
                else
                  str << "<p>#{rendered_text}</p>\n"
                end
              end
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
      end
    end
  end
end
