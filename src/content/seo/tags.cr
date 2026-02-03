require "../../models/config"
require "../../models/page"

module Hwaro
  module Content
    module Seo
      module Tags
        extend self

        def canonical_tag(page : Models::Page, config : Models::Config) : String
          # Use permalink if available, otherwise construct from base_url + url
          url = page.permalink || "#{config.base_url.rstrip("/")}#{page.url.starts_with?("/") ? page.url : "/#{page.url}"}"
          %(<link rel="canonical" href="#{url}">)
        end

        def hreflang_tags(page : Models::Page, config : Models::Config) : String
          return "" unless config.multilingual?
          return "" if page.translations.empty?

          tags = [] of String

          # Add current page
          current_url = page.permalink || "#{config.base_url.rstrip("/")}#{page.url.starts_with?("/") ? page.url : "/#{page.url}"}"
          lang_code = page.language || config.default_language
          tags << %(<link rel="alternate" hreflang="#{lang_code}" href="#{current_url}">)

          # Add translations
          page.translations.each do |t|
            next if t.is_current

            # TranslationLink url is relative, so we need to make it absolute
            abs_url = t.url.starts_with?("http") ? t.url : "#{config.base_url.rstrip("/")}#{t.url.starts_with?("/") ? t.url : "/#{t.url}"}"
            tags << %(<link rel="alternate" hreflang="#{t.code}" href="#{abs_url}">)
          end

          # Sort tags to ensure deterministic output
          tags.sort.join("\n")
        end
      end
    end
  end
end
