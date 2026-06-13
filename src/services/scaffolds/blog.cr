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
            "partials/search.html" => search_overlay_html,
            "index.html"           => blog_home_template,
            "page.html"            => blog_page_template,
            "section.html"         => blog_section_template,
            "post.html"            => post_template,
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

            # SEO & Feeds
            str << sitemap_config
            str << robots_config
            str << llms_config
            str << feeds_config(["posts"])

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
              {{ og_all_tags }}
              {{ jsonld }}
              {{ hreflang_tags }}
              {{ pagination_seo_links }}
              #{styles}
              {{ highlight_css }}
              {{ math_tags }}
              {{ mermaid_tags }}
              {{ auto_includes_css }}
            </head>
            <body data-section="{{ page.section }}">
              <a class="skip-link" href="#main">Skip to content</a>
            HTML
        end

        # Override footer for blog (Jinja2 syntax)
        protected def footer_template : String
          <<-HTML
                <footer class="blog-footer">
                  <p>Powered by Hwaro</p>
                </footer>
              </main>
            </div>
            {{ highlight_js }}
            <script src="{{ base_url }}/js/search.js"></script>
            {{ auto_includes_js }}
            </body>
            </html>
            HTML
        end

        def static_files : Hash(String, String)
          super.merge({
            "css/style.css" => css_content,
            "js/search.js"  => search_js_content,
          })
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
            description = ""
            authors = []
            categories = []
            tags = {{ tags }}
            +++

            MD
        end

        private def css_content : String
          <<-CSS
            :root {
              --primary: #b35454;
              --primary-hover: #8f4040;
              --text: #2a241f;
              --text-secondary: #5c5248;
              --text-muted: #8a7c6e;
              --border: #e4dacd;
              --border-light: #efe8dd;
              --bg: #faf7f2;
              --bg-secondary: #f1eae0;
              --bg-code: #f1eae0;
              --header-h: 52px;
              --content-max-w: 860px;
              --radius: 10px;
              --radius-sm: 6px;
              --font-serif: "Charter", "Bitstream Charter", "Iowan Old Style", "Palatino Linotype", Georgia, "Noto Serif KR", serif;
              --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
              --font-mono: ui-monospace, "SF Mono", "Cascadia Code", Menlo, Consolas, monospace;
            }

            *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

            body {
              font-family: var(--font-sans);
              font-size: 16px;
              line-height: 1.7;
              color: var(--text);
              background: var(--bg);
              -webkit-font-smoothing: antialiased;
              -moz-osx-font-smoothing: grayscale;
            }

            ::selection { background: rgba(179, 84, 84, 0.18); }

            /* Header */
            .blog-header {
              position: fixed;
              top: 0;
              left: 0;
              right: 0;
              height: var(--header-h);
              background: rgba(250, 247, 242, 0.85);
              backdrop-filter: saturate(180%) blur(20px);
              -webkit-backdrop-filter: saturate(180%) blur(20px);
              border-bottom: 1px solid var(--border-light);
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
              font-family: var(--font-serif);
              font-weight: 700;
              font-size: 1.15rem;
              color: var(--text);
              text-decoration: none;
              letter-spacing: -0.01em;
              margin-right: 2.5rem;
            }

            .blog-header .logo:hover { color: var(--primary); }

            .blog-header nav {
              display: flex;
              gap: 1.25rem;
            }

            .blog-header nav a {
              color: var(--text-secondary);
              text-decoration: none;
              font-size: 0.85rem;
              font-weight: 400;
              padding: 0.25rem 0;
              transition: color 0.15s;
            }

            .blog-header nav a:hover { color: var(--text); }

            .header-right {
              margin-left: auto;
              display: flex;
              align-items: center;
              gap: 1rem;
              padding-left: 1.25rem;
            }

            /* Language switcher (only rendered for multilingual sites). */
            .lang-switcher { display: flex; gap: 0.5rem; font-size: 0.85rem; }
            .lang-switcher a { color: var(--text-muted); text-decoration: none; padding: 0.15rem 0.4rem; border-radius: 4px; }
            .lang-switcher a:hover { color: var(--text); background: var(--bg-secondary); }
            .lang-switcher a[aria-current="true"] { color: var(--text); font-weight: 600; }

            /* Layout */
            .blog-container {
              padding-top: var(--header-h);
              min-height: 100vh;
            }

            .blog-main {
              max-width: var(--content-max-w);
              margin: 0 auto;
              padding: 2.5rem 1.5rem;
            }

            .blog-main h1 {
              font-family: var(--font-serif);
              font-size: 2.1rem;
              font-weight: 700;
              margin: 0 0 0.5rem 0;
              letter-spacing: -0.018em;
              line-height: 1.2;
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
              background: linear-gradient(90deg, #c46262, #8f4040);
            }

            .blog-main h2 {
              font-family: var(--font-serif);
              font-size: 1.45rem;
              font-weight: 700;
              margin: 2.5rem 0 0.75rem 0;
              letter-spacing: -0.008em;
              text-wrap: balance;
            }

            .blog-main h3 {
              font-family: var(--font-serif);
              font-size: 1.15rem;
              font-weight: 700;
              margin: 2rem 0 0.5rem 0;
            }

            .blog-main h4 {
              font-size: 0.95rem;
              font-weight: 600;
              margin: 1.5rem 0 0.5rem 0;
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

            /* Links: ember, with an underline that warms up on hover. */
            a {
              color: var(--primary);
              text-decoration: underline;
              text-decoration-color: color-mix(in srgb, var(--primary) 35%, transparent);
              text-underline-offset: 3px;
              transition: color 0.15s ease, text-decoration-color 0.15s ease;
            }
            a:hover { color: var(--primary-hover); text-decoration-color: currentColor; }
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
            }

            pre {
              padding: 1rem 1.25rem;
              border-radius: var(--radius);
              overflow-x: auto;
              border: 1px solid var(--border);
              margin: 1rem 0 1.5rem 0;
              line-height: 1.5;
              background: var(--bg-code);
            }

            /* Drop the highlight theme's own white background so syntax tokens
               sit on the warm code well instead of a white box. `pre code.hljs`
               (0,1,2) outranks the theme's `.hljs` (0,1,0). */
            pre code, pre code.hljs { background: transparent; padding: 0; font-size: 0.82rem; }

            /* Tables */
            table { width: 100%; border-collapse: collapse; margin: 1rem 0 1.5rem 0; font-size: 0.9rem; }
            th { text-align: left; padding: 0.6rem 0.75rem; border-bottom: 2px solid var(--border); font-weight: 600; font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.03em; color: var(--text-secondary); }
            td { padding: 0.5rem 0.75rem; border-bottom: 1px solid var(--border-light); vertical-align: top; }

            /* Blockquote */
            blockquote {
              font-family: var(--font-serif);
              font-style: italic;
              border-left: 1px solid var(--primary);
              padding: 0.1rem 0 0.1rem 1.25rem;
              margin: 1.4rem 0;
              color: var(--text-secondary);
            }

            blockquote p { margin-bottom: 0; }

            /* Images */
            img { max-width: 100%; height: auto; border-radius: var(--radius-sm); outline: 1px solid rgba(0, 0, 0, 0.06); outline-offset: -1px; }

            /* Home */
            .home-hero {
              padding-bottom: 1.75rem;
              margin-bottom: 2.25rem;
              border-bottom: 1px solid var(--border-light);
            }

            .home-title {
              position: relative;
              font-family: var(--font-serif);
              font-size: 2.6rem;
              font-weight: 700;
              line-height: 1.1;
              letter-spacing: -0.02em;
              margin: 0 0 1rem 0;
              padding-bottom: 0.9rem;
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
              background: linear-gradient(90deg, #c46262, #8f4040);
            }

            .home-tagline {
              font-family: var(--font-serif);
              font-size: 1.2rem;
              line-height: 1.5;
              color: var(--text-secondary);
              margin: 0;
              max-width: 38rem;
            }

            .home-intro {
              color: var(--text-secondary);
              margin-bottom: 2.5rem;
            }
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
            .home-more a:hover { color: var(--primary-hover); text-decoration: underline; }

            /* Post list */
            .post-list { list-style: none; padding: 0; }

            .post-item {
              padding: 1.25rem 0;
              border-bottom: 1px solid var(--border-light);
              transition: background 0.1s;
            }

            .post-item:last-child { border-bottom: none; }

            .post-title {
              font-family: var(--font-serif);
              margin: 0 0 0.3rem 0;
              font-size: 1.25rem;
              font-weight: 700;
              line-height: 1.3;
            }

            .post-title a {
              color: var(--text);
              text-decoration: none;
              transition: color 0.15s;
            }

            .post-title a:hover { color: var(--primary); text-decoration: none; }

            .post-meta {
              color: var(--text-muted);
              font-size: 0.8rem;
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
              border-bottom: 1px solid var(--border-light);
            }

            .post-header h1 { margin-bottom: 0.75rem; }
            .post-content { line-height: 1.8; }

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

            .post-content h2 {
              margin-top: 2.5rem;
              padding-bottom: 0.4rem;
              border-bottom: 1px solid var(--border-light);
            }

            /* Tags */
            .tag {
              display: inline-block;
              background: var(--bg-secondary);
              padding: 0.2rem 0.6rem;
              border-radius: 20px;
              font-size: 0.75rem;
              color: var(--text-secondary);
              text-decoration: none;
              border: 1px solid var(--border);
              transition: all 0.15s;
            }

            .tag:hover {
              background: var(--primary);
              color: var(--bg);
              border-color: var(--primary);
              text-decoration: none;
            }

            .tag:active { transform: scale(0.96); }

            /* Section list */
            ul.section-list { list-style: none; padding: 0; }

            ul.section-list li {
              margin-bottom: 0.5rem;
              padding: 0.75rem 1rem;
              background: var(--bg-secondary);
              border-radius: var(--radius-sm);
              border: 1px solid var(--border-light);
              transition: border-color 0.15s;
            }

            ul.section-list li:hover { border-color: var(--border); }
            ul.section-list li a { font-weight: 500; color: var(--primary); }

            .taxonomy-desc { color: var(--text-muted); margin-bottom: 1.5rem; }

            /* Pagination */
            nav.pagination { margin: 1.5rem 0; }
            nav.pagination .pagination-list { list-style: none; display: flex; gap: 0.5rem; flex-wrap: wrap; align-items: center; }
            nav.pagination a { display: inline-block; padding: 0.25rem 0.55rem; border-radius: var(--radius-sm); border: 1px solid var(--border-light); color: var(--text-secondary); text-decoration: none; }
            nav.pagination a:hover { color: var(--primary); border-color: var(--primary); }
            .pagination-current span { display: inline-block; padding: 0.25rem 0.55rem; border-radius: var(--radius-sm); border: 1px solid var(--primary); background: color-mix(in srgb, var(--primary) 8%, transparent); color: var(--primary); }
            .pagination-disabled span { display: inline-block; padding: 0.25rem 0.55rem; border-radius: var(--radius-sm); border: 1px solid var(--border-light); color: var(--text-muted); opacity: 0.5; }

            /* Footer */
            .blog-footer {
              margin-top: 3rem;
              padding-top: 1.5rem;
              border-top: 1px solid var(--border-light);
              color: var(--text-muted);
              font-size: 0.8rem;
            }

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
              transition: all 0.15s;
              font-family: inherit;
            }

            .search-trigger:hover { border-color: var(--text-muted); color: var(--text); }

            .search-trigger kbd {
              font-size: 0.65rem;
              padding: 0.1rem 0.35rem;
              border: 1px solid var(--border);
              border-radius: 3px;
              background: var(--bg-secondary);
              color: var(--text-muted);
              font-family: inherit;
              line-height: 1.4;
            }

            /* Search overlay */
            .search-overlay {
              display: none;
              position: fixed;
              inset: 0;
              background: rgba(0, 0, 0, 0.4);
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
              background: var(--bg);
              border-radius: var(--radius);
              box-shadow: 0 16px 70px rgba(0, 0, 0, 0.2);
              display: flex;
              flex-direction: column;
              overflow: hidden;
              align-self: flex-start;
            }

            .search-input-wrap {
              display: flex;
              align-items: center;
              gap: 0.6rem;
              padding: 0.75rem 1rem;
              border-bottom: 1px solid var(--border-light);
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
              background: var(--bg-secondary);
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

            .search-result-item:hover, .search-result-item.active { background: var(--bg-secondary); text-decoration: none; }
            .search-result-item .search-result-title { font-weight: 500; font-size: 0.9rem; margin-bottom: 0.15rem; }
            .search-result-item .search-result-snippet { font-size: 0.8rem; color: var(--text-secondary); line-height: 1.4; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
            .search-result-item .search-result-snippet mark { background: rgba(179, 84, 84, 0.15); color: var(--primary-hover); border-radius: 2px; padding: 0 1px; }
            .search-no-results { padding: 2rem 1rem; text-align: center; color: var(--text-muted); font-size: 0.9rem; }

            .search-hint {
              padding: 0.5rem 0.75rem;
              display: flex;
              gap: 1rem;
              justify-content: center;
              border-top: 1px solid var(--border-light);
              color: var(--text-muted);
              font-size: 0.7rem;
            }

            .search-hint kbd {
              font-size: 0.65rem;
              padding: 0 0.3rem;
              border: 1px solid var(--border);
              border-radius: 3px;
              background: var(--bg-secondary);
              font-family: inherit;
              line-height: 1.4;
            }

            /* Search trigger press feedback */
            .search-trigger { transition: border-color 0.15s ease, color 0.15s ease, transform 0.1s ease; }
            .search-trigger:active { transform: scale(0.96); }

            /* Responsive */
            @media (max-width: 640px) {
              .blog-header nav { display: none; }
              .blog-main { padding: 1.5rem 1rem; }
              .blog-main h1 { font-size: 1.6rem; }
            }

            @media (prefers-reduced-motion: reduce) {
              *, *::before, *::after { transition-duration: 0.01ms !important; }
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
                  html += '<a class="search-result-item" href="' + r.url + '" data-index="' + j + '">'
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

        # Search overlay HTML
        private def search_overlay_html : String
          <<-HTML
            <div class="search-overlay" id="searchOverlay" onclick="if(event.target===this)closeSearch()">
              <div class="search-modal">
                <div class="search-input-wrap">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
                  <input type="search" id="searchInput" aria-label="Search" placeholder="Search posts..." autocomplete="off">
                  <kbd onclick="closeSearch()">ESC</kbd>
                </div>
                <div class="search-results" id="searchResults"></div>
              </div>
            </div>
            HTML
        end

        # Blog header navigation HTML
        private def blog_nav_html : String
          <<-HTML
            <header class="blog-header">
              <div class="blog-header-inner">
                <a href="{{ base_url }}{{ lang_prefix }}/" class="logo">{{ site.title | e }}</a>
                <nav>
                  <!-- To add new top-level sections (e.g. /notes/, /projects/):
                       1. Create content/SECTION/_index.md
                       2. Replace the hardcoded links below with this dynamic
                          loop. It shows only the current language's sections;
                          s.url already carries the language prefix, so do NOT
                          add lang_prefix. Sort by "weight" for explicit order.
                       (The example below is wrapped in a raw block so it
                       isn't executed while it lives in the comment.)
                       {% raw %}
                       {% for s in site.sections | sort(attribute="title") %}
                         {% if not s.transparent and s.name and s.language == page_language %}<a href="{{ base_url }}{{ s.url }}">{{ s.title }}</a>{% endif %}
                       {% endfor %}
                       {% endraw %}
                  -->
                  <a href="{{ base_url }}{{ lang_prefix }}/posts/">Posts</a>
                  <a href="{{ base_url }}{{ lang_prefix }}/archives/">Archives</a>
                  <a href="{{ base_url }}{{ lang_prefix }}/about/">About</a>
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
                </header>
                {% if content %}<div class="home-intro">{{ content }}</div>{% endif %}
                <section class="home-latest" aria-labelledby="home-latest-title">
                  <h2 id="home-latest-title" class="home-section-title">Latest posts</h2>
                  <ul class="post-list">
                    {% for p in site.pages | selectattr("date") | rejectattr("is_index") | rejectattr("draft") | sort(attribute="date", reverse=true) %}
                    {% if loop.index <= 5 %}
                      <li class="post-item">
                        <div class="post-meta"><time datetime="{{ p.date }}">{{ p.date }}</time></div>
                        <h3 class="post-title"><a href="{{ base_url }}{{ p.url }}">{{ p.title | e }}</a></h3>
                        {% if p.description %}<p class="post-excerpt">{{ p.description | e }}</p>{% endif %}
                      </li>
                    {% endif %}
                    {% endfor %}
                  </ul>
                  <p class="home-more"><a href="{{ base_url }}{{ lang_prefix }}/posts/">View all posts &rarr;</a></p>
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
        private def post_template : String
          <<-HTML
            {% include "header.html" %}
            {% include "partials/nav.html" %}
            {% include "partials/search.html" %}
            <div class="blog-container">
              <main id="main" class="blog-main">
                <article class="post">
                  <header class="post-header">
                    <h1>{{ page.title | e }}</h1>
                    <div class="post-meta">
                      <time>{{ page.date }}</time>
                    </div>
                  </header>
                  <div class="post-content">
                    {{ content }}
                  </div>

                  {# Series nav walks `series_pages` (ordered by series_weight)
                     via the 1-based `series_index`, NOT page.lower/page.higher
                     — those are the section's flat date-ordered neighbours, so
                     they ordered chapters by date and even linked non-series
                     posts. #}
                  {% if page.series %}
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

        # Override navigation (not used directly - kept for base class compatibility)
        protected def navigation : String
          <<-NAV
            <nav>
              <a href="{{ base_url }}{{ lang_prefix }}/">Home</a>
              <a href="{{ base_url }}{{ lang_prefix }}/posts/">Posts</a>
              <a href="{{ base_url }}{{ lang_prefix }}/archives/">Archives</a>
              <a href="{{ base_url }}{{ lang_prefix }}/about/">About</a>
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
              str << "A blog powered by [Hwaro](https://github.com/hahwul/hwaro) — a fast, lightweight static site generator.\n"
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
            description: "A blog powered by Hwaro — posts, archives, and tags.",
            tags: ["home"]
          )
        end

        private def about_content(skip_taxonomies : Bool) : String
          body = <<-BODY
            Welcome to my blog! I write about technology, programming, and other interesting topics.

            ## Contact

            Feel free to reach out through social media or email.
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
            Welcome to my first blog post! This blog is powered by Hwaro, a fast and lightweight static site generator written in Crystal.

            ## Why Hwaro?

            Hwaro offers a simple yet powerful way to create static websites:

            - **Fast**: Built with Crystal for blazing fast build times
            - **Simple**: Easy to understand directory structure
            - **Flexible**: Supports custom templates and shortcodes

            Stay tuned for more posts!
            BODY

          render_page(
            title: "Hello World",
            body: body,
            skip_taxonomies: skip_taxonomies,
            date: sample_date(10),
            description: "My first blog post using Hwaro static site generator.",
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
            around the URL — for example, [Hwaro on GitHub](https://github.com/hahwul/hwaro).
            Prefix the same form with `!` to embed an image instead.

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
                {% for p in site.pages | selectattr("date") | rejectattr("is_index") | rejectattr("draft") | sort(attribute="date", reverse=true) %}
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
