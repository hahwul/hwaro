require "crinja"
require "uri"

module Hwaro
  module Content
    module Processors
      module Filters
        module UrlFilters
          def self.register(env : Crinja)
            # Absolute URL filter
            env.filters["absolute_url"] = Crinja.filter do
              url = target.to_s
              base_url = env.resolve("base_url").to_s

              if url.starts_with?("http://") || url.starts_with?("https://")
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

              if url.starts_with?("/")
                # Extract path component from base_url (strip protocol + host)
                base_path = URI.parse(base_url).path.rstrip("/")
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
