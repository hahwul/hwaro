# Docs Dark scaffold - documentation-focused structure with dark theme
#
# Inherits layout, content, templates, and JS from Docs scaffold.
# Overrides only CSS (dark color variables) and highlight theme.

require "./docs"

module Hwaro
  module Services
    module Scaffolds
      class DocsDark < Docs
        def type : Config::Options::ScaffoldType
          Config::Options::ScaffoldType::DocsDark
        end

        def description : String
          "Documentation-focused structure with dark theme"
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
            str << feeds_config

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
            # Code blocks are highlighted at build time and themed by an inlined,
            # ember-warm dark theme in css/style.css — no JavaScript and no external
            # requests. Switch mode to "client" (+ use_cdn = true or local assets)
            # to highlight in the browser with Highlight.js instead.

            [highlight]
            enabled = true
            mode = "server"              # "server" = highlight at build time (no JS); "client" = Highlight.js
            theme = "github-dark"        # Fallback theme for "client" mode; the default ships an inlined theme
            use_cdn = false              # "client" mode only: true loads Highlight.js from a CDN

            TOML
        end

        private def css_content : String
          <<-CSS
            #{font_face_css("../fonts")}

            :root {
              color-scheme: dark;
              --primary: #ec7a66;
              --primary-hover: #f39683;
              --heading: #f5f2ed;
              --text: #dedad3;
              --text-secondary: #a7a199;
              --text-muted: #7d776e;
              --border: #2b2926;
              --border-light: #201e1c;
              --bg: #0f0f0e;
              --bg-sidebar: #151412;
              --bg-secondary: #1a1917;
              --bg-code: #1e1c19;
              --header-h: 52px;
              --sidebar-w: 260px;
              --content-max-w: 780px;
              --radius: 10px;
              --radius-sm: 6px;
              --font-serif: "Charter", "Bitstream Charter", "Iowan Old Style", "Palatino Linotype", Georgia, "Noto Serif KR", serif;
              --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
              --font-mono: ui-monospace, "SF Mono", "Cascadia Code", Menlo, Consolas, monospace;
            }

            *,
            *::before,
            *::after {
              box-sizing: border-box;
              margin: 0;
              padding: 0;
            }

            body {
              font-family: var(--font-sans);
              font-size: 15px;
              line-height: 1.6;
              color: var(--text);
              background: var(--bg);
              -webkit-font-smoothing: antialiased;
              -moz-osx-font-smoothing: grayscale;
            }

            ::selection { background: color-mix(in srgb, var(--primary) 30%, transparent); }

            /* Header */
            .docs-header {
              position: fixed;
              top: 0;
              left: 0;
              right: 0;
              height: var(--header-h);
              background: rgba(15, 15, 14, 0.85);
              backdrop-filter: saturate(180%) blur(20px);
              -webkit-backdrop-filter: saturate(180%) blur(20px);
              border-bottom: 1px solid var(--border-light);
              display: flex;
              align-items: center;
              padding: 0 1.5rem;
              z-index: 100;
            }

            .docs-header .logo {
              font-family: var(--font-serif);
              font-weight: 700;
              font-size: 1.15rem;
              color: var(--heading);
              text-decoration: none;
              margin-right: 2rem;
              letter-spacing: -0.01em;
            }

            .docs-header .logo span {
              color: var(--text-muted);
              font-weight: 400;
              margin-left: 0.25rem;
              font-size: 0.8rem;
            }

            .docs-header nav {
              display: flex;
              gap: 1.25rem;
            }

            .docs-header nav a {
              color: var(--text-secondary);
              text-decoration: none;
              font-size: 0.85rem;
              font-weight: 400;
              padding: 0.25rem 0;
              transition: color 0.15s;
            }

            .docs-header nav a:hover {
              color: var(--text);
            }

            .header-right {
              margin-left: auto;
              display: flex;
              align-items: center;
              gap: 1rem;
            }

            .header-right a {
              color: var(--text-secondary);
              text-decoration: none;
              font-size: 0.85rem;
              transition: color 0.15s;
            }

            .header-right a:hover {
              color: var(--text);
            }

            /* Layout */
            .docs-container {
              display: flex;
              padding-top: var(--header-h);
              min-height: 100vh;
            }

            /* Sidebar */
            /* Sidebar: one luminance step above the canvas so the two
               surfaces read as distinct without heavy borders. */
            .docs-sidebar {
              position: fixed;
              top: var(--header-h);
              left: 0;
              width: var(--sidebar-w);
              height: calc(100vh - var(--header-h));
              background: var(--bg-sidebar);
              border-right: 1px solid var(--border-light);
              padding: 1.25rem 0.75rem;
              overflow-y: auto;
              scrollbar-width: thin;
            }

            .docs-sidebar::-webkit-scrollbar {
              width: 4px;
            }

            .docs-sidebar::-webkit-scrollbar-thumb {
              background: var(--border);
              border-radius: 2px;
            }

            .sidebar-section {
              margin-bottom: 1.5rem;
            }

            .sidebar-title {
              font-size: 0.7rem;
              font-weight: 600;
              text-transform: uppercase;
              color: var(--text-muted);
              margin-bottom: 0.4rem;
              letter-spacing: 0.04em;
              padding-left: 0.75rem;
            }

            .sidebar-links {
              list-style: none;
            }

            .sidebar-links li {
              margin-bottom: 1px;
            }

            .sidebar-links a {
              display: block;
              padding: 0.3rem 0.75rem;
              color: var(--text-secondary);
              text-decoration: none;
              border-radius: var(--radius-sm);
              font-size: 0.85rem;
              transition: all 0.15s;
              line-height: 1.4;
            }

            .sidebar-links a:hover {
              background: color-mix(in srgb, var(--primary) 8%, transparent);
              color: var(--text);
            }

            .sidebar-links a.active {
              background: color-mix(in srgb, var(--primary) 14%, transparent);
              color: var(--primary-hover);
              font-weight: 600;
            }

            /* Main content */
            .docs-main {
              flex: 1;
              margin-left: var(--sidebar-w);
              padding: 2.5rem 3rem;
              max-width: calc(var(--content-max-w) + var(--sidebar-w) + 6rem);
            }

            .docs-main h1 {
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
            .docs-main > h1:first-child {
              position: relative;
              padding-bottom: 0.9rem;
            }

            .docs-main > h1:first-child::after {
              content: "";
              position: absolute;
              left: 0;
              bottom: 0;
              width: 2.75rem;
              height: 3px;
              border-radius: 999px;
              background: linear-gradient(90deg, #f39683, #cc5d4b);
            }

            .docs-main h2 {
              font-family: var(--font-serif);
              font-size: 1.45rem;
              font-weight: 700;
              margin: 2.5rem 0 0.75rem 0;
              letter-spacing: -0.008em;
              color: var(--heading);
              text-wrap: balance;
            }

            .docs-main h3 {
              font-size: 1.1rem;
              font-weight: 600;
              margin: 2rem 0 0.5rem 0;
              color: var(--heading);
            }

            .docs-main h4 {
              font-size: 0.95rem;
              font-weight: 600;
              margin: 1.5rem 0 0.5rem 0;
              color: var(--heading);
            }

            .docs-main p {
              margin-bottom: 1rem;
              line-height: 1.7;
            }

            .docs-main ul,
            .docs-main ol {
              margin-bottom: 1rem;
              padding-left: 1.5rem;
            }

            .docs-main li {
              margin-bottom: 0.35rem;
              line-height: 1.6;
            }

            /* Links: ember, with an underline that warms up on hover.
               Navigation surfaces opt out below. */
            a {
              color: var(--primary);
              text-decoration: underline;
              text-decoration-color: color-mix(in srgb, var(--primary) 35%, transparent);
              text-underline-offset: 3px;
              transition: color 0.15s ease, text-decoration-color 0.15s ease;
            }

            a:hover {
              color: var(--primary-hover);
              text-decoration-color: currentColor;
            }

            .docs-header a, .skip-link, .sidebar-links a, .docs-toc a,
            ul.section-list a, nav.pagination a, .search-result-item {
              text-decoration: none;
            }

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
              box-shadow: inset 0 1px 0 rgba(236, 229, 220, 0.05);
            }

            /* Force the highlight theme's own (cold navy github-dark)
               background off so syntax tokens sit on the warm ember card
               instead of a clashing box. `pre code.hljs` (0,1,2) outranks
               the theme's `.hljs` (0,1,0). */
            pre code, pre code.hljs {
              background: transparent;
              padding: 0;
              font-size: 0.82rem;
              color: var(--text);
            }
            #{highlight_theme_css(true)}

            /* Tables */
            table {
              width: 100%;
              border-collapse: collapse;
              margin: 1rem 0 1.5rem 0;
              font-size: 0.9rem;
            }

            th {
              text-align: left;
              padding: 0.6rem 0.75rem;
              border-bottom: 2px solid var(--border);
              font-weight: 600;
              font-size: 0.8rem;
              text-transform: uppercase;
              letter-spacing: 0.03em;
              color: var(--text-secondary);
            }

            td {
              padding: 0.5rem 0.75rem;
              border-bottom: 1px solid var(--border-light);
              vertical-align: top;
            }

            /* Blockquote */
            blockquote {
              font-family: var(--font-serif);
              font-style: italic;
              border-left: 1px solid var(--primary);
              padding: 0.1rem 0 0.1rem 1.25rem;
              margin: 1.4rem 0;
              color: var(--text-secondary);
            }

            blockquote p {
              margin-bottom: 0;
            }

            /* Info boxes: tinted surfaces with a hairline border in the
               same hue — no heavy accent bars. */
            .info-box {
              padding: 0.875rem 1.125rem;
              border-radius: var(--radius-sm);
              margin: 1rem 0;
              border: 1px solid;
              font-size: 0.9rem;
            }

            .info-box.note {
              background: color-mix(in srgb, var(--primary) 9%, transparent);
              border-color: color-mix(in srgb, var(--primary) 35%, transparent);
            }

            .info-box.warning {
              background: rgba(214, 164, 91, 0.09);
              border-color: rgba(214, 164, 91, 0.35);
            }

            .info-box.tip {
              background: rgba(126, 168, 130, 0.09);
              border-color: rgba(126, 168, 130, 0.35);
            }

            /* Section list */
            ul.section-list {
              list-style: none;
              padding: 0;
            }

            ul.section-list li {
              margin-bottom: 0.5rem;
              padding: 0.75rem 1rem;
              background: var(--bg-secondary);
              border-radius: var(--radius-sm);
              border: 1px solid var(--border-light);
              transition: border-color 0.15s;
            }

            ul.section-list li:hover {
              border-color: var(--border);
            }

            ul.section-list li a {
              font-weight: 500;
              color: var(--primary);
            }

            /* Navigation pagination */
            nav.pagination {
              margin: 1.5rem 0;
            }

            nav.pagination .pagination-list {
              list-style: none;
              display: flex;
              gap: 0.5rem;
              flex-wrap: wrap;
              align-items: center;
            }

            nav.pagination a {
              display: inline-block;
              padding: 0.25rem 0.55rem;
              border-radius: var(--radius-sm);
              border: 1px solid var(--border-light);
              color: var(--text-secondary);
              text-decoration: none;
            }

            nav.pagination a:hover {
              color: var(--primary);
              border-color: var(--primary);
            }

            .pagination-current span {
              display: inline-block;
              padding: 0.25rem 0.55rem;
              border-radius: var(--radius-sm);
              border: 1px solid var(--primary);
              background: color-mix(in srgb, var(--primary) 8%, transparent);
              color: var(--primary);
            }

            .pagination-disabled span {
              display: inline-block;
              padding: 0.25rem 0.55rem;
              border-radius: var(--radius-sm);
              border: 1px solid var(--border-light);
              color: var(--text-muted);
              opacity: 0.5;
            }

            /* Footer */
            .docs-footer {
              margin-top: 3rem;
              padding-top: 1.5rem;
              border-top: 1px solid var(--border-light);
              color: var(--text-muted);
              font-size: 0.8rem;
            }

            /* Search trigger button */
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

            .search-trigger:hover {
              border-color: var(--text-muted);
              color: var(--text);
            }

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

            .search-overlay.active {
              display: flex;
            }

            .search-modal {
              width: 560px;
              max-width: 90vw;
              max-height: 70vh;
              background: var(--bg-secondary);
              border-radius: var(--radius);
              box-shadow: 0 16px 70px rgba(0, 0, 0, 0.5);
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

            .search-input-wrap svg {
              flex-shrink: 0;
              color: var(--text-muted);
            }

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

            .search-input-wrap input::placeholder {
              color: var(--text-muted);
            }

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

            .search-results {
              overflow-y: auto;
              padding: 0.5rem;
            }

            .search-result-item {
              display: block;
              padding: 0.6rem 0.75rem;
              border-radius: var(--radius-sm);
              text-decoration: none;
              color: var(--text);
              cursor: pointer;
              transition: background 0.1s;
            }

            .search-result-item:hover,
            .search-result-item.active {
              background: var(--bg);
              text-decoration: none;
            }

            .search-result-item .search-result-title {
              font-weight: 500;
              font-size: 0.9rem;
              margin-bottom: 0.15rem;
            }

            .search-result-item .search-result-snippet {
              font-size: 0.8rem;
              color: var(--text-secondary);
              line-height: 1.4;
              display: -webkit-box;
              -webkit-line-clamp: 2;
              -webkit-box-orient: vertical;
              overflow: hidden;
            }

            .search-result-item .search-result-snippet mark {
              background: color-mix(in srgb, var(--primary) 22%, transparent);
              color: var(--primary-hover);
              border-radius: 2px;
              padding: 0 1px;
            }

            .search-no-results {
              padding: 2rem 1rem;
              text-align: center;
              color: var(--text-muted);
              font-size: 0.9rem;
            }

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
              background: var(--bg);
              font-family: inherit;
              line-height: 1.4;
            }

            /* Search trigger press feedback */
            .search-trigger:active {
              transform: scale(0.96);
            }

            /* Responsive */
            @media (max-width: 768px) {
              .docs-sidebar {
                display: none;
              }
              .docs-main {
                margin-left: 0;
                padding: 1.5rem 1rem;
              }
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
