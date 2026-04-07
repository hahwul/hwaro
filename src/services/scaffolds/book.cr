# Book scaffold - mdBook-style book structure
#
# This scaffold creates a book-style site with chapter-based navigation,
# previous/next page links, keyboard arrow key navigation, and a clean
# reading-focused design inspired by mdBook.

require "./base"

module Hwaro
  module Services
    module Scaffolds
      class Book < Base
        def type : Config::Options::ScaffoldType
          Config::Options::ScaffoldType::Book
        end

        def description : String
          "Book-style structure with chapters, prev/next navigation, and keyboard shortcuts"
        end

        protected def config_title : String
          "My Book"
        end

        protected def config_description : String
          "A book powered by Hwaro."
        end

        def content_files(skip_taxonomies : Bool = false) : Hash(String, String)
          files = {} of String => String

          files["index.md"] = index_content

          # Chapter 1
          files["chapter-1/_index.md"] = chapter_1_index
          files["chapter-1/getting-started.md"] = getting_started_content
          files["chapter-1/installation.md"] = installation_content

          # Chapter 2
          files["chapter-2/_index.md"] = chapter_2_index
          files["chapter-2/basic-usage.md"] = basic_usage_content
          files["chapter-2/configuration.md"] = configuration_content

          # Chapter 3
          files["chapter-3/_index.md"] = chapter_3_index
          files["chapter-3/advanced-topics.md"] = advanced_topics_content

          files
        end

        def template_files(skip_taxonomies : Bool = false) : Hash(String, String)
          files = {
            "header.html"  => header_template,
            "footer.html"  => footer_template,
            "page.html"    => book_page_template,
            "section.html" => book_section_template,
            "404.html"     => not_found_template,
          }

          unless skip_taxonomies
            files["taxonomy.html"] = taxonomy_template
            files["taxonomy_term.html"] = taxonomy_term_template
          end

          files
        end

        def config_content(skip_taxonomies : Bool = false) : String
          config = String.build do |str|
            str << base_config(config_title, config_description)
            str << multilingual_config
            str << plugins_config
            str << content_files_config
            str << highlight_config
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

        protected def header_template : String
          <<-HTML
          <!DOCTYPE html>
          <html lang="{{ page_language }}">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta name="description" content="{{ page.description | e }}">
            <title>{{ page.title | e }} - {{ site.title | e }}</title>
            {{ og_all_tags }}
            {{ hreflang_tags }}
            #{styles}
            {{ highlight_css }}
            {{ auto_includes_css }}
          </head>
          <body data-section="{{ page.section }}">
          HTML
        end

        protected def styles : String
          <<-CSS
            <link rel="stylesheet" href="{{ base_url }}/css/style.css">
          CSS
        end

        def static_files : Hash(String, String)
          {
            "css/style.css" => css_content,
            "js/book.js"    => book_js_content,
          }
        end

        private def css_content : String
          <<-CSS
          :root {
            --primary: #444444;
            --primary-hover: #222222;
            --primary-subtle: rgba(0, 0, 0, 0.035);
            --text: #1a1a1a;
            --text-secondary: #555555;
            --text-muted: #aaaaaa;
            --border: #e5e5e5;
            --border-light: #f0f0f0;
            --bg: #ffffff;
            --bg-secondary: #f7f7f7;
            --bg-sidebar: #f9f9f9;
            --bg-code: #f5f5f5;
            --header-h: 50px;
            --sidebar-w: 280px;
            --content-max-w: 780px;
            --radius: 6px;
            --radius-sm: 3px;
            --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.04);
            --shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
          }

          *,
          *::before,
          *::after {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
          }

          html {
            scroll-behavior: smooth;
          }

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
            top: 0;
            left: 0;
            right: 0;
            height: var(--header-h);
            background: var(--bg);
            border-bottom: 1px solid var(--border);
            display: grid;
            grid-template-columns: 1fr auto 1fr;
            align-items: center;
            padding: 0 0.75rem;
            z-index: 100;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          }

          .header-left {
            display: flex;
            align-items: center;
            justify-content: flex-start;
          }

          .header-center {
            display: flex;
            align-items: center;
            justify-content: center;
          }

          .header-right {
            display: flex;
            align-items: center;
            justify-content: flex-end;
            gap: 0.25rem;
          }

          /* ── Icon Button (shared by toggle, search, fullscreen) ── */
          .icon-btn {
            display: flex;
            align-items: center;
            justify-content: center;
            width: 34px;
            height: 34px;
            border: none;
            border-radius: var(--radius-sm);
            background: none;
            color: var(--text-muted);
            cursor: pointer;
            transition: color 0.15s, background 0.15s;
            padding: 0;
          }

          .icon-btn:hover {
            color: var(--text-secondary);
            background: var(--primary-subtle);
          }

          .book-header .logo {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            font-weight: 500;
            font-size: 0.82rem;
            color: var(--text-secondary);
            text-decoration: none;
            letter-spacing: 0.01em;
          }

          .book-header .logo:hover {
            color: var(--text);
            text-decoration: none;
          }

          /* ── Fullscreen Toggle ── */
          .fullscreen-toggle .fs-exit {
            display: none;
          }

          .fullscreen-active .fullscreen-toggle .fs-enter {
            display: none;
          }

          .fullscreen-active .fullscreen-toggle .fs-exit {
            display: block;
          }

          /* ── Layout ── */
          .book-container {
            display: flex;
            padding-top: var(--header-h);
            min-height: 100vh;
          }

          /* ── Sidebar ── */
          .book-sidebar {
            position: fixed;
            top: var(--header-h);
            left: 0;
            width: var(--sidebar-w);
            height: calc(100vh - var(--header-h));
            background: var(--bg-sidebar);
            border-right: 1px solid var(--border);
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

          .book-sidebar::-webkit-scrollbar {
            width: 4px;
          }

          .book-sidebar::-webkit-scrollbar-thumb {
            background: var(--border);
            border-radius: 2px;
          }

          .chapter-group {
            margin-bottom: 0.25rem;
          }

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

          .chapter-title:first-child {
            margin-top: 0;
          }

          .chapter-links {
            list-style: none;
          }

          .chapter-links li {
            margin: 0;
          }

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
            background: rgba(0, 0, 0, 0.025);
          }

          .chapter-links a.active {
            color: var(--text);
            background: rgba(0, 0, 0, 0.04);
            border-left-color: var(--text);
            font-weight: 600;
          }

          /* ── Main Content ── */
          .book-main {
            flex: 1;
            margin-left: var(--sidebar-w);
            display: flex;
            flex-direction: column;
            min-height: calc(100vh - var(--header-h));
            transition: margin-left 0.25s ease;
            position: relative;
          }

          .book-sidebar.collapsed ~ .book-main {
            margin-left: 0;
          }

          .book-content {
            flex: 1;
            max-width: var(--content-max-w);
            margin: 0 auto;
            padding: 2.5rem 3rem;
            width: 100%;
          }

          /* ── Typography ── */
          .book-content h1,
          .book-content h2,
          .book-content h3,
          .book-content h4 {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          }

          .book-content h1 {
            font-size: 2rem;
            font-weight: 700;
            margin: 0 0 1rem 0;
            letter-spacing: -0.02em;
            line-height: 1.3;
            color: var(--text);
          }

          .book-content h2 {
            font-size: 1.5rem;
            font-weight: 600;
            margin: 2.5rem 0 0.75rem 0;
            letter-spacing: -0.015em;
            padding-bottom: 0.5rem;
            border-bottom: 1px solid var(--border-light);
          }

          .book-content h3 {
            font-size: 1.2rem;
            font-weight: 600;
            margin: 2rem 0 0.5rem 0;
          }

          .book-content h4 {
            font-size: 1.05rem;
            font-weight: 600;
            margin: 1.5rem 0 0.5rem 0;
          }

          .book-content p {
            margin-bottom: 1.35rem;
            line-height: 1.9;
          }

          .book-content ul,
          .book-content ol {
            margin-bottom: 1.35rem;
            padding-left: 1.5rem;
          }

          .book-content li {
            margin-bottom: 0.3rem;
            line-height: 1.85;
          }

          .book-content li + li {
            margin-top: 0.2rem;
          }

          .book-content strong {
            font-weight: 700;
            color: var(--text);
          }

          /* Links */
          a {
            color: var(--text);
            text-decoration: underline;
            text-decoration-color: var(--border);
            text-underline-offset: 2px;
            transition: text-decoration-color 0.15s;
          }

          a:hover {
            text-decoration-color: var(--text);
          }

          /* Code */
          code {
            background: var(--bg-code);
            padding: 0.15rem 0.4rem;
            border-radius: var(--radius-sm);
            font-size: 0.85em;
            font-family: "SF Mono", SFMono-Regular, ui-monospace, Menlo, Consolas, monospace;
          }

          pre {
            background: var(--bg-code);
            padding: 1rem 1.25rem;
            border-radius: var(--radius);
            overflow-x: auto;
            border: 1px solid var(--border);
            margin: 1.25rem 0 1.5rem 0;
            line-height: 1.6;
          }

          pre code {
            background: none;
            padding: 0;
            font-size: 0.84rem;
          }

          /* Tables */
          table {
            width: 100%;
            border-collapse: collapse;
            margin: 1.25rem 0 1.5rem 0;
            font-size: 0.9rem;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          }

          th {
            text-align: left;
            padding: 0.6rem 0.75rem;
            border-bottom: 2px solid var(--border);
            font-weight: 600;
            font-size: 0.8rem;
            color: var(--text-secondary);
          }

          td {
            padding: 0.55rem 0.75rem;
            border-bottom: 1px solid var(--border-light);
            vertical-align: top;
          }

          /* Blockquote */
          blockquote {
            border-left: 2px solid var(--border);
            padding: 0.5rem 1.25rem;
            margin: 1.25rem 0;
            color: var(--text-secondary);
            font-style: italic;
          }

          blockquote p {
            margin-bottom: 0;
          }

          /* Info boxes */
          .info-box {
            padding: 0.875rem 1.25rem;
            border-radius: var(--radius);
            margin: 1.25rem 0;
            border-left: 3px solid;
            font-size: 0.9rem;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          }

          .info-box.note {
            background: rgba(0, 0, 0, 0.025);
            border-color: #999999;
          }

          .info-box.warning {
            background: rgba(180, 130, 40, 0.05);
            border-color: #b0873a;
          }

          .info-box.tip {
            background: rgba(60, 130, 80, 0.04);
            border-color: #6a9a6e;
          }

          /* Horizontal rule */
          hr {
            border: none;
            border-top: 1px solid var(--border);
            margin: 2rem 0;
          }

          /* Section list */
          ul.section-list {
            list-style: none;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          }

          ul.section-list li {
            margin-bottom: 0.35rem;
            padding: 0.6rem 0.9rem;
            background: var(--bg-secondary);
            border-radius: var(--radius);
            border: 1px solid var(--border-light);
            transition: border-color 0.15s;
          }

          ul.section-list li:hover {
            border-color: var(--border);
          }

          ul.section-list li a {
            font-weight: 500;
            text-decoration: none;
            color: var(--text);
          }

          /* Pagination */
          nav.pagination {
            margin: 1.5rem 0;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
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
            border-radius: var(--radius);
            border: 1px solid var(--border);
            color: var(--text-secondary);
            text-decoration: none;
          }

          nav.pagination a:hover {
            color: var(--text);
            border-color: var(--text-muted);
          }

          .pagination-current span {
            display: inline-block;
            padding: 0.25rem 0.55rem;
            border-radius: var(--radius);
            border: 1px solid var(--text-muted);
            background: var(--primary-subtle);
            color: var(--text);
          }

          .pagination-disabled span {
            display: inline-block;
            padding: 0.25rem 0.55rem;
            border-radius: var(--radius);
            border: 1px solid var(--border);
            color: var(--text-muted);
            opacity: 0.5;
          }

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
            background: var(--bg);
            border: 1px solid var(--border);
            transition: all 0.2s;
            z-index: 30;
            box-shadow: var(--shadow-sm);
          }

          .book-nav-arrow:hover {
            color: var(--text);
            border-color: var(--text-muted);
            box-shadow: var(--shadow);
            text-decoration: none;
          }

          .book-nav-arrow:active {
            transform: translateY(-50%) scale(0.95);
          }

          .book-nav-arrow svg {
            width: 18px;
            height: 18px;
          }

          .book-nav-arrow--prev {
            left: 16px;
            z-index: 60;
          }

          .book-nav-arrow--next {
            right: 16px;
          }

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

          .book-nav-arrow--prev .book-nav-tooltip {
            left: calc(100% + 8px);
            top: 50%;
            transform: translateY(-50%);
          }

          .book-nav-arrow--next .book-nav-tooltip {
            right: calc(100% + 8px);
            top: 50%;
            transform: translateY(-50%);
          }

          .book-nav-arrow:hover .book-nav-tooltip {
            opacity: 1;
          }

          /* ── Footer ── */
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

          /* ── Search Overlay ── */
          .search-overlay {
            display: none;
            position: fixed;
            inset: 0;
            background: rgba(0, 0, 0, 0.3);
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
            width: 520px;
            max-width: 90vw;
            max-height: 70vh;
            background: var(--bg);
            border-radius: var(--radius);
            box-shadow: 0 16px 70px rgba(0, 0, 0, 0.15);
            display: flex;
            flex-direction: column;
            overflow: hidden;
            align-self: flex-start;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
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
            font-size: 0.95rem;
            font-family: inherit;
            color: var(--text);
            background: transparent;
          }

          .search-input-wrap input::placeholder {
            color: var(--text-muted);
          }

          .search-input-wrap kbd {
            font-size: 0.6rem;
            padding: 0.1rem 0.35rem;
            border: 1px solid var(--border);
            border-radius: 3px;
            background: var(--bg-secondary);
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
            padding: 0.5rem 0.75rem;
            border-radius: var(--radius-sm);
            text-decoration: none;
            color: var(--text);
            cursor: pointer;
            transition: background 0.1s;
          }

          .search-result-item:hover,
          .search-result-item.active {
            background: var(--bg-secondary);
            text-decoration: none;
          }

          .search-result-item .search-result-title {
            font-weight: 500;
            font-size: 0.88rem;
            margin-bottom: 0.1rem;
          }

          .search-result-item .search-result-snippet {
            font-size: 0.78rem;
            color: var(--text-secondary);
            line-height: 1.4;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
            overflow: hidden;
          }

          .search-result-item .search-result-snippet mark {
            background: rgba(0, 0, 0, 0.07);
            color: var(--text);
            border-radius: 2px;
            padding: 0 1px;
          }

          .search-no-results {
            padding: 2rem 1rem;
            text-align: center;
            color: var(--text-muted);
            font-size: 0.88rem;
          }

          .search-hint {
            padding: 0.5rem 0.75rem;
            display: flex;
            gap: 1rem;
            justify-content: center;
            border-top: 1px solid var(--border-light);
            color: var(--text-muted);
            font-size: 0.65rem;
          }

          .search-hint kbd {
            font-size: 0.6rem;
            padding: 0 0.25rem;
            border: 1px solid var(--border);
            border-radius: 3px;
            background: var(--bg-secondary);
            font-family: inherit;
            line-height: 1.4;
          }

          /* ── Responsive ── */
          @media (max-width: 900px) {
            .book-sidebar {
              transform: translateX(-100%);
              visibility: hidden;
            }

            .book-sidebar.open {
              transform: translateX(0);
              visibility: visible;
              box-shadow: 4px 0 24px rgba(0, 0, 0, 0.08);
            }

            .book-main {
              margin-left: 0 !important;
            }

            .book-content {
              padding: 1.5rem 1.25rem;
            }

            .book-nav-arrow {
              display: none;
            }

            .book-footer {
              padding: 1rem 1.25rem 1.5rem;
            }
          }

          @media (min-width: 901px) {
            .book-sidebar.open {
              transform: translateX(0);
              visibility: visible;
            }
          }
          CSS
        end

        private def book_js_content : String
          <<-JS
          (function () {
            // ── Keyboard Navigation (← →) ──
            var prevLink = document.querySelector('.book-nav-arrow--prev');
            var nextLink = document.querySelector('.book-nav-arrow--next');

            document.addEventListener('keydown', function (e) {
              // Skip if user is typing in an input/textarea or search is open
              var tag = e.target.tagName;
              if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
              if (e.target.isContentEditable) return;
              if (document.querySelector('.search-overlay.active')) return;

              if (e.key === 'ArrowLeft' && prevLink) {
                e.preventDefault();
                window.location.href = prevLink.href;
              } else if (e.key === 'ArrowRight' && nextLink) {
                e.preventDefault();
                window.location.href = nextLink.href;
              }
            });

            // ── Sidebar Toggle ──
            var SIDEBAR_KEY = 'hwaro-book-sidebar';
            var toggle = document.querySelector('.menu-toggle');
            var sidebar = document.querySelector('.book-sidebar');
            var isMobile = window.matchMedia('(max-width: 900px)');

            function applySidebarState() {
              if (!sidebar) return;
              if (isMobile.matches) {
                // On mobile: start collapsed, toggle with 'open' class
                sidebar.classList.remove('collapsed');
                sidebar.classList.remove('open');
              } else {
                // On desktop: respect stored preference (default: collapsed)
                var stored = localStorage.getItem(SIDEBAR_KEY);
                if (stored === 'open') {
                  sidebar.classList.remove('collapsed');
                } else {
                  sidebar.classList.add('collapsed');
                }
              }
            }

            applySidebarState();
            isMobile.addEventListener('change', applySidebarState);

            if (toggle && sidebar) {
              toggle.addEventListener('click', function () {
                if (isMobile.matches) {
                  sidebar.classList.toggle('open');
                } else {
                  var collapsed = sidebar.classList.toggle('collapsed');
                  localStorage.setItem(SIDEBAR_KEY, collapsed ? 'collapsed' : 'open');
                }
              });
              // Close sidebar overlay when clicking outside on mobile
              document.addEventListener('click', function (e) {
                if (isMobile.matches && sidebar.classList.contains('open') &&
                    !sidebar.contains(e.target) &&
                    !toggle.contains(e.target)) {
                  sidebar.classList.remove('open');
                }
              });
            }

            // ── Active Sidebar Link ──
            var currentPath = window.location.pathname.replace(/\\/+$/, '') || '/';
            var links = document.querySelectorAll('.chapter-links a');
            for (var i = 0; i < links.length; i++) {
              var linkPath = links[i].getAttribute('href');
              if (linkPath) {
                linkPath = linkPath.replace(/\\/+$/, '') || '/';
                if (linkPath === currentPath) {
                  links[i].classList.add('active');
                  links[i].scrollIntoView({ block: 'center', behavior: 'instant' });
                }
              }
            }

            // ── Search ──
            var searchData = null;
            var activeIndex = -1;
            var overlay = document.getElementById('searchOverlay');
            var input = document.getElementById('searchInput');
            var resultsEl = document.getElementById('searchResults');

            function loadSearchData(cb) {
              if (searchData) return cb(searchData);
              var base = document.querySelector('link[rel="stylesheet"]').href;
              var searchUrl = base.substring(0, base.indexOf('/css/')) + '/search.json';
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
              var results = [];
              for (var i = 0; i < searchData.length; i++) {
                var item = searchData[i];
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
            // ── Fullscreen ──
            window.toggleFullscreen = function () {
              if (!document.fullscreenElement) {
                document.documentElement.requestFullscreen().then(function () {
                  document.body.classList.add('fullscreen-active');
                }).catch(function () {});
              } else {
                document.exitFullscreen().then(function () {
                  document.body.classList.remove('fullscreen-active');
                }).catch(function () {});
              }
            };

            document.addEventListener('fullscreenchange', function () {
              if (!document.fullscreenElement) {
                document.body.classList.remove('fullscreen-active');
              }
            });
          })();
          JS
        end

        # Footer template
        protected def footer_template : String
          <<-HTML
              <div class="book-footer">
                <p>Powered by Hwaro</p>
              </div>
            </main>
          </div>
          {{ highlight_js }}
          <script src="{{ base_url }}/js/book.js"></script>
          {{ auto_includes_js }}
          </body>
          </html>
          HTML
        end

        # Search overlay HTML
        private def search_overlay_html : String
          <<-HTML
          <div class="search-overlay" id="searchOverlay" onclick="if(event.target===this)closeSearch()">
            <div class="search-modal">
              <div class="search-input-wrap">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
                <input type="text" id="searchInput" placeholder="Search this book..." autocomplete="off">
                <kbd onclick="closeSearch()">ESC</kbd>
              </div>
              <div class="search-results" id="searchResults"></div>
            </div>
          </div>
          HTML
        end

        # Header navigation
        private def book_header_html : String
          <<-HTML
          <header class="book-header">
            <div class="header-left">
              <button class="icon-btn menu-toggle" aria-label="Toggle sidebar">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="18" x2="21" y2="18"/></svg>
              </button>
            </div>
            <div class="header-center">
              <a href="{{ base_url }}/" class="logo">{{ site.title }}</a>
            </div>
            <div class="header-right">
              <button class="icon-btn" onclick="openSearch()" title="Search (⌘K)" aria-label="Search">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
              </button>
              <button class="icon-btn fullscreen-toggle" onclick="toggleFullscreen()" title="Toggle fullscreen" aria-label="Toggle fullscreen">
                <svg class="fs-enter" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 3 21 3 21 9"/><polyline points="9 21 3 21 3 15"/><line x1="21" y1="3" x2="14" y2="10"/><line x1="3" y1="21" x2="10" y2="14"/></svg>
                <svg class="fs-exit" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 14 10 14 10 20"/><polyline points="20 10 14 10 14 4"/><line x1="14" y1="10" x2="21" y2="3"/><line x1="3" y1="21" x2="10" y2="14"/></svg>
              </button>
            </div>
          </header>
          HTML
        end

        # Sidebar
        private def book_sidebar_html : String
          <<-HTML
            <aside class="book-sidebar collapsed">
              <div class="chapter-group">
                <span class="chapter-title">Introduction</span>
                <ul class="chapter-links">
                  <li><a href="{{ base_url }}/">Welcome</a></li>
                </ul>
              </div>
              <div class="chapter-group">
                <span class="chapter-title">Chapter 1</span>
                <ul class="chapter-links">
                  <li><a href="{{ base_url }}/chapter-1/"><span class="num">1.</span> Getting Started</a></li>
                  <li><a href="{{ base_url }}/chapter-1/getting-started/"><span class="num">1.1</span> Overview</a></li>
                  <li><a href="{{ base_url }}/chapter-1/installation/"><span class="num">1.2</span> Installation</a></li>
                </ul>
              </div>
              <div class="chapter-group">
                <span class="chapter-title">Chapter 2</span>
                <ul class="chapter-links">
                  <li><a href="{{ base_url }}/chapter-2/"><span class="num">2.</span> Usage</a></li>
                  <li><a href="{{ base_url }}/chapter-2/basic-usage/"><span class="num">2.1</span> Basic Usage</a></li>
                  <li><a href="{{ base_url }}/chapter-2/configuration/"><span class="num">2.2</span> Configuration</a></li>
                </ul>
              </div>
              <div class="chapter-group">
                <span class="chapter-title">Chapter 3</span>
                <ul class="chapter-links">
                  <li><a href="{{ base_url }}/chapter-3/"><span class="num">3.</span> Advanced</a></li>
                  <li><a href="{{ base_url }}/chapter-3/advanced-topics/"><span class="num">3.1</span> Advanced Topics</a></li>
                </ul>
              </div>
            </aside>
          HTML
        end

        # Prev/Next side arrow navigation HTML
        private def book_nav_html : String
          <<-HTML
          {% if page.lower %}
          <a href="{{ page.lower.url }}" class="book-nav-arrow book-nav-arrow--prev" title="{{ page.lower.title }}">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>
            <span class="book-nav-tooltip">{{ page.lower.title }}</span>
          </a>
          {% endif %}
          {% if page.higher %}
          <a href="{{ page.higher.url }}" class="book-nav-arrow book-nav-arrow--next" title="{{ page.higher.title }}">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>
            <span class="book-nav-tooltip">{{ page.higher.title }}</span>
          </a>
          {% endif %}
          HTML
        end

        # Page template
        private def book_page_template : String
          <<-HTML
          {% include "header.html" %}
          #{book_header_html}
          #{search_overlay_html}
          #{book_nav_html}
          <div class="book-container">
          #{book_sidebar_html}
            <main class="book-main">
              <div class="book-content">
                <h1>{{ page.title | e }}</h1>
                {{ content }}
              </div>
          {% include "footer.html" %}
          HTML
        end

        # Section template
        private def book_section_template : String
          <<-HTML
          {% include "header.html" %}
          #{book_header_html}
          #{search_overlay_html}
          #{book_nav_html}
          <div class="book-container">
          #{book_sidebar_html}
            <main class="book-main">
              <div class="book-content">
                <h1>{{ page.title | e }}</h1>
                {{ content }}

                <h2>In This Chapter</h2>
                <ul class="section-list">
                  {{ section.list }}
                </ul>
                {{ pagination }}
              </div>
          {% include "footer.html" %}
          HTML
        end

        # ── Content Files ──

        private def index_content : String
          <<-CONTENT
+++
title = "Introduction"
weight = 0
+++

Welcome to **My Book**. This book is powered by [Hwaro](https://github.com/hahwul/hwaro), a fast and lightweight static site generator.

## What This Book Covers

This book is organized into the following chapters:

- **Chapter 1: Getting Started** - Learn the fundamentals and get set up
- **Chapter 2: Usage** - Understand basic usage and configuration
- **Chapter 3: Advanced** - Dive into advanced topics and techniques

## How to Navigate

You can navigate this book using:

- The **sidebar** on the left to jump to any chapter
- The **previous/next links** at the bottom of each page
- **Keyboard shortcuts**: press `←` and `→` arrow keys to go to the previous or next page
- **Search**: press `Ctrl+K` or `⌘K` to search the entire book
CONTENT
        end

        private def chapter_1_index : String
          <<-CONTENT
+++
title = "Getting Started"
weight = 1
+++

This chapter covers the fundamentals you need to know before diving in.

## Overview

We'll walk you through:

1. A high-level overview of the project
2. Installing the required dependencies
3. Setting up your development environment
CONTENT
        end

        private def getting_started_content : String
          <<-CONTENT
+++
title = "Overview"
weight = 1
+++

Let's start with a high-level overview of what this project is about and what problems it solves.

## Background

This project was created to solve common challenges in building documentation and reference material.

## Key Concepts

Before proceeding, familiarize yourself with these key concepts:

- **Content** - Markdown files that contain your writing
- **Templates** - HTML templates that control layout and presentation
- **Configuration** - TOML files that customize behavior

## Prerequisites

Make sure you have the following installed:

- A text editor
- A terminal application
- Git (recommended)

## Next Steps

Once you're familiar with these concepts, proceed to [Installation](/chapter-1/installation/).
CONTENT
        end

        private def installation_content : String
          <<-CONTENT
+++
title = "Installation"
weight = 2
+++

This page walks you through the installation process.

## System Requirements

- macOS, Linux, or Windows (WSL)
- 512MB RAM minimum

## Install from Source

```bash
git clone https://github.com/hahwul/hwaro
cd hwaro
shards install
shards build --release
```

## Verify Installation

```bash
./bin/hwaro --version
```

You should see a version number printed to the terminal.

## Create Your First Project

```bash
hwaro init my-book --scaffold book
cd my-book
hwaro serve
```

Visit `http://localhost:3000` in your browser to see the result.
CONTENT
        end

        private def chapter_2_index : String
          <<-CONTENT
+++
title = "Usage"
weight = 2
+++

Now that you have everything installed, let's learn how to use it effectively.

## Topics

- **Basic Usage** - Day-to-day commands and workflows
- **Configuration** - Customizing behavior through config files
CONTENT
        end

        private def basic_usage_content : String
          <<-CONTENT
+++
title = "Basic Usage"
weight = 1
+++

Learn the essential commands and workflows for daily use.

## Building Your Site

```bash
hwaro build
```

This compiles all content into the `public/` directory.

## Development Server

```bash
hwaro serve
```

Starts a local server at `http://localhost:3000` with live reload.

## Creating New Content

```bash
hwaro new chapter-2/new-page.md
```

This creates a new Markdown file with front matter template.

## Project Structure

```
my-book/
├── config.toml          # Site configuration
├── content/             # Your book content
│   ├── index.md         # Introduction
│   ├── chapter-1/       # Chapter 1
│   │   ├── _index.md
│   │   └── ...
│   └── chapter-2/       # Chapter 2
│       └── ...
├── templates/           # Page templates
├── static/              # Static assets (CSS, JS)
└── public/              # Generated output
```

## Tips

- Use `weight` in front matter to control page ordering within chapters
- Use `draft = true` to hide work-in-progress pages from builds
- Add `<!-- more -->` in content to define a summary break point
CONTENT
        end

        private def configuration_content : String
          <<-CONTENT
+++
title = "Configuration"
weight = 2
+++

Customize your book through the `config.toml` file.

## Basic Settings

```toml
title = "My Book"
description = "A comprehensive guide"
base_url = "https://mybook.example.com"
```

## Search

Enable full-text search:

```toml
[search]
enabled = true
format = "fuse_json"
fields = ["title", "content"]
```

## Syntax Highlighting

```toml
[highlight]
enabled = true
theme = "github"
use_cdn = true
```

## SEO

```toml
[sitemap]
enabled = true

[robots]
enabled = true
```

## All Options

For a complete list of configuration options, refer to the [Hwaro documentation](https://github.com/hahwul/hwaro).
CONTENT
        end

        private def chapter_3_index : String
          <<-CONTENT
+++
title = "Advanced"
weight = 3
+++

This chapter covers advanced topics for power users.

## Topics

- **Advanced Topics** - Customization, theming, and extending functionality
CONTENT
        end

        private def advanced_topics_content : String
          <<-CONTENT
+++
title = "Advanced Topics"
weight = 1
+++

Once you've mastered the basics, explore these advanced features.

## Custom Templates

Override any template by creating a file with the same name in your `templates/` directory:

```
templates/
├── page.html       # Override the default page layout
├── section.html    # Override the section layout
└── shortcodes/     # Custom shortcode templates
    └── note.html
```

## Shortcodes

Create reusable content components:

```jinja
{# templates/shortcodes/note.html #}
<div class="info-box note">
  <strong>Note:</strong> {{ body }}
</div>
```

Use in your Markdown:

```jinja
{{ note(body="This is an important note.") }}
```

## Taxonomies

Organize content with tags and categories:

```toml
[[taxonomies]]
name = "tags"
feed = true
```

In your content front matter:

```toml
+++
title = "My Page"
[taxonomies]
tags = ["guide", "advanced"]
+++
```

## Multilingual Support

Add language variants:

```toml
default_language = "en"

[languages.en]
language_name = "English"

[languages.ko]
language_name = "한국어"
```

Create translated files using language suffixes: `page.ko.md`
CONTENT
        end
      end
    end
  end
end
