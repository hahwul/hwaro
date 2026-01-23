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
            <meta name="description" content="<%= page_description %>">
            <title><%= page_title %> - <%= site_title %></title>
            <%= og_all_tags %>
            #{styles}
            <%= highlight_css %>
            <%= auto_includes_css %>
          </head>
          <body data-section="<%= page_section %>">
            <div class="site-wrapper">
              <header class="site-header">
                <a href="<%= base_url %>/" class="site-logo"><%= site_title %></a>
                #{navigation}
              </header>

          HTML
        end

        # Common template: footer
        protected def footer_template : String
          <<-HTML
              <footer class="site-footer">
                <p>Powered by Hwaro</p>
              </footer>
            </div>
            <%= highlight_js %>
            <%= auto_includes_js %>
          </body>
          </html>
          HTML
        end

        # Common template: page
        protected def page_template : String
          <<-HTML
          <%= render "header" %>
            <main class="site-main">
              <%= content %>
            </main>
          <%= render "footer" %>
          HTML
        end

        # Common template: section
        protected def section_template : String
          <<-HTML
          <%= render "header" %>
            <main class="site-main">
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
            <main class="site-main">
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
            <main class="site-main">
              <h1><%= page_title %></h1>
              <p class="taxonomy-desc">Browse all terms in this taxonomy:</p>
              <%= content %>
            </main>
          <%= render "footer" %>
          HTML
        end

        # Common template: taxonomy_term
        protected def taxonomy_term_template : String
          <<-HTML
          <%= render "header" %>
            <main class="site-main">
              <h1><%= page_title %></h1>
              <p class="taxonomy-desc">Posts tagged with this term:</p>
              <%= content %>
            </main>
          <%= render "footer" %>
          HTML
        end

        # Override in subclasses to customize styles
        protected def styles : String
          <<-CSS
            <style>
              :root {
                --primary: #0070f3;
                --text: #24292f;
                --text-muted: #57606a;
                --border: #d0d7de;
                --bg: #ffffff;
                --bg-subtle: #f6f8fa;
              }
              *, *::before, *::after { box-sizing: border-box; }
              body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; line-height: 1.6; margin: 0; color: var(--text); background: var(--bg); }

              /* Layout */
              .site-wrapper { max-width: 720px; margin: 0 auto; padding: 0 1.5rem; }
              .site-header { display: flex; align-items: center; justify-content: space-between; padding: 1.25rem 0; border-bottom: 1px solid var(--border); margin-bottom: 2rem; }
              .site-logo { font-weight: 600; font-size: 1.1rem; color: var(--text); text-decoration: none; }
              .site-logo:hover { color: var(--primary); }
              .site-header nav { display: flex; gap: 1.25rem; }
              .site-header nav a { color: var(--text-muted); text-decoration: none; font-size: 0.9rem; }
              .site-header nav a:hover { color: var(--primary); }
              .site-main { min-height: calc(100vh - 200px); }
              .site-footer { margin-top: 3rem; padding: 1.5rem 0; border-top: 1px solid var(--border); color: var(--text-muted); font-size: 0.85rem; text-align: center; }

              /* Typography */
              h1, h2, h3 { line-height: 1.3; margin-top: 1.5em; margin-bottom: 0.5em; font-weight: 600; }
              h1 { font-size: 1.75rem; margin-top: 0; }
              h2 { font-size: 1.35rem; }
              h3 { font-size: 1.1rem; }
              p { margin: 1em 0; }
              a { color: var(--primary); text-decoration: none; }
              a:hover { text-decoration: underline; }
              code { background: var(--bg-subtle); padding: 0.15rem 0.4rem; border-radius: 4px; font-size: 0.85em; font-family: ui-monospace, "SFMono-Regular", Consolas, monospace; }
              pre { background: var(--bg-subtle); padding: 1rem; border-radius: 6px; overflow-x: auto; border: 1px solid var(--border); }
              pre code { background: none; padding: 0; }

              /* Components */
              ul.section-list { list-style: none; padding: 0; margin: 1.5rem 0; }
              ul.section-list li { margin-bottom: 0.5rem; padding: 0.6rem 0.75rem; background: var(--bg-subtle); border-radius: 6px; border: 1px solid var(--border); }
              ul.section-list li a { font-weight: 500; }
              .taxonomy-desc { color: var(--text-muted); margin-bottom: 1.5rem; }

              /* Responsive */
              @media (max-width: 600px) {
                .site-header { flex-direction: column; gap: 0.75rem; align-items: flex-start; }
                .site-wrapper { padding: 0 1rem; }
              }
            </style>
          CSS
        end

        # Override in subclasses to customize navigation
        protected def navigation : String
          <<-NAV
                <nav>
                  <a href="<%= base_url %>/">Home</a>
                  <a href="<%= base_url %>/about/">About</a>
                </nav>
          NAV
        end

        # Common config sections
        protected def base_config(title : String = "My Hwaro Site", description : String = "Welcome to my new Hwaro site.") : String
          <<-TOML
          # =============================================================================
          # Site Configuration
          # =============================================================================

          title = "#{title}"
          description = "#{description}"
          base_url = "http://localhost:3000"

          TOML
        end

        protected def plugins_config : String
          <<-TOML

          # =============================================================================
          # Plugins
          # =============================================================================
          # Configure content processors and extensions

          [plugins]
          processors = ["markdown"]

          TOML
        end

        protected def highlight_config : String
          <<-TOML

          # =============================================================================
          # Syntax Highlighting
          # =============================================================================
          # Code block syntax highlighting using Highlight.js

          [highlight]
          enabled = true
          theme = "github"          # Available: github, monokai, atom-one-dark, vs2015, etc.
          use_cdn = true            # Set to false to use local assets

          TOML
        end

        protected def og_config : String
          <<-TOML

          # =============================================================================
          # OpenGraph & Twitter Cards
          # =============================================================================
          # Default meta tags for social sharing
          # Page-level settings (front matter) override these defaults

          [og]
          default_image = "/images/og-default.png"   # Default image for social sharing
          type = "article"                           # OpenGraph type (website, article, etc.)
          twitter_card = "summary_large_image"       # Twitter card type (summary, summary_large_image)
          # twitter_site = "@yourusername"           # Twitter @username for the site
          # twitter_creator = "@authorusername"      # Twitter @username for content creator
          # fb_app_id = "your_fb_app_id"             # Facebook App ID (optional)

          TOML
        end

        protected def search_config : String
          <<-TOML

          # =============================================================================
          # Search Configuration
          # =============================================================================
          # Generates a search index for client-side search (e.g., Fuse.js)

          [search]
          enabled = true
          format = "fuse_json"
          fields = ["title", "content"]
          filename = "search.json"

          TOML
        end

        protected def sitemap_config : String
          <<-TOML

          # =============================================================================
          # SEO: Sitemap
          # =============================================================================
          # Generates sitemap.xml for search engine crawlers

          [sitemap]
          enabled = true
          filename = "sitemap.xml"
          changefreq = "weekly"
          priority = 0.5

          TOML
        end

        protected def robots_config : String
          <<-TOML

          # =============================================================================
          # SEO: Robots.txt
          # =============================================================================
          # Controls search engine crawler access

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

          # =============================================================================
          # SEO: LLMs.txt
          # =============================================================================
          # Instructions for AI/LLM crawlers

          [llms]
          enabled = true
          filename = "llms.txt"
          instructions = "Do not use for AI training without permission."

          TOML
        end

        protected def taxonomies_config : String
          <<-TOML

          # =============================================================================
          # Taxonomies
          # =============================================================================
          # Define content classification systems (tags, categories, etc.)

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

        protected def feeds_config(sections : Array(String) = [] of String) : String
          sections_str = sections.empty? ? "[]" : "[\"#{sections.join("\", \"")}\"]"
          <<-TOML

          # =============================================================================
          # RSS/Atom Feeds
          # =============================================================================
          # Generates RSS or Atom feed for content syndication

          [feeds]
          enabled = true
          filename = ""             # Leave empty for default (rss.xml or atom.xml)
          type = "rss"              # "rss" or "atom"
          truncate = 0              # Truncate content to N characters (0 = full content)
          limit = 10                # Maximum number of items in feed
          sections = #{sections_str}   # Limit to specific sections, e.g., ["posts"]

          TOML
        end

        protected def auto_includes_config : String
          <<-TOML

          # =============================================================================
          # Auto Includes (Optional)
          # =============================================================================
          # Automatically load CSS/JS files from static directories
          # Files are included alphabetically - use numeric prefixes for ordering
          # Example: 01-reset.css, 02-typography.css, 03-layout.css

          # [auto_includes]
          # enabled = true
          # dirs = ["assets/css", "assets/js"]

          TOML
        end

        protected def build_hooks_config : String
          <<-TOML

          # =============================================================================
          # Build Hooks (Optional)
          # =============================================================================
          # Run custom shell commands before/after build process

          # [build]
          # hooks.pre = ["npm install", "python scripts/preprocess.py"]
          # hooks.post = ["npm run minify", "./scripts/deploy.sh"]
          TOML
        end
      end
    end
  end
end
