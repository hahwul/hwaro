# Blog Dark scaffold - blog-focused structure with dark theme
#
# Inherits layout, content, templates, and JS from Blog scaffold.
# Overrides only CSS (dark color variables) and highlight theme.
# Warm charcoal dark palette with copper/amber accents.

require "./blog"

module Hwaro
  module Services
    module Scaffolds
      class BlogDark < Blog
        def type : Config::Options::ScaffoldType
          Config::Options::ScaffoldType::BlogDark
        end

        def description : String
          "Blog-focused structure with dark theme"
        end

        protected def config_highlight_theme : String
          "github-dark"
        end

        def config_content(skip_taxonomies : Bool = false, multilingual_languages : Array(String) = [] of String) : String
          config = String.build do |str|
            # Site basics
            str << base_config(config_title, config_description)

            # Content & Processing
            str << multilingual_config(multilingual_languages)
            str << plugins_config
            str << content_files_config
            str << highlight_dark_config
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

        private def highlight_dark_config : String
          <<-TOML

            # =============================================================================
            # Syntax Highlighting
            # =============================================================================
            # Code block syntax highlighting using Highlight.js

            [highlight]
            enabled = true
            theme = "github-dark"    # Dark theme for syntax highlighting
            use_cdn = true            # Set to false to use local assets

            TOML
        end

        private def css_content : String
          <<-CSS
            :root {
              color-scheme: dark;
              --primary: #c87a7a;
              --primary-hover: #d69292;
              --heading: #ece5dc;
              --text: #d9d2c9;
              --text-secondary: #a3958a;
              --text-muted: #8f8174;
              --border: #2f2822;
              --border-light: #251f1a;
              --bg: #16120e;
              --bg-secondary: #1e1813;
              --bg-code: #1e1813;
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

            ::selection { background: rgba(200, 122, 122, 0.3); }

            /* Header */
            .blog-header {
              position: fixed;
              top: 0;
              left: 0;
              right: 0;
              height: var(--header-h);
              background: rgba(22, 18, 14, 0.85);
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
              color: var(--heading);
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
              background: linear-gradient(90deg, #d69292, #b35454);
            }

            .blog-main h2 {
              font-family: var(--font-serif);
              font-size: 1.45rem;
              font-weight: 700;
              margin: 2.5rem 0 0.75rem 0;
              letter-spacing: -0.008em;
              color: var(--heading);
              text-wrap: balance;
            }

            .blog-main h3 {
              font-family: var(--font-serif);
              font-size: 1.15rem;
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

            /* Links: ember, with an underline that warms up on hover. */
            a {
              color: var(--primary);
              text-decoration: underline;
              text-decoration-color: rgba(200, 122, 122, 0.35);
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
              color: var(--primary);
              border: 1px solid var(--border);
            }

            pre {
              padding: 1rem 1.25rem;
              border-radius: var(--radius);
              overflow-x: auto;
              border: 1px solid var(--border);
              margin: 1rem 0 1.5rem 0;
              line-height: 1.5;
              background: var(--bg-secondary);
            }

            pre code { background: none; padding: 0; font-size: 0.82rem; color: var(--text); border: none; }

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
            img { max-width: 100%; height: auto; border-radius: var(--radius-sm); outline: 1px solid rgba(255, 255, 255, 0.08); outline-offset: -1px; }

            /* Post list */
            .post-list { list-style: none; padding: 0; }

            .post-item {
              padding: 1.25rem 0;
              border-bottom: 1px solid var(--border);
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
              color: var(--heading);
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
              border-bottom: 1px solid var(--border);
            }

            .post-header h1 { margin-bottom: 0.75rem; }
            .post-content { line-height: 1.8; }

            .post-content h2 {
              margin-top: 2.5rem;
              padding-bottom: 0.4rem;
              border-bottom: 1px solid var(--border);
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

            /* Section list */
            ul.section-list { list-style: none; padding: 0; }

            ul.section-list li {
              margin-bottom: 0.5rem;
              padding: 0.75rem 1rem;
              background: var(--bg-secondary);
              border-radius: var(--radius-sm);
              border: 1px solid var(--border);
              transition: border-color 0.15s;
            }

            ul.section-list li:hover { border-color: var(--text-muted); }
            ul.section-list li a { font-weight: 500; color: var(--primary); }

            .taxonomy-desc { color: var(--text-muted); margin-bottom: 1.5rem; }

            /* Pagination */
            nav.pagination { margin: 1.5rem 0; }
            nav.pagination .pagination-list { list-style: none; display: flex; gap: 0.5rem; flex-wrap: wrap; align-items: center; }
            nav.pagination a { display: inline-block; padding: 0.25rem 0.55rem; border-radius: var(--radius-sm); border: 1px solid var(--border); color: var(--text-secondary); text-decoration: none; }
            nav.pagination a:hover { color: var(--primary); border-color: var(--primary); }
            .pagination-current span { display: inline-block; padding: 0.25rem 0.55rem; border-radius: var(--radius-sm); border: 1px solid var(--primary); background: rgba(200, 122, 122, 0.12); color: var(--primary); }
            .pagination-disabled span { display: inline-block; padding: 0.25rem 0.55rem; border-radius: var(--radius-sm); border: 1px solid var(--border); color: var(--text-muted); opacity: 0.5; }

            /* Footer */
            .blog-footer {
              margin-top: 3rem;
              padding-top: 1.5rem;
              border-top: 1px solid var(--border);
              color: var(--text-muted);
              font-size: 0.8rem;
            }

            .blog-footer a { color: var(--primary); }

            /* Search trigger */
            .search-trigger {
              display: flex;
              align-items: center;
              gap: 0.4rem;
              padding: 0.3rem 0.6rem;
              border: 1px solid var(--border);
              border-radius: var(--radius-sm);
              background: transparent;
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
              background: rgba(0, 0, 0, 0.6);
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
              background: var(--bg-secondary);
              border-radius: var(--radius);
              box-shadow: 0 16px 70px rgba(0, 0, 0, 0.5);
              border: 1px solid var(--border);
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
              border-bottom: 1px solid var(--border);
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
              background: var(--bg);
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

            .search-result-item:hover, .search-result-item.active { background: var(--bg); text-decoration: none; }
            .search-result-item .search-result-title { font-weight: 500; font-size: 0.9rem; margin-bottom: 0.15rem; }
            .search-result-item .search-result-snippet { font-size: 0.8rem; color: var(--text-secondary); line-height: 1.4; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
            .search-result-item .search-result-snippet mark { background: rgba(200, 122, 122, 0.22); color: var(--primary-hover); border-radius: 2px; padding: 0 1px; }
            .search-no-results { padding: 2rem 1rem; text-align: center; color: var(--text-muted); font-size: 0.9rem; }

            .search-hint {
              padding: 0.5rem 0.75rem;
              display: flex;
              gap: 1rem;
              justify-content: center;
              border-top: 1px solid var(--border);
              color: var(--text-muted);
              font-size: 0.7rem;
            }

            .search-hint kbd {
              font-size: 0.65rem;
              padding: 0 0.3rem;
              border: 1px solid var(--border);
              border-radius: 3px;
              background: var(--bg);
              font-family: inherit;
              line-height: 1.4;
            }

            /* Scrollbar */
            ::-webkit-scrollbar { width: 8px; height: 8px; }
            ::-webkit-scrollbar-track { background: var(--bg-secondary); }
            ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 4px; }
            ::-webkit-scrollbar-thumb:hover { background: var(--text-muted); }

            /* Search trigger press feedback */
            .search-trigger { transition: border-color 0.15s ease, color 0.15s ease, transform 0.1s ease; }
            .search-trigger:active { transform: scale(0.96); }
            .tag:active { transform: scale(0.96); }

            /* Responsive */
            @media (max-width: 640px) {
              body { font-size: 15px; }
              .blog-header nav { display: none; }
              .blog-main { padding: 1.5rem 1rem; }
              .blog-main h1 { font-size: 1.6rem; }
            }

            @media (prefers-reduced-motion: reduce) {
              *, *::before, *::after { transition-duration: 0.01ms !important; }
            }
            CSS
        end
      end
    end
  end
end
