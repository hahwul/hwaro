# Docs scaffold - documentation-focused structure
#
# This scaffold creates a documentation site with organized sections,
# sidebar navigation, search overlay, and Apple-inspired design.

require "./base"

module Hwaro
  module Services
    module Scaffolds
      class Docs < Base
        def type : Config::Options::ScaffoldType
          Config::Options::ScaffoldType::Docs
        end

        def description : String
          "Documentation-focused structure with organized sections and sidebar"
        end

        protected def config_title : String
          "Documentation"
        end

        protected def config_description : String
          "Project documentation powered by Hwaro."
        end

        def content_files(skip_taxonomies : Bool = false) : Hash(String, String)
          files = {} of String => String

          # Homepage (docs landing)
          files["index.md"] = index_content

          # Getting Started section
          files["getting-started/_index.md"] = getting_started_index
          files["getting-started/installation.md"] = installation_content
          files["getting-started/quick-start.md"] = quick_start_content
          files["getting-started/configuration.md"] = configuration_content

          # Guide section
          files["guide/_index.md"] = guide_index
          files["guide/content-management.md"] = content_management_content
          files["guide/templates.md"] = templates_content
          files["guide/shortcodes.md"] = shortcodes_content

          # API Reference section
          files["reference/_index.md"] = reference_index
          files["reference/cli.md"] = cli_reference_content
          files["reference/config.md"] = config_reference_content

          files
        end

        def template_files(skip_taxonomies : Bool = false) : Hash(String, String)
          files = {
            "header.html"  => header_template,
            "footer.html"  => footer_template,
            "page.html"    => docs_page_template,
            "section.html" => docs_section_template,
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
            # Site basics
            str << base_config("Documentation", "Project documentation powered by Hwaro.")

            # Content & Processing
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

        # Override header for docs - minimal header integrated with layout (Jinja2 syntax)
        protected def header_template : String
          <<-HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta name="description" content="{{ page.description }}">
            <title>{{ page.title }} - {{ site.title }}</title>
            {{ og_all_tags }}
            #{styles}
            {{ highlight_css }}
            {{ auto_includes_css }}
          </head>
          <body data-section="{{ page.section }}">
          HTML
        end

        # Override styles for docs - modern unified layout
        protected def styles : String
          <<-CSS
            <link rel="stylesheet" href="{{ base_url }}/css/style.css">
          CSS
        end

        def static_files : Hash(String, String)
          {
            "css/style.css" => css_content,
            "js/search.js"  => search_js_content,
          }
        end

        private def css_content : String
          <<-CSS
          :root {
            --primary: #0071e3;
            --primary-hover: #0077ed;
            --text: #1d1d1f;
            --text-secondary: #6e6e73;
            --text-muted: #86868b;
            --border: #d2d2d7;
            --border-light: #e8e8ed;
            --bg: #ffffff;
            --bg-secondary: #f5f5f7;
            --bg-code: #f5f5f7;
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
            background: rgba(255, 255, 255, 0.8);
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
            background: #eef6ff;
            border-color: var(--primary);
          }

          .info-box.warning {
            background: #fff8e6;
            border-color: #bf5600;
          }

          .info-box.tip {
            background: #eefbf1;
            border-color: #1a7f37;
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
            background: rgba(0, 0, 0, 0.4);
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
            padding: 0.6rem 0.75rem;
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
            background: rgba(0, 113, 227, 0.15);
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
            background: var(--bg-secondary);
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

        private def search_js_content : String
          <<-JS
          (function () {
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
          })();
          JS
        end

        # Docs-specific page template
        # Override footer for docs (Jinja2 syntax)
        protected def footer_template : String
          <<-HTML
              <div class="docs-footer">
                <p>Powered by Hwaro</p>
              </div>
            </main>
          </div>
          {{ highlight_js }}
          <script src="{{ base_url }}/js/search.js"></script>
          {{ auto_includes_js }}
          </body>
          </html>
          HTML
        end

        # Search overlay HTML shared by page and section templates
        private def search_overlay_html : String
          <<-HTML
          <div class="search-overlay" id="searchOverlay" onclick="if(event.target===this)closeSearch()">
            <div class="search-modal">
              <div class="search-input-wrap">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
                <input type="text" id="searchInput" placeholder="Search documentation..." autocomplete="off">
                <kbd onclick="closeSearch()">ESC</kbd>
              </div>
              <div class="search-results" id="searchResults"></div>
            </div>
          </div>
          HTML
        end

        # Header navigation HTML shared by page and section templates
        private def docs_nav_html : String
          <<-HTML
          <header class="docs-header">
            <a href="{{ base_url }}/" class="logo">{{ site.title }} <span>Documentation</span></a>
            <nav>
              <a href="{{ base_url }}/getting-started/">Getting Started</a>
              <a href="{{ base_url }}/guide/">Guide</a>
              <a href="{{ base_url }}/reference/">Reference</a>
            </nav>
            <div class="header-right">
              <button class="search-trigger" onclick="openSearch()" title="Search">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
                <span>Search</span>
                <kbd>&#8984;K</kbd>
              </button>
            </div>
          </header>
          HTML
        end

        # Sidebar HTML shared by page and section templates
        private def docs_sidebar_html : String
          <<-HTML
            <aside class="docs-sidebar">
              <div class="sidebar-section">
                <div class="sidebar-title">Getting Started</div>
                <ul class="sidebar-links">
                  <li><a href="{{ base_url }}/getting-started/">Overview</a></li>
                  <li><a href="{{ base_url }}/getting-started/installation/">Installation</a></li>
                  <li><a href="{{ base_url }}/getting-started/quick-start/">Quick Start</a></li>
                  <li><a href="{{ base_url }}/getting-started/configuration/">Configuration</a></li>
                </ul>
              </div>
              <div class="sidebar-section">
                <div class="sidebar-title">Guide</div>
                <ul class="sidebar-links">
                  <li><a href="{{ base_url }}/guide/">Overview</a></li>
                  <li><a href="{{ base_url }}/guide/content-management/">Content Management</a></li>
                  <li><a href="{{ base_url }}/guide/templates/">Templates</a></li>
                  <li><a href="{{ base_url }}/guide/shortcodes/">Shortcodes</a></li>
                </ul>
              </div>
              <div class="sidebar-section">
                <div class="sidebar-title">Reference</div>
                <ul class="sidebar-links">
                  <li><a href="{{ base_url }}/reference/">Overview</a></li>
                  <li><a href="{{ base_url }}/reference/cli/">CLI Commands</a></li>
                  <li><a href="{{ base_url }}/reference/config/">Configuration</a></li>
                </ul>
              </div>
            </aside>
          HTML
        end

        # Docs-specific page template (Jinja2 syntax)
        private def docs_page_template : String
          <<-HTML
          {% include "header.html" %}
          #{docs_nav_html}
          #{search_overlay_html}
          <div class="docs-container">
          #{docs_sidebar_html}
            <main class="docs-main">
              <h1>{{ page.title }}</h1>
              {{ content }}
          {% include "footer.html" %}
          HTML
        end

        # Docs-specific section template (Jinja2 syntax)
        private def docs_section_template : String
          <<-HTML
          {% include "header.html" %}
          #{docs_nav_html}
          #{search_overlay_html}
          <div class="docs-container">
          #{docs_sidebar_html}
            <main class="docs-main">
              <h1>{{ page.title }}</h1>
              {{ content }}

              <h2>In This Section</h2>
              <ul class="section-list">
                {{ section.list }}
              </ul>
              {{ pagination }}
          {% include "footer.html" %}
          HTML
        end

        # Content files
        private def index_content : String
          <<-CONTENT
+++
title = "Documentation"
+++

This documentation site is powered by [Hwaro](https://github.com/hahwul/hwaro), a fast and lightweight static site generator.

## Quick Links

- **[Getting Started](/getting-started/)** - Installation, setup, and basic usage
- **[Guide](/guide/)** - In-depth guides on content, templates, and more
- **[Reference](/reference/)** - CLI commands and configuration options

## Features

- **Write in Markdown** - Simple, readable content authoring
- **Jinja2 Templates** - Customizable templates via Crinja engine
- **Fast Builds** - Powered by Crystal for blazing fast build times
- **Built-in Search** - Client-side search with keyboard shortcuts
- **Responsive Layout** - Documentation layout that works on all devices
- **Syntax Highlighting** - Code blocks with automatic syntax highlighting
CONTENT
        end

        private def getting_started_index : String
          <<-CONTENT
+++
title = "Getting Started"
+++

Welcome to the Getting Started guide. This section will help you set up your first Hwaro documentation site.

## What You'll Learn

1. How to install Hwaro
2. Creating your first documentation site
3. Basic configuration options
4. Building and previewing your site
CONTENT
        end

        private def installation_content : String
          <<-CONTENT
+++
title = "Installation"
+++

Learn how to install Hwaro on your system.

## Prerequisites

- [Crystal](https://crystal-lang.org/) 1.0 or later
- Git (optional, for cloning)

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

You should see the version number if Hwaro is installed correctly.

## Next Steps

Once installed, proceed to the [Quick Start](/getting-started/quick-start.html) guide.
CONTENT
        end

        private def quick_start_content : String
          <<-CONTENT
+++
title = "Quick Start"
+++

Get up and running with Hwaro in minutes.

## Create a New Project

```bash
hwaro init my-docs --scaffold docs
cd my-docs
```

## Project Structure

```
my-docs/
├── config.toml          # Site configuration
├── content/             # Markdown content files
│   ├── index.md
│   ├── getting-started/
│   └── guide/
├── templates/           # Jinja2 templates
└── static/              # Static assets
```

## Build Your Site

```bash
hwaro build
```

The generated site will be in the `public/` directory.

## Preview Locally

```bash
hwaro serve
```

Visit `http://localhost:3000` to see your site.

## Next Steps

- Read about [Configuration](/getting-started/configuration.html)
- Learn about [Content Management](/guide/content-management.html)
CONTENT
        end

        private def configuration_content : String
          <<-CONTENT
+++
title = "Configuration"
+++

Hwaro is configured through a `config.toml` file in your project root.

## Basic Configuration

```toml
title = "My Documentation"
description = "Project documentation"
base_url = "https://docs.example.com"
```

## Search Configuration

```toml
[search]
enabled = true
format = "fuse_json"
fields = ["title", "content"]
```

## SEO Configuration

```toml
[sitemap]
enabled = true

[robots]
enabled = true
```

## Full Reference

See the [Configuration Reference](/reference/config.html) for all available options.
CONTENT
        end

        private def guide_index : String
          <<-CONTENT
+++
title = "Guide"
+++

This section contains in-depth guides for using Hwaro effectively.

## Topics

Learn about the core concepts and features of Hwaro:

- **Content Management** - Organize and write your documentation
- **Templates** - Customize the look and feel of your site
- **Shortcodes** - Add reusable components to your content
CONTENT
        end

        private def content_management_content : String
          <<-CONTENT
+++
title = "Content Management"
+++

Learn how to organize and write content in Hwaro.

## Content Directory

All content files live in the `content/` directory:

```
content/
├── index.md              # Homepage
├── getting-started/      # Section
│   ├── _index.md         # Section index
│   ├── installation.md   # Page
│   └── quick-start.md    # Page
└── guide/
    └── ...
```

## Front Matter

Each content file starts with front matter in TOML format:

```markdown
+++
title = "Page Title"
date = "2024-01-01"
description = "Page description for SEO"
+++

# Your Content Here
```

## Sections

Sections are directories containing related content. Each section should have an `_index.md` file.

## Links

Link to other pages using relative paths:

```markdown
[Installation](/getting-started/installation.html)
```

## Images

Place images in `static/` and reference them:

```markdown
![Diagram](/images/diagram.png)
```
CONTENT
        end

        private def templates_content : String
          <<-CONTENT
+++
title = "Templates"
+++

Hwaro uses Jinja2-compatible templates (via Crinja) for rendering pages.

## Template Directory

Templates are stored in `templates/`:

```
templates/
├── base.html       # Base template with common structure
├── page.html       # Regular pages
├── section.html    # Section indexes
├── partials/       # Partial templates
│   └── nav.html
└── shortcodes/     # Shortcode templates
```

## Available Variables

In templates, you have access to:

| Flat Variable | Object Access | Description |
|---------------|---------------|-------------|
| `page_title` | `page.title` | Current page title |
| `site_title` | `site.title` | Site title from config |
| `content` | — | Rendered page content |
| `base_url` | `site.base_url` | Site base URL |

## Template Inheritance

Extend base templates:

```jinja
{% extends "base.html" %}
{% block content %}{{ content }}{% endblock %}
```

## Including Partials

Include other templates:

```jinja
{% include "partials/nav.html" %}
```

## Customization

Modify templates to change the site layout, add navigation, or include custom scripts.
CONTENT
        end

        private def shortcodes_content : String
          <<-CONTENT
+++
title = "Shortcodes"
+++

Shortcodes are reusable content snippets you can embed in your Markdown.

## Using Shortcodes

In your Markdown content:

```jinja
{{ alert(type="info", message="This is an info alert") }}
```

## Built-in Shortcodes

### Alert

Display an alert box:

```jinja
{{ alert(type="warning", message="Be careful!") }}
```

Types: `info`, `warning`, `tip`, `note`

## Creating Custom Shortcodes

1. Create a template in `templates/shortcodes/`:

```jinja
{# templates/shortcodes/highlight.html #}
<mark class="highlight">{{ text }}</mark>
```

2. Use it in your content:

```jinja
{{ highlight(text="Important text here") }}
```

## Advanced Example

```jinja
{# templates/shortcodes/alert.html #}
{% if type and message %}
<div class="alert alert-{{ type }}">
  {{ message | safe }}
</div>
{% endif %}
```

## Best Practices

- Keep shortcodes simple and focused
- Document your custom shortcodes
- Use semantic HTML in shortcode templates
- Use the `safe` filter for HTML content
CONTENT
        end

        private def reference_index : String
          <<-CONTENT
+++
title = "Reference"
+++

Technical reference documentation for Hwaro.

## Contents

- **CLI Commands** - All available command-line commands
- **Configuration** - Complete configuration options reference
CONTENT
        end

        private def cli_reference_content : String
          <<-CONTENT
+++
title = "CLI Commands"
+++

Reference for all Hwaro command-line commands.

## hwaro init

Initialize a new Hwaro project.

```bash
hwaro init [path] [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--scaffold TYPE` | Scaffold type: simple, blog, blog-dark, docs, docs-dark (default: simple) |
| `--force` | Overwrite existing files |
| `--skip-sample-content` | Don't create sample content |

**Examples:**

```bash
hwaro init my-site
hwaro init my-blog --scaffold blog
hwaro init my-blog --scaffold blog-dark
hwaro init my-docs --scaffold docs --force
hwaro init my-docs --scaffold docs-dark
```

## hwaro build

Build the static site.

```bash
hwaro build [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--config FILE` | Use a custom config file |
| `--output DIR` | Output directory (default: public) |

## hwaro serve

Start a development server.

```bash
hwaro serve [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--port PORT` | Server port (default: 3000) |
| `--host HOST` | Server host (default: localhost) |

## hwaro new

Create a new content file.

```bash
hwaro new [path]
```

Creates a new Markdown file with front matter template.
CONTENT
        end

        private def config_reference_content : String
          <<-CONTENT
+++
title = "Configuration Reference"
+++

Complete reference for `config.toml` options.

## Site Settings

```toml
title = "Site Title"
description = "Site description"
base_url = "https://example.com"
```

| Key | Type | Description |
|-----|------|-------------|
| `title` | string | Site title |
| `description` | string | Site description |
| `base_url` | string | Production URL |

## Search

```toml
[search]
enabled = true
format = "fuse_json"
fields = ["title", "content"]
filename = "search.json"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | false | Enable search index |
| `format` | string | "fuse_json" | Index format |
| `fields` | array | ["title"] | Fields to index |

## Sitemap

```toml
[sitemap]
enabled = true
filename = "sitemap.xml"
changefreq = "weekly"
priority = 0.5
```

## RSS/Atom Feeds

```toml
[feeds]
enabled = true
type = "rss"
limit = 10
sections = ["posts"]
```

## Taxonomies

```toml
[[taxonomies]]
name = "tags"
feed = true

[[taxonomies]]
name = "categories"
paginate_by = 10
```
CONTENT
        end
      end
    end
  end
end
