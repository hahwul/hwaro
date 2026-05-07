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

        def template_files(skip_taxonomies : Bool = false) : Hash(String, String)
          files = {
            "header.html"   => header_template,
            "footer.html"   => footer_template,
            "page.html"     => blog_page_template,
            "section.html"  => blog_section_template,
            "post.html"     => post_template,
            "archives.html" => archives_template,
            "404.html"      => not_found_template,
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
            str << base_config(config_title, config_description)

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
            str << feeds_config(["posts"])

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

        # Override styles for blog - external CSS file
        protected def styles : String
          <<-CSS
            <link rel="stylesheet" href="{{ base_url }}/css/style.css">
            CSS
        end

        # Override header for blog - minimal, delegates layout to page templates (Jinja2 syntax)
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
          {
            "css/style.css" => css_content,
            "js/search.js"  => search_js_content,
          }
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
              --primary: #3b82f6;
              --primary-hover: #2563eb;
              --text: #1e293b;
              --text-secondary: #475569;
              --text-muted: #94a3b8;
              --border: #e2e8f0;
              --border-light: #f1f5f9;
              --bg: #ffffff;
              --bg-secondary: #f8fafc;
              --bg-code: #f1f5f9;
              --header-h: 52px;
              --content-max-w: 860px;
              --radius: 10px;
              --radius-sm: 6px;
            }

            *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

            body {
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif;
              font-size: 15px;
              line-height: 1.7;
              color: var(--text);
              background: var(--bg);
              -webkit-font-smoothing: antialiased;
              -moz-osx-font-smoothing: grayscale;
            }

            /* Header */
            .blog-header {
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
              font-weight: 600;
              font-size: 1.05rem;
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
              font-size: 2rem;
              font-weight: 700;
              margin: 0 0 0.5rem 0;
              letter-spacing: -0.025em;
              line-height: 1.2;
            }

            .blog-main h2 {
              font-size: 1.4rem;
              font-weight: 600;
              margin: 2.5rem 0 0.75rem 0;
              letter-spacing: -0.015em;
            }

            .blog-main h3 {
              font-size: 1.1rem;
              font-weight: 600;
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

            /* Links */
            a { color: var(--primary); text-decoration: none; }
            a:hover { text-decoration: underline; }

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

            pre code { background: none; padding: 0; font-size: 0.82rem; }

            /* Tables */
            table { width: 100%; border-collapse: collapse; margin: 1rem 0 1.5rem 0; font-size: 0.9rem; }
            th { text-align: left; padding: 0.6rem 0.75rem; border-bottom: 2px solid var(--border); font-weight: 600; font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.03em; color: var(--text-secondary); }
            td { padding: 0.5rem 0.75rem; border-bottom: 1px solid var(--border-light); vertical-align: top; }

            /* Blockquote */
            blockquote {
              border-left: 3px solid var(--primary);
              padding: 0.5rem 1rem;
              margin: 1rem 0;
              background: var(--bg-secondary);
              border-radius: 0 var(--radius-sm) var(--radius-sm) 0;
              color: var(--text-secondary);
            }

            blockquote p { margin-bottom: 0; }

            /* Images */
            img { max-width: 100%; height: auto; border-radius: var(--radius-sm); }

            /* Post list */
            .post-list { list-style: none; padding: 0; }

            .post-item {
              padding: 1.25rem 0;
              border-bottom: 1px solid var(--border-light);
              transition: background 0.1s;
            }

            .post-item:last-child { border-bottom: none; }

            .post-title {
              margin: 0 0 0.3rem 0;
              font-size: 1.15rem;
              font-weight: 600;
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
              color: white;
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
            .search-result-item .search-result-snippet mark { background: rgba(59, 130, 246, 0.15); color: var(--primary); border-radius: 2px; padding: 0 1px; }
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

            /* Selection */
            ::selection { background: color-mix(in srgb, var(--primary) 20%, transparent); }

            /* Responsive */
            @media (max-width: 640px) {
              .blog-header nav { display: none; }
              .blog-main { padding: 1.5rem 1rem; }
              .blog-main h1 { font-size: 1.5rem; }
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

        # Search overlay HTML
        private def search_overlay_html : String
          <<-HTML
            <div class="search-overlay" id="searchOverlay" onclick="if(event.target===this)closeSearch()">
              <div class="search-modal">
                <div class="search-input-wrap">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
                  <input type="text" id="searchInput" placeholder="Search posts..." autocomplete="off">
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
                <a href="{{ base_url }}{{ lang_prefix }}/" class="logo">{{ site.title }}</a>
                <nav>
                  <a href="{{ base_url }}{{ lang_prefix }}/posts/">Posts</a>
                  <a href="{{ base_url }}{{ lang_prefix }}/archives/">Archives</a>
                  <a href="{{ base_url }}{{ lang_prefix }}/about/">About</a>
                </nav>
                <div class="header-right">
                  {% if page.translations | length > 0 %}
                  <nav class="lang-switcher" aria-label="Language">
                    {% for t in page.translations %}
                    <a href="{{ t.url }}" hreflang="{{ t.code }}"{% if t.is_current %} aria-current="true"{% endif %}>{{ t.code | upper }}</a>
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

        # Blog-specific page template (Jinja2 syntax)
        private def blog_page_template : String
          <<-HTML
            {% include "header.html" %}
            #{blog_nav_html}
            #{search_overlay_html}
            <div class="blog-container">
              <main class="blog-main">
                <h1>{{ page.title | e }}</h1>
                {{ content }}
            {% include "footer.html" %}
            HTML
        end

        # Blog-specific section template (Jinja2 syntax)
        private def blog_section_template : String
          <<-HTML
            {% include "header.html" %}
            #{blog_nav_html}
            #{search_overlay_html}
            <div class="blog-container">
              <main class="blog-main">
                <h1>{{ page.title | e }}</h1>
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
            #{blog_nav_html}
            #{search_overlay_html}
            <div class="blog-container">
              <main class="blog-main">
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
                </article>
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
        private def render_page(
          title : String,
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
            str << "title = \"#{title}\"\n"
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
            str << "This is a blog powered by [Hwaro](https://github.com/hahwul/hwaro), a fast and lightweight static site generator.\n\n"

            if skip_taxonomies
              str << "Check out the latest posts in the [Posts](/posts/) section.\n"
            else
              str << "Check out the latest posts in the [Posts](/posts/) section, or browse by:\n\n"
              str << "- [Tags](/tags/)\n"
              str << "- [Categories](/categories/)\n"
              str << "- [Authors](/authors/)\n"
            end
          end

          render_page(
            title: "Home",
            body: body,
            skip_taxonomies: skip_taxonomies,
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
            tags: ["about"],
            categories: ["pages"]
          )
        end

        private def posts_index_content : String
          <<-CONTENT
            +++
            title = "Posts"
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
            +++

            Browse every post by date.
            CONTENT
        end

        # Archives template (Jinja2 syntax). Lists every published
        # post under the `posts` section, sorted newest-first. Each
        # entry shows the date so readers can scan the timeline; we
        # avoid `{% set %}` year-grouping because Crinja doesn't
        # implement Jinja2's `namespace()` helper that would otherwise
        # let us track the current year across iterations cleanly.
        # Users who want grouped-by-year output can override this
        # template in their project's `templates/archives.html`.
        private def archives_template : String
          <<-HTML
            {% include "header.html" %}
            <header class="blog-header">
              <div class="blog-header-inner">
                <a href="{{ base_url }}{{ lang_prefix }}/" class="logo">{{ site.title }}</a>
                <nav>
                  <a href="{{ base_url }}{{ lang_prefix }}/posts/">Posts</a>
                  <a href="{{ base_url }}{{ lang_prefix }}/archives/">Archives</a>
                  <a href="{{ base_url }}{{ lang_prefix }}/about/">About</a>
                </nav>
              </div>
            </header>
            <div class="blog-container">
              <main class="blog-main">
                <h1>{{ page.title | e }}</h1>
                {{ content }}

                <ul class="archive-list">
                {% for p in site.pages | selectattr("section", "equalto", "posts") | rejectattr("is_index") | rejectattr("draft") | sort(attribute="date", reverse=true) %}
                  <li class="archive-entry">
                    <time datetime="{{ p.date }}">{{ p.date }}</time>
                    <a href="{{ base_url }}{{ p.url }}">{{ p.title | e }}</a>
                  </li>
                {% endfor %}
                </ul>
              </main>
            </div>
            {% include "footer.html" %}
            HTML
        end
      end
    end
  end
end
