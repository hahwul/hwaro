# Base scaffold class for project initialization
#
# Scaffolds provide pre-configured content and templates for different
# project types (simple, blog, docs, etc.)
#
# Templates use Jinja2 syntax (powered by Crinja):
# - {{ variable }} - print variable
# - {% if condition %}...{% endif %} - conditionals
# - {% for item in items %}...{% endfor %} - loops
# - {% include "partial.html" %} - includes
# - {% extends "base.html" %} - inheritance
# - {{ value | filter }} - filters

require "../../config/options/init_options"
require "../config_snippets"

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

        # Returns the content files to emit for a multilingual project.
        # The first language in `languages` is the default (no filename
        # suffix); each additional language gets a `.{lang}.md` copy of
        # every Markdown file with a translation-TODO notice inserted.
        #
        # Scaffolds can override this when they want to ship real
        # translations, but the default preserves the scaffold's own
        # content structure (posts/, guide/, chapter-N/, …) instead of
        # collapsing everything into a generic index/about/blog layout.
        def multilingual_content_files(
          languages : Array(String),
          skip_taxonomies : Bool = false,
        ) : Hash(String, String)
          base = content_files(skip_taxonomies)
          return base if languages.size <= 1

          result = {} of String => String
          base.each { |path, body| result[path] = body }

          # languages[0] is the default language (no suffix); clone every
          # Markdown file for each additional language.
          languages[1..].each do |lang|
            base.each do |path, body|
              next unless path.ends_with?(".md")
              localized_body = localize_internal_links(body, lang)
              result[localize_path(path, lang)] = prepend_translation_notice(localized_body, lang)
            end
          end

          result
        end

        # Rewrite Markdown links that point at the default-language URL
        # space so they resolve to the translated locale's URL space
        # instead. Without this, `index.ko.md`'s body keeps
        # `[Posts](/posts/)` and the Korean homepage links a Korean
        # reader straight back to the English `/posts/` index
        # (gh#524).
        #
        # We only rewrite absolute internal links (`](/foo)` /
        # `](/foo/)` /…) — external `http(s)://` URLs and relative
        # links pass through unchanged. Already-prefixed links like
        # `](/ko/foo)` are skipped so callers can localize a body
        # that's already partially translated. Image syntax
        # (`![alt](/img.png)`) is left alone because static assets
        # live at the site root regardless of locale; we capture the
        # optional leading `!` and pass image matches through
        # untouched.
        protected def localize_internal_links(body : String, lang : String) : String
          prefix = "/#{lang}/"
          body.gsub(/(!?)\[([^\]]*)\]\((\/[^)\s]+)\)/) do |match|
            bang = $~[1]
            label = $~[2]
            target = $~[3]
            if !bang.empty?
              match
            elsif target.starts_with?(prefix) || target == "/#{lang}"
              match
            else
              "[#{label}](#{prefix}#{target.lchop("/")})"
            end
          end
        end

        # Insert a language code before the extension:
        #   "index.md"              -> "index.ko.md"
        #   "posts/hello.md"        -> "posts/hello.ko.md"
        #   "posts/_index.md"       -> "posts/_index.ko.md"
        protected def localize_path(path : String, lang : String) : String
          ext = File.extname(path)
          stem = path[0, path.size - ext.size]
          "#{stem}.#{lang}#{ext}"
        end

        # Keep any TOML (`+++`) or YAML (`---`) front matter block at the
        # top of the file and insert the notice after it, so users see
        # the TODO above the body without breaking parseable metadata.
        protected def prepend_translation_notice(body : String, lang : String) : String
          notice = "<!-- TODO: Translate this page to '#{lang}'. -->\n\n"

          delimiter = if body.starts_with?("+++\n")
                        "+++"
                      elsif body.starts_with?("---\n")
                        "---"
                      end

          return notice + body unless delimiter

          lines = body.split("\n")
          close_index = nil
          lines.each_with_index do |line, i|
            next if i == 0
            if line == delimiter
              close_index = i
              break
            end
          end

          return notice + body unless close_index

          front_matter = lines[0..close_index].join("\n")
          rest = close_index + 1 < lines.size ? lines[(close_index + 1)..].join("\n") : ""
          "#{front_matter}\n\n#{notice}#{rest.lstrip("\n")}"
        end

        # Returns template files as a hash of path => content
        abstract def template_files(skip_taxonomies : Bool = false) : Hash(String, String)

        # Returns static files as a hash of path => content
        def static_files : Hash(String, String)
          {} of String => String
        end

        # Returns shortcode files as a hash of path => content
        def shortcode_files : Hash(String, String)
          {
            "shortcodes/alert.html" => alert_shortcode,
          }
        end

        # Returns archetype files (path relative to `archetypes/`) as a
        # hash of path => content. The default set ships a `default.md`
        # that `hwaro new` picks up automatically (see
        # `Services::Creator#find_archetype`), which both makes the
        # archetype slot discoverable and ensures scaffolded content gets
        # reasonable default front matter (TOML + `description`) without
        # relying on the built-in template. Subclasses can extend this to
        # add section-specific archetypes (e.g. `posts.md`).
        def archetype_files : Hash(String, String)
          {
            "default.md" => default_archetype,
          }
        end

        # Built-in default archetype content (TOML front matter).
        # `Services::Creator` substitutes `{{ title }}`, `{{ date }}`,
        # `{{ draft }}`, and `{{ tags }}`; other fields (description) ship
        # with empty values for users to fill in.
        #
        # The body is intentionally empty: every scaffold's `page.html` /
        # `post.html` already renders `<h1>{{ page.title | e }}</h1>`, so
        # injecting a `# {{ title }}` here would produce two H1s on every
        # page created via `hwaro new` (gh#525).
        protected def default_archetype : String
          <<-MD
            +++
            title = "{{ title }}"
            date = "{{ date }}"
            draft = {{ draft }}
            description = ""
            tags = {{ tags }}
            +++

            MD
        end

        # Returns the config.toml content
        abstract def config_content(skip_taxonomies : Bool = false) : String

        # Returns the site title used in config (overridable per scaffold)
        protected def config_title : String
          "My Hwaro Site"
        end

        # Returns the site description used in config (overridable per scaffold)
        protected def config_description : String
          "Welcome to my new Hwaro site."
        end

        # Returns the highlight.js theme name (overridable for dark scaffolds)
        protected def config_highlight_theme : String
          "github"
        end

        # Returns a minimal config.toml without comments and optional sections
        def minimal_config_content(skip_taxonomies : Bool = false) : String
          String.build do |str|
            str << "title = \"#{config_title}\"\n"
            str << "description = \"#{config_description}\"\n"
            str << "base_url = \"http://localhost:3000\"\n"
            str << "\n[plugins]\n"
            str << "processors = [\"markdown\"]\n"
            str << "\n[content.files]\n"
            str << "allow_extensions = [\"jpg\", \"jpeg\", \"png\", \"gif\", \"svg\", \"webp\"]\n"
            str << "\n[highlight]\n"
            str << "enabled = true\n"
            str << "theme = \"#{config_highlight_theme}\"\n"
            str << "use_cdn = true\n"
            unless skip_taxonomies
              str << "\n[[taxonomies]]\n"
              str << "name = \"tags\"\n"
              str << "feed = true\n"
              str << "\n[[taxonomies]]\n"
              str << "name = \"categories\"\n"
              str << "\n[[taxonomies]]\n"
              str << "name = \"authors\"\n"
            end
            str << "\n[sitemap]\n"
            str << "enabled = true\n"
            str << "\n[feeds]\n"
            str << "enabled = true\n"
            str << "type = \"rss\"\n"
            str << "limit = 10\n"
            # `--minimal-config` previously dropped `[search]` entirely,
            # which silently broke the search button in the blog/docs/
            # book scaffolds (their JS still fetched `/search.json`).
            # Keep search on so the scaffold templates work out of the
            # box; users who don't want it can flip `enabled = false`
            # (gh#528 B).
            str << "\n[search]\n"
            str << "enabled = true\n"
            str << "format = \"fuse_json\"\n"
          end
        end

        # Common shortcode: alert (Jinja2 syntax)
        protected def alert_shortcode : String
          <<-HTML
            <div class="alert" style="padding: 1rem; border: 1px solid #ddd; background-color: #f9f9f9; border-left: 5px solid #0070f3; margin: 1rem 0;">
              <strong>{{ type | upper }}:</strong> {{ body }}
            </div>
            HTML
        end

        # Common template: header (Jinja2 syntax)
        protected def header_template : String
          <<-HTML
            <!DOCTYPE html>
            <html lang="{{ page_language }}">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <meta name="description" content="{{ page.description | e }}">
              <title>{% if page.title is present %}{{ page.title | e }} - {% endif %}{{ site.title | e }}</title>
              {{ og_all_tags }}
              {{ hreflang_tags }}
              #{styles}
              {{ highlight_css }}
              {{ auto_includes_css }}
            </head>
            <body data-section="{{ page.section }}">
              <div class="site-wrapper">
                <header class="site-header">
                  <a href="{{ base_url }}/" class="site-logo">{{ site.title }}</a>
                  #{navigation}
                </header>

            HTML
        end

        # Common template: footer (Jinja2 syntax)
        protected def footer_template : String
          <<-HTML
                <footer class="site-footer">
                  <p>Powered by Hwaro</p>
                </footer>
              </div>
              {{ highlight_js }}
              {{ auto_includes_js }}
            </body>
            </html>
            HTML
        end

        # Common template: page (Jinja2 syntax). Renders the title as
        # `<h1>` so content authors don't need to repeat it in every
        # markdown body — and so `hwaro new` can ship an empty body
        # without losing the heading (gh#525).
        protected def page_template : String
          <<-HTML
            {% include "header.html" %}
              <main class="site-main">
                <h1>{{ page.title | e }}</h1>
                {{ content }}
              </main>
            {% include "footer.html" %}
            HTML
        end

        # Common template: section (Jinja2 syntax)
        protected def section_template : String
          <<-HTML
            {% include "header.html" %}
              <main class="site-main">
                <h1>{{ page.title | e }}</h1>
                {{ content }}
                <ul class="section-list">
                  {{ section.list }}
                </ul>
                {{ pagination }}
              </main>
            {% include "footer.html" %}
            HTML
        end

        # Common template: 404 (Jinja2 syntax)
        protected def not_found_template : String
          <<-HTML
            {% include "header.html" %}
              <main class="site-main">
                <h1>404 Not Found</h1>
                <p>The page you are looking for does not exist.</p>
                <p><a href="{{ base_url }}/">Return to Home</a></p>
              </main>
            {% include "footer.html" %}
            HTML
        end

        # Common template: taxonomy (Jinja2 syntax)
        protected def taxonomy_template : String
          <<-HTML
            {% include "header.html" %}
              <main class="site-main">
                <h1>{{ page.title | e }}</h1>
                <p class="taxonomy-desc">Browse all terms in this taxonomy:</p>
                {{ content }}
              </main>
            {% include "footer.html" %}
            HTML
        end

        # Common template: taxonomy_term (Jinja2 syntax)
        protected def taxonomy_term_template : String
          <<-HTML
            {% include "header.html" %}
              <main class="site-main">
                <h1>{{ page.title | e }}</h1>
                <p class="taxonomy-desc">Posts tagged with this term:</p>
                {{ content }}
              </main>
            {% include "footer.html" %}
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
              nav.pagination { margin: 1.5rem 0; }
              nav.pagination .pagination-list { list-style: none; padding: 0; margin: 0; display: flex; gap: 0.5rem; flex-wrap: wrap; align-items: center; }
              nav.pagination a { display: inline-block; padding: 0.25rem 0.55rem; border-radius: 6px; border: 1px solid var(--border); color: var(--text-muted); text-decoration: none; }
              nav.pagination a:hover { color: var(--primary); border-color: var(--primary); }
              .pagination-current span { display: inline-block; padding: 0.25rem 0.55rem; border-radius: 6px; border: 1px solid var(--primary); background: color-mix(in srgb, var(--primary) 12%, transparent); }
              .pagination-disabled span { display: inline-block; padding: 0.25rem 0.55rem; border-radius: 6px; border: 1px solid var(--border); color: var(--text-muted); opacity: 0.6; }

              /* Responsive */
              @media (max-width: 600px) {
                .site-header { flex-direction: column; gap: 0.75rem; align-items: flex-start; }
                .site-wrapper { padding: 0 1rem; }
              }
            </style>
            CSS
        end

        # Override in subclasses to customize navigation (Jinja2 syntax)
        protected def navigation : String
          <<-NAV
            <nav>
              <a href="{{ base_url }}/">Home</a>
              <a href="{{ base_url }}/about/">About</a>
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

        protected def multilingual_config : String
          <<-TOML

            # =============================================================================
            # Multilingual (Optional)
            # =============================================================================
            # Enable multilingual routing by defining languages and a default language.
            # Then add language variants using filename suffixes:
            # - content/about.md -> /about/
            # - content/about.ko.md -> /ko/about/
            # - content/about/index.ko.md -> /ko/about/

            # default_language = "en"
            #
            # [languages.en]
            # language_name = "English"
            # weight = 1
            #
            # [languages.ko]
            # language_name = "한국어"
            # weight = 2

            TOML
        end

        protected def plugins_config : String
          ConfigSnippets.plugins
        end

        protected def pagination_config : String
          ConfigSnippets.pagination
        end

        protected def content_files_config : String
          <<-TOML

            # =============================================================================
            # Content Files
            # =============================================================================
            # Publish non-Markdown files from `content/` into the output directory.
            # Example: content/about/profile.jpg -> /about/profile.jpg

            [content.files]
            allow_extensions = ["jpg", "jpeg", "png", "gif", "svg", "webp"]
            # disallow_extensions = ["psd"]
            # disallow_paths = ["private/**", "**/_*"]

            TOML
        end

        protected def highlight_config : String
          ConfigSnippets.highlight
        end

        protected def og_config : String
          ConfigSnippets.og
        end

        protected def search_config : String
          ConfigSnippets.search
        end

        protected def sitemap_config : String
          ConfigSnippets.sitemap
        end

        protected def robots_config : String
          ConfigSnippets.robots
        end

        protected def llms_config : String
          ConfigSnippets.llms
        end

        protected def series_config : String
          ConfigSnippets.series
        end

        protected def related_config : String
          ConfigSnippets.related
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
            full_content = true       # true = full HTML in feed, false = description/summary only
            limit = 10                # Maximum number of items in feed
            sections = #{sections_str}   # Limit to specific sections, e.g., ["posts"]
            # default_language_only = true  # Multilingual: true = main feed has default language only
            #                               #              false = main feed includes all languages

            TOML
        end

        protected def permalinks_config : String
          ConfigSnippets.permalinks
        end

        protected def auto_includes_config : String
          ConfigSnippets.auto_includes
        end

        protected def assets_config : String
          ConfigSnippets.assets
        end

        protected def markdown_config : String
          ConfigSnippets.markdown
        end

        protected def build_hooks_config : String
          ConfigSnippets.build
        end

        protected def pwa_config : String
          ConfigSnippets.pwa
        end

        protected def amp_config : String
          ConfigSnippets.amp
        end

        protected def og_auto_image_config : String
          ConfigSnippets.og_auto_image
        end

        protected def image_processing_config : String
          ConfigSnippets.image_processing
        end

        protected def deployment_config : String
          ConfigSnippets.deployment
        end
      end
    end
  end
end
