require "html"

# Internal Link Resolver
#
# Resolves Zola-style internal links (`@/path.md`) in rendered HTML.
# After markd converts `[text](@/path.md)` to `<a href="@/path.md">`,
# this module scans the HTML for `href="@/..."` patterns and replaces
# them with the target page's calculated output URL.
#
# This post-processing approach catches links from both Markd and
# TableParser output in one pass, and avoids false positives in code
# blocks (where `@/` would be entity-encoded by markd).

module Hwaro
  module Content
    module Processors
      module InternalLinkResolver
        extend self

        # Matches href="@/path" and href="@/path#anchor"
        INTERNAL_LINK_REGEX = /href="@\/([^"#]*)(?:#([^"]*))?"/

        # Resolve internal `@/` links in HTML to actual page URLs.
        #
        # - `html` — rendered HTML string
        # - `pages_by_path` — map from content path (e.g. "blog/post.md") to Page
        # - `source_path` — path of the page being rendered (for warning messages)
        def resolve(html : String, pages_by_path : Hash(String, Models::Page), source_path : String) : String
          return html unless html.includes?("@/")

          html.gsub(INTERNAL_LINK_REGEX) do |match|
            content_path = $1
            anchor = $2?

            if content_path.empty?
              Logger.warn "  [WARN] Empty internal link '@/' in '#{source_path}'"
              next match
            end

            if page = pages_by_path[content_path]?
              url = HTML.escape(page.url)
              if anchor && !anchor.empty?
                "href=\"#{url}##{HTML.escape(anchor)}\""
              else
                "href=\"#{url}\""
              end
            else
              Logger.warn "  [WARN] Internal link '@/#{content_path}' in '#{source_path}' could not be resolved: page not found."
              match
            end
          end
        end
      end
    end
  end
end
