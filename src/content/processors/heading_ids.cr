# Heading id assignment — the dedup/slugify core shared by
# `Markdown#post_process_html`'s TOC pass (the stock, no-hooks path) and
# `HookedRenderer#heading` (the render-hooks path, see `render_hooks.cr`).
#
# Both callers need the SAME algorithm so a heading rendered through the
# `render-heading` hook gets exactly the id `post_process_html` would have
# assigned it — that's what lets the two paths converge on byte-identical
# final HTML (see the render-hooks functional/unit specs).

require "html"
require "../../utils/text_utils"
require "../../utils/logger"

module Hwaro
  module Content
    module Processors
      module HeadingIds
        extend self

        # Assigns a unique id for one heading, mutating `used_ids`/
        # `id_counters` (shared, document-scoped state threaded across every
        # heading of one page) so later calls see this id as taken.
        #
        # `title_text` is the heading's plain-text title — tags stripped,
        # HTML entities still escaped (as `post_process_html` extracts it
        # from the rendered inner HTML). `existing_id` is the heading's own
        # `id="..."` attribute when it already has one (a custom `{#id}`,
        # or — on the hook path — an id a hook template already emitted);
        # when present it's used as-is instead of slugifying the title.
        #
        # Dedup: a collision appends `-1`, `-2`, ... via `id_counters`
        # (O(1) amortized instead of re-scanning `used_ids` for a free
        # suffix).
        def assign(title_text : String, existing_id : String?, used_ids : Set(String), id_counters : Hash(String, Int32)) : String
          # The heading text reaches us entity-escaped (`&` → `&amp;` by
          # Markd); unescape before slugifying so "Tom & Jerry" gets the id
          # "tom-jerry", not "tom-amp-jerry".
          slug = Utils::TextUtils.slugify(HTML.unescape(title_text))
          id = existing_id || (slug.empty? ? "heading" : slug)

          if used_ids.includes?(id)
            base_id = id
            id_counters[base_id] += 1
            id = "#{base_id}-#{id_counters[base_id]}"
            # Handle the rare case where the suffixed id also exists
            while used_ids.includes?(id)
              id_counters[base_id] += 1
              id = "#{base_id}-#{id_counters[base_id]}"
            end
            # Renaming an auto-generated slug is routine (repeated section
            # titles), but renaming an AUTHOR-WRITTEN `{#id}` silently moves
            # the anchor the author explicitly asked for — warn, like menus
            # already do for duplicate identifiers. `used_ids` is page-scoped,
            # so this only fires for a duplicate within one page.
            if existing_id
              Logger.warn "Duplicate explicit heading id '##{base_id}' — this heading was renamed to '##{id}'; links to '##{base_id}' resolve to the first occurrence."
            end
          end
          used_ids << id

          id
        end
      end
    end
  end
end
