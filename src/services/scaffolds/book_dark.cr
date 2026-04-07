# Book Dark scaffold - mdBook-style book structure with dark theme
#
# Inherits layout, content, templates, and JS from Book scaffold.
# Overrides only CSS (dark color variables) and highlight theme.

require "./book"

module Hwaro
  module Services
    module Scaffolds
      class BookDark < Book
        def type : Config::Options::ScaffoldType
          Config::Options::ScaffoldType::BookDark
        end

        def description : String
          "Book-style structure with chapters, prev/next navigation, and dark theme"
        end

        protected def config_highlight_theme : String
          "github-dark"
        end

        def config_content(skip_taxonomies : Bool = false) : String
          config = String.build do |str|
            str << base_config(config_title, config_description)
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
            str << sitemap_config
            str << robots_config
            str << llms_config
            str << feeds_config
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
            --primary: #b0b0b0;
            --primary-hover: #d0d0d0;
            --primary-subtle: rgba(255, 255, 255, 0.03);
            --text: #c0c0c0;
            --text-secondary: #777777;
            --text-muted: #4a4a4a;
            --border: #2a2a2a;
            --border-light: #1f1f1f;
            --bg: #111111;
            --bg-secondary: #181818;
            --bg-sidebar: #0e0e0e;
            --bg-code: #1a1a1a;
            --header-h: 50px;
            --sidebar-w: 280px;
            --content-max-w: 780px;
            --radius: 6px;
            --radius-sm: 3px;
            --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.3);
            --shadow: 0 2px 8px rgba(0, 0, 0, 0.4);
          }

          *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
          html { scroll-behavior: smooth; }

          body {
            font-family: "Georgia", "Times New Roman", "Noto Serif KR", "Noto Serif", serif;
            font-size: 20px;
            line-height: 1.9;
            color: var(--text);
            background: var(--bg);
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
          }

          /* ── Header ── */
          .book-header {
            position: fixed;
            top: 0; left: 0; right: 0;
            height: var(--header-h);
            background: rgba(17, 17, 17, 0.9);
            backdrop-filter: saturate(180%) blur(20px);
            -webkit-backdrop-filter: saturate(180%) blur(20px);
            border-bottom: 1px solid var(--border-light);
            display: grid;
            grid-template-columns: 1fr auto 1fr;
            align-items: center;
            padding: 0 0.75rem;
            z-index: 100;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          }

          .header-left { display: flex; align-items: center; justify-content: flex-start; }
          .header-center { display: flex; align-items: center; justify-content: center; }
          .header-right { display: flex; align-items: center; justify-content: flex-end; gap: 0.25rem; }

          .icon-btn {
            display: flex; align-items: center; justify-content: center;
            width: 34px; height: 34px;
            border: none; border-radius: var(--radius-sm);
            background: none; color: var(--text-muted);
            cursor: pointer; transition: color 0.15s, background 0.15s; padding: 0;
          }
          .icon-btn:hover { color: var(--text-secondary); background: rgba(255,255,255,0.04); }

          .book-header .logo {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            font-weight: 500; font-size: 0.82rem;
            color: var(--text-secondary); text-decoration: none; letter-spacing: 0.01em;
          }
          .book-header .logo:hover { color: var(--text); text-decoration: none; }

          .fullscreen-toggle .fs-exit { display: none; }
          .fullscreen-active .fullscreen-toggle .fs-enter { display: none; }
          .fullscreen-active .fullscreen-toggle .fs-exit { display: block; }

          .book-container {
            display: flex;
            padding-top: var(--header-h);
            min-height: 100vh;
          }

          .book-sidebar {
            position: fixed;
            top: var(--header-h);
            left: 0;
            width: var(--sidebar-w);
            height: calc(100vh - var(--header-h));
            background: var(--bg-sidebar);
            border-right: 1px solid var(--border-light);
            padding: 1rem 0;
            overflow-y: auto;
            scrollbar-width: thin;
            scrollbar-color: var(--border) transparent;
            z-index: 50;
            transition: transform 0.25s ease, visibility 0.25s;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          }

          .book-sidebar.collapsed {
            transform: translateX(-100%);
            visibility: hidden;
          }

          .book-sidebar::-webkit-scrollbar { width: 4px; }
          .book-sidebar::-webkit-scrollbar-thumb { background: var(--border); border-radius: 2px; }

          .chapter-group { margin-bottom: 0.25rem; }

          .chapter-title {
            display: block;
            padding: 0.4rem 1.25rem;
            font-size: 0.65rem;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.06em;
            color: var(--text-muted);
            margin-top: 0.75rem;
          }

          .chapter-title:first-child { margin-top: 0; }
          .chapter-links { list-style: none; }
          .chapter-links li { margin: 0; }

          .chapter-links a {
            display: flex;
            align-items: baseline;
            gap: 0.5rem;
            padding: 0.3rem 1.25rem;
            color: var(--text-secondary);
            text-decoration: none;
            font-size: 0.84rem;
            line-height: 1.5;
            transition: all 0.1s;
            border-left: 2px solid transparent;
          }

          .chapter-links a .num {
            font-size: 0.72rem;
            color: var(--text-muted);
            font-variant-numeric: tabular-nums;
            min-width: 1.5em;
          }

          .chapter-links a:hover {
            color: var(--text);
            background: rgba(255, 255, 255, 0.03);
          }

          .chapter-links a.active {
            color: var(--text);
            background: rgba(255, 255, 255, 0.05);
            border-left-color: var(--text);
            font-weight: 600;
          }

          .book-main {
            flex: 1;
            margin-left: var(--sidebar-w);
            display: flex;
            flex-direction: column;
            min-height: calc(100vh - var(--header-h));
            transition: margin-left 0.25s ease;
            position: relative;
          }

          .book-sidebar.collapsed ~ .book-main { margin-left: 0; }

          .book-content {
            flex: 1;
            max-width: var(--content-max-w);
            margin: 0 auto;
            padding: 2.5rem 3rem;
            width: 100%;
          }

          .book-content h1, .book-content h2, .book-content h3, .book-content h4 {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          }

          .book-content h1 { font-size: 2rem; font-weight: 700; margin: 0 0 1rem 0; letter-spacing: -0.02em; line-height: 1.3; }
          .book-content h2 { font-size: 1.5rem; font-weight: 600; margin: 2.5rem 0 0.75rem 0; letter-spacing: -0.015em; padding-bottom: 0.5rem; border-bottom: 1px solid var(--border-light); }
          .book-content h3 { font-size: 1.2rem; font-weight: 600; margin: 2rem 0 0.5rem 0; }
          .book-content h4 { font-size: 1.05rem; font-weight: 600; margin: 1.5rem 0 0.5rem 0; }
          .book-content p { margin-bottom: 1.35rem; line-height: 1.9; }
          .book-content ul, .book-content ol { margin-bottom: 1.35rem; padding-left: 1.5rem; }
          .book-content li { margin-bottom: 0.3rem; line-height: 1.85; }
          .book-content li + li { margin-top: 0.2rem; }
          .book-content strong { font-weight: 700; color: var(--text); }

          a { color: var(--text); text-decoration: underline; text-decoration-color: var(--border); text-underline-offset: 2px; transition: text-decoration-color 0.15s; }
          a:hover { text-decoration-color: var(--text-secondary); }

          code { background: var(--bg-code); padding: 0.15rem 0.4rem; border-radius: var(--radius-sm); font-size: 0.85em; font-family: "SF Mono", SFMono-Regular, ui-monospace, Menlo, Consolas, monospace; }
          pre { background: var(--bg-code); padding: 1rem 1.25rem; border-radius: var(--radius); overflow-x: auto; border: 1px solid var(--border); margin: 1.25rem 0 1.5rem 0; line-height: 1.6; }
          pre code { background: none; padding: 0; font-size: 0.84rem; }

          table { width: 100%; border-collapse: collapse; margin: 1.25rem 0 1.5rem 0; font-size: 0.9rem; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
          th { text-align: left; padding: 0.6rem 0.75rem; border-bottom: 2px solid var(--border); font-weight: 600; font-size: 0.8rem; color: var(--text-secondary); }
          td { padding: 0.55rem 0.75rem; border-bottom: 1px solid var(--border-light); vertical-align: top; }

          blockquote { border-left: 2px solid var(--border); padding: 0.5rem 1.25rem; margin: 1.25rem 0; color: var(--text-secondary); font-style: italic; }
          blockquote p { margin-bottom: 0; }

          .info-box { padding: 0.875rem 1.25rem; border-radius: var(--radius); margin: 1.25rem 0; border-left: 3px solid; font-size: 0.9rem; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
          .info-box.note { background: rgba(255, 255, 255, 0.03); border-color: #777777; }
          .info-box.warning { background: rgba(200, 160, 60, 0.06); border-color: #a08840; }
          .info-box.tip { background: rgba(100, 180, 120, 0.05); border-color: #5a9a64; }

          hr { border: none; border-top: 1px solid var(--border); margin: 2rem 0; }

          ul.section-list { list-style: none; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
          ul.section-list li { margin-bottom: 0.35rem; padding: 0.6rem 0.9rem; background: var(--bg-secondary); border-radius: var(--radius); border: 1px solid var(--border-light); transition: border-color 0.15s; }
          ul.section-list li:hover { border-color: var(--border); }
          ul.section-list li a { font-weight: 500; text-decoration: none; color: var(--text); }

          nav.pagination { margin: 1.5rem 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
          nav.pagination .pagination-list { list-style: none; display: flex; gap: 0.5rem; flex-wrap: wrap; align-items: center; }
          nav.pagination a { display: inline-block; padding: 0.25rem 0.55rem; border-radius: var(--radius); border: 1px solid var(--border); color: var(--text-secondary); text-decoration: none; }
          nav.pagination a:hover { color: var(--text); border-color: var(--text-muted); }
          .pagination-current span { display: inline-block; padding: 0.25rem 0.55rem; border-radius: var(--radius); border: 1px solid var(--text-muted); background: var(--primary-subtle); color: var(--text); }
          .pagination-disabled span { display: inline-block; padding: 0.25rem 0.55rem; border-radius: var(--radius); border: 1px solid var(--border); color: var(--text-muted); opacity: 0.5; }

          /* ── Prev / Next Side Arrows ── */
          .book-nav-arrow {
            position: fixed;
            top: 50%;
            transform: translateY(-50%);
            display: flex;
            align-items: center;
            justify-content: center;
            width: 40px;
            height: 40px;
            border-radius: 50%;
            text-decoration: none;
            color: var(--text-muted);
            background: var(--bg-secondary);
            border: 1px solid var(--border);
            transition: all 0.2s;
            z-index: 30;
            box-shadow: var(--shadow-sm);
          }

          .book-nav-arrow:hover { color: var(--text); border-color: var(--text-muted); box-shadow: var(--shadow); text-decoration: none; }
          .book-nav-arrow:active { transform: translateY(-50%) scale(0.95); }
          .book-nav-arrow svg { width: 18px; height: 18px; }
          .book-nav-arrow--prev { left: 16px; z-index: 60; }
          .book-nav-arrow--next { right: 16px; }

          .book-nav-arrow .book-nav-tooltip {
            position: absolute;
            white-space: nowrap;
            background: var(--text);
            color: var(--bg);
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            font-size: 0.72rem;
            font-weight: 500;
            padding: 0.3rem 0.6rem;
            border-radius: var(--radius-sm);
            pointer-events: none;
            opacity: 0;
            transition: opacity 0.15s;
            max-width: 200px;
            overflow: hidden;
            text-overflow: ellipsis;
          }

          .book-nav-arrow--prev .book-nav-tooltip { left: calc(100% + 8px); top: 50%; transform: translateY(-50%); }
          .book-nav-arrow--next .book-nav-tooltip { right: calc(100% + 8px); top: 50%; transform: translateY(-50%); }
          .book-nav-arrow:hover .book-nav-tooltip { opacity: 1; }

          .book-footer {
            max-width: var(--content-max-w);
            margin: 0 auto;
            padding: 1.25rem 3rem 2rem;
            width: 100%;
            border-top: 1px solid var(--border-light);
            color: var(--text-muted);
            font-size: 0.75rem;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          }

          .search-overlay { display: none; position: fixed; inset: 0; background: rgba(0, 0, 0, 0.5); backdrop-filter: blur(4px); -webkit-backdrop-filter: blur(4px); z-index: 200; justify-content: center; padding-top: 12vh; }
          .search-overlay.active { display: flex; }

          .search-modal { width: 520px; max-width: 90vw; max-height: 70vh; background: var(--bg-secondary); border-radius: var(--radius); box-shadow: 0 16px 70px rgba(0, 0, 0, 0.4); display: flex; flex-direction: column; overflow: hidden; align-self: flex-start; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
          .search-input-wrap { display: flex; align-items: center; gap: 0.6rem; padding: 0.75rem 1rem; border-bottom: 1px solid var(--border-light); }
          .search-input-wrap svg { flex-shrink: 0; color: var(--text-muted); }
          .search-input-wrap input { flex: 1; border: none; outline: none; font-size: 0.95rem; font-family: inherit; color: var(--text); background: transparent; }
          .search-input-wrap input::placeholder { color: var(--text-muted); }
          .search-input-wrap kbd { font-size: 0.6rem; padding: 0.1rem 0.35rem; border: 1px solid var(--border); border-radius: 3px; background: var(--bg); color: var(--text-muted); font-family: inherit; cursor: pointer; line-height: 1.4; }

          .search-results { overflow-y: auto; padding: 0.5rem; }
          .search-result-item { display: block; padding: 0.5rem 0.75rem; border-radius: var(--radius-sm); text-decoration: none; color: var(--text); cursor: pointer; transition: background 0.1s; }
          .search-result-item:hover, .search-result-item.active { background: var(--bg); text-decoration: none; }
          .search-result-item .search-result-title { font-weight: 500; font-size: 0.88rem; margin-bottom: 0.1rem; }
          .search-result-item .search-result-snippet { font-size: 0.78rem; color: var(--text-secondary); line-height: 1.4; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
          .search-result-item .search-result-snippet mark { background: rgba(255, 255, 255, 0.08); color: var(--text); border-radius: 2px; padding: 0 1px; }
          .search-no-results { padding: 2rem 1rem; text-align: center; color: var(--text-muted); font-size: 0.88rem; }
          .search-hint { padding: 0.5rem 0.75rem; display: flex; gap: 1rem; justify-content: center; border-top: 1px solid var(--border-light); color: var(--text-muted); font-size: 0.65rem; }
          .search-hint kbd { font-size: 0.6rem; padding: 0 0.25rem; border: 1px solid var(--border); border-radius: 3px; background: var(--bg); font-family: inherit; line-height: 1.4; }

          @media (max-width: 900px) {
            .book-sidebar { transform: translateX(-100%); visibility: hidden; }
            .book-sidebar.open { transform: translateX(0); visibility: visible; box-shadow: 4px 0 24px rgba(0, 0, 0, 0.3); }
            .book-main { margin-left: 0 !important; }
            .book-content { padding: 1.5rem 1.25rem; }
            .book-nav-arrow { display: none; }
            .book-footer { padding: 1rem 1.25rem 1.5rem; }
          }

          @media (min-width: 901px) {
            .book-sidebar.open { transform: translateX(0); visibility: visible; }
          }
          CSS
        end
      end
    end
  end
end
