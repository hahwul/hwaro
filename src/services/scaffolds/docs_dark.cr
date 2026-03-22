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

        def config_content(skip_taxonomies : Bool = false) : String
          config = String.build do |str|
            # Site basics
            str << base_config(config_title, config_description)

            # Content & Processing
            str << multilingual_config
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
            str << image_processing_config
            str << build_hooks_config
            str << pwa_config
            str << amp_config
            str << og_auto_image_config
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
            --primary: #2997ff;
            --primary-hover: #4dacff;
            --text: #f5f5f7;
            --text-secondary: #a1a1a6;
            --text-muted: #6e6e73;
            --border: #424245;
            --border-light: #303033;
            --bg: #1d1d1f;
            --bg-secondary: #2c2c2e;
            --bg-code: #2c2c2e;
            --header-h: 52px;
            --sidebar-w: 260px;
            --content-max-w: 780px;
            --radius: 10px;
            --radius-sm: 6px;
          }

          *,
          *::before,
          *::after {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
          }

          body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif;
            font-size: 15px;
            line-height: 1.6;
            color: var(--text);
            background: var(--bg);
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
          }

          /* Header */
          .docs-header {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            height: var(--header-h);
            background: rgba(29, 29, 31, 0.8);
            backdrop-filter: saturate(180%) blur(20px);
            -webkit-backdrop-filter: saturate(180%) blur(20px);
            border-bottom: 1px solid var(--border-light);
            display: flex;
            align-items: center;
            padding: 0 1.5rem;
            z-index: 100;
          }

          .docs-header .logo {
            font-weight: 600;
            font-size: 1.05rem;
            color: var(--text);
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
          .docs-sidebar {
            position: fixed;
            top: var(--header-h);
            left: 0;
            width: var(--sidebar-w);
            height: calc(100vh - var(--header-h));
            background: var(--bg);
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
            background: var(--bg-secondary);
            color: var(--text);
          }

          .sidebar-links a.active {
            background: var(--primary);
            color: white;
            font-weight: 500;
          }

          /* Main content */
          .docs-main {
            flex: 1;
            margin-left: var(--sidebar-w);
            padding: 2.5rem 3rem;
            max-width: calc(var(--content-max-w) + var(--sidebar-w) + 6rem);
          }

          .docs-main h1 {
            font-size: 2rem;
            font-weight: 700;
            margin: 0 0 0.5rem 0;
            letter-spacing: -0.025em;
            line-height: 1.2;
          }

          .docs-main h2 {
            font-size: 1.4rem;
            font-weight: 600;
            margin: 2.5rem 0 0.75rem 0;
            letter-spacing: -0.015em;
            color: var(--text);
          }

          .docs-main h3 {
            font-size: 1.1rem;
            font-weight: 600;
            margin: 2rem 0 0.5rem 0;
            color: var(--text);
          }

          .docs-main h4 {
            font-size: 0.95rem;
            font-weight: 600;
            margin: 1.5rem 0 0.5rem 0;
            color: var(--text);
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

          /* Links */
          a {
            color: var(--primary);
            text-decoration: none;
          }

          a:hover {
            text-decoration: underline;
          }

          /* Code */
          code {
            background: var(--bg-code);
            padding: 0.15rem 0.4rem;
            border-radius: 4px;
            font-size: 0.85em;
            font-family: "SF Mono", SFMono-Regular, ui-monospace, Menlo, Consolas, monospace;
            color: var(--text);
          }

          pre {
            padding: 1rem 1.25rem;
            border-radius: var(--radius);
            overflow-x: auto;
            border: 1px solid var(--border-light);
            margin: 1rem 0 1.5rem 0;
            line-height: 1.5;
          }

          pre code {
            background: none;
            padding: 0;
            font-size: 0.82rem;
          }

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
            border-left: 3px solid var(--primary);
            padding: 0.5rem 1rem;
            margin: 1rem 0;
            background: var(--bg-secondary);
            border-radius: 0 var(--radius-sm) var(--radius-sm) 0;
            color: var(--text-secondary);
          }

          blockquote p {
            margin-bottom: 0;
          }

          /* Info boxes */
          .info-box {
            padding: 0.75rem 1rem;
            border-radius: var(--radius-sm);
            margin: 1rem 0;
            border-left: 3px solid;
            font-size: 0.9rem;
          }

          .info-box.note {
            background: rgba(41, 151, 255, 0.1);
            border-color: var(--primary);
          }

          .info-box.warning {
            background: rgba(255, 159, 10, 0.1);
            border-color: #ff9f0a;
          }

          .info-box.tip {
            background: rgba(48, 209, 88, 0.1);
            border-color: #30d158;
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
            background: rgba(41, 151, 255, 0.2);
            color: var(--primary);
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
          CSS
        end
      end
    end
  end
end
