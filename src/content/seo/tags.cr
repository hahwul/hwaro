require "html"
require "../../models/config"
require "../../models/page"

module Hwaro
  module Content
    module Seo
      module Tags
        extend self

        # Compute the canonical URL for a page (absolute URL with base_url).
        def canonical_url(page : Models::Page, config : Models::Config) : String
          page.permalink || "#{config.base_url_stripped}#{page.url.starts_with?("/") ? page.url : "/#{page.url}"}"
        end

        def canonical_tag(page : Models::Page, config : Models::Config) : String
          url = canonical_url(page, config)
          # Fast path: skip HTML.escape when URL has no escapable chars (common case for URLs)
          escaped = url.includes?('&') || url.includes?('"') || url.includes?('<') || url.includes?('>') ? HTML.escape(url) : url
          %(<link rel="canonical" href="#{escaped}">)
        end

        def hreflang_tags(page : Models::Page, config : Models::Config) : String
          return "" unless config.multilingual?
          return "" if page.translations.empty?

          base = config.base_url_stripped

          String.build(page.translations.size * 80) do |str|
            # Add current page
            current_url = page.permalink || "#{base}#{page.url.starts_with?("/") ? page.url : "/#{page.url}"}"
            lang_code = page.language || config.default_language
            str << %(<link rel="alternate" hreflang="#{HTML.escape(lang_code)}" href="#{HTML.escape(current_url)}">)

            # Add translations (already ordered by ordered_language_codes via link_translations!)
            page.translations.each do |t|
              next if t.is_current
              abs_url = t.url.starts_with?("http") ? t.url : "#{base}#{t.url.starts_with?("/") ? t.url : "/#{t.url}"}"
              str << '\n'
              str << %(<link rel="alternate" hreflang="#{HTML.escape(t.code)}" href="#{HTML.escape(abs_url)}">)
            end
          end
        end
      end
    end
  end
end
