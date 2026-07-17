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

        # Matches any href/src attribute value (relative or absolute).
        ANY_LINK_ATTR_REGEX = /\b(href|src)="([^"]*)"/

        # A URI scheme prefix (e.g. `https:`, `mailto:`, `tel:`, `data:`).
        SCHEME_PREFIX_REGEX = /\A[a-zA-Z][a-zA-Z0-9+.\-]*:/

        # Resolve internal `@/` links in HTML to actual page URLs.
        #
        # - `html` — rendered HTML string
        # - `pages_by_path` — map from content path (e.g. "blog/post.md") to Page
        # - `source_path` — path of the page being rendered (for warning messages)
        # - `base_url` — site base_url, used to prepend the path component (e.g. "/noir")
        #   so links work when the site is served from a subpath. When empty or root,
        #   no prefix is added and behavior matches the previous output.
        # - `misses` — optional accumulator for unresolved links. Each entry is
        #   `{target, reason}` with reason "page not found" or "empty link".
        #   Callers running under `[links] broken_internal = "error"` collect
        #   them to fail the build after the render fan-out; warnings are
        #   still logged either way. `nil` keeps warn-only behavior.
        def resolve(
          html : String,
          pages_by_path : Hash(String, Models::Page),
          source_path : String,
          base_url : String = "",
          misses : Array({String, String})? = nil,
        ) : String
          return html unless html.includes?("@/")

          # Only treat base_url as a subpath prefix when it is a real absolute
          # URL (has a scheme). A host-only or malformed value like
          # "example.com" parses with the whole string as `.path`, which would
          # otherwise be prepended to every link ("example.com/a/"). Match the
          # defensive URI::Error rescue used by the sibling absolutize methods.
          base_path = if base_url.empty?
                        ""
                      else
                        begin
                          uri = URI.parse(base_url)
                          uri.scheme ? uri.path.rstrip("/") : ""
                        rescue URI::Error
                          ""
                        end
                      end

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
              misses << {content_path, "empty link"} if misses
              next match
            end

            if page = pages_by_path[path_part]?
              page_url = page.url.starts_with?("/") ? page.url : "/#{page.url}"
              url = HTML.escape("#{base_path}#{page_url}")
              # `query`/`anchor` are usually captured out of already-rendered
              # HTML, where Markd has escaped `&` to `&amp;` — blindly
              # re-escaping produced `&amp;amp;`, a literal `&amp;` in the
              # link target. Collapse ONLY `&amp;` before escaping (not a full
              # HTML.unescape: that decodes semicolon-less legacy entities, so
              # a raw query like `?a=1&copy=2` would corrupt to `©=2`). One
              # escaping level results for both rendered and raw `&` input.
              url += "?#{HTML.escape(query.gsub("&amp;", "&"))}" unless query.empty?
              if anchor && !anchor.empty?
                "href=\"#{url}##{HTML.escape(anchor.gsub("&amp;", "&"))}\""
              else
                "href=\"#{url}\""
              end
            else
              Logger.warn "Internal link '@/#{content_path}' in '#{source_path}' could not be resolved: page not found."
              misses << {content_path, "page not found"} if misses
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

        # Make every relative href/src in `html` absolute against `page_url`
        # (an absolute URL like "https://host/blog/post/").
        #
        # Feed bodies (RSS <content:encoded>, Atom <content>) are consumed out
        # of the page's URL context, so document-relative ("../x/") and
        # root-relative ("/img.svg") links must be absolutized — otherwise a
        # reader resolves them against the feed/reader URL and they break.
        # Absolute URLs, protocol-relative (`//host`), scheme links
        # (`mailto:`/`tel:`/`data:`), and pure in-page anchors (`#x`) are left
        # untouched. A no-op when `page_url` is not an absolute URL (no host
        # to resolve against — e.g. an empty base_url deploy).
        def absolutize_links(html : String, page_url : String) : String
          return html if page_url.empty?
          return html unless html.includes?("href=\"") || html.includes?("src=\"")

          base = URI.parse(page_url)
          return html if base.host.nil?

          html.gsub(ANY_LINK_ATTR_REGEX) do |match|
            attr = $1
            value = $2
            if value.empty? || absolute_or_anchor?(value)
              match
            else
              begin
                # `value` came from already-rendered HTML, so its entities
                # (e.g. `&amp;` in a query) are escaped; URI#resolve preserves
                # them literally, so re-escaping here would double-encode.
                "#{attr}=\"#{base.resolve(value)}\""
              rescue URI::Error
                match
              end
            end
          end
        rescue URI::Error
          html
        end

        # True for href/src values that must NOT be resolved against the page
        # URL: absolute URLs (scheme:), protocol-relative (//host), and pure
        # in-page anchors (#section).
        private def absolute_or_anchor?(value : String) : Bool
          value.starts_with?('#') ||
            value.starts_with?("//") ||
            value.matches?(SCHEME_PREFIX_REGEX)
        end
      end
    end
  end
end
