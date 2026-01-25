module Hwaro
  module Services
    module Defaults
      class TemplateSamples
        def self.header : String
          <<-HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta name="description" content="{{ site_description }}">
            <title>{{ page_title }} - {{ site_title }}</title>
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 2rem; color: #333; }
              header { margin-bottom: 2rem; border-bottom: 1px solid #eaeaea; padding-bottom: 1rem; }
              h1, h2, h3 { line-height: 1.2; }
              nav a { margin-right: 1rem; text-decoration: none; color: #0070f3; }
              nav a:hover { text-decoration: underline; }
              footer { margin-top: 3rem; border-top: 1px solid #eaeaea; padding-top: 1rem; color: #666; font-size: 0.9rem; text-align: center; }
              code { background: #f4f4f4; padding: 0.2rem 0.4rem; border-radius: 3px; font-size: 0.9em; }
              ul.section-list { list-style: none; padding: 0; }
              ul.section-list li { margin-bottom: 0.5rem; }
              nav.pagination { margin: 1.5rem 0; }
              nav.pagination .pagination-list { list-style: none; padding: 0; margin: 0; display: flex; gap: 0.5rem; flex-wrap: wrap; align-items: center; }
              nav.pagination a { color: #0070f3; text-decoration: none; padding: 0.25rem 0.5rem; border: 1px solid #eaeaea; border-radius: 6px; }
              nav.pagination a:hover { text-decoration: underline; }
              .pagination-current span { padding: 0.25rem 0.5rem; border: 1px solid #0070f3; border-radius: 6px; background: #eef6ff; }
              .pagination-disabled span { padding: 0.25rem 0.5rem; border: 1px solid #eaeaea; border-radius: 6px; color: #999; }
            </style>
          </head>
          <body data-section="{{ page_section }}">
            <header>
              <h3>{{ site_title }}</h3>
              <nav>
                <a href="{{ base_url }}/">Home</a>
                <a href="{{ base_url }}/about/">About</a>
              </nav>
            </header>

          HTML
        end

        def self.footer : String
          <<-HTML
            <footer>
              <p>Powered by Hwaro</p>
            </footer>
          </body>
          </html>
          HTML
        end

        def self.page : String
          <<-HTML
          {% include "header.html" %}
          <main>
            {{ content }}
          </main>
          {% include "footer.html" %}
          HTML
        end

        def self.section : String
          <<-HTML
          {% include "header.html" %}
          <main>
            <h1>{{ page_title }}</h1>
            {{ content }}

          <ul class="section-list">
            {{ section_list }}
          </ul>
          {{ pagination }}

          </main>
          {% include "footer.html" %}
          HTML
        end

        def self.not_found : String
          <<-HTML
          {% include "header.html" %}
          <main>
            <h1>404 Not Found</h1>
            <p>The page you are looking for does not exist.</p>
            <p><a href="{{ base_url }}/">Return to Home</a></p>
          </main>
          {% include "footer.html" %}
          HTML
        end

        def self.alert : String
          <<-HTML
          <div class="alert" style="padding: 1rem; border: 1px solid #ddd; background-color: #f9f9f9; border-left: 5px solid #0070f3; margin: 1rem 0;">
            <strong>{{ type | upper }}:</strong> {{ message }}
          </div>
          HTML
        end

        def self.taxonomy : String
          <<-HTML
          {% include "header.html" %}
          <main>
            <h1>{{ page_title }}</h1>
            <p>Browse all terms in this taxonomy:</p>
            {{ content }}
          </main>
          {% include "footer.html" %}
          HTML
        end

        def self.taxonomy_term : String
          <<-HTML
          {% include "header.html" %}
          <main>
            <h1>{{ page_title }}</h1>
            <p>Posts tagged with this term:</p>
            {{ content }}
          </main>
          {% include "footer.html" %}
          HTML
        end
      end
    end
  end
end
