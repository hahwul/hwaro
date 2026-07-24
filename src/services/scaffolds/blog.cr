# Blog scaffold - blog-focused structure
#
# This scaffold creates a blog-oriented site with posts section,
# archives, tags, categories, and blog-specific templates.
# Features: fixed header with backdrop blur, search overlay (Cmd+K),
# polished typography and post card layout.

require "./base"

module Hwaro
  module Services
    module Scaffolds
      class Blog < Base
        def type : Config::Options::ScaffoldType
          Config::Options::ScaffoldType::Blog
        end

        def description : String
          "Blog-focused structure with posts, archives, and taxonomies"
        end

        protected def config_title : String
          "My Blog"
        end

        protected def config_description : String
          "Welcome to my personal blog powered by Hwaro."
        end

        # Limit the main feed to posts so the default/minimal config matches
        # the full-config feed (the homepage/about/archives are not posts).
        protected def feed_sections : Array(String)
          ["posts"]
        end

        def content_files(skip_taxonomies : Bool = false) : Hash(String, String)
          files = {} of String => String

          # Homepage (blog listing)
          files["index.md"] = index_content(skip_taxonomies)

          # About page
          files["about.md"] = about_content(skip_taxonomies)

          # Blog section
          files["posts/_index.md"] = posts_index_content

          # Sample posts
          files["posts/hello-world.md"] = sample_post_1(skip_taxonomies)
          files["posts/getting-started-with-hwaro.md"] = sample_post_2(skip_taxonomies)
          files["posts/markdown-tips.md"] = sample_post_3(skip_taxonomies)

          # Archives page
          files["archives.md"] = archives_content

          files
        end

        # Blog templates share the same chrome (header nav + search
        # overlay + container open) across page/section/post/archives/
        # taxonomy/404. We extract those into `partials/` so users editing
        # the nav only have to touch one file — and so 404/taxonomy don't
        # render as bare unstyled fragments outside the blog container,
        # which previously left dangling `</main></div>` from
        # `footer.html` (gh#fix-scaffold-broken-404-taxonomy).
        def template_files(skip_taxonomies : Bool = false) : Hash(String, String)
          files = {
            "header.html"          => header_template,
            "footer.html"          => footer_template,
            "partials/nav.html"    => blog_nav_html,
            "partials/search.html" => search_overlay_html("Search posts..."),
            "index.html"           => blog_home_template,
            "page.html"            => blog_page_template,
            "section.html"         => blog_section_template,
            "post.html"            => post_template(skip_taxonomies),
            "archives.html"        => archives_template,
            "404.html"             => blog_not_found_template,
          }

          unless skip_taxonomies
            files["taxonomy.html"] = blog_taxonomy_template
            files["taxonomy_term.html"] = blog_taxonomy_term_template
          end

          files
        end

        def config_content(skip_taxonomies : Bool = false, multilingual_languages : Array(String) = [] of String) : String
          config = String.build do |str|
            # Site basics
            str << base_config(config_title, config_description)

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

        # `[[menus.main]]` entries backing blog_nav_html's
        # `get_menu(name="main")` loop — matches the three links the
        # scaffold's own content creates (posts/_index.md, archives.md,
        # about.md). Add a fourth entry here (or register a page into
        # "main" from its own front matter with `menus = ["main"]`) to
        # extend the nav without touching a template.
        private def menu_entries_toml : String
          <<-TOML

            [[menus.main]]
            name = "Posts"
            url = "/posts/"
            weight = 1

            [[menus.main]]
            name = "Archives"
            url = "/archives/"
            weight = 2

            [[menus.main]]
            name = "About"
            url = "/about/"
            weight = 3

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
            # Named navigation menus, rendered by partials/nav.html via
            # {% for item in get_menu(name="main") %}. Add/reorder entries
            # here, or register a page/section into "main" from its own
            # front matter with `menus = ["main"]` — no template edit
            # required either way.
            TOML
          banner + menu_entries_toml
        end

        # `hwaro init`'s DEFAULT path (no `--full-config`) and
        # `--minimal-config` both build on `minimal_config_content`, NOT
        # `config_content` — without this override, blog_nav_html's
        # `get_menu(name="main")` would resolve against a config with no
        # `[[menus.*]]` at all, rendering an empty nav out of the box.
        def minimal_config_content(skip_taxonomies : Bool = false, multilingual_languages : Array(String) = [] of String) : String
          super + menu_entries_toml
        end

        # Override styles for blog - external CSS file
        protected def styles : String
          <<-CSS
            <link rel="stylesheet" href="{{ base_url }}/css/style.css">
            CSS
        end

        # Override header for blog - minimal, delegates layout to page
        # templates (Jinja2 syntax). `page.title` and `page.description`
        # are guarded so untitled pages don't render `<title> - Site</title>`
        # or an empty `<meta name="description">`.
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
              #{theme_head_script}
              {{ og_all_tags }}
              {{ canonical_tag }}
              {{ jsonld }}
              {{ hreflang_tags }}
              {{ pagination_seo_links }}
              #{styles}
              {# The syntax theme is inlined in css/style.css, so no highlight theme
                 stylesheet link is emitted here (sub-path safe). Highlight.js itself
                 still loads from the footer. #}
              {{ math_tags }}
              {{ mermaid_tags }}
              {{ auto_includes_css }}
            </head>
            <body data-section="{{ page.section }}">
              <a class="skip-link" href="#main">Skip to content</a>
            HTML
        end

        # Override footer for blog (Jinja2 syntax). The colophon carries the
        # site's own name — an imprint line, not a generator ad.
        protected def footer_template : String
          <<-HTML
                <footer class="blog-footer">
                  <p>{{ site.title | e }} · Powered by <a href="https://github.com/hahwul/hwaro">Hwaro</a></p>
                </footer>
              </main>
            </div>
            {{ highlight_js }}
            <script src="{{ base_url }}/js/search.js"></script>
            #{theme_toggle_script}
            {{ auto_includes_js }}
            </body>
            </html>
            HTML
        end

        def static_files : Hash(String, String)
          super.merge({
            "css/style.css" => css_content,
            "js/search.js"  => search_js_content,
          }).merge(font_files)
        end

        # Blog ships a `posts.md` archetype in addition to `default.md` so
        # `hwaro new posts/<slug>.md` auto-matches it (see
        # `Services::Creator#find_archetype`) and scaffolds blog-shaped
        # front matter (authors/categories) without the user having to
        # write the archetype themselves.
        def archetype_files : Hash(String, String)
          super.merge({
            "posts.md" => posts_archetype,
          })
        end

        protected def posts_archetype : String
          # Body intentionally empty — `post.html` renders the title as
          # `<h1>` already, so a `# {{ title }}` here would duplicate it
          # (gh#525).
          <<-MD
            +++
            title = "{{ title }}"
            date = "{{ date }}"
            draft = {{ draft }}
            description = "{{ description }}"
            authors = []
            categories = []
            tags = {{ tags }}
            +++

            MD
        end

        private def css_content : String
          <<-CSS
            #{font_face_css("../fonts")}

            #{design_root("--header-h: 52px;\n--content-max-w: 860px;")}

            *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

            body {
              font-family: var(--font-sans);
              font-size: var(--step-0);
              line-height: 1.7;
              color: var(--text);
              background: var(--bg);
              -webkit-font-smoothing: antialiased;
              -moz-osx-font-smoothing: grayscale;
            }

            ::selection { background: var(--selection); }

            /* Header — fixed glass bar over the page. */
            .blog-header {
              position: fixed;
              top: 0;
              left: 0;
              right: 0;
              height: var(--header-h);
              background: var(--glass);
              backdrop-filter: saturate(180%) blur(20px);
              -webkit-backdrop-filter: saturate(180%) blur(20px);
              border-bottom: 1px solid var(--border-subtle);
              display: flex;
              align-items: center;
              justify-content: center;
              padding: 0 1.5rem;
              z-index: 100;
            }

            .blog-header-inner {
              display: flex;
              align-items: center;
              width: 100%;
              max-width: var(--content-max-w);
            }

            .blog-header .logo {
              display: inline-flex;
              align-items: center;
              gap: 0.55rem;
              font-family: var(--font-serif);
              font-weight: 700;
              font-size: 1.15rem;
              color: var(--heading);
              text-decoration: none;
              letter-spacing: -0.01em;
              margin-right: 2.5rem;
            }

            /* The ember spark — the same diamond the favicon, dividers, and
               footer colophon share. */
            .blog-header .logo::before {
              content: "";
              width: 8px;
              height: 8px;
              flex: none;
              border-radius: 2px;
              transform: rotate(45deg);
              background: var(--spark);
            }

            .blog-header .logo:hover { color: var(--primary); }

            .blog-header nav {
              display: flex;
              gap: 1.25rem;
            }

            .blog-header nav a {
              color: var(--text-secondary);
              text-decoration: none;
              font-size: var(--step--1);
              font-weight: 400;
              padding: 0.25rem 0;
              border-bottom: 2px solid transparent;
              transition: color var(--transition), border-color var(--transition);
            }

            .blog-header nav a:hover { color: var(--text); }
            .blog-header nav a[aria-current="page"] { color: var(--heading); border-bottom-color: var(--primary); }

            .header-right {
              margin-left: auto;
              display: flex;
              align-items: center;
              gap: 1rem;
              padding-left: 1.25rem;
            }

            /* Language switcher (only rendered for multilingual sites). */
            .lang-switcher { display: flex; gap: 0.5rem; font-size: var(--step--1); }
            .lang-switcher a { color: var(--text-muted); text-decoration: none; padding: 0.15rem 0.4rem; border-radius: 4px; }
            .lang-switcher a:hover { color: var(--text); background: var(--bg-subtle); }
            .lang-switcher a[aria-current="true"] { color: var(--text); font-weight: 600; }

            /* Layout */
            .blog-container {
              padding-top: var(--header-h);
              min-height: 100vh;
            }

            .blog-main {
              max-width: var(--content-max-w);
              margin: 0 auto;
              padding: var(--space-6) var(--space-5);
            }

            .blog-main h1 {
              font-family: var(--font-serif);
              font-size: var(--step-4);
              font-weight: 700;
              margin: 0 0 0.5rem 0;
              letter-spacing: -0.022em;
              line-height: 1.15;
              color: var(--heading);
              text-wrap: balance;
            }

            /* Page title gets a short ember rule — the one mark every
               hwaro scaffold shares. */
            .blog-main > h1:first-child,
            .post-header h1 {
              position: relative;
              padding-bottom: 0.9rem;
            }

            .blog-main > h1:first-child::after,
            .post-header h1::after {
              content: "";
              position: absolute;
              left: 0;
              bottom: 0;
              width: 2.75rem;
              height: 3px;
              border-radius: 999px;
              background: linear-gradient(90deg, var(--rule-from), var(--rule-to));
            }

            .blog-main h2 {
              font-family: var(--font-serif);
              font-size: var(--step-2);
              font-weight: 700;
              margin: 2.5rem 0 0.75rem 0;
              letter-spacing: -0.012em;
              color: var(--heading);
              text-wrap: balance;
            }

            .blog-main h3 {
              font-family: var(--font-serif);
              font-size: var(--step-1);
              font-weight: 700;
              margin: 2rem 0 0.5rem 0;
              color: var(--heading);
            }

            .blog-main h4 {
              font-size: 0.95rem;
              font-weight: 600;
              margin: 1.5rem 0 0.5rem 0;
              color: var(--heading);
            }

            .blog-main p {
              margin-bottom: 1rem;
              line-height: 1.7;
            }

            .blog-main ul, .blog-main ol {
              margin-bottom: 1rem;
              padding-left: 1.5rem;
            }

            .blog-main li {
              margin-bottom: 0.35rem;
              line-height: 1.6;
            }

            /* Lists carry the ember in their punctuation: serif numerals on
               ordered lists, warmed discs on unordered ones. (Chrome-less
               lists — post feed, pagination, search — set list-style: none,
               so no marker is painted there.) */
            .blog-main ol > li::marker { font-family: var(--font-serif); font-weight: 700; color: var(--primary); font-variant-numeric: tabular-nums; }
            .blog-main ul > li::marker { color: var(--primary); }

            /* Thematic break as an ember spark on a fading hairline — the
               scaffold's asterism. */
            hr { border: none; height: 1px; margin: var(--space-7) 0; position: relative; overflow: visible; background: linear-gradient(90deg, transparent, var(--border), var(--border), transparent); }
            hr::after { content: ""; position: absolute; left: 50%; top: 50%; width: 7px; height: 7px; border-radius: 1px; transform: translate(-50%, -50%) rotate(45deg); background: var(--spark); box-shadow: 0 0 0 7px var(--bg); }

            /* Links: ember, with an underline that warms up on hover. */
            a {
              color: var(--primary);
              text-decoration: underline;
              text-decoration-color: color-mix(in srgb, var(--primary) 35%, transparent);
              text-underline-offset: 3px;
              transition: color var(--transition), text-decoration-color var(--transition);
            }
            a:hover { color: var(--primary-strong); text-decoration-color: currentColor; }
            .blog-header a, .skip-link, .post-title a, .tag,
            ul.section-list a, nav.pagination a, .search-result-item { text-decoration: none; }

            /* Code */
            code {
              background: var(--bg-code);
              padding: 0.15rem 0.4rem;
              border-radius: 4px;
              font-size: 0.85em;
              font-family: var(--font-mono);
              color: var(--text);
              overflow-wrap: break-word;
            }

            pre {
              padding: 1rem 1.25rem;
              border-radius: var(--radius);
              overflow-x: auto;
              border: 1px solid var(--border);
              margin: 1rem 0 1.5rem 0;
              line-height: 1.5;
              background: var(--bg-code);
              scrollbar-width: thin;
              scrollbar-color: var(--border) transparent;
            }

            /* Drop the highlight theme's own white background so syntax tokens
               sit on the warm code well instead of a white box. `pre code.hljs`
               (0,1,2) outranks the theme's `.hljs` (0,1,0). */
            pre code, pre code.hljs { background: transparent; padding: 0; font-size: 0.82rem; }
            #{highlight_theme_css}

            #{theme_toggle_css}

            /* Tables */
            table { width: 100%; border-collapse: collapse; margin: 1rem 0 1.5rem 0; font-size: 0.9rem; }
            th { text-align: left; padding: 0.6rem 0.75rem; border-bottom: 2px solid var(--border); font-weight: 600; font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.03em; color: var(--text-secondary); }
            td { padding: 0.5rem 0.75rem; border-bottom: 1px solid var(--border-subtle); vertical-align: top; }
            tbody tr { transition: background var(--transition); }
            @media (hover: hover) { tbody tr:hover { background: var(--primary-tint); } }

            /* Blockquote as pulled voice: a hanging ember quote instead of
               a fence, set a touch larger in the serif italic. */
            blockquote {
              font-family: var(--font-serif);
              font-style: italic;
              font-size: 1.06em;
              margin: var(--space-5) 0;
              padding: 0 0 0 var(--space-6);
              position: relative;
              color: var(--text-secondary);
            }

            blockquote::before {
              content: "\\201C";
              position: absolute;
              left: 0;
              top: -0.08em;
              font-size: 2.6em;
              line-height: 1;
              font-style: normal;
              color: var(--primary);
              opacity: 0.45;
            }

            blockquote p { margin-bottom: 0.35rem; }
            blockquote p:last-child { margin-bottom: 0; }

            /* Images */
            img { max-width: 100%; height: auto; border-radius: var(--radius-sm); outline: 1px solid var(--edge); outline-offset: -1px; }

            /* Home — a compact masthead: title, tagline, and the intro copy
               all live in the hero so the feed starts within reach. */
            .home-hero {
              padding: var(--space-6) 0 var(--space-5);
              margin-bottom: var(--space-5);
              border-bottom: 1px solid var(--border-subtle);
            }

            .home-title {
              position: relative;
              font-family: var(--font-serif);
              font-size: var(--step-4);
              font-weight: 700;
              line-height: 1.1;
              letter-spacing: -0.02em;
              margin: 0 0 1rem 0;
              padding-bottom: 0.9rem;
              color: var(--heading);
              text-wrap: balance;
            }

            /* The shared ember rule — so the homepage carries the same mark
               every other hwaro scaffold shows under its page title. */
            .home-title::after {
              content: "";
              position: absolute;
              left: 0;
              bottom: 0;
              width: 2.75rem;
              height: 3px;
              border-radius: 999px;
              background: linear-gradient(90deg, var(--rule-from), var(--rule-to));
            }

            .home-tagline {
              font-family: var(--font-serif);
              font-size: var(--step-1);
              line-height: 1.5;
              color: var(--text-secondary);
              margin: 0;
              max-width: 38rem;
            }

            .home-intro {
              color: var(--text-secondary);
              max-width: var(--measure);
              margin-top: 1.1rem;
            }
            .home-intro p { margin: 0.5em 0; }
            .home-intro p:last-child { margin-bottom: 0; }

            /* `.blog-main h2` (0,1,1) outranks a bare `.home-section-title`
               (0,1,0), so the eyebrow needs the element to keep its small
               uppercase sans look instead of inheriting the serif h2. */
            .blog-main h2.home-section-title {
              font-family: var(--font-sans);
              font-size: 0.78rem;
              font-weight: 600;
              text-transform: uppercase;
              letter-spacing: 0.08em;
              color: var(--text-muted);
              margin: 0 0 0.5rem 0;
            }

            .home-more {
              margin-top: 1.25rem;
              font-size: 0.9rem;
            }
            .home-more a {
              color: var(--primary);
              font-weight: 500;
              text-decoration: none;
            }
            .home-more a::after {
              content: "\\2192";
              display: inline-block;
              margin-left: 0.35rem;
              transition: transform var(--transition);
            }
            .home-more a:hover { color: var(--primary-strong); }
            .home-more a:hover::after { transform: translateX(3px); }

            /* Post list — an editorial ledger: tabular dates down a quiet
               left rail, serif titles and excerpts beside them. */
            .post-list { list-style: none; padding: 0; }

            .post-item {
              display: grid;
              grid-template-columns: 6.5rem 1fr;
              gap: var(--space-4);
              padding: var(--space-4) var(--space-3);
              margin-inline: calc(-1 * var(--space-3));
              border-radius: var(--radius-sm);
              border-bottom: 1px solid var(--border-subtle);
              transition: background var(--transition);
            }

            .post-item:last-child { border-bottom: none; }
            @media (hover: hover) { .post-item:hover { background: var(--primary-tint); } }

            .post-date {
              color: var(--text-muted);
              font-size: var(--step--1);
              font-variant-numeric: tabular-nums;
              letter-spacing: 0.02em;
              padding-top: 0.3rem;
            }

            /* `.blog-main h3` (0,1,1) would outrank a bare `.post-title`
               (0,1,0) and push feed titles below their date rail, so the
               feed/prose scopes are spelled out. */
            .blog-main .post-title, .post-title {
              font-family: var(--font-serif);
              margin: 0 0 0.3rem 0;
              font-size: var(--step-1);
              font-weight: 700;
              line-height: 1.3;
            }

            /* List titles read as ink; hover warms the color and slides an
               ember arrow in — no underline soup in the feed. */
            .post-title a {
              color: var(--heading);
              text-decoration: none;
              transition: color var(--transition);
            }

            .post-title a::after {
              content: "\\2192";
              display: inline-block;
              margin-left: 0.45rem;
              color: var(--primary);
              opacity: 0;
              transform: translateX(-4px);
              transition: opacity var(--transition), transform var(--transition);
            }

            .post-title a:hover { color: var(--primary); text-decoration: none; }
            @media (hover: hover) { .post-title a:hover::after { opacity: 1; transform: translateX(0); } }

            .post-meta {
              color: var(--text-muted);
              font-size: var(--step--1);
              font-variant-numeric: tabular-nums;
              letter-spacing: 0.02em;
              margin-bottom: 0.5rem;
              display: flex;
              align-items: center;
              gap: 0.75rem;
            }

            .post-excerpt {
              color: var(--text-secondary);
              font-size: 0.9rem;
              margin: 0;
              line-height: 1.5;
            }

            /* Post detail */
            .post-header {
              margin-bottom: 2rem;
              padding-bottom: 1.5rem;
              border-bottom: 1px solid var(--border-subtle);
            }

            .post-header h1 { margin-bottom: 0.75rem; }
            .post-meta-sep { color: var(--text-muted); }
            .post-tags { display: flex; flex-wrap: wrap; gap: 0.4rem; margin-top: 0.85rem; }
            .post-content { line-height: 1.8; }

            /* Prose holds the measure; the 860px container stays for code,
               tables, and images (wide code, narrow prose). */
            .post-content p, .post-content li { max-width: var(--measure); }

            .series-nav {
              margin-top: 2rem;
              padding: 0.75rem 1rem;
              border: 1px solid var(--border);
              border-radius: var(--radius-sm);
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 0.75rem;
              font-size: 0.85rem;
            }
            .series-nav .series-name {
              color: var(--text-muted);
              font-weight: 500;
            }
            .series-nav a { color: var(--primary); text-decoration: none; }
            .series-nav a:hover { text-decoration: underline; }

            .related-posts {
              margin-top: 2.5rem;
              padding-top: 1.5rem;
              border-top: 1px solid var(--border);
            }
            .related-title {
              font-size: 0.8rem;
              font-weight: 600;
              text-transform: uppercase;
              letter-spacing: 0.04em;
              color: var(--text-muted);
              margin: 0 0 0.75rem 0;
            }
            .related-posts ul { margin: 0; padding-left: 1.1rem; }
            .related-posts li { margin: 0.25rem 0; }
            .related-posts a { color: var(--primary); text-decoration: none; }
            .related-posts a:hover { text-decoration: underline; }

            /* Older/newer neighbours — a quiet card pair that warms on hover. */
            .post-nav {
              display: grid;
              grid-template-columns: 1fr 1fr;
              gap: var(--space-3);
              margin-top: var(--space-6);
              padding-top: var(--space-5);
              border-top: 1px solid var(--border-subtle);
            }
            .post-nav-link {
              display: flex;
              flex-direction: column;
              gap: 0.2rem;
              padding: var(--space-3) var(--space-4);
              border: 1px solid var(--border);
              border-radius: var(--radius-sm);
              text-decoration: none;
              transition: border-color var(--transition), background var(--transition);
            }
            .post-nav-prev { grid-column: 1; }
            .post-nav-next { grid-column: 2; text-align: right; }
            .post-nav-link:hover { border-color: color-mix(in srgb, var(--primary) 45%, transparent); background: var(--primary-tint); text-decoration: none; }
            .post-nav-label { font-size: 0.72rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: var(--text-muted); }
            .post-nav-title { font-family: var(--font-serif); font-weight: 700; color: var(--heading); }

            /* Section headings rely on scale and space, not fences — the
               ember punctuation (rule, sparks, markers) carries structure. */
            .post-content h2 { margin-top: 3rem; }

            /* Tags — quiet outline pills that take the ember tint on hover
               instead of flipping to a solid fill. */
            .tag {
              display: inline-flex;
              align-items: center;
              background: transparent;
              padding: 0.15rem 0.7rem;
              border-radius: 999px;
              font-size: 0.75rem;
              color: var(--text-secondary);
              text-decoration: none;
              border: 1px solid var(--border);
              transition: color var(--transition), border-color var(--transition), background var(--transition), transform 0.1s var(--ease-out);
            }

            .tag:hover {
              background: var(--primary-tint);
              color: var(--primary-strong);
              border-color: color-mix(in srgb, var(--primary) 45%, transparent);
              text-decoration: none;
            }

            .tag:active { transform: scale(0.96); }

            /* Section list */
            ul.section-list { list-style: none; padding: 0; }

            ul.section-list li {
              margin-bottom: 0.5rem;
              padding: 0.75rem 1rem;
              background: var(--bg-subtle);
              border-radius: var(--radius-sm);
              border: 1px solid var(--border-subtle);
              transition: border-color var(--transition);
            }

            ul.section-list li:hover { border-color: var(--border); }
            ul.section-list li a { font-weight: 500; color: var(--primary); }

            .taxonomy-desc { color: var(--text-muted); margin-bottom: 1.5rem; }

            /* Pagination */
            nav.pagination { margin: 1.5rem 0; }
            nav.pagination .pagination-list { list-style: none; display: flex; gap: 0.5rem; flex-wrap: wrap; align-items: center; }
            nav.pagination a { display: inline-block; padding: 0.25rem 0.55rem; border-radius: var(--radius-sm); border: 1px solid var(--border-subtle); color: var(--text-secondary); text-decoration: none; }
            nav.pagination a:hover { color: var(--primary); border-color: var(--primary); }
            .pagination-current span { display: inline-block; padding: 0.25rem 0.55rem; border-radius: var(--radius-sm); border: 1px solid var(--primary); background: var(--primary-tint); color: var(--primary); }
            .pagination-disabled span { display: inline-block; padding: 0.25rem 0.55rem; border-radius: var(--radius-sm); border: 1px solid var(--border-subtle); color: var(--text-muted); opacity: 0.5; }

            /* Archives — the same date-rail ledger rhythm as the home feed,
               tightened for scanning whole years at a glance. */
            .archive-list { list-style: none; padding: 0; margin: var(--space-5) 0; }
            .archive-entry {
              display: grid;
              grid-template-columns: 6.5rem 1fr;
              gap: var(--space-4);
              padding: 0.55rem var(--space-3);
              margin-inline: calc(-1 * var(--space-3));
              border-radius: var(--radius-sm);
              border-bottom: 1px solid var(--border-subtle);
              transition: background var(--transition);
            }
            .archive-entry:first-child { border-top: 1px solid var(--border-subtle); }
            @media (hover: hover) { .archive-entry:hover { background: var(--primary-tint); } }
            .archive-entry time {
              color: var(--text-muted);
              font-size: var(--step--1);
              font-variant-numeric: tabular-nums;
              letter-spacing: 0.02em;
              padding-top: 0.15rem;
            }
            .archive-entry a {
              font-family: var(--font-serif);
              font-weight: 500;
              color: var(--text);
              text-decoration: none;
              transition: color var(--transition);
            }
            .archive-entry a:hover { color: var(--primary); }

            /* Footer as colophon: a centered spark over a serif italic
               imprint line, like the last page of a well-set book. */
            .blog-footer {
              margin-top: var(--space-8);
              padding-bottom: var(--space-5);
              text-align: center;
              color: var(--text-muted);
              font-size: var(--step--1);
            }
            .blog-footer::before {
              content: "";
              display: block;
              width: 7px;
              height: 7px;
              margin: 0 auto var(--space-4);
              border-radius: 1px;
              transform: rotate(45deg);
              background: var(--spark);
            }
            .blog-footer p { font-family: var(--font-serif); font-style: italic; margin: 0; }
            .blog-footer a { color: inherit; text-decoration: none; transition: color var(--transition); }
            .blog-footer a:hover { color: var(--primary); }

            /* Search trigger */
            .search-trigger {
              display: flex;
              align-items: center;
              gap: 0.4rem;
              padding: 0.3rem 0.6rem;
              border: 1px solid var(--border);
              border-radius: var(--radius-sm);
              background: var(--bg);
              color: var(--text-secondary);
              font-size: 0.8rem;
              cursor: pointer;
              transition: all var(--transition);
              font-family: inherit;
            }

            .search-trigger:hover { border-color: var(--text-muted); color: var(--text); }

            .search-trigger kbd {
              font-size: 0.65rem;
              padding: 0.1rem 0.35rem;
              border: 1px solid var(--border);
              border-radius: 3px;
              background: var(--bg-raised);
              box-shadow: 0 1px 0 var(--border);
              color: var(--text-muted);
              font-family: inherit;
              line-height: 1.4;
            }

            /* Search overlay */
            .search-overlay {
              display: none;
              position: fixed;
              inset: 0;
              background: var(--scrim);
              backdrop-filter: blur(4px);
              -webkit-backdrop-filter: blur(4px);
              z-index: 200;
              justify-content: center;
              padding-top: 12vh;
            }

            .search-overlay.active { display: flex; }

            .search-modal {
              width: 560px;
              max-width: 90vw;
              max-height: 70vh;
              background: color-mix(in srgb, var(--bg-raised) 88%, transparent);
              backdrop-filter: saturate(180%) blur(24px);
              -webkit-backdrop-filter: saturate(180%) blur(24px);
              border: 1px solid var(--border-subtle);
              border-radius: var(--radius);
              box-shadow: var(--shadow-lg);
              display: flex;
              flex-direction: column;
              overflow: hidden;
              align-self: flex-start;
            }
            @supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) { .search-modal { background: var(--bg-raised); } }

            /* The palette settles into place when it opens. */
            @media (prefers-reduced-motion: no-preference) {
              .search-overlay.active { transition: opacity 0.15s var(--ease-out); }
              .search-overlay.active .search-modal { transition: opacity 0.18s var(--ease-out), transform 0.18s var(--ease-out); }
              @starting-style {
                .search-overlay.active { opacity: 0; }
                .search-overlay.active .search-modal { opacity: 0; transform: translateY(-8px) scale(0.985); }
              }
            }

            .search-input-wrap {
              display: flex;
              align-items: center;
              gap: 0.6rem;
              padding: 0.75rem 1rem;
              border-bottom: 1px solid var(--border-subtle);
            }

            .search-input-wrap svg { flex-shrink: 0; color: var(--text-muted); }

            :focus-visible { outline: 2px solid var(--primary); outline-offset: 2px; }
            .search-input-wrap:focus-within { outline: 2px solid var(--primary); outline-offset: 2px; }
            .skip-link { position: absolute; top: -100px; left: 0; background: var(--primary); color: var(--bg); padding: 0.5rem 1rem; z-index: 1000; }
            .skip-link:focus { top: 0; }
            .search-input-wrap input {
              flex: 1;
              border: none;
              outline: none;
              font-size: 1rem;
              font-family: inherit;
              color: var(--text);
              background: transparent;
            }

            .search-input-wrap input::placeholder { color: var(--text-muted); }

            .search-input-wrap kbd {
              font-size: 0.65rem;
              padding: 0.15rem 0.4rem;
              border: 1px solid var(--border);
              border-radius: 3px;
              background: var(--bg-raised);
              box-shadow: 0 1px 0 var(--border);
              color: var(--text-muted);
              font-family: inherit;
              cursor: pointer;
              line-height: 1.4;
            }

            .search-results { overflow-y: auto; padding: 0.5rem; }

            .search-result-item {
              display: block;
              padding: 0.6rem 0.75rem;
              border-radius: var(--radius-sm);
              text-decoration: none;
              color: var(--text);
              cursor: pointer;
              transition: background 0.1s;
            }

            .search-result-item:hover, .search-result-item.active { background: var(--bg-subtle); text-decoration: none; }
            .search-result-item .search-result-title { font-weight: 500; font-size: 0.9rem; margin-bottom: 0.15rem; }
            .search-result-item .search-result-snippet { font-size: 0.8rem; color: var(--text-secondary); line-height: 1.4; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
            .search-result-item .search-result-snippet mark { background: color-mix(in srgb, var(--primary) 15%, transparent); color: var(--primary-strong); border-radius: 2px; padding: 0 1px; }
            .search-no-results { padding: 2rem 1rem; text-align: center; color: var(--text-muted); font-size: 0.9rem; }

            .search-hint {
              padding: 0.5rem 0.75rem;
              display: flex;
              gap: 1rem;
              justify-content: center;
              border-top: 1px solid var(--border-subtle);
              color: var(--text-muted);
              font-size: 0.7rem;
            }

            .search-hint kbd {
              font-size: 0.65rem;
              padding: 0 0.3rem;
              border: 1px solid var(--border);
              border-radius: 3px;
              background: var(--bg-raised);
              box-shadow: 0 1px 0 var(--border);
              font-family: inherit;
              line-height: 1.4;
            }

            /* Search trigger press feedback */
            .search-trigger { transition: border-color var(--transition), color var(--transition), transform 0.1s var(--ease-out); }
            .search-trigger:active { transform: scale(0.96); }

            /* Reading progress — a 2px ember thread across the top of post
               pages, driven entirely by CSS scroll-driven animation. Browsers
               without animation-timeline (and reduced-motion readers) simply
               never see it. */
            .reading-progress { display: none; }
            @supports (animation-timeline: scroll()) {
              @media (prefers-reduced-motion: no-preference) {
                .reading-progress {
                  display: block;
                  position: fixed;
                  top: 0;
                  left: 0;
                  right: 0;
                  height: 2px;
                  z-index: 110;
                  transform-origin: 0 50%;
                  background: linear-gradient(90deg, var(--rule-from), var(--rule-to));
                  animation: reading-progress linear both;
                  animation-timeline: scroll(root);
                }
                @keyframes reading-progress {
                  from { transform: scaleX(0); }
                  to { transform: scaleX(1); }
                }
              }
            }

            /* Responsive — the type scale is fluid, so only the frame
               needs to adapt. The date rails stack above their entries. */
            @media (max-width: 640px) {
              .blog-header nav { display: none; }
              .blog-main { padding: var(--space-5) var(--space-4); }
              .home-hero { padding-top: var(--space-5); }
              .post-item, .archive-entry { grid-template-columns: 1fr; gap: 0.2rem; }
              .post-date, .archive-entry time { padding-top: 0; }
              .post-nav { grid-template-columns: 1fr; }
              .post-nav-next { grid-column: auto; text-align: left; }
            }

            @media (prefers-reduced-motion: reduce) {
              *, *::before, *::after { transition-duration: 0.01ms !important; animation-duration: 0.01ms !important; animation-iteration-count: 1 !important; }
            }
            CSS
        end

        private def search_js_content : String
          <<-'JS'
            (function () {
              var searchData = null;
              var activeIndex = -1;
              var overlay = document.getElementById('searchOverlay');
              var input = document.getElementById('searchInput');
              var resultsEl = document.getElementById('searchResults');

              function loadSearchData(cb) {
                if (searchData) return cb(searchData);
                var link = document.querySelector('link[rel="stylesheet"][href*="/css/"]');
                var path = link ? new URL(link.href, document.baseURI).pathname : '/css/';
                var searchUrl = path.substring(0, path.indexOf('/css/')) + '/search.json';
                fetch(searchUrl)
                  .then(function (r) { return r.json(); })
                  .then(function (data) { searchData = data; cb(data); })
                  .catch(function () { searchData = []; cb([]); });
              }

              window.openSearch = function () {
                overlay.classList.add('active');
                input.value = '';
                resultsEl.innerHTML = '';
                activeIndex = -1;
                input.focus();
                loadSearchData(function () {});
              };

              window.closeSearch = function () {
                overlay.classList.remove('active');
                activeIndex = -1;
              };

              document.addEventListener('keydown', function (e) {
                if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
                  e.preventDefault();
                  if (overlay.classList.contains('active')) {
                    closeSearch();
                  } else {
                    openSearch();
                  }
                }
                if (e.key === 'Escape' && overlay.classList.contains('active')) {
                  closeSearch();
                }
              });

              function escapeHtml(s) {
                var d = document.createElement('div');
                d.textContent = s;
                return d.innerHTML;
              }

              function highlightMatch(text, query) {
                if (!query) return escapeHtml(text);
                var escaped = query.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
                var re = new RegExp('(' + escaped + ')', 'gi');
                return escapeHtml(text).replace(re, '<mark>$1</mark>');
              }

              function getSnippet(content, query) {
                var lower = content.toLowerCase();
                var idx = lower.indexOf(query.toLowerCase());
                var start = Math.max(0, idx - 60);
                var end = Math.min(content.length, idx + query.length + 100);
                var snippet = content.substring(start, end).replace(/\\s+/g, ' ').trim();
                if (start > 0) snippet = '...' + snippet;
                if (end < content.length) snippet = snippet + '...';
                return snippet;
              }

              function search(query) {
                if (!searchData || !query.trim()) {
                  resultsEl.innerHTML = '';
                  activeIndex = -1;
                  return;
                }
                var q = query.trim().toLowerCase();
                var pageLang = document.documentElement.lang || '';
                var results = [];
                for (var i = 0; i < searchData.length; i++) {
                  var item = searchData[i];
                  if (pageLang && item.lang && item.lang !== pageLang) continue;
                  var titleIdx = item.title.toLowerCase().indexOf(q);
                  var contentIdx = item.content.toLowerCase().indexOf(q);
                  if (titleIdx !== -1 || contentIdx !== -1) {
                    var score = titleIdx !== -1 ? 100 - titleIdx : contentIdx;
                    results.push({ item: item, score: score });
                  }
                }
                results.sort(function (a, b) { return b.score - a.score; });
                results = results.slice(0, 10);

                if (results.length === 0) {
                  resultsEl.innerHTML = '<div class="search-no-results">No results for "' + escapeHtml(query) + '"</div>';
                  activeIndex = -1;
                  return;
                }

                var html = '';
                for (var j = 0; j < results.length; j++) {
                  var r = results[j].item;
                  var snippet = getSnippet(r.content, query.trim());
                  html += '<a class="search-result-item" href="' + encodeURI(r.url) + '" data-index="' + j + '">'
                    + '<div class="search-result-title">' + highlightMatch(r.title, query.trim()) + '</div>'
                    + '<div class="search-result-snippet">' + highlightMatch(snippet, query.trim()) + '</div>'
                    + '</a>';
                }
                html += '<div class="search-hint"><span><kbd>&uarr;</kbd><kbd>&darr;</kbd> navigate</span><span><kbd>Enter</kbd> open</span><span><kbd>ESC</kbd> close</span></div>';
                resultsEl.innerHTML = html;
                activeIndex = -1;
              }

              function updateActive() {
                var items = resultsEl.querySelectorAll('.search-result-item');
                for (var i = 0; i < items.length; i++) {
                  items[i].classList.toggle('active', i === activeIndex);
                }
                if (activeIndex >= 0 && items[activeIndex]) {
                  items[activeIndex].scrollIntoView({ block: 'nearest' });
                }
              }

              if (input) {
                input.addEventListener('input', function () {
                  loadSearchData(function () { search(input.value); });
                });

                input.addEventListener('keydown', function (e) {
                  var items = resultsEl.querySelectorAll('.search-result-item');
                  var count = items.length;
                  if (e.key === 'ArrowDown') {
                    e.preventDefault();
                    activeIndex = (activeIndex + 1) % count;
                    updateActive();
                  } else if (e.key === 'ArrowUp') {
                    e.preventDefault();
                    activeIndex = (activeIndex - 1 + count) % count;
                    updateActive();
                  } else if (e.key === 'Enter') {
                    e.preventDefault();
                    if (activeIndex >= 0 && items[activeIndex]) {
                      window.location.href = items[activeIndex].href;
                    } else if (items.length > 0) {
                      window.location.href = items[0].href;
                    }
                  }
                });
              }
            })();
            JS
        end

        # Blog header navigation HTML
        private def blog_nav_html : String
          <<-HTML
            <header class="blog-header">
              <div class="blog-header-inner">
                <a href="{{ base_url }}{{ lang_prefix }}/" class="logo">{{ site.title | e }}</a>
                <nav>
                  <!-- Add/reorder links via [[menus.main]] in config.toml, or
                       register a page/section into "main" from its own front
                       matter with `menus = ["main"]` — no template edit
                       required either way. -->
                  {% for item in get_menu(name="main") %}<a href="{{ item.href }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>{% endfor %}
                </nav>
                <div class="header-right">
                  {% if page.translations | length > 0 %}
                  <nav class="lang-switcher" aria-label="Language">
                    {% for t in page.translations %}
                    <a href="{{ base_url }}{{ t.url }}" hreflang="{{ t.code }}"{% if t.is_current %} aria-current="true"{% endif %}>{{ t.code | upper }}</a>
                    {% endfor %}
                  </nav>
                  {% endif %}
                  <button class="search-trigger" onclick="openSearch()" title="Search">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
                    <span>Search</span>
                    <kbd>&#8984;K</kbd>
                  </button>
                  #{theme_toggle_html}
                </div>
              </div>
            </header>
            HTML
        end

        # Blog-specific page template (Jinja2 syntax). All blog templates
        # share the same chrome (nav, search overlay, container open) via
        # `partials/`, so this template only carries the body — and
        # `footer.html` closes the container the same way for all of
        # them. That symmetry is what keeps 404/taxonomy from emitting
        # dangling `</main></div>` like the previous version did.
        # Dedicated homepage layout. The engine routes the root index page
        # to `index.html` when it exists (see `determine_template`), so the
        # landing page gets a proper hero + recent-posts feed instead of the
        # bare `page.html` body that left the blog home feeling unfinished.
        private def blog_home_template : String
          <<-HTML
            {% include "header.html" %}
            {% include "partials/nav.html" %}
            {% include "partials/search.html" %}
            <div class="blog-container">
              <main id="main" class="blog-main">
                <header class="home-hero">
                  <h1 class="home-title">{{ site.title | e }}</h1>
                  {% if site.description %}<p class="home-tagline">{{ site.description | e }}</p>{% endif %}
                  {% if content %}<div class="home-intro">{{ content }}</div>{% endif %}
                </header>
                <section class="home-latest" aria-labelledby="home-latest-title">
                  <h2 id="home-latest-title" class="home-section-title">Latest posts</h2>
                  <ul class="post-list">
                    {% for p in site.pages | selectattr("date") | rejectattr("is_index") | rejectattr("draft") | selectattr("language", "equalto", page_language) | sort(attribute="date", reverse=true) %}
                    {% if loop.index <= 5 %}
                      <li class="post-item">
                        <time class="post-date" datetime="{{ p.date }}">{{ p.date }}</time>
                        <div class="post-item-body">
                          <h3 class="post-title"><a href="{{ base_url }}{{ p.url }}">{{ p.title | e }}</a></h3>
                          {% if p.description %}<p class="post-excerpt">{{ p.description | e }}</p>{% endif %}
                        </div>
                      </li>
                    {% endif %}
                    {% endfor %}
                  </ul>
                  <p class="home-more"><a href="{{ base_url }}{{ lang_prefix }}/posts/">View all posts</a></p>
                </section>
            {% include "footer.html" %}
            HTML
        end

        private def blog_page_template : String
          <<-HTML
            {% include "header.html" %}
            {% include "partials/nav.html" %}
            {% include "partials/search.html" %}
            <div class="blog-container">
              <main id="main" class="blog-main">
                {% if page.title is present %}<h1>{{ page.title | e }}</h1>{% endif %}
                {{ content }}
            {% include "footer.html" %}
            HTML
        end

        # Blog-specific section template (Jinja2 syntax)
        private def blog_section_template : String
          <<-HTML
            {% include "header.html" %}
            {% include "partials/nav.html" %}
            {% include "partials/search.html" %}
            <div class="blog-container">
              <main id="main" class="blog-main">
                {% if page.title is present %}<h1>{{ page.title | e }}</h1>{% endif %}
                {{ content }}

                <ul class="section-list">
                  {{ section.list }}
                </ul>
                {{ pagination }}
            {% include "footer.html" %}
            HTML
        end

        # Blog-specific post template (Jinja2 syntax)
        #
        # The tag pills are omitted for `--skip-taxonomies` sites so posts
        # never link to `/tags/…` pages that don't exist. `get_taxonomy_url`
        # handles term slugs, base_url, and language prefixes.
        private def post_template(skip_taxonomies : Bool = false) : String
          tags_block = skip_taxonomies ? "" : <<-TAGS

            {% if page.tags %}
            <div class="post-tags">
              {% for t in page.tags %}<a class="tag" href="{{ get_taxonomy_url(kind='tags', term=t) }}">{{ t | e }}</a>{% endfor %}
            </div>
            {% endif %}
            TAGS
          <<-HTML
            {% include "header.html" %}
            {% include "partials/nav.html" %}
            {% include "partials/search.html" %}
            <div class="reading-progress" aria-hidden="true"></div>
            <div class="blog-container">
              <main id="main" class="blog-main">
                <article class="post">
                  <header class="post-header">
                    <h1>{{ page.title | e }}</h1>
                    <div class="post-meta">
                      <time datetime="{{ page.date }}">{{ page.date }}</time>
                      {% if page.reading_time %}<span class="post-meta-sep">·</span> <span class="post-reading-time">{{ page.reading_time }} min read</span>{% endif %}
                    </div>#{tags_block}
                  </header>
                  <div class="post-content">
                    {{ content }}
                  </div>

                  {# Series nav walks `series_pages` (ordered by series_weight)
                     via the 1-based `series_index`, NOT page.lower/page.higher
                     — those are the section's flat date-ordered neighbours, so
                     they ordered chapters by date and even linked non-series
                     posts. #}
                  {# Guard on `series_pages` too: with [series] disabled (or a
                     single-post series) the engine never populates series_pages,
                     so without this the nav rendered as an orphan box carrying
                     only the series name and no prev/next links. #}
                  {% if page.series and page.series_pages %}
                  <nav class="series-nav" aria-label="Series navigation">
                    {% if page.series_index > 1 %}
                    <a href="{{ base_url }}{{ page.series_pages[page.series_index - 2].url }}" class="series-prev" rel="prev">← {{ page.series_pages[page.series_index - 2].title | e }}</a>
                    {% endif %}
                    <span class="series-name">{{ page.series | e }}</span>
                    {% if page.series_index < (page.series_pages | length) %}
                    <a href="{{ base_url }}{{ page.series_pages[page.series_index].url }}" class="series-next" rel="next">{{ page.series_pages[page.series_index].title | e }} →</a>
                    {% endif %}
                  </nav>
                  {% endif %}

                  {# Related posts (shown when [related] is enabled and matches exist). #}
                  {% if page.related_posts %}
                  <aside class="related-posts" aria-label="Related posts">
                    <h2 class="related-title">Related posts</h2>
                    <ul>
                      {% for r in page.related_posts %}
                      <li><a href="{{ base_url }}{{ r.url }}">{{ r.title | e }}</a></li>
                      {% endfor %}
                    </ul>
                  </aside>
                  {% endif %}

                  {# Older/newer neighbours. page.lower/page.higher are the
                     flat reading chain, which for a date-sorted feed runs
                     newest to oldest: lower is the newer post, higher the
                     older one. Both links are guarded to stay inside this
                     post's section and to skip _index. #}
                  {% if (page.lower and page.lower.section == page.section and not page.lower.is_index) or (page.higher and page.higher.section == page.section and not page.higher.is_index) %}
                  <nav class="post-nav" aria-label="More posts">
                    {% if page.lower and page.lower.section == page.section and not page.lower.is_index %}
                    <a class="post-nav-link post-nav-prev" href="{{ base_url }}{{ page.lower.url }}" rel="prev">
                      <span class="post-nav-label">Newer</span>
                      <span class="post-nav-title">{{ page.lower.title | e }}</span>
                    </a>
                    {% endif %}
                    {% if page.higher and page.higher.section == page.section and not page.higher.is_index %}
                    <a class="post-nav-link post-nav-next" href="{{ base_url }}{{ page.higher.url }}" rel="next">
                      <span class="post-nav-label">Older</span>
                      <span class="post-nav-title">{{ page.higher.title | e }}</span>
                    </a>
                    {% endif %}
                  </nav>
                  {% endif %}
                </article>
            {% include "footer.html" %}
            HTML
        end

        # Blog-specific 404 template — wraps the message in the same
        # blog-container/blog-main scaffolding the rest of the site uses,
        # so the page actually shows the nav and the closing tags from
        # `footer.html` line up. Previously this used the generic
        # `not_found_template` (`<main class="site-main">`) which left
        # an unmatched `</main></div>` after the footer ran.
        private def blog_not_found_template : String
          <<-HTML
            {% include "header.html" %}
            {% include "partials/nav.html" %}
            {% include "partials/search.html" %}
            <div class="blog-container">
              <main id="main" class="blog-main">
                <h1>404 Not Found</h1>
                <p>The page you are looking for does not exist.</p>
                <p><a href="{{ base_url }}{{ lang_prefix }}/">Return to home</a></p>
            {% include "footer.html" %}
            HTML
        end

        # Blog-specific taxonomy template — wraps the term list in the
        # same chrome as page.html so the footer's closing tags match.
        private def blog_taxonomy_template : String
          <<-HTML
            {% include "header.html" %}
            {% include "partials/nav.html" %}
            {% include "partials/search.html" %}
            <div class="blog-container">
              <main id="main" class="blog-main">
                <h1>{{ page.title | e }}</h1>
                <p class="taxonomy-desc">Browse all terms in this taxonomy:</p>
                {{ content }}
            {% include "footer.html" %}
            HTML
        end

        private def blog_taxonomy_term_template : String
          <<-HTML
            {% include "header.html" %}
            {% include "partials/nav.html" %}
            {% include "partials/search.html" %}
            <div class="blog-container">
              <main id="main" class="blog-main">
                <h1>{{ page.title | e }}</h1>
                <p class="taxonomy-desc">Posts tagged with this term:</p>
                {{ content }}
            {% include "footer.html" %}
            HTML
        end

        # Override navigation (not used directly - kept for base class
        # compatibility). Mirrors blog_nav_html's menu-driven nav so this
        # stays in sync with the real header if anything ever calls it.
        protected def navigation : String
          <<-NAV
            <nav>
              {% for item in get_menu(name="main") %}<a href="{{ item.href }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>{% endfor %}
            </nav>
            NAV
        end

        # Generates a sample post date relative to today, so a freshly
        # scaffolded site never shows a stale "last post was in 2024" feel.
        private def sample_date(offset_days : Int32) : String
          (Time.utc - offset_days.days).to_s("%Y-%m-%d")
        end

        # Content files
        # `title` may be `nil` to skip the field entirely — the homepage
        # uses that path so its `<h1>` doesn't read "Home", and the
        # `<title>` tag falls back to `site.title` via the header guard.
        private def render_page(
          title : String?,
          body : String,
          skip_taxonomies : Bool,
          date : String? = nil,
          description : String? = nil,
          tags : Array(String)? = nil,
          categories : Array(String)? = nil,
          authors : Array(String)? = nil,
        ) : String
          String.build do |str|
            str << "+++\n"
            str << "title = \"#{title}\"\n" if title
            str << "date = \"#{date}\"\n" if date
            unless skip_taxonomies
              str << "tags = #{tags.inspect}\n" if tags
              str << "categories = #{categories.inspect}\n" if categories
              str << "authors = #{authors.inspect}\n" if authors
            end
            str << "description = \"#{description}\"\n" if description
            str << "+++\n\n"
            str << body
          end
        end

        private def index_content(skip_taxonomies : Bool) : String
          body = String.build do |str|
            # The homepage hero already shows the site title + description,
            # so this intro stays short and just points readers toward the
            # taxonomy archives. The recent-posts feed is rendered by the
            # `index.html` template, not by this content.
            if skip_taxonomies
              str << "A blog powered by [Hwaro](https://github.com/hahwul/hwaro), a fast and lightweight static site generator.\n"
            else
              str << "A blog powered by [Hwaro](https://github.com/hahwul/hwaro). Browse posts by [Tags](/tags/), [Categories](/categories/), or [Authors](/authors/).\n"
            end
          end

          # Title intentionally empty so the homepage doesn't render an
          # `<h1>Home</h1>` that just duplicates the site logo (the
          # template guards the H1 with `is present`). The `<title>`
          # tag falls back to `site.title` via the same guard in
          # `header.html`. Note: omitting the field entirely would
          # make the runtime default it to "Untitled", which `is
          # present` reads as truthy and re-introduces the H1 — so we
          # write the empty value explicitly.
          render_page(
            title: "",
            body: body,
            skip_taxonomies: skip_taxonomies,
            description: "A blog powered by Hwaro: posts, archives, and tags.",
            tags: ["home"]
          )
        end

        private def about_content(skip_taxonomies : Bool) : String
          body = <<-BODY
            Welcome! This blog runs on [Hwaro](https://github.com/hahwul/hwaro), a static site generator written in Crystal.

            ## Make it yours

            Edit `content/about.md` and introduce yourself in a paragraph or two: who writes here, what you write about, and where readers can reach you. One honest paragraph beats any template text.
            BODY

          render_page(
            title: "About",
            body: body,
            skip_taxonomies: skip_taxonomies,
            description: "A short introduction to this blog and its author.",
            tags: ["about"],
            categories: ["pages"]
          )
        end

        private def posts_index_content : String
          <<-CONTENT
            +++
            title = "Posts"
            description = "An index of every published blog post."
            # Child pages of this section render with templates/post.html
            # (article layout with publish date, meta, and series navigation).
            page_template = "post"
            +++

            Browse all blog posts below.
            CONTENT
        end

        private def sample_post_1(skip_taxonomies : Bool) : String
          body = <<-BODY
            Every blog starts somewhere, and this one starts here. The site around this post is powered by Hwaro, a fast static site generator written in Crystal.

            ## What the samples show

            Three sample posts (including this one) demonstrate how dates, tags, and categories flow through the homepage feed, the archives, and the taxonomy pages. When you're ready to write for real:

            - Delete the samples under `content/posts/`.
            - Run `hwaro new posts/my-first-post.md` to start a post; the archetype fills in the front matter.
            - Publish with `hwaro build`.

            The feed and archives pick up new posts automatically. Nothing else to wire up.
            BODY

          render_page(
            title: "Hello World",
            body: body,
            skip_taxonomies: skip_taxonomies,
            date: sample_date(10),
            description: "Where this blog starts, and how to make it yours.",
            tags: ["introduction", "hello"],
            categories: ["general"],
            authors: ["admin"]
          )
        end

        private def sample_post_2(skip_taxonomies : Bool) : String
          body = <<-BODY
            In this post, I'll walk you through the basics of setting up and using Hwaro.

            ## Installation

            First, make sure you have Crystal installed. Then:

            ```bash
            git clone https://github.com/hahwul/hwaro
            cd hwaro
            shards build
            ```

            ## Creating Your First Site

            ```bash
            hwaro init my-blog --scaffold blog
            cd my-blog
            hwaro serve
            ```

            That's it! Your blog is now running at `http://localhost:3000`.

            ## Next Steps

            - Customize your templates in the `templates/` directory
            - Add new posts in `content/posts/`
            - Configure your site in `config.toml`
            BODY

          render_page(
            title: "Getting Started with Hwaro",
            body: body,
            skip_taxonomies: skip_taxonomies,
            date: sample_date(5),
            description: "A beginner's guide to building websites with Hwaro.",
            tags: ["tutorial", "getting-started", "hwaro"],
            categories: ["tutorials"],
            authors: ["admin"]
          )
        end

        private def sample_post_3(skip_taxonomies : Bool) : String
          body = <<-BODY
            Hwaro uses Markdown for content. Here are some useful formatting tips.

            ## Text Formatting

            - **Bold text** using `**bold**`
            - *Italic text* using `*italic*`
            - `Inline code` using backticks

            ## Code Blocks

            Use triple backticks for code blocks:

            ```crystal
            puts "Hello from Crystal!"
            ```

            ## Lists

            Ordered lists:
            1. First item
            2. Second item
            3. Third item

            Unordered lists:
            - Item one
            - Item two
            - Item three

            ## Links and Images

            Create a link with square brackets around the text and parentheses
            around the URL, for example [Hwaro on GitHub](https://github.com/hahwul/hwaro).
            Prefix the same form with `!` to embed an image instead.

            ## Tables

            | Syntax | Renders as |
            |--------|------------|
            | `**bold**` | **bold** |
            | `*italic*` | *italic* |
            | `` `code` `` | `code` |

            ## Blockquotes

            > This is a blockquote.
            > It can span multiple lines.

            Happy writing!
            BODY

          render_page(
            title: "Markdown Tips and Tricks",
            body: body,
            skip_taxonomies: skip_taxonomies,
            date: sample_date(0),
            description: "Learn useful Markdown formatting techniques for your blog posts.",
            tags: ["markdown", "writing", "tips"],
            categories: ["tutorials"],
            authors: ["admin"]
          )
        end

        # Archives page front matter — picks up `templates/archives.html`
        # which actually renders the archive listing dynamically. The
        # body is just an intro line that lives above the generated
        # list; the template iterates `site.pages` to do the work.
        # Replaces the previous placeholder that only said "Browse all
        # posts by date" without rendering anything (gh#523).
        private def archives_content : String
          <<-CONTENT
            +++
            title = "Archives"
            template = "archives"
            description = "Every blog post, sorted by date."
            [extra]
            og_type = "website"
            +++

            Browse every post by date.
            CONTENT
        end

        # Archives template (Jinja2 syntax). Lists every dated,
        # non-draft, non-index page sorted newest-first. Filtering on
        # `date` truthiness instead of a hardcoded section name keeps
        # the page useful when the user renames `posts/` or adds dated
        # content under another section. Users who only want one
        # section can override this template and add a
        # `selectattr("section", "equalto", "...")` filter.
        #
        # We avoid `{% set %}` year-grouping because Crinja doesn't
        # implement Jinja2's `namespace()` helper that would otherwise
        # let us track the current year across iterations cleanly.
        #
        # `selectattr("language", "equalto", page_language)` keeps a
        # multilingual site's archives scoped to the current language —
        # without it every language's posts pile into one list.
        private def archives_template : String
          <<-HTML
            {% include "header.html" %}
            {% include "partials/nav.html" %}
            {% include "partials/search.html" %}
            <div class="blog-container">
              <main id="main" class="blog-main">
                {% if page.title is present %}<h1>{{ page.title | e }}</h1>{% endif %}
                {{ content }}

                <ul class="archive-list">
                {% for p in site.pages | selectattr("date") | rejectattr("is_index") | rejectattr("draft") | selectattr("language", "equalto", page_language) | sort(attribute="date", reverse=true) %}
                  <li class="archive-entry">
                    <time datetime="{{ p.date }}">{{ p.date }}</time>
                    <a href="{{ base_url }}{{ p.url }}">{{ p.title | e }}</a>
                  </li>
                {% endfor %}
                </ul>
            {% include "footer.html" %}
            HTML
        end
      end
    end
  end
end
