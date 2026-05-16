# Bare scaffold - minimal structure with semantic HTML only
#
# Generates only directory structure and config.toml with
# semantic HTML templates. No CSS styles, no search JS,
# no opinionated templates.

require "./base"

module Hwaro
  module Services
    module Scaffolds
      class Bare < Base
        def type : Config::Options::ScaffoldType
          Config::Options::ScaffoldType::Bare
        end

        def description : String
          "Minimal structure with semantic HTML only (no styles, no JS)"
        end

        def content_files(skip_taxonomies : Bool = false) : Hash(String, String)
          {
            "index.md" => index_content,
            "about.md" => about_content,
          }
        end

        # `bare` ships no taxonomy templates by default — taxonomies are
        # opt-in here (see `config_content`), so the matching templates
        # would be dead files. Users who add `[[taxonomies]]` later can
        # copy from the simple scaffold or generate their own.
        def template_files(skip_taxonomies : Bool = false) : Hash(String, String)
          {
            "header.html"  => bare_header_template,
            "footer.html"  => bare_footer_template,
            "page.html"    => page_template,
            "section.html" => bare_section_template,
            "404.html"     => bare_not_found_template,
          }
        end

        # `bare` keeps the inherited favicon — the "no batteries"
        # promise is about CSS/JS, not about leaving every browser
        # tab with a 404 for `/favicon.ico`.

        def shortcode_files : Hash(String, String)
          {} of String => String
        end

        # `bare` is intentionally minimal — taxonomies/search/highlight are
        # opt-in features that conflict with the "no batteries" promise of
        # this scaffold. Users who want them can copy from the simple
        # scaffold or pass `--scaffold simple`. The `taxonomies_config`
        # override above is therefore omitted from the default emit even
        # when `--include-taxonomies` is set; we still ship the taxonomy
        # templates below so users can wire them up later by adding
        # `[[taxonomies]]` entries themselves.
        def config_content(skip_taxonomies : Bool = false) : String
          config = String.build do |str|
            str << base_config
            str << plugins_config
            str << content_files_config
            str << sitemap_config
            str << feeds_config
          end
          config
        end

        # Bare header: semantic HTML only, no styles. `page.title` and
        # `page.description` are guarded so a page without front-matter
        # values doesn't emit `<title> - Site</title>` or an empty
        # `<meta name="description">`.
        private def bare_header_template : String
          <<-HTML
            <!DOCTYPE html>
            <html lang="{{ page_language }}">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <meta name="description" content="{{ page.description | default(site.description, true) | e }}">
              <title>{% if page.title is present %}{{ page.title | e }} - {% endif %}{{ site.title | e }}</title>
              <link rel="icon" type="image/svg+xml" href="{{ base_url }}/favicon.svg">
            </head>
            <body>
              <header>
                <a href="{{ base_url }}/">{{ site.title }}</a>
                <nav>
                  <a href="{{ base_url }}/">Home</a>
                  <a href="{{ base_url }}/about/">About</a>
                </nav>
              </header>

            HTML
        end

        # Bare footer: semantic HTML only
        private def bare_footer_template : String
          <<-HTML
                <footer>
                  <p>Powered by Hwaro</p>
                </footer>
            </body>
            </html>
            HTML
        end

        # Bare section template
        private def bare_section_template : String
          <<-HTML
            {% include "header.html" %}
              <main>
                {% if page.title is present %}<h1>{{ page.title | e }}</h1>{% endif %}
                {{ content }}
                <ul>
                  {{ section.list }}
                </ul>
                {{ pagination }}
              </main>
            {% include "footer.html" %}
            HTML
        end

        # Bare 404 template
        private def bare_not_found_template : String
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

        # `page.html` renders `page.title` as `<h1>`, so bodies start at
        # level 2 to avoid a duplicate H1 (gh#525).
        private def index_content : String
          <<-CONTENT
            +++
            title = "Welcome to Hwaro"
            description = "A fresh static site generated by Hwaro."
            +++

            This is a fresh static site generated by [Hwaro](https://github.com/hahwul/hwaro).
            CONTENT
        end

        private def about_content : String
          <<-CONTENT
            +++
            title = "About"
            description = "A short introduction to this site."
            +++

            This is an about page.
            CONTENT
        end

        # `bare` ships no `[[taxonomies]]` block (see `config_content`),
        # so the default archetype intentionally omits the `tags` field
        # the base archetype includes — otherwise every page generated
        # via `hwaro new` would carry an empty `tags = []` line that
        # the runtime never reads.
        protected def default_archetype : String
          <<-MD
            +++
            title = "{{ title }}"
            date = "{{ date }}"
            draft = {{ draft }}
            description = ""
            +++

            MD
        end
      end
    end
  end
end
