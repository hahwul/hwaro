# Shared TOML config snippets used by both scaffold (hwaro init)
# and doctor (hwaro doctor --fix).
#
# Scaffold uses the full version (commented: false) with real values
# and detailed documentation. Doctor uses the commented version
# (commented: true) with all values commented out so nothing changes
# behavior unexpectedly when appended to an existing config.

module Hwaro
  module Services
    module ConfigSnippets
      # Single source of truth for "what can `doctor --fix` add and what
      # is each section called?". A SECTION_REGISTRY entry pairs the
      # human description with a proc that produces the commented TOML
      # snippet. Adding a new auto-fixable section requires touching
      # exactly one entry (instead of updating both KNOWN_SECTIONS and
      # the dispatch case in `doctor_snippet_for` and risking drift).
      alias SectionEntry = NamedTuple(description: String, snippet: -> String)

      SECTION_REGISTRY = {
        "plugins"          => {description: "Content processors and extensions", snippet: -> { plugins(commented: true) }},
        "highlight"        => {description: "Syntax highlighting (Highlight.js)", snippet: -> { highlight(commented: true) }},
        "og"               => {description: "OpenGraph & Twitter Cards", snippet: -> { og(commented: true) }},
        "search"           => {description: "Client-side search index", snippet: -> { search(commented: true) }},
        "serve"            => {description: "Development server options (custom response headers)", snippet: -> { serve(commented: true) }},
        "pagination"       => {description: "Pagination settings", snippet: -> { pagination(commented: true) }},
        "series"           => {description: "Series grouping", snippet: -> { series(commented: true) }},
        "related"          => {description: "Related posts", snippet: -> { related(commented: true) }},
        "markdown"         => {description: "Markdown parser options", snippet: -> { markdown(commented: true) }},
        "sitemap"          => {description: "Sitemap generation", snippet: -> { sitemap(commented: true) }},
        "robots"           => {description: "Robots.txt generation", snippet: -> { robots(commented: true) }},
        "llms"             => {description: "LLM crawler instructions (llms.txt)", snippet: -> { llms(commented: true) }},
        "feeds"            => {description: "RSS/Atom feed generation", snippet: -> { feeds(commented: true) }},
        "build"            => {description: "Build hooks (pre/post commands)", snippet: -> { build(commented: true) }},
        "links"            => {description: "Internal link checking (broken @/ links)", snippet: -> { links(commented: true) }},
        "permalinks"       => {description: "URL path overrides", snippet: -> { permalinks(commented: true) }},
        "auto_includes"    => {description: "Automatic CSS/JS loading", snippet: -> { auto_includes(commented: true) }},
        "assets"           => {description: "Asset pipeline (bundling, minification)", snippet: -> { assets(commented: true) }},
        "sass"             => {description: "Built-in Sass/SCSS compilation", snippet: -> { sass(commented: true) }},
        "deployment"       => {description: "Deployment targets", snippet: -> { deployment(commented: true) }},
        "image_processing" => {description: "Image resizing and LQIP placeholder generation", snippet: -> { image_processing(commented: true) }},
        "pwa"              => {description: "Progressive Web App (manifest.json, service worker)", snippet: -> { pwa(commented: true) }},
        "amp"              => {description: "AMP page generation", snippet: -> { amp(commented: true) }},
        "menus"            => {description: "Navigation menus (Hugo-style [[menus.*]])", snippet: -> { menus(commented: true) }},
      } of String => SectionEntry

      # Same idea for sub-sections (parent table must already exist
      # before doctor offers to add the child).
      SUB_SECTION_REGISTRY = {
        {"content", "files"}         => {description: "Non-Markdown file publishing from content/", snippet: -> { content_files }},
        {"content", "new"}           => {description: "Front matter and bundle defaults for `hwaro new`", snippet: -> { content_new(commented: true) }},
        {"og", "auto_image"}         => {description: "Auto-generated OG images", snippet: -> { og_auto_image }},
        {"image_processing", "lqip"} => {description: "Low-Quality Image Placeholder (LQIP) generation", snippet: -> { image_processing_lqip }},
      } of Tuple(String, String) => SectionEntry

      # Backward-compatible aliases. The registries above are the only
      # place to edit; these dictionaries are derived for callers (and
      # specs) that walk descriptions only.
      KNOWN_SECTIONS     = SECTION_REGISTRY.transform_values(&.[:description])
      KNOWN_SUB_SECTIONS = SUB_SECTION_REGISTRY.transform_values(&.[:description])

      def self.content_files : String
        <<-TOML

          # =============================================================================
          # Content Files (Optional)
          # =============================================================================
          # Publish non-Markdown files from content/ into the output directory
          # Example: content/about/profile.jpg -> /about/profile.jpg

          # [content.files]
          # allow_extensions = ["jpg", "jpeg", "png", "gif", "svg", "webp"]
          # disallow_extensions = ["psd"]
          # disallow_paths = ["private/**", "**/_*"]

          TOML
      end

      def self.pwa(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # PWA (Progressive Web App) (Optional)
            # =============================================================================
            # Generate manifest.json and service worker for offline access

            # [pwa]
            # enabled = true
            # name = "My Site"
            # short_name = "Site"
            # theme_color = "#ffffff"
            # background_color = "#ffffff"
            # display = "standalone"
            # icons = ["static/icon-192.png", "static/icon-512.png"]
            # cache_strategy = "cache-first"

            TOML
        else
          <<-TOML

            # =============================================================================
            # PWA (Progressive Web App) (Optional)
            # =============================================================================
            # Generate manifest.json and service worker for offline access and installability

            # [pwa]
            # enabled = true
            # name = "My Site"
            # short_name = "Site"
            # theme_color = "#ffffff"
            # background_color = "#ffffff"
            # display = "standalone"
            # start_url = "/"
            # icons = ["static/icon-192.png", "static/icon-512.png"]
            # offline_page = "/offline.html"
            # precache_urls = ["/", "/about/"]
            # cache_strategy = "cache-first"  # cache-first, network-first, stale-while-revalidate

            TOML
        end
      end

      def self.amp(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # AMP (Accelerated Mobile Pages) (Optional)
            # =============================================================================
            # Generate AMP-compliant versions of content pages

            # [amp]
            # enabled = true
            # path_prefix = "amp"
            # sections = ["posts"]

            TOML
        else
          <<-TOML

            # =============================================================================
            # AMP (Accelerated Mobile Pages) (Optional)
            # =============================================================================
            # Generate AMP-compliant versions of content pages

            # [amp]
            # enabled = true
            # path_prefix = "amp"        # Output under /amp/ prefix
            # sections = ["posts"]       # Limit to specific sections (empty = all)

            TOML
        end
      end

      # `[content.new]` controls the front matter `hwaro new` writes.
      # Defaults match `ContentNewConfig#initialize` in
      # src/models/config.cr — the snippet documents the surface so
      # users can flip from TOML to YAML/JSON or add fields without
      # spelunking through code.
      def self.content_new(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Content Creation (Optional)
            # =============================================================================
            # Front matter format and default fields used by `hwaro new`

            # [content.new]
            # front_matter_format = "toml"
            # default_fields = ["description"]
            # bundle = false

            TOML
        else
          <<-TOML

            # =============================================================================
            # Content Creation (Optional)
            # =============================================================================
            # Customize what `hwaro new <path>` writes when there's no archetype
            # match. Archetypes in `archetypes/` always take priority.

            # [content.new]
            # front_matter_format = "toml"        # "toml" (default), "yaml", or "json"
            # default_fields = ["description"]    # Extra fields beyond title/date/draft/tags
            # bundle = false                      # If true, create page bundles (foo/index.md) instead of foo.md

            TOML
        end
      end

      def self.doctor(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Doctor
            # =============================================================================
            # Configure doctor diagnostics behavior

            # [doctor]
            # ignore = ["content-draft", "content-description-missing"]

            TOML
        else
          <<-TOML

            # =============================================================================
            # Doctor
            # =============================================================================
            # Configure doctor diagnostics behavior
            # Add rule IDs to the ignore list to suppress known issues
            # Run `hwaro doctor --json` to see rule IDs in the output

            [doctor]
            ignore = []

            TOML
        end
      end

      def self.plugins(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Plugins
            # =============================================================================
            # Configure content processors and extensions

            # [plugins]
            # processors = ["markdown"]

            TOML
        else
          <<-TOML

            # =============================================================================
            # Plugins
            # =============================================================================
            # Configure content processors and extensions

            [plugins]
            processors = ["markdown"]

            TOML
        end
      end

      def self.highlight(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Syntax Highlighting
            # =============================================================================
            # Code blocks are highlighted at build time (no JavaScript);
            # set mode = "client" to highlight in the browser with Highlight.js

            # [highlight]
            # enabled = true
            # mode = "server"
            # theme = "github"
            # use_cdn = true
            # line_numbers = false
            # copy = false

            TOML
        else
          <<-TOML

            # =============================================================================
            # Syntax Highlighting
            # =============================================================================
            # Code blocks are highlighted at build time (hljs-compatible CSS classes,
            # no JavaScript shipped) and themed by an inlined, ember-warm theme in the
            # scaffold's CSS (so you recolor syntax by editing that CSS, not the
            # `theme` below). Set `mode = "client"` to opt back into browser-side
            # Highlight.js instead.

            [highlight]
            enabled = true
            mode = "server"           # "server" = build-time (no JS); "client" = Highlight.js in the browser
            theme = "github"          # Highlight.js theme name; the scaffold's inlined CSS overrides its colors
            use_cdn = true            # true loads Highlight.js from a CDN; false expects a self-hosted build
            line_numbers = false      # true adds line numbers to every fenced code block (override per-block with {linenos=false})
            copy = true               # copy-to-clipboard button on code blocks (default false; override per-block with {copy=...})

            TOML
        end
      end

      def self.og(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # OpenGraph & Twitter Cards
            # =============================================================================
            # Default meta tags for social sharing

            # [og]
            # default_image = "/images/og-default.png"
            # type = "article"
            # twitter_card = "summary_large_image"
            # twitter_site = "@yourusername"

            TOML
        else
          <<-TOML

            # =============================================================================
            # OpenGraph & Twitter Cards
            # =============================================================================
            # Default meta tags for social sharing.
            # Page-level settings (front matter) override these defaults.
            # The runtime auto-emits og:type="website" for the homepage,
            # section indexes, taxonomy listings, and 404 page; the value
            # below applies to article-style content pages only.

            [og]
            # default_image = "/images/og-default.png" # Drop a 1200x630 image under static/ and uncomment
            type = "article"                           # OpenGraph type for content pages (website, article, …)
            twitter_card = "summary_large_image"       # Twitter card type (summary, summary_large_image)
            # twitter_site = "@yourusername"           # Twitter @username for the site
            # twitter_creator = "@authorusername"      # Twitter @username for content creator
            # fb_app_id = "your_fb_app_id"             # Facebook App ID (optional)

            TOML
        end
      end

      def self.sitemap(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Sitemap
            # =============================================================================
            # Generates sitemap.xml for search engine crawlers

            # [sitemap]
            # enabled = true
            # filename = "sitemap.xml"
            # changefreq = "weekly"
            # priority = 0.5

            TOML
        else
          <<-TOML

            # =============================================================================
            # Sitemap
            # =============================================================================
            # Generates sitemap.xml for search engine crawlers

            [sitemap]
            enabled = true
            filename = "sitemap.xml"
            changefreq = "weekly"
            priority = 0.5
            exclude = []              # Exclude paths or patterns from sitemap

            TOML
        end
      end

      def self.robots(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Robots.txt
            # =============================================================================
            # Controls search engine crawler access

            # [robots]
            # enabled = true
            # filename = "robots.txt"
            # rules = [
            #   { user_agent = "*", disallow = ["/admin", "/private"] }
            # ]

            TOML
        else
          <<-TOML

            # =============================================================================
            # Robots.txt
            # =============================================================================
            # Controls search engine crawler access

            [robots]
            enabled = true
            filename = "robots.txt"
            rules = [
              { user_agent = "*", disallow = ["/admin", "/private"] },
              { user_agent = "GPTBot", disallow = ["/"] }
            ]

            TOML
        end
      end

      def self.llms(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # LLMs.txt
            # =============================================================================
            # Instructions for AI/LLM crawlers

            # [llms]
            # enabled = true
            # filename = "llms.txt"
            # instructions = "Do not use for AI training without permission."
            # full_enabled = false
            # full_filename = "llms-full.txt"

            TOML
        else
          <<-TOML

            # =============================================================================
            # LLMs.txt
            # =============================================================================
            # Instructions for AI/LLM crawlers

            [llms]
            enabled = true
            filename = "llms.txt"
            instructions = "Do not use for AI training without permission."
            # Optional: Generate a single text file containing all Markdown pages
            full_enabled = false
            full_filename = "llms-full.txt"

            TOML
        end
      end

      def self.feeds(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # RSS/Atom Feeds
            # =============================================================================
            # Generates RSS or Atom feed for content syndication
            # (templates/rss.xml.jinja or atom.xml.jinja overrides the built-in markup)

            # [feeds]
            # enabled = true
            # type = "rss"
            # limit = 10
            # full_content = true
            # sections = []

            TOML
        else
          <<-TOML

            # =============================================================================
            # RSS/Atom Feeds
            # =============================================================================
            # Generates RSS or Atom feed for content syndication
            # (templates/rss.xml.jinja or atom.xml.jinja overrides the built-in markup)

            [feeds]
            enabled = true
            filename = ""             # Leave empty for default (rss.xml or atom.xml)
            type = "rss"              # "rss" or "atom"
            truncate = 0              # Truncate content to N characters (0 = full content)
            full_content = true       # true = full HTML in feed, false = description/summary only
            limit = 10                # Maximum number of items in feed
            sections = []             # Limit to specific sections, e.g., ["posts"]

            TOML
        end
      end

      def self.build(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Build Hooks (Optional)
            # =============================================================================
            # Run custom shell commands before/after build process

            # [build]
            # hooks.pre = ["npm install"]
            # hooks.post = ["npm run minify"]

            TOML
        else
          <<-TOML

            # =============================================================================
            # Build Hooks (Optional)
            # =============================================================================
            # Run custom shell commands before/after build process

            # [build]
            # hooks.pre = ["npm install", "python scripts/preprocess.py"]
            # hooks.post = ["npm run minify", "./scripts/deploy.sh"]

            TOML
        end
      end

      def self.links(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Links (Optional)
            # =============================================================================
            # How unresolved @/ internal links are treated during the build

            # [links]
            # broken_internal = "warn" # "error" fails the build listing every offender

            TOML
        else
          <<-TOML

            # =============================================================================
            # Links (Optional)
            # =============================================================================
            # How unresolved @/ internal links are treated during the build.
            # "warn" (default) logs a warning and keeps the raw markup;
            # "error" fails the build with an aggregated list of every offender.

            # [links]
            # broken_internal = "warn"

            TOML
        end
      end

      def self.permalinks(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Permalinks (Optional)
            # =============================================================================
            # Remap a content directory to a different output path

            # [permalinks]
            # "old/posts" = "posts"
            # "posts" = "/:year/:month/:day/:slug/"

            TOML
        else
          <<-TOML

            # =============================================================================
            # Permalinks (Optional)
            # =============================================================================
            # Remap a content directory to a different output path. The matched
            # directory prefix is rewritten and any deeper path is preserved
            # (e.g. "old/posts" => "posts" moves content/old/posts/x.md to /posts/x/).
            # Targets with :tokens are Hugo-style patterns that rebuild the whole
            # URL for leaf pages (:year/:month/:day/:slug/:title/:section/:filename).

            # [permalinks]
            # "old/posts" = "posts"
            # "posts" = "/:year/:month/:day/:slug/"

            TOML
        end
      end

      def self.auto_includes(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Auto Includes (Optional)
            # =============================================================================
            # Automatically load CSS/JS files from static directories

            # [auto_includes]
            # enabled = true
            # dirs = ["assets/css", "assets/js"]

            TOML
        else
          <<-TOML

            # =============================================================================
            # Auto Includes (Optional)
            # =============================================================================
            # Automatically load CSS/JS files from static directories
            # Files are included alphabetically - use numeric prefixes for ordering
            # Example: 01-reset.css, 02-typography.css, 03-layout.css

            # [auto_includes]
            # enabled = true
            # dirs = ["assets/css", "assets/js"]

            TOML
        end
      end

      def self.og_auto_image : String
        <<-TOML

          # =============================================================================
          # Auto OG Images (Optional)
          # =============================================================================
          # Auto-generate Open Graph preview images for social sharing
          # Images are created for pages without a custom `image` in front matter

          # [og.auto_image]
          # enabled = true
          # background = "#171310"
          # text_color = "#f4ede4"
          # accent_color = "#ec7a66"
          # secondary_color = ""           # 2nd color for split/brutalist (auto-derived if empty)
          # font_size = 56
          # logo = "static/logo.png"
          # logo_position = "bottom-left"  # bottom-left, bottom-right, top-left, top-right
          # output_dir = "og-images"
          # show_title = true
          # style = "default"              # masthead layout: eyebrow + corner glow (current default)
          # # Recommended modern styles (much more distinctive):
          # # style = "editorial"   # clean + harmonious (great default for most sites)
          # # style = "artistic"    # rich/illustrative backgrounds
          # # style = "hero"        # bold poster-style typography
          # # style = "surreal"     # experimental & artistic
          # # style = "monument"    # extreme minimal + massive type
          # # Bold geometric styles (high-contrast, design-forward):
          # # style = "split"       # diagonal two-tone color block
          # # style = "band"        # magazine color band behind the title
          # # style = "brutalist"   # thick framed panel with a hard offset shadow
          # # Signature styles (complete, self-contained compositions):
          # # style = "terminal"    # code-editor window with prompt + cursor
          # # style = "bauhaus"     # flat geometric art-poster shapes
          # # style = "halftone"    # print-style halftone dot fade
          # pattern_opacity = 0.35
          # pattern_scale = 1.0
          # background_image = ""          # Background image file path (embedded as base64)
          # overlay_opacity = 0.45
          # format = "png"                 # png (default) or svg — social platforms don't render SVG og:image
          # text_panel = 0.0               # 0.0–0.6 — adds subtle panel behind text (recommended with modern styles)
          # accent_bars = false            # Draw thin top/bottom accent bars (off by default; set true to opt in)
          # lazy_generate = false          # If true, skip bulk OG generation during `hwaro serve`.
          #                                  # Recommended: true for local development on large sites.

          TOML
      end

      def self.series(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Series (Optional)
            # =============================================================================
            # Group posts into ordered series

            # [series]
            # enabled = true

            TOML
        else
          <<-TOML

            # =============================================================================
            # Series
            # =============================================================================
            # Group posts into ordered series for sequential reading.
            # Use `series = "Series Name"` in front matter to assign posts.
            # Use `series_weight = 1` to control ordering within a series.

            [series]
            enabled = true

            TOML
        end
      end

      def self.related(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Related Posts (Optional)
            # =============================================================================
            # Recommend related content based on shared taxonomy terms

            # [related]
            # enabled = true
            # limit = 5
            # taxonomies = ["tags"]

            TOML
        else
          <<-TOML

            # =============================================================================
            # Related Posts
            # =============================================================================
            # Recommend related content based on shared taxonomy terms

            [related]
            enabled = true
            limit = 5
            taxonomies = ["tags"]

            TOML
        end
      end

      def self.search(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Search (Optional)
            # =============================================================================
            # Generate search index for client-side search

            # [search]
            # enabled = true
            # format = "fuse_json"
            # fields = ["title", "content"]
            # tokenize_cjk = false

            TOML
        else
          # `tokenize_cjk` defaults to false to keep Latin-script sites
          # cheap; CJK readers should flip it to true so substring
          # matches inside Korean/Japanese/Chinese words still surface
          # the right pages.
          <<-TOML

            # =============================================================================
            # Search Configuration
            # =============================================================================
            # Generates a search index for client-side search (e.g., Fuse.js)

            [search]
            enabled = true
            format = "fuse_json"
            fields = ["title", "content"]
            filename = "search.json"
            exclude = []              # Exclude paths or patterns from search index
            tokenize_cjk = false      # Set true for Korean/Japanese/Chinese substring matching

            TOML
        end
      end

      def self.pagination(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Pagination (Optional)
            # =============================================================================

            # [pagination]
            # enabled = false
            # per_page = 10

            TOML
        else
          <<-TOML

            # =============================================================================
            # Pagination
            # =============================================================================
            # Enable pagination for section listing pages (e.g., /posts/, /blog/).
            # You can override per section in `_index.md` with:
            # - paginate = 10
            # - pagination_enabled = true
            # - sort_by = "date" | "title" | "weight"
            # - reverse = false

            [pagination]
            enabled = false
            per_page = 10

            TOML
        end
      end

      def self.markdown(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Markdown (Optional)
            # =============================================================================

            # [markdown]
            # safe = false
            # lazy_loading = false
            # emoji = false
            # footnotes = true
            # task_lists = true
            # task_list_classes = false
            # definition_lists = true
            # admonitions = true
            # heading_ids = true
            # mermaid = false
            # math = false
            # math_engine = "katex"
            # smart_punctuation = false
            # containers = false
            # insert_anchor_links = "none"
            # external_links_target_blank = false
            # external_links_no_follow = false
            # external_links_no_referrer = false

            TOML
        else
          # Defaults match `MarkdownConfig#initialize` in src/models/config.cr —
          # showing the real defaults (rather than commenting everything out)
          # makes the feature surface discoverable without behaviour changes.
          <<-TOML

            # =============================================================================
            # Markdown Configuration (Optional)
            # =============================================================================
            # Configure markdown parser behavior

            [markdown]
            safe = false             # If true, raw HTML in markdown is stripped (replaced by comments)
            lazy_loading = false     # If true, automatically add loading="lazy" to img tags
            emoji = false            # If true, convert emoji shortcodes (e.g. :smile:) to emoji characters
            footnotes = true         # GitHub-flavored footnote syntax: [^1] / [^1]: definition
            task_lists = true        # Task list syntax: - [ ] todo / - [x] done
            task_list_classes = false # GFM classes (task-list-item / contains-task-list) on task-list markup
            definition_lists = true  # Definition list syntax (Term newline ": Definition")
            admonitions = true       # GitHub-style `> [!NOTE]` blockquotes render as admonition <div>s
            heading_ids = true       # `## Heading {#custom-id}` sets an explicit id
            mermaid = false          # Render ```mermaid code blocks as diagrams (loads mermaid.js)
            math = false             # Inline ($...$) and block ($$...$$) math (loads math_engine)
            math_engine = "katex"    # "katex" or "mathjax"
            smart_punctuation = false # Typographic quotes/dashes/ellipses ("x" -> curly, -- -> dash, ... -> ellipsis)
            containers = false       # :::note Title ... ::: custom containers (admonition markup)
            insert_anchor_links = "none" # Site-wide heading anchor links: "none", "left", or "right"
            external_links_target_blank = false # target="_blank" rel="noopener" on absolute http(s) links
            external_links_no_follow = false    # rel="nofollow" on absolute http(s) links
            external_links_no_referrer = false  # rel="noreferrer" on absolute http(s) links

            TOML
        end
      end

      def self.assets(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Asset Pipeline (Optional)
            # =============================================================================

            # [assets]
            # enabled = true
            # minify = true
            # fingerprint = true

            TOML
        else
          <<-TOML

            # =============================================================================
            # Asset Pipeline (Optional)
            # =============================================================================
            # Bundle, minify, and fingerprint CSS/JS files for production.
            # Use {{ asset(name="main.css") }} in templates to resolve paths.

            # [assets]
            # enabled = true
            # minify = true
            # fingerprint = true
            # source_dir = "static"
            # output_dir = "assets"

            # [[assets.bundles]]
            # name = "main.css"
            # files = ["css/reset.css", "css/style.css"]

            # [[assets.bundles]]
            # name = "app.js"
            # files = ["js/util.js", "js/app.js"]

            TOML
        end
      end

      def self.sass(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Sass/SCSS Compilation (Optional)
            # =============================================================================

            # [sass]
            # enabled = true
            # minify = true

            TOML
        else
          <<-TOML

            # =============================================================================
            # Sass/SCSS Compilation (Optional)
            # =============================================================================
            # Compile static/**/*.scss to sibling .css files at build time.
            # Pure Crystal — no external tools. Partials (_*.scss) are only
            # reachable via @use/@import and never publish; raw .scss sources
            # are excluded from the static copy while enabled.

            # [sass]
            # enabled = true
            # minify = true

            TOML
        end
      end

      def self.image_processing(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Image Processing (Optional)
            # =============================================================================
            # Automatic image resizing and LQIP (Low-Quality Image Placeholder) generation
            # Uses vendored stb libraries — no external tools required.
            # Use resize_image() in templates to generate responsive variants.

            # [image_processing]
            # enabled = true
            # widths = [320, 640, 1024, 1280]
            # quality = 85
            #
            # [image_processing.lqip]
            # enabled = true
            # width = 32             # Placeholder width in pixels (8-128)
            # quality = 20           # JPEG quality for placeholder (1-100, lower = smaller)

            TOML
        else
          <<-TOML

            # =============================================================================
            # Image Processing (Optional)
            # =============================================================================
            # Automatic image resizing and LQIP (Low-Quality Image Placeholder) generation.
            # Uses vendored stb libraries — no external tools required.
            #
            # Use resize_image() in templates:
            #   {% set img = resize_image(path="/images/hero.jpg", width=1024) %}
            #   <img src="{{ img.url }}"
            #        style="background-image: url({{ img.lqip }}); background-size: cover;"
            #        loading="lazy">

            # [image_processing]
            # enabled = true
            # widths = [320, 640, 1024, 1280]
            # quality = 85
            #
            # [image_processing.lqip]
            # enabled = true
            # width = 32             # Placeholder width in pixels (8-128)
            # quality = 20           # JPEG quality for placeholder (1-100, lower = smaller)

            TOML
        end
      end

      def self.image_processing_lqip : String
        <<-TOML

          # =============================================================================
          # LQIP — Low-Quality Image Placeholder (Optional)
          # =============================================================================
          # Generate tiny base64-encoded placeholder images and dominant colors
          # Requires [image_processing] to be enabled

          # [image_processing.lqip]
          # enabled = true
          # width = 32             # Placeholder width in pixels (8-128)
          # quality = 20           # JPEG quality for placeholder (1-100, lower = smaller)

          TOML
      end

      def self.deployment(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Deployment (Optional)
            # =============================================================================

            # [deployment]
            # target = "prod"
            # source_dir = "public"
            #
            # [[deployment.targets]]
            # name = "prod"
            # url = "file://./out"

            TOML
        else
          <<-TOML

            # =============================================================================
            # Deployment (Optional)
            # =============================================================================
            # Configure deploy targets for `hwaro deploy`
            #
            # - Local filesystem sync: url = "file://./out"
            # - Remote/object stores: set `command` and use external tools (aws/gsutil/rsync/etc)
            #
            # Placeholders for `command`:
            #   {source} => source directory (default: public)
            #   {url}    => target url
            #   {target} => target name

            # [deployment]
            # target = "prod"
            # source_dir = "public"
            # confirm = false
            # dryRun = false
            # maxDeletes = 256      # safety limit (-1 disables)

            # [[deployment.targets]]
            # name = "prod"
            # url = "file://./out"

            # [[deployment.targets]]
            # name = "s3"
            # url = "s3://my-bucket"
            # command = "aws s3 sync {source}/ {url} --delete"

            # [[deployment.matchers]]
            # pattern = "^.+\\.html$"
            # force = true          # always re-copy matches, even when identical

            TOML
        end
      end

      def self.serve(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Serve (Development Server) (Optional)
            # =============================================================================
            # Custom response headers injected on every request while running
            # `hwaro serve`. Extremely useful for reproducing production
            # reverse-proxy, CDN, or security header behaviour locally.

            # [serve]
            # fast = true                    # Default to fast dev mode (skip heavy OG + image processing)
            #
            # (response headers live under the [serve.headers] table below)

            # [serve.headers]
            # X-Frame-Options = "SAMEORIGIN"
            # X-Content-Type-Options = "nosniff"
            # Referrer-Policy = "strict-origin-when-cross-origin"
            # # Cache-Control = "public, max-age=3600"

            TOML
        else
          <<-TOML

            # =============================================================================
            # Serve (Development Server) (Optional)
            # =============================================================================
            # Custom response headers injected on every request while running
            # `hwaro serve`. Extremely useful for reproducing production
            # reverse-proxy, CDN, or security header behaviour locally.

            [serve.headers]
            X-Frame-Options = "SAMEORIGIN"
            X-Content-Type-Options = "nosniff"
            Referrer-Policy = "strict-origin-when-cross-origin"
            # Cache-Control = "public, max-age=3600"

            TOML
        end
      end

      def self.menus(commented : Bool = false) : String
        if commented
          <<-TOML

            # =============================================================================
            # Menus (Optional)
            # =============================================================================
            # Named navigation menus, resolved into a tree in templates via
            # {% for item in get_menu(name="main") %} or site.menus.main.
            # `name` is required; everything else defaults (weight = 0,
            # identifier = name, parent = none, url = "").
            # Pages/sections can also join a menu from their own front
            # matter (`menus = ["main"]`) without touching this file.

            # [[menus.main]]
            # name = "Home"
            # url = "/"
            # weight = 1

            # [[menus.main]]
            # name = "Posts"
            # url = "/posts/"
            # weight = 2
            # identifier = "posts"

            # Per-language overrides replace the whole menu for that language
            # (a [languages.<code>] block with no [[languages.<code>.menus.*]]
            # inherits this global set instead):
            # [[languages.ko.menus.main]]
            # name = "홈"
            # url = "/ko/"
            # weight = 1

            TOML
        else
          <<-TOML

            # =============================================================================
            # Menus
            # =============================================================================
            # Named navigation menus. Render with:
            #   {% for item in get_menu(name="main") %}
            #     <a href="{{ item.href }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>
            #   {% endfor %}

            [[menus.main]]
            name = "Home"
            url = "/"
            weight = 1

            TOML
        end
      end

      # Resolve a snippet for the given section key, looking up the
      # SECTION_REGISTRY (top-level keys like "pwa") or SUB_SECTION_REGISTRY
      # (dotted keys like "og.auto_image"). The top-level `[doctor]` key
      # is special-cased because it documents diagnostics behaviour and
      # isn't surfaced via KNOWN_SECTIONS (no need to advertise it as a
      # missing-section advisory).
      def self.doctor_snippet_for(key : String) : String?
        if entry = SECTION_REGISTRY[key]?
          return entry[:snippet].call
        end
        if key.includes?(".")
          parent, _, child = key.partition('.')
          if entry = SUB_SECTION_REGISTRY[{parent, child}]?
            return entry[:snippet].call
          end
        end
        return doctor(commented: true) if key == "doctor"
        nil
      end
    end
  end
end
