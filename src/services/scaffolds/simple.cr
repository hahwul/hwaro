# Simple scaffold - basic pages structure
#
# This is the default scaffold that creates a minimal site with
# just a homepage and about page.

require "./base"

module Hwaro
  module Services
    module Scaffolds
      class Simple < Base
        def type : Config::Options::ScaffoldType
          Config::Options::ScaffoldType::Simple
        end

        def description : String
          "Homepage, about page, taxonomies (tags/categories/authors), and search"
        end

        def content_files(skip_taxonomies : Bool = false) : Hash(String, String)
          files = {} of String => String

          if skip_taxonomies
            files["index.md"] = index_content_simple
            files["about.md"] = about_content_simple
          else
            files["index.md"] = index_content
            files["about.md"] = about_content
          end

          files
        end

        # Ship the embedded Charter (Charis SIL) faces the inline
        # stylesheet's `@font-face` blocks reference, alongside the
        # inherited favicon.
        def static_files : Hash(String, String)
          super.merge(font_files)
        end

        def template_files(skip_taxonomies : Bool = false) : Hash(String, String)
          files = {
            "header.html"  => header_template,
            "footer.html"  => footer_template,
            "page.html"    => page_template,
            "section.html" => section_template,
            "404.html"     => not_found_template,
          }

          unless skip_taxonomies
            files["taxonomy.html"] = taxonomy_template
            files["taxonomy_term.html"] = taxonomy_term_template
          end

          files
        end

        def config_content(skip_taxonomies : Bool = false, multilingual_languages : Array(String) = [] of String) : String
          config = String.build do |str|
            # Site basics
            str << base_config

            # Content & Processing
            str << multilingual_config(multilingual_languages)
            str << plugins_config
            str << content_files_config
            str << highlight_config
            str << og_config
            str << search_config
            str << pagination_config
            str << series_config
            str << related_config
            str << taxonomies_config unless skip_taxonomies
            str << menus_config

            # SEO & Feeds
            str << sitemap_config
            str << robots_config
            str << llms_config
            str << feeds_config(feed_sections)

            # Optional features (commented out by default)
            str << permalinks_config
            str << auto_includes_config
            str << assets_config
            str << markdown_config
            str << content_new_config
            str << image_processing_config
            str << build_hooks_config
            str << pwa_config
            str << amp_config
            str << og_auto_image_config
            str << doctor_config
            str << deployment_config
          end
          config
        end

        # `[[menus.main]]` entries backing the overridden `navigation` below
        # (`{% for item in get_menu(name="main") %}`) — matches the two
        # links the scaffold's own content creates (index.md, about.md).
        # Add a third entry here (or register a page/section into "main"
        # from its own front matter with `menus = ["main"]`) to extend the
        # nav without touching a template.
        private def menu_entries_toml : String
          <<-TOML

            [[menus.main]]
            name = "Home"
            url = "/"
            weight = 1

            [[menus.main]]
            name = "About"
            url = "/about/"
            weight = 2

            TOML
        end

        # `--full-config` path: same entries as `minimal_config_content`
        # below, with a discoverability banner matching the rest of
        # `config_content`'s commented sections.
        protected def menus_config : String
          banner = <<-TOML

            # =============================================================================
            # Menus
            # =============================================================================
            # Named navigation menus, rendered in templates/header.html via
            # {% for item in get_menu(name="main") %}. Add/reorder entries
            # here, or register a page/section into "main" from its own
            # front matter with `menus = ["main"]` — no template edit
            # required either way.
            TOML
          banner + menu_entries_toml
        end

        # `hwaro init`'s DEFAULT path (no `--full-config`) and
        # `--minimal-config` both build on `minimal_config_content`, NOT
        # `config_content` — without this override, the overridden
        # `navigation`'s `get_menu(name="main")` would resolve against a
        # config with no `[[menus.*]]` at all, rendering an empty nav out
        # of the box.
        def minimal_config_content(skip_taxonomies : Bool = false, multilingual_languages : Array(String) = [] of String) : String
          super + menu_entries_toml
        end

        # Overrides Base#navigation: renders the "main" menu instead of two
        # hardcoded links, so adding a nav item no longer requires editing
        # this template.
        protected def navigation : String
          <<-NAV
            <nav>
              {% for item in get_menu(name="main") %}<a href="{{ item.href }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>{% endfor %}
            </nav>
            NAV
        end

        # Content files. Bodies intentionally start at level 2 — `page.html`
        # renders `page.title` as `<h1>`, so a body `# Title` would duplicate
        # it (gh#525).
        private def index_content : String
          <<-CONTENT
            +++
            title = "Welcome to Hwaro"
            description = "A fresh static site generated by Hwaro."
            tags = ["welcome", "getting-started"]
            +++

            Your site is live, and everything on this page is yours to rewrite. It is built with [Hwaro](https://github.com/hahwul/hwaro), a fast static site generator written in Crystal.

            ## Start here

            1. Edit `content/index.md` and make this page say something true.
            2. Add Markdown files under `content/` to grow the site.
            3. Run `hwaro serve` to preview changes with live reload.
            4. Run `hwaro build` when you are ready to publish.

            ---

            ## Where things live

            - `content/` holds every page as plain Markdown.
            - `templates/` shapes the HTML around it.
            - `static/` is copied through untouched.
            - `config.toml` turns features on and off.

            Readers can also browse this site by [Tags](/tags/) or [Categories](/categories/).
            CONTENT
        end

        private def index_content_simple : String
          <<-CONTENT
            +++
            title = "Welcome to Hwaro"
            description = "A fresh static site generated by Hwaro."
            +++

            Your site is live, and everything on this page is yours to rewrite. It is built with [Hwaro](https://github.com/hahwul/hwaro), a fast static site generator written in Crystal.

            ## Start here

            1. Edit `content/index.md` and make this page say something true.
            2. Add Markdown files under `content/` to grow the site.
            3. Run `hwaro serve` to preview changes with live reload.
            4. Run `hwaro build` when you are ready to publish.

            ---

            ## Where things live

            - `content/` holds every page as plain Markdown.
            - `templates/` shapes the HTML around it.
            - `static/` is copied through untouched.
            - `config.toml` turns features on and off.
            CONTENT
        end

        private def about_content : String
          <<-CONTENT
            +++
            title = "About"
            description = "A short introduction to this site and its author."
            tags = ["about"]
            categories = ["pages"]
            +++

            Hello! This site is built with [Hwaro](https://github.com/hahwul/hwaro), a static site generator written in Crystal.

            ## Make it yours

            Edit `content/about.md` and tell readers, in a paragraph or two:

            - who writes here,
            - what the site covers, and
            - how to reach you.

            One honest paragraph beats any template text. Delete the rest of this page once it's written.

            ## Adding pages to the menu

            The navigation is menu-driven: add a `[[menus.main]]` entry in `config.toml` (or set `menus = ["main"]` in a page's front matter) and the header picks it up. No template edits needed.
            CONTENT
        end

        private def about_content_simple : String
          <<-CONTENT
            +++
            title = "About"
            description = "A short introduction to this site and its author."
            +++

            Hello! This site is built with [Hwaro](https://github.com/hahwul/hwaro), a static site generator written in Crystal.

            ## Make it yours

            Edit `content/about.md` and tell readers, in a paragraph or two:

            - who writes here,
            - what the site covers, and
            - how to reach you.

            One honest paragraph beats any template text. Delete the rest of this page once it's written.
            CONTENT
        end
      end
    end
  end
end
