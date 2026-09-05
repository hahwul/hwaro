# Markdown extensions — custom attributes ({.class #id key=value}).
#
# One file per `# --- X ---` pass of the pre/post-processing pipeline; the
# pass ORDER is fixed in ../markdown_extensions.cr (`preprocess` /
# `postprocess`). Parts only reopen the module: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
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
        # an optional wrapper the image trails inside (group 3), and the
        # marker comment this preprocess pass appended. The wrapper is what a
        # `render-image.html` hook emits around the `<img>` (e.g. a
        # `<figure>…</figure>`): the marker lands after the *whole* hook
        # output, not glued to the `<img>`, so a naive "marker immediately
        # follows the tag" match would drop the attributes silently. The
        # tempered gap stops at the next image or marker, so back-to-back
        # attributed images each bind their own block, and the no-hook case
        # (marker glued to the tag) keeps an empty group 3. It also stops at a
        # closing block tag Markd wraps the image in (`</p>`, `</li>`, table
        # cells, `</hN>`, …): an image's own marker is always in the same block,
        # so the gap never legitimately crosses one — this prevents a plain
        # (marker-less) image from reaching forward and absorbing a *later*
        # element's marker (e.g. a heading whose non-conformant hook emitted
        # non-`<hN>` markup, leaving its HATTR marker unconsumed by the heading
        # pass). Hook wrappers (`</figure>`, `</span>`, `</a>`, `</picture>`, …)
        # are deliberately NOT excluded, so they still bind normally.
        IMG_HATTR_RE = /(<img\b(?:[^>"']|"[^"]*"|'[^']*')*?)(\s*\/?>)((?:(?!<img\b|<!--HATTR:|<\/(?:p|li|t[dh]|d[dt]|h[1-6])\b).)*?)<!--HATTR:([0-9a-f]+)-->/m

        def postprocess_attributes(html : String) : String
          return html unless html.includes?("<!--HATTR:")

          result = html.gsub(HEADING_TAG_FOR_HID_RE) do |match|
            tag = $1
            attrs = $2
            inner = $3

            if hattr_match = inner.match(HATTR_MARKER_RE)
              parsed = decode_and_parse_hattr(hattr_match[1])
              if parsed
                # The preprocess step glued the marker on with a leading
                # space (`… title <!--HATTR:…-->`); remove them together.
                # Dropping only the marker left a doubled space behind when
                # a heading render hook appends markup after `{{ text }}`.
                marker_with_space = " #{hattr_match[0]}"
                cleaned_inner = if inner.includes?(marker_with_space)
                                  inner.sub(marker_with_space, "")
                                else
                                  inner.sub(hattr_match[0], "")
                                end
                cleaned_inner = cleaned_inner.rstrip
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
            wrapper = $3
            parsed = decode_and_parse_hattr($4)
            if parsed
              "#{MarkdownAttributes.apply_to_img(img_open, parsed)}#{closer}#{wrapper}"
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
      end
    end
  end
end
