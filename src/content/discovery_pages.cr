require "../models/page"

# Shared page-list shaping for the public discovery surfaces (sitemap,
# search index): URL dedupe and config-driven path exclusion.

module Hwaro
  module Content
    module DiscoveryPages
      extend self

      # Deduplicate by URL, keeping the page the build actually wrote: the
      # render phase resolves an output-URL collision in source-path sort
      # order, first claim wins (render.cr#compute_output_url_winners), so
      # the winner is the page whose `path` sorts FIRST. Original list
      # order is preserved.
      def dedupe_by_url(pages : Array(Models::Page)) : Array(Models::Page)
        winners = {} of String => Models::Page
        pages.each do |p|
          if prev = winners[p.url]?
            winners[p.url] = p if p.path < prev.path
          else
            winners[p.url] = p
          end
        end
        pages.select { |p| winners[p.url].same?(p) }
      end

      # Drop pages whose URL equals an excluded path or lives under an
      # excluded prefix. Exclude entries may omit the leading slash.
      def reject_excluded!(pages : Array(Models::Page), exclude : Array(String)) : Array(Models::Page)
        return pages if exclude.empty?

        excluded_paths = exclude.map do |path|
          path.starts_with?('/') ? path : "/#{path}"
        end

        pages.reject! do |page|
          page_url = page.url.starts_with?('/') ? page.url : "/#{page.url}"
          excluded_paths.any? { |excluded| page_url == excluded || page_url.starts_with?(excluded.ends_with?("/") ? excluded : excluded + "/") }
        end
        pages
      end
    end
  end
end
