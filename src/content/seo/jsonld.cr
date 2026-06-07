require "json"
require "../../models/config"
require "../../models/page"

module Hwaro
  module Content
    module Seo
      module JsonLd
        extend self

        # Generate Article JSON-LD for a page
        def article(page : Models::Page, config : Models::Config, site : Models::Site? = nil) : String
          base = config.base_url_stripped
          url = page.permalink || "#{base}#{page.url.starts_with?("/") ? page.url : "/#{page.url}"}"

          date_published = page.date.try(&.to_s("%Y-%m-%dT%H:%M:%S%:z"))
          updated_str = page.updated.try(&.to_s("%Y-%m-%dT%H:%M:%S%:z"))
          desc = page.description
          image_url = if image = page.image
                        image.starts_with?("http") ? image : "#{base}#{image.starts_with?("/") ? image : "/#{image}"}"
                      end
          # Prefer the resolved display name from site.authors (data/authors
          # enrichment) so the schema.org author matches the visible author name
          # used on /authors/ pages, not the raw frontmatter id. Falls back to the
          # raw value when no data entry (or no site) is available.
          author_name = page.authors.first?
          if (raw_id = author_name) && (s = site)
            if author = s.authors[raw_id.strip.downcase]?
              author_raw = author.raw
              if author_raw.is_a?(Hash) && (name_val = author_raw["name"]?)
                author_name = name_val.to_s
              end
            end
          end

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

          json = JSON.build do |j|
            j.object do
              j.field "@context", "https://schema.org"
              j.field "@type", "BreadcrumbList"
              j.field "itemListElement" do
                j.array do
                  items.each do |item|
                    j.object do
                      item.each do |k, v|
                        j.field k, v
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
          %(<script type="application/ld+json">#{escape_for_script(json)}</script>)
        end

        # Escape HTML-significant characters as `\uXXXX` so JSON can never
        # break out of the surrounding `<script>` element. `<` etc. are
        # valid JSON escapes that decode back to the original characters in
        # any JSON parser, so the structured data stays intact. This mirrors
        # Go's `encoding/json` HTML escaping and defends against both
        # `</script>` injection and the "script data double escape" trap a
        # bare `<!--<script` would otherwise spring (gh: dogfooding find).
        private def escape_for_script(json : String) : String
          # U+2028/U+2029 are valid in JSON strings but are JS line terminators;
          # escaping them (as Go's encoding/json does) keeps the JSON-LD payload
          # parseable by stricter/older consumers embedding it in inline script.
          json.gsub('<', "\\u003c").gsub('>', "\\u003e").gsub('&', "\\u0026")
            .gsub('\u2028', "\\u2028").gsub('\u2029', "\\u2029")
        end

        # Coerce a `page.extra[key]` value to `Array(String)` regardless of whether
        # the parser produced `Array(String)` (all-strings case) or `Array(ExtraValue)`
        # (mixed case). Non-string elements are filtered out.
        private def extra_string_array(page : Models::Page, key : String) : Array(String)?
          case raw = page.extra[key]?
          when Array(String)
            raw
          when Array
            raw.compact_map { |v| v.as?(String) }
          end
        end

        # Read an array-of-tables `extra` value. A TOML `[[extra.faq]]` block (or
        # equivalent JSON/YAML array of objects) parses to Array(ExtraValue) whose
        # elements are Hash(String, ExtraValue); the flat-string helper above
        # discards those. Returns nil when the value isn't a non-empty hash array.
        private def extra_hash_array(page : Models::Page, key : String) : Array(Hash(String, Models::ExtraValue))?
          raw = page.extra[key]?
          return unless raw.is_a?(Array)
          out = raw.compact_map { |v| v.as?(Hash(String, Models::ExtraValue)) }
          out.empty? ? nil : out
        end

        private def extract_faq_items(page : Models::Page) : Array(NamedTuple(question: String, answer: String))
          items = [] of NamedTuple(question: String, answer: String)

          # Parse from page content: look for ## Q: ... / A: ... pattern
          # or from extra["faq"] if available as string pairs
          if faq_pairs = extra_string_array(page, "faq")
            # Pairs: ["Q1", "A1", "Q2", "A2"]
            faq_pairs.each_slice(2) do |pair|
              if pair.size == 2
                items << {question: pair[0], answer: pair[1]}
              end
            end
          end

          # Also check faq_questions / faq_answers parallel arrays
          if questions = extra_string_array(page, "faq_questions")
            if answers = extra_string_array(page, "faq_answers")
              questions.zip(answers).each do |q, a|
                items << {question: q, answer: a}
              end
            end
          end

          # Table-array form documented above: [[extra.faq]] with question/answer.
          if hash_items = extra_hash_array(page, "faq")
            hash_items.each do |h|
              q = h["question"]?.try(&.as?(String))
              a = h["answer"]?.try(&.as?(String))
              items << {question: q, answer: a} if q && a
            end
          end

          items
        end

        private def extract_howto_steps(page : Models::Page) : Array(NamedTuple(name: String, text: String))
          steps = [] of NamedTuple(name: String, text: String)

          if steps_pairs = extra_string_array(page, "howto_steps")
            # Pairs: ["Step Name", "Step Text", ...]
            steps_pairs.each_slice(2) do |pair|
              if pair.size == 2
                steps << {name: pair[0], text: pair[1]}
              end
            end
          end

          # Also check howto_names / howto_texts parallel arrays
          if names = extra_string_array(page, "howto_names")
            if texts = extra_string_array(page, "howto_texts")
              names.zip(texts).each do |n, t|
                steps << {name: n, text: t}
              end
            end
          end

          # Table-array form documented above: [[extra.howto_steps]] name/text.
          if hash_steps = extra_hash_array(page, "howto_steps")
            hash_steps.each do |h|
              n = h["name"]?.try(&.as?(String))
              t = h["text"]?.try(&.as?(String))
              steps << {name: n, text: t} if n && t
            end
          end

          steps
        end
      end
    end
  end
end
