require "html"
require "uri"

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

        # Matches a plain root-relative href/src value (e.g. href="/posts/").
        # `\/[^\/"]` excludes protocol-relative `//host` URLs; the alternation
        # also allows a bare `/` (the homepage link).
        ROOT_RELATIVE_ATTR_REGEX = /\b(href|src)="(\/(?:[^\/"][^"]*)?)"/

        # Resolve internal `@/` links in HTML to actual page URLs.
        #
        # - `html` — rendered HTML string
        # - `pages_by_path` — map from content path (e.g. "blog/post.md") to Page
        # - `source_path` — path of the page being rendered (for warning messages)
        # - `base_url` — site base_url, used to prepend the path component (e.g. "/noir")
        #   so links work when the site is served from a subpath. When empty or root,
        #   no prefix is added and behavior matches the previous output.
        def resolve(
          html : String,
          pages_by_path : Hash(String, Models::Page),
          source_path : String,
          base_url : String = "",
        ) : String
          return html unless html.includes?("@/")

          base_path = base_url.empty? ? "" : URI.parse(base_url).path.rstrip("/")

          html.gsub(INTERNAL_LINK_REGEX) do |match|
            content_path = $1
            anchor = $2?

            # Split off a query string so `@/path.md?x=y` resolves on the path
            # alone (pages_by_path keys never contain `?`), then re-append it.
            # partition leaves path_part == content_path / query == "" when
            # there's no `?`, preserving existing behavior.
            path_part, _, query = content_path.partition('?')

            if path_part.empty?
              Logger.warn "Empty internal link '@/' in '#{source_path}'"
              next match
            end

            if page = pages_by_path[path_part]?
              page_url = page.url.starts_with?("/") ? page.url : "/#{page.url}"
              url = HTML.escape("#{base_path}#{page_url}")
              url += "?#{HTML.escape(query)}" unless query.empty?
              if anchor && !anchor.empty?
                "href=\"#{url}##{HTML.escape(anchor)}\""
              else
                "href=\"#{url}\""
              end
            else
              Logger.warn "Internal link '@/#{content_path}' in '#{source_path}' could not be resolved: page not found."
              match
            end
          end
        end

        # Prefix plain root-relative links in rendered content (e.g. a scaffold
        # or author-written `[Posts](/posts/)` -> `<a href="/posts/">`) with the
        # base_url path component so they resolve under a subpath deployment
        # (GitHub/GitLab project pages served at `https://user.github.io/repo/`).
        #
        # This mirrors `Config#with_base_path` for content-body anchors that the
        # template layer never touches. Because `page.content` is reused by the
        # feed and search generators, fixing it here also keeps RSS
        # `<content:encoded>` and the search index subpath-correct.
        #
        # A complete no-op when `base_url` has no subpath (the common
        # domain-root deploy), so root-relative links are preserved there.
        # Protocol-relative (`//host`), absolute (`http(s)://`), anchor (`#`),
        # and already-prefixed links are left untouched.
        def prefix_root_relative_links(html : String, base_url : String) : String
          return html if base_url.empty?
          return html unless html.includes?("=\"/")

          base_path = URI.parse(base_url).path.rstrip("/")
          return html if base_path.empty?

          prefix_slash = "#{base_path}/"

          html.gsub(ROOT_RELATIVE_ATTR_REGEX) do |match|
            attr = $1
            value = $2
            # Leave values that already carry the base_path (e.g. links the
            # InternalLinkResolver pass above already resolved) untouched.
            if value == base_path || value.starts_with?(prefix_slash)
              match
            else
              "#{attr}=\"#{base_path}#{value}\""
            end
          end
        rescue URI::Error
          html
        end
      end
    end
  end
end
