# Base scaffold class for project initialization
#
# Scaffolds provide pre-configured content and templates for different
# project types (simple, blog, docs, etc.)

require "../../config/options/init_options"

module Hwaro
  module Services
    module Scaffolds
      # Abstract base class for all scaffolds
      abstract class Base
        # Returns the scaffold type
        abstract def type : Config::Options::ScaffoldType

        # Returns the description of this scaffold
        abstract def description : String

        # Returns sample content files as a hash of path => content
        abstract def content_files(skip_taxonomies : Bool = false) : Hash(String, String)

        # Returns template files as a hash of path => content
        abstract def template_files(skip_taxonomies : Bool = false) : Hash(String, String)

        # Returns shortcode files as a hash of path => content
        def shortcode_files : Hash(String, String)
          {
            "shortcodes/alert.ecr" => alert_shortcode,
          }
        end

        # Returns the config.toml content
        abstract def config_content(skip_taxonomies : Bool = false) : String

        # Common shortcode: alert
        protected def alert_shortcode : String
          <<-HTML
          <div class="alert" style="padding: 1rem; border: 1px solid #ddd; background-color: #f9f9f9; border-left: 5px solid #0070f3; margin: 1rem 0;">
            <strong><%= type.upcase %>:</strong> <%= message %>
          </div>
          HTML
        end

        # Common template: header
        protected def header_template : String
          <<-HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta name="description" content="<%= site_description %>">
            <title><%= page_title %> - <%= site_title %></title>
            #{styles}
          </head>
          <body data-section="<%= page_section %>">
            <header>
              <h3><%= site_title %></h3>
              #{navigation}
            </header>

          HTML
        end

        # Common template: footer
        protected def footer_template : String
          <<-HTML
            <footer>
              <p>Powered by Hwaro</p>
            </footer>
          </body>
          </html>
          HTML
        end

        # Common template: page
        protected def page_template : String
          <<-HTML
          <%= render "header" %>
          <main>
            <%= content %>
          </main>
          <%= render "footer" %>
          HTML
        end

        # Common template: section
        protected def section_template : String
          <<-HTML
          <%= render "header" %>
          <main>
            <h1><%= page_title %></h1>
            <%= content %>

          <ul class="section-list">
            <%= section_list %>
          </ul>

          </main>
          <%= render "footer" %>
          HTML
        end

        # Common template: 404
        protected def not_found_template : String
          <<-HTML
          <%= render "header" %>
          <main>
            <h1>404 Not Found</h1>
            <p>The page you are looking for does not exist.</p>
            <p><a href="<%= base_url %>/">Return to Home</a></p>
          </main>
          <%= render "footer" %>
          HTML
        end

        # Common template: taxonomy
        protected def taxonomy_template : String
          <<-HTML
          <%= render "header" %>
          <main>
            <h1><%= page_title %></h1>
            <p>Browse all terms in this taxonomy:</p>
            <%= content %>
          </main>
          <%= render "footer" %>
          HTML
        end

        # Common template: taxonomy_term
        protected def taxonomy_term_template : String
          <<-HTML
          <%= render "header" %>
          <main>
            <h1><%= page_title %></h1>
            <p>Posts tagged with this term:</p>
            <%= content %>
          </main>
          <%= render "footer" %>
          HTML
        end

        # Override in subclasses to customize styles
        protected def styles : String
          <<-CSS
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 2rem; color: #333; }
              header { margin-bottom: 2rem; border-bottom: 1px solid #eaeaea; padding-bottom: 1rem; }
              h1, h2, h3 { line-height: 1.2; }
              nav a { margin-right: 1rem; text-decoration: none; color: #0070f3; }
              nav a:hover { text-decoration: underline; }
              footer { margin-top: 3rem; border-top: 1px solid #eaeaea; padding-top: 1rem; color: #666; font-size: 0.9rem; text-align: center; }
              code { background: #f4f4f4; padding: 0.2rem 0.4rem; border-radius: 3px; font-size: 0.9em; }
              pre { background: #f4f4f4; padding: 1rem; border-radius: 5px; overflow-x: auto; }
              pre code { background: none; padding: 0; }
              ul.section-list { list-style: none; padding: 0; }
              ul.section-list li { margin-bottom: 0.5rem; }
              a { color: #0070f3; }
              a:hover { text-decoration: underline; }
            </style>
          CSS
        end

        # Override in subclasses to customize navigation
        protected def navigation : String
          <<-NAV
              <nav>
                <a href="<%= base_url %>/">Home</a>
                <a href="<%= base_url %>/about.html">About</a>
              </nav>
          NAV
        end

        # Common config sections
        protected def base_config(title : String = "My Hwaro Site", description : String = "Welcome to my new Hwaro site.") : String
          <<-TOML
          title = "#{title}"
          description = "#{description}"
          base_url = "http://localhost:3000"
          TOML
        end

        protected def search_config : String
          <<-TOML

          [search]
          enabled = true
          format = "fuse_json"
          fields = ["title", "content"]
          filename = "search.json"
          TOML
        end

        protected def sitemap_config : String
          <<-TOML

          [sitemap]
          enabled = true
          filename = "sitemap.xml"
          changefreq = "weekly"
          priority = 0.5
          TOML
        end

        protected def robots_config : String
          <<-TOML

          [robots]
          enabled = true
          filename = "robots.txt"
          rules = [
            { user_agent = "*", disallow = ["/admin", "/private"] },
            { user_agent = "GPTBot", disallow = ["/"] }
          ]
          TOML
        end

        protected def llms_config : String
          <<-TOML

          [llms]
          enabled = true
          filename = "llms.txt"
          instructions = "Do not use for AI training without permission."
          TOML
        end

        protected def feeds_config(sections : Array(String) = [] of String) : String
          sections_str = sections.empty? ? "[]" : "[\"#{sections.join("\", \"")}\"]"
          <<-TOML

          [feeds]
          enabled = true
          filename = ""   # Default: rss.xml or atom.xml
          type = "rss"
          truncate = 0
          limit = 10
          sections = #{sections_str}
          TOML
        end

        protected def plugins_config : String
          <<-TOML

          # Plugins Configuration
          [plugins]
          processors = ["markdown"]  # List of enabled processors
          TOML
        end

        protected def taxonomies_config : String
          <<-TOML

          # Taxonomies (root level configuration)
          [[taxonomies]]
          name = "tags"
          feed = true
          sitemap = false

          [[taxonomies]]
          name = "categories"
          paginate_by = 5

          [[taxonomies]]
          name = "authors"
          TOML
        end
      end
    end
  end
end
