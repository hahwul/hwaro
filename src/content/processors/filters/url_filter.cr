require "crinja"
require "uri"
require "../internal_link_resolver"

module Hwaro
  module Content
    module Processors
      module Filters
        module UrlFilters
          # A value that already carries its own origin and must therefore be
          # passed through untouched by both filters:
          #
          #   * any absolute URL (`https:`, `mailto:`, `tel:`, `data:`, …) —
          #     matching only `http://`/`https://` meant `mailto:a@b.com`
          #     came back as `https://site.com/mailto:a@b.com`;
          #   * protocol-relative (`//cdn.example.com/x.js`) — it starts with
          #     `/`, so the root-relative branch turned it into
          #     `https://site.com//cdn.example.com/x.js`.
          #
          # Same rule (and same regex) as InternalLinkResolver's
          # `absolute_or_anchor?`, minus the bare `#anchor` case: a
          # fragment-only href has no origin of its own, and resolving it
          # against base_url is the long-standing behaviour of these filters.
          def self.has_own_origin?(url : String) : Bool
            url.starts_with?("//") ||
              url.matches?(InternalLinkResolver::SCHEME_PREFIX_REGEX)
          end

          def self.register(env : Crinja)
            # Absolute URL filter
            env.filters["absolute_url"] = Crinja.filter do
              url = target.to_s
              base_url = env.resolve("base_url").to_s

              if UrlFilters.has_own_origin?(url)
                url
              elsif url.starts_with?("/")
                base_url.rstrip("/") + url
              else
                base_url.rstrip("/") + "/" + url
              end
            end

            # Relative URL filter — returns path-only URL (no protocol/host)
            env.filters["relative_url"] = Crinja.filter do
              url = target.to_s
              base_url = env.resolve("base_url").to_s

              if !UrlFilters.has_own_origin?(url) && url.starts_with?("/")
                # Extract path component from base_url (strip protocol + host).
                # A malformed base_url must not abort the whole build — fall
                # back to no prefix, which is what an empty base_url yields.
                base_path = begin
                  URI.parse(base_url).path.rstrip("/")
                rescue URI::Error
                  ""
                end
                base_path + url
              else
                url
              end
            end
          end
        end
      end
    end
  end
end
