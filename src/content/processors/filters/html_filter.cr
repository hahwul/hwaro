require "crinja"
require "markd"

module Hwaro
  module Content
    module Processors
      module Filters
        module HtmlFilters
          def self.register(env : Crinja)
            # Strip HTML tags filter
            env.filters["strip_html"] = Crinja.filter do
              target.to_s.gsub(/<[^>]*>/, "")
            end

            # Markdownify filter
            env.filters["markdownify"] = Crinja.filter do
              Markd.to_html(target.to_s)
            end

            # XML escape filter
            env.filters["xml_escape"] = Crinja.filter do
              target.to_s
                .gsub("&", "&amp;")
                .gsub("<", "&lt;")
                .gsub(">", "&gt;")
                .gsub("\"", "&quot;")
                .gsub("'", "&apos;")
            end

            # Safe filter
            env.filters["safe"] = Crinja.filter do
              Crinja::Value.new(Crinja::SafeString.new(target.to_s))
            end
          end
        end
      end
    end
  end
end
