require "json"
require "../../models/config"
require "../../models/page"

module Hwaro
  module Content
    module Seo
      module JsonLd
        extend self

        # Generate Article JSON-LD for a page
        def article(page : Models::Page, config : Models::Config) : String
          base = config.base_url.rstrip("/")
          url = page.permalink || "#{base}#{page.url.starts_with?("/") ? page.url : "/#{page.url}"}"

          date_published = page.date.try(&.to_s("%Y-%m-%dT%H:%M:%S%:z")) || ""
          updated_str = page.updated.try(&.to_s("%Y-%m-%dT%H:%M:%S%:z"))
          desc = page.description
          image_url = if image = page.image
                        image.starts_with?("http") ? image : "#{base}#{image.starts_with?("/") ? image : "/#{image}"}"
                      end
          author_name = page.authors.first?

          json = JSON.build do |j|
            j.object do
              j.field "@context", "https://schema.org"
              j.field "@type", "Article"
              j.field "headline", page.title
              j.field "url", url
              j.field "datePublished", date_published
              if us = updated_str
                j.field "dateModified", us
              end
              if d = desc
                j.field "description", d
              end
              if img = image_url
                j.field "image", img
              end
              if name = author_name
                j.field "author" do
                  j.object do
                    j.field "@type", "Person"
                    j.field "name", name
                  end
                end
              end
            end
          end

          %(<script type="application/ld+json">#{json}</script>)
        end

        # Generate BreadcrumbList JSON-LD from page ancestors
        def breadcrumb(page : Models::Page, config : Models::Config) : String
          base = config.base_url.rstrip("/")

          items = [] of Hash(String, String | Int32)

          # Home
          items << {
            "@type"    => "ListItem",
            "position" => 1,
            "name"     => config.title,
            "item"     => "#{base}/",
          }

          # Ancestors
          page.ancestors.each_with_index do |ancestor, idx|
            ancestor_url = "#{base}#{ancestor.url.starts_with?("/") ? ancestor.url : "/#{ancestor.url}"}"
            items << {
              "@type"    => "ListItem",
              "position" => idx + 2,
              "name"     => ancestor.title,
              "item"     => ancestor_url,
            }
          end

          # Current page (last item, no "item" URL per spec recommendation)
          items << {
            "@type"    => "ListItem",
            "position" => items.size + 1,
            "name"     => page.title,
          }

          json = JSON.build do |json|
            json.object do
              json.field "@context", "https://schema.org"
              json.field "@type", "BreadcrumbList"
              json.field "itemListElement" do
                json.array do
                  items.each do |item|
                    json.object do
                      item.each do |k, v|
                        json.field k, v
                      end
                    end
                  end
                end
              end
            end
          end

          %(<script type="application/ld+json">#{json}</script>)
        end

        # Generate both Article + BreadcrumbList JSON-LD
        def all_tags(page : Models::Page, config : Models::Config) : String
          parts = [] of String
          parts << article(page, config)
          parts << breadcrumb(page, config) unless page.ancestors.empty? && page.is_index
          parts.join("\n")
        end

      end
    end
  end
end
