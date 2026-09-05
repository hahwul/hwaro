# Markdown extensions — custom heading ids ({#id}) and fence-aware line passes.
#
# One file per `# --- X ---` pass of the pre/post-processing pipeline; the
# pass ORDER is fixed in ../markdown_extensions.cr (`preprocess` /
# `postprocess`). Parts only reopen the module: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
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

        # Quote-aware attrs (a `>` inside a quoted value must not end the
        # tag); the id checks guard with `(?<![\w-])` so `data-id=` never
        # counts as the element's id.
        HEADING_TAG_FOR_HID_RE = /<(h[1-6])((?:[^>"']|"[^"]*"|'[^']*')*)>(.*?)<\/\1>/m
        HID_MARKER_RE          = /<!--HID:([A-Za-z][\w:-]*)-->/
        EXISTING_ID_RE         = /(?<![\w-])id\s*=\s*"[^"]*"/i
        ANY_ID_ATTR_PRESENT_RE = /(?<![\w-])id\s*=/i

        def postprocess_heading_ids(html : String) : String
          return html unless html.includes?("<!--HID:")

          html.gsub(HEADING_TAG_FOR_HID_RE) do |match|
            tag = $1
            attrs = $2
            inner = $3

            if hid_match = inner.match(HID_MARKER_RE)
              id = hid_match[1]
              cleaned_inner = inner.sub(hid_match[0], "").rstrip

              # `backreferences: false`: `HID_MARKER_RE`'s grammar already
              # excludes `\`, so no id can carry one today — but the guard
              # keeps that invariant local, so loosening the marker grammar
              # later can't turn an id into a replacement backreference (see
              # the same guard in `postprocess_external_links`).
              new_attrs = if attrs.matches?(ANY_ID_ATTR_PRESENT_RE)
                            attrs.sub(EXISTING_ID_RE, %(id="#{id}"), backreferences: false)
                          else
                            "#{attrs.rstrip} id=\"#{id}\""
                          end

              "<#{tag}#{new_attrs}>#{cleaned_inner}</#{tag}>"
            else
              match
            end
          end
        end
      end
    end
  end
end
