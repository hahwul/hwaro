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
          base = config.base_url_stripped
          url = page.permalink || "#{base}#{page.url.starts_with?("/") ? page.url : "/#{page.url}"}"

          date_published = page.date.try(&.to_s("%Y-%m-%dT%H:%M:%S%:z"))
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
              if dp = date_published
                j.field "datePublished", dp
              end
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

          wrap_script(json)
        end

        # Generate BreadcrumbList JSON-LD from page ancestors
        def breadcrumb(page : Models::Page, config : Models::Config) : String
          base = config.base_url_stripped

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

          wrap_script(json)
        end

        # Generate FAQPage JSON-LD from page extra field "faq"
        # Front matter format:
        #   schema_type = "FAQ"
        #   [[extra.faq]]
        #   question = "What is Hwaro?"
        #   answer = "A static site generator."
        def faq_page(page : Models::Page, config : Models::Config) : String
          faq_items = extract_faq_items(page)
          return "" if faq_items.empty?

          json = JSON.build do |j|
            j.object do
              j.field "@context", "https://schema.org"
              j.field "@type", "FAQPage"
              j.field "mainEntity" do
                j.array do
                  faq_items.each do |item|
                    j.object do
                      j.field "@type", "Question"
                      j.field "name", item[:question]
                      j.field "acceptedAnswer" do
                        j.object do
                          j.field "@type", "Answer"
                          j.field "text", item[:answer]
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          wrap_script(json)
        end

        # Generate HowTo JSON-LD from page extra field "howto_steps"
        # Front matter format:
        #   schema_type = "HowTo"
        #   [[extra.howto_steps]]
        #   name = "Step 1"
        #   text = "Do this first."
        def how_to(page : Models::Page, config : Models::Config) : String
          steps = extract_howto_steps(page)
          return "" if steps.empty?

          base = config.base_url_stripped
          url = "#{base}#{page.url.starts_with?("/") ? page.url : "/#{page.url}"}"

          json = JSON.build do |j|
            j.object do
              j.field "@context", "https://schema.org"
              j.field "@type", "HowTo"
              j.field "name", page.title
              j.field "url", url
              if desc = page.description
                j.field "description", desc
              end
              j.field "step" do
                j.array do
                  steps.each_with_index do |step, idx|
                    j.object do
                      j.field "@type", "HowToStep"
                      j.field "position", idx + 1
                      j.field "name", step[:name]
                      j.field "text", step[:text]
                      if step_url = step[:url]?
                        j.field "url", step_url
                      end
                    end
                  end
                end
              end
            end
          end

          wrap_script(json)
        end

        # Generate WebSite JSON-LD with optional SearchAction (sitelinks search box)
        def website(config : Models::Config) : String
          base = config.base_url_stripped
          return "" if base.empty?

          has_search = config.search.enabled

          json = JSON.build do |j|
            j.object do
              j.field "@context", "https://schema.org"
              j.field "@type", "WebSite"
              j.field "name", config.title
              j.field "url", "#{base}/"
              unless config.description.empty?
                j.field "description", config.description
              end
              if has_search
                j.field "potentialAction" do
                  j.object do
                    j.field "@type", "SearchAction"
                    j.field "target" do
                      j.object do
                        j.field "@type", "EntryPoint"
                        j.field "urlTemplate", "#{base}/?q={search_term_string}"
                      end
                    end
                    j.field "query-input", "required name=search_term_string"
                  end
                end
              end
            end
          end

          wrap_script(json)
        end

        # Generate Person JSON-LD from author info
        def person(name : String, config : Models::Config, url : String? = nil, image : String? = nil) : String
          base = config.base_url_stripped

          json = JSON.build do |j|
            j.object do
              j.field "@context", "https://schema.org"
              j.field "@type", "Person"
              j.field "name", name
              if u = url
                j.field "url", u.starts_with?("http") ? u : "#{base}#{u.starts_with?("/") ? u : "/#{u}"}"
              end
              if img = image
                j.field "image", img.starts_with?("http") ? img : "#{base}#{img.starts_with?("/") ? img : "/#{img}"}"
              end
            end
          end

          wrap_script(json)
        end

        # Generate Organization JSON-LD from site config
        def organization(config : Models::Config, logo : String? = nil) : String
          base = config.base_url_stripped
          return "" if base.empty?

          json = JSON.build do |j|
            j.object do
              j.field "@context", "https://schema.org"
              j.field "@type", "Organization"
              j.field "name", config.title
              j.field "url", "#{base}/"
              unless config.description.empty?
                j.field "description", config.description
              end
              if logo_url = logo
                j.field "logo", logo_url.starts_with?("http") ? logo_url : "#{base}#{logo_url.starts_with?("/") ? logo_url : "/#{logo_url}"}"
              end
            end
          end

          wrap_script(json)
        end

        # Auto-detect and generate schema based on page.extra["schema_type"]
        def for_page(page : Models::Page, config : Models::Config) : String
          schema_type = page.extra["schema_type"]?.try(&.as?(String)) || ""

          case schema_type.downcase
          when "faq", "faqpage"
            faq_page(page, config)
          when "howto", "how-to"
            how_to(page, config)
          else
            "" # No extra schema; Article is always generated separately
          end
        end

        # Generate both Article + BreadcrumbList + extended type JSON-LD
        def all_tags(page : Models::Page, config : Models::Config) : String
          parts = [] of String
          parts << article(page, config)
          parts << breadcrumb(page, config) unless page.ancestors.empty? && page.is_index

          extra_schema = for_page(page, config)
          parts << extra_schema unless extra_schema.empty?

          parts.join("\n")
        end

        private def wrap_script(json : String) : String
          %(<script type="application/ld+json">#{json.gsub("</", "<\\/")}</script>)
        end

        private def extract_faq_items(page : Models::Page) : Array(NamedTuple(question: String, answer: String))
          items = [] of NamedTuple(question: String, answer: String)

          # Parse from page content: look for ## Q: ... / A: ... pattern
          # or from extra["faq"] if available as string pairs
          if faq_raw = page.extra["faq"]?
            case faq_raw
            when Array(String)
              # Pairs: ["Q1", "A1", "Q2", "A2"]
              faq_raw.each_slice(2) do |pair|
                if pair.size == 2
                  items << {question: pair[0], answer: pair[1]}
                end
              end
            end
          end

          # Also check faq_questions / faq_answers parallel arrays
          if questions = page.extra["faq_questions"]?.try(&.as?(Array(String)))
            if answers = page.extra["faq_answers"]?.try(&.as?(Array(String)))
              questions.zip(answers).each do |q, a|
                items << {question: q, answer: a}
              end
            end
          end

          items
        end

        private def extract_howto_steps(page : Models::Page) : Array(NamedTuple(name: String, text: String))
          steps = [] of NamedTuple(name: String, text: String)

          if steps_raw = page.extra["howto_steps"]?
            case steps_raw
            when Array(String)
              # Pairs: ["Step Name", "Step Text", ...]
              steps_raw.each_slice(2) do |pair|
                if pair.size == 2
                  steps << {name: pair[0], text: pair[1]}
                end
              end
            end
          end

          # Also check howto_names / howto_texts parallel arrays
          if names = page.extra["howto_names"]?.try(&.as?(Array(String)))
            if texts = page.extra["howto_texts"]?.try(&.as?(Array(String)))
              names.zip(texts).each do |n, t|
                steps << {name: n, text: t}
              end
            end
          end

          steps
        end
      end
    end
  end
end
