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
require "./design_tokens"
require "./embedded_fonts"

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
          # Allow an optional Markdown link title (`(/posts/ "All posts")`) and
          # preserve it — otherwise titled links keep the default-language URL.
          body.gsub(/(!?)\[([^\]]*)\]\((\/[^)\s]+)(\s+"[^"]*")?\)/) do |match|
            bang = $~[1]
            label = $~[2]
            target = $~[3]
            title = $~[4]? || ""
            if !bang.empty?
              match
            elsif target.starts_with?(prefix) || target == "/#{lang}"
              match
            else
              "[#{label}](#{prefix}#{target.lchop("/")}#{title})"
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

        # Returns static files as a hash of path => content. Every
        # scaffold inherits a tiny SVG favicon so a freshly-generated
        # site doesn't show a blank tab icon. Scaffolds that override
        # `static_files` (blog/docs/book) merge `super` to keep it.
        def static_files : Hash(String, String)
          {
            "favicon.svg" => default_favicon_svg,
          }
        end

        # The embedded Charis SIL faces (+ its OFL license), keyed by the
        # path they're written to under `static/`. Scaffolds whose CSS
        # declares the `@font-face` blocks merge this into `static_files`
        # so the serif heading signature renders identically off-Apple
        # (see `EmbeddedFonts`). `bare` intentionally skips it — it ships
        # no stylesheet to reference the faces. The String values carry
        # raw woff2 bytes; `File.write` emits them verbatim.
        def font_files : Hash(String, String)
          {
            "fonts/charis-sil-400.woff2"    => EmbeddedFonts.regular,
            "fonts/charis-sil-700.woff2"    => EmbeddedFonts.bold,
            "fonts/charis-sil-italic.woff2" => EmbeddedFonts.italic,
            "fonts/OFL.txt"                 => EmbeddedFonts.ofl_license,
          }
        end

        # `@font-face` blocks that bind the embedded Charis SIL faces to
        # the family name `"Charter"`. `local()` comes first so a machine
        # that already has Charter (macOS/iOS) uses it with no download;
        # everyone else fetches the subset woff2. `font_path_prefix`
        # differs per scaffold: the simple scaffold inlines its CSS into a
        # template (so it can use `{{ base_url }}`), while blog/docs/book
        # ship an external stylesheet at `/css/style.css` and must point
        # at the fonts relatively (`../fonts/...`) to survive sub-path
        # deploys.
        protected def font_face_css(font_path_prefix : String) : String
          <<-CSS
            @font-face {
              font-family: "Charter";
              font-style: normal;
              font-weight: 400;
              font-display: swap;
              src: local("Charter"), local("Charis SIL"), url("#{font_path_prefix}/charis-sil-400.woff2") format("woff2");
            }
            @font-face {
              font-family: "Charter";
              font-style: normal;
              font-weight: 700;
              font-display: swap;
              src: local("Charter Bold"), local("Charis SIL Bold"), url("#{font_path_prefix}/charis-sil-700.woff2") format("woff2");
            }
            @font-face {
              font-family: "Charter";
              font-style: italic;
              font-weight: 400;
              font-display: swap;
              src: local("Charter Italic"), local("Charis SIL Italic"), url("#{font_path_prefix}/charis-sil-italic.woff2") format("woff2");
            }
            CSS
        end

        # 32×32 SVG favicon. Inline (no external file dep), themable
        # by editing the `currentColor`/`fill` values, and crisp at
        # any DPR. We use a neutral mark instead of the hwaro logo so
        # users don't have to remember to swap branding before
        # publishing. The ember red matches the scaffold stylesheets'
        # `--primary` token.
        protected def default_favicon_svg : String
          <<-SVG
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
              <rect width="32" height="32" rx="6" fill="#b35454"/>
              <path d="M9 8h3v7h8V8h3v16h-3v-7h-8v7H9z" fill="#ffffff"/>
            </svg>
            SVG
        end

        # The shared `:root` token prelude (see DesignTokens). `layout` lines
        # add per-scaffold geometry tokens inside the same block.
        protected def design_root(layout : String = "") : String
          DesignTokens.root_block(layout)
        end

        # The ember-warm syntax-highlight theme, inlined into each scaffold's
        # stylesheet and colored entirely through the `--code-*` tokens (see
        # DesignTokens.highlight_css). Because the rules live in the scaffold
        # stylesheet (loaded via `{{ base_url }}/css/style.css`) they stay
        # correct under sub-path deploys, unlike a root-absolute `/assets/...`
        # theme link, and they cover both `mode = "client"` and
        # `mode = "server"` output (same hljs classes). The colors resolve
        # per the page's color-scheme — no dark variant needed.
        protected def highlight_theme_css : String
          DesignTokens.highlight_css
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
        # `{{ draft }}`, `{{ tags }}`, and `{{ description }}`. An unset
        # description substitutes to "" — identical to the prior hardcoded
        # empty value — while the interactive `hwaro new` wizard fills it in.
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
            description = "{{ description }}"
            tags = {{ tags }}
            +++

            MD
        end

        # Returns the config.toml content. `multilingual_languages` (from
        # `--include-multilingual`) is threaded through so the full config
        # emits a real, enabled `[languages]` block instead of the commented
        # placeholder.
        abstract def config_content(skip_taxonomies : Bool = false, multilingual_languages : Array(String) = [] of String) : String

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

        # Display name for language codes (used in minimal + balanced config for --include-multilingual).
        protected def language_display_name(code : String) : String
          case code.downcase
          when "en" then "English"
          when "ko" then "한국어"
          when "ja" then "日本語"
          when "zh" then "中文"
          when "es" then "Español"
          when "fr" then "Français"
          when "de" then "Deutsch"
          when "pt" then "Português"
          when "ru" then "Русский"
          when "it" then "Italiano"
          when "nl" then "Nederlands"
          when "pl" then "Polski"
          when "vi" then "Tiếng Việt"
          when "th" then "ไทย"
          when "ar" then "العربية"
          when "hi" then "हिन्दी"
          else           code.upcase
          end
        end

        # Sections the scaffold's main feed should be limited to. Empty means
        # no filter (every renderable page). Post-oriented scaffolds override
        # this (e.g. ["posts"]) so the default/minimal config matches the
        # full-config feed and the homepage/about/archives don't pollute it.
        protected def feed_sections : Array(String)
          [] of String
        end

        # Returns a minimal config.toml without comments and optional sections
        def minimal_config_content(skip_taxonomies : Bool = false, multilingual_languages : Array(String) = [] of String) : String
          String.build do |str|
            str << "title = \"#{config_title}\"\n"
            str << "description = \"#{config_description}\"\n"
            str << "base_url = \"http://localhost:3000\"\n"

            # Multilingual support (only when 2+ languages requested; single lang
            # is treated as non-multilingual per initializer tests).
            if multilingual_languages.size > 1
              default_lang = multilingual_languages.first
              str << "default_language = \"#{default_lang}\"\n\n"
              str << "[languages]\n"
              lang_blocks = multilingual_languages.map_with_index do |lang, index|
                lang_name = language_display_name(lang)
                tax_line = skip_taxonomies ? "" : "\n  taxonomies = [\"tags\", \"categories\", \"authors\"]"
                "  [languages.#{lang}]\n" \
                "  language_name = \"#{lang_name}\"\n" \
                "  weight = #{index + 1}\n" \
                "  generate_feed = true\n" \
                "  build_search_index = true#{tax_line}"
              end
              str << lang_blocks.join("\n\n")
              str << "\n\n"
            end

            str << "[plugins]\n"
            str << "processors = [\"markdown\"]\n"
            str << "\n[content.files]\n"
            str << "allow_extensions = [\"jpg\", \"jpeg\", \"png\", \"gif\", \"svg\", \"webp\"]\n"
            str << "\n[highlight]\n"
            str << "enabled = true\n"
            str << "mode = \"client\"\n"
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
            unless feed_sections.empty?
              str << "sections = [#{feed_sections.map { |s| %("#{s}") }.join(", ")}]\n"
            end
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
        #
        # The body is piped through `markdownify` so markdown written inside
        # the alert — **bold**, `code`, [links](…) — renders as HTML instead
        # of appearing as literal markup. (Crinja autoescaping is off here, the
        # same way `{{ content }}` emits rendered HTML.)
        protected def alert_shortcode : String
          # A translucent ember tint driven by the shared --primary token so
          # the alert follows the resolved scheme (and any user retheme).
          # The `#b35454` var() fallbacks keep the shortcode rendering
          # identically on `bare`, which ships no stylesheet and therefore
          # no tokens. `color: inherit` keeps the body on the theme palette.
          <<-HTML
            <div class="alert" style="padding: 0.875rem 1.125rem; border: 1px solid color-mix(in srgb, var(--primary, #b35454) 30%, transparent); background-color: color-mix(in srgb, var(--primary, #b35454) 7%, transparent); border-radius: 6px; margin: 1rem 0; color: inherit;">
              <strong style="color: var(--primary, #b35454);">{{ type | upper }}:</strong> {{ body | markdownify }}
            </div>
            HTML
        end

        # Common template: header (Jinja2 syntax).
        #
        # Both `page.title` and `page.description` are guarded so a page
        # without front-matter values doesn't render `<title> - Site</title>`
        # or an empty `<meta name="description">` — the latter actively
        # hurts SEO/social previews. Empty strings are treated the same as
        # missing via `default(_, true)`.
        protected def header_template : String
          <<-HTML
            <!DOCTYPE html>
            <html lang="{{ page_language }}">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <meta name="description" content="{{ page.description | default(site.description, true) | e }}">
              <title>{% if page.title is present %}{{ page.title | e }} - {% endif %}{{ site.title | e }}</title>
              <link rel="icon" type="image/svg+xml" href="{{ base_url }}/favicon.svg">
              {{ og_all_tags }}
              {{ canonical_tag }}
              {{ jsonld }}
              {{ hreflang_tags }}
              {{ pagination_seo_links }}
              #{styles}
              {# The syntax theme is inlined in the CSS above, so no highlight
                 theme stylesheet link is emitted here (sub-path safe). Highlight.js
                 itself still loads from the footer. #}
              {{ math_tags }}
              {{ mermaid_tags }}
              {{ auto_includes_css }}
            </head>
            <body data-section="{{ page.section }}">
              <a class="skip-link" href="#main">Skip to content</a>
              <div class="site-wrapper">
                <header class="site-header">
                  <a href="{{ base_url }}{{ lang_prefix }}/" class="site-logo">{{ site.title | e }}</a>
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
        # without losing the heading (gh#525). The H1 is guarded so a
        # title-less homepage (e.g. a hero-style index) doesn't emit an
        # empty `<h1></h1>`.
        protected def page_template : String
          <<-HTML
            {% include "header.html" %}
              <main id="main" class="site-main">
                {% if page.title is present %}<h1>{{ page.title | e }}</h1>{% endif %}
                {{ content }}
              </main>
            {% include "footer.html" %}
            HTML
        end

        # Common template: section (Jinja2 syntax)
        protected def section_template : String
          <<-HTML
            {% include "header.html" %}
              <main id="main" class="site-main">
                {% if page.title is present %}<h1>{{ page.title | e }}</h1>{% endif %}
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
              <main id="main" class="site-main">
                <h1>404 Not Found</h1>
                <p>The page you are looking for does not exist.</p>
                <p><a href="{{ base_url }}{{ lang_prefix }}/">Return to Home</a></p>
              </main>
            {% include "footer.html" %}
            HTML
        end

        # Common template: taxonomy (Jinja2 syntax)
        protected def taxonomy_template : String
          <<-HTML
            {% include "header.html" %}
              <main id="main" class="site-main">
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
              <main id="main" class="site-main">
                <h1>{{ page.title | e }}</h1>
                <p class="taxonomy-desc">Posts tagged with this term:</p>
                {{ content }}
              </main>
            {% include "footer.html" %}
            HTML
        end

        # Override in subclasses to customize styles.
        #
        # "Hwaro Ember" theme: warm paper neutrals + the hwaro brand
        # ember red (#b35454) as the single accent, with Charter serif
        # headings against a sans body. Charter ships embedded (Charis
        # SIL, OFL) via the `@font-face` blocks below, so the heading
        # signature renders the same off-Apple; this CSS is inlined into a
        # template, so the font URLs can use `{{ base_url }}`.
        protected def styles : String
          <<-CSS
            <style>
              #{font_face_css("{{ base_url }}/fonts")}
              #{design_root("--content-max-w: 720px;")}
              *, *::before, *::after { box-sizing: border-box; }
              body { font-family: var(--font-sans); font-size: var(--step-0); line-height: 1.7; margin: 0; color: var(--text); background: var(--bg); -webkit-font-smoothing: antialiased; -moz-osx-font-smoothing: grayscale; }
              ::selection { background: var(--selection); }

              /* Layout */
              .site-wrapper { max-width: var(--content-max-w); margin: 0 auto; padding: 0 var(--space-5); }
              .site-header { display: flex; align-items: baseline; justify-content: space-between; padding: var(--space-5) 0 var(--space-4); border-bottom: 1px solid var(--border); margin-bottom: var(--space-6); }
              .site-logo { font-family: var(--font-serif); font-weight: 700; font-size: var(--step-1); color: var(--heading); text-decoration: none; letter-spacing: -0.01em; }
              .site-logo:hover { color: var(--primary); }
              .site-header nav { display: flex; gap: 1.4rem; }
              .site-header nav a { color: var(--text-muted); text-decoration: none; font-size: var(--step--1); transition: color var(--transition); }
              .site-header nav a:hover { color: var(--primary); }
              .site-main { min-height: calc(100vh - 220px); }
              .site-footer { margin-top: var(--space-7); padding: var(--space-5) 0 var(--space-6); border-top: 1px solid var(--border); color: var(--text-muted); font-size: var(--step--1); text-align: center; }

              /* Typography — the fluid minor-third scale. */
              h1, h2, h3 { font-family: var(--font-serif); line-height: 1.25; margin-top: 1.6em; margin-bottom: 0.5em; font-weight: 700; color: var(--heading); text-wrap: balance; }
              h1 { font-size: var(--step-3); margin-top: 0; letter-spacing: -0.018em; }
              h2 { font-size: var(--step-2); letter-spacing: -0.008em; }
              h3 { font-size: var(--step-1); }
              p { margin: 1em 0; text-wrap: pretty; }
              .site-main p, .site-main li { max-width: var(--measure); }

              /* Page title gets a short ember rule — the one mark every
                 hwaro scaffold shares — and its first paragraph reads as a
                 lede, giving the page a real focal point. */
              .site-main > h1:first-child { position: relative; padding-bottom: 0.9rem; margin-bottom: 1.1rem; }
              .site-main > h1:first-child::after { content: ""; position: absolute; left: 0; bottom: 0; width: 2.75rem; height: 3px; border-radius: 999px; background: linear-gradient(90deg, var(--rule-from), var(--rule-to)); }
              .site-main > h1:first-child + p { font-size: var(--step-1); line-height: 1.55; color: var(--text-secondary); }

              /* Links: ember, with an underline that warms up on hover. */
              a { color: var(--primary); text-decoration: underline; text-decoration-color: color-mix(in srgb, var(--primary) 35%, transparent); text-underline-offset: 3px; transition: color var(--transition), text-decoration-color var(--transition); }
              a:hover { color: var(--primary-strong); text-decoration-color: currentColor; }
              .site-header a, .skip-link, ul.section-list a, nav.pagination a { text-decoration: none; }

              code { background: var(--bg-code); padding: 0.15rem 0.4rem; border-radius: 4px; font-size: 0.85em; font-family: var(--font-mono); }
              pre { background: var(--bg-code); padding: var(--space-4) var(--space-5); border-radius: var(--radius-sm); overflow-x: auto; border: 1px solid var(--border-subtle); line-height: 1.55; }
              /* Keep `.hljs` transparent so code sits on the warm well; if a
                 user switches to a CDN theme it won't repaint a clashing box.
                 `pre code.hljs` (0,1,2) outranks a theme's `.hljs` (0,1,0). */
              pre code, pre code.hljs { background: transparent; padding: 0; }
              #{highlight_theme_css}
              img { max-width: 100%; height: auto; border-radius: 4px; outline: 1px solid var(--edge); outline-offset: -1px; }
              blockquote { font-family: var(--font-serif); font-style: italic; margin: 1.4em 0; padding: 0.1rem 0 0.1rem var(--space-5); color: var(--text-muted); border-left: 1px solid var(--primary); }
              table { border-collapse: collapse; width: 100%; margin: 1em 0; font-size: 0.95em; }
              th, td { border-bottom: 1px solid var(--border); padding: 0.55rem 0.75rem; text-align: left; }
              th { font-size: 0.8em; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); border-bottom: 2px solid var(--border); }
              hr { border: none; border-top: 1px solid var(--border); margin: var(--space-6) 0; }

              /* Components */
              ul.section-list { list-style: none; padding: 0; margin: var(--space-5) 0; }
              ul.section-list li { padding: 0.85rem 0.1rem; border-bottom: 1px solid var(--bg-subtle); }
              ul.section-list li:first-child { border-top: 1px solid var(--bg-subtle); }
              ul.section-list li a { font-family: var(--font-serif); font-weight: 500; font-size: var(--step-1); color: var(--text); transition: color var(--transition); }
              ul.section-list li a:hover { color: var(--primary); }
              .taxonomy-desc { color: var(--text-muted); margin-bottom: var(--space-5); }
              nav.pagination { margin: var(--space-6) 0; }
              nav.pagination .pagination-list { list-style: none; padding: 0; margin: 0; display: flex; gap: var(--space-2); flex-wrap: wrap; align-items: center; font-variant-numeric: tabular-nums; }
              nav.pagination a { display: inline-block; padding: 0.25rem 0.6rem; border-radius: var(--radius-sm); border: 1px solid var(--border); color: var(--text-muted); transition: color var(--transition), border-color var(--transition), transform 0.1s ease; }
              nav.pagination a:hover { color: var(--primary); border-color: var(--primary); }
              nav.pagination a:active { transform: scale(0.96); }
              .pagination-current span { display: inline-block; padding: 0.25rem 0.6rem; border-radius: var(--radius-sm); border: 1px solid var(--primary); background: var(--primary-tint); color: var(--primary-strong); }
              .pagination-disabled span { display: inline-block; padding: 0.25rem 0.6rem; border-radius: var(--radius-sm); border: 1px solid var(--border); color: var(--text-muted); opacity: 0.6; }

              /* Responsive — the type scale is fluid, so only the frame
                 needs to adapt. */
              @media (max-width: 600px) {
                .site-header { flex-direction: column; gap: 0.6rem; align-items: flex-start; }
                .site-wrapper { padding: 0 var(--space-4); }
              }

              /* Accessibility */
              :focus-visible { outline: 2px solid var(--primary); outline-offset: 2px; }
              .skip-link { position: absolute; top: -100px; left: 0; background: var(--primary); color: var(--bg); padding: var(--space-2) var(--space-4); z-index: 1000; border-radius: 0 0 var(--radius-sm) 0; }
              .skip-link:focus { top: 0; }
              @media (prefers-reduced-motion: reduce) {
                *, *::before, *::after { transition-duration: 0.01ms !important; }
              }
            </style>
            CSS
        end

        # Override in subclasses to customize navigation (Jinja2 syntax)
        protected def navigation : String
          <<-NAV
            <nav>
              <!-- Add links for new sections here (e.g. /notes/, /til/).
                   Dynamic version (copy out and remove the hardcoded links
                   below). It lists only the current language's sections;
                   s.url already includes the language prefix, so do NOT add
                   lang_prefix. For custom ordering, set `weight` in each
                   section's front matter and use sort(attribute="weight").
                   (The example below is wrapped in a raw block so it
                   isn't executed here.)
                   {% raw %}
                   {% for s in site.sections | sort(attribute="title") %}
                     {% if not s.transparent and s.name and s.language == page_language %}<a href="{{ base_url }}{{ s.url }}">{{ s.title }}</a>{% endif %}
                   {% endfor %}
                   {% endraw %}
              -->
              <a href="{{ base_url }}{{ lang_prefix }}/">Home</a>
              <a href="{{ base_url }}{{ lang_prefix }}/about/">About</a>
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

        protected def multilingual_config(multilingual_languages : Array(String) = [] of String) : String
          # When `--include-multilingual` requested 2+ languages, emit a real,
          # enabled languages block so the full config honors the flag (gh: the
          # full-config path used to drop multilingual entirely, leaving
          # `.ko.md` variants routed as literal `/about.ko/` pages).
          if multilingual_languages.size > 1
            default_lang = multilingual_languages.first
            lang_blocks = multilingual_languages.map_with_index do |lang, index|
              "  [languages.#{lang}]\n" \
              "  language_name = \"#{language_display_name(lang)}\"\n" \
              "  weight = #{index + 1}\n" \
              "  generate_feed = true\n" \
              "  build_search_index = true"
            end
            return String.build do |str|
              str << "\n"
              str << "# =============================================================================\n"
              str << "# Multilingual\n"
              str << "# =============================================================================\n"
              str << "# Language variants use filename suffixes:\n"
              str << "# - content/about.md -> /about/\n"
              str << "# - content/about.ko.md -> /ko/about/\n\n"
              str << "default_language = \"#{default_lang}\"\n\n"
              str << "[languages]\n"
              str << lang_blocks.join("\n\n")
              str << "\n\n"
            end
          end

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

        # Dark-theme highlight block shared by the *_dark scaffolds (identical
        # across blog/docs/book dark variants).
        protected def highlight_dark_config : String
          <<-TOML

            # =============================================================================
            # Syntax Highlighting
            # =============================================================================
            # Code blocks are highlighted in the browser by Highlight.js and themed by
            # an inlined, ember-warm dark theme in css/style.css (so you recolor syntax
            # by editing that CSS, not the `theme` below). `mode = "server"` can
            # highlight at build time with no JS, but its Tartrazine backend isn't
            # multi-thread-safe, so the scaffold default stays "client".

            [highlight]
            enabled = true
            mode = "client"              # "client" = Highlight.js in the browser; "server" = build-time (no JS)
            theme = "github-dark"        # Highlight.js theme name; the scaffold's inlined CSS overrides its colors
            use_cdn = true               # true loads Highlight.js from a CDN; false expects a self-hosted build

            TOML
        end

        # Shared search overlay markup; only the input placeholder varies per
        # scaffold (e.g. "Search posts...", "Search documentation...").
        protected def search_overlay_html(placeholder : String) : String
          <<-HTML
            <div class="search-overlay" id="searchOverlay" onclick="if(event.target===this)closeSearch()">
              <div class="search-modal">
                <div class="search-input-wrap">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
                  <input type="search" id="searchInput" aria-label="Search" placeholder="#{placeholder}" autocomplete="off">
                  <kbd onclick="closeSearch()">ESC</kbd>
                </div>
                <div class="search-results" id="searchResults"></div>
              </div>
            </div>
            HTML
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

        protected def content_new_config : String
          ConfigSnippets.content_new
        end

        protected def doctor_config : String
          ConfigSnippets.doctor
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
