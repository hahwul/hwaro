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
      # Known config sections that can be auto-added by doctor --fix.
      # Each key maps to a human-readable description.
      # doctor_snippet_for(key) must return non-nil for every key listed here.
      KNOWN_SECTIONS = {
        "plugins"          => "Content processors and extensions",
        "highlight"        => "Syntax highlighting (Highlight.js)",
        "og"               => "OpenGraph & Twitter Cards",
        "search"           => "Client-side search index",
        "pagination"       => "Pagination settings",
        "series"           => "Series grouping",
        "related"          => "Related posts",
        "markdown"         => "Markdown parser options",
        "sitemap"          => "Sitemap generation",
        "robots"           => "Robots.txt generation",
        "llms"             => "LLM crawler instructions (llms.txt)",
        "feeds"            => "RSS/Atom feed generation",
        "build"            => "Build hooks (pre/post commands)",
        "permalinks"       => "URL path overrides",
        "auto_includes"    => "Automatic CSS/JS loading",
        "assets"           => "Asset pipeline (bundling, minification)",
        "deployment"       => "Deployment targets",
        "image_processing" => "Image resizing and LQIP placeholder generation",
        "pwa"              => "Progressive Web App (manifest.json, service worker)",
        "amp"              => "AMP page generation",
        "doctor"           => "Doctor diagnostics settings (ignore rules)",
      }

      # Sub-sections that doctor checks when the parent section exists
      KNOWN_SUB_SECTIONS = {
        {"content", "files"}         => "Non-Markdown file publishing from content/",
        {"og", "auto_image"}         => "Auto-generated OG images",
        {"image_processing", "lqip"} => "Low-Quality Image Placeholder (LQIP) generation",
      }

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
          # Code block syntax highlighting using Highlight.js

          # [highlight]
          # enabled = true
          # theme = "github"
          # use_cdn = true

          TOML
        else
          <<-TOML

          # =============================================================================
          # Syntax Highlighting
          # =============================================================================
          # Code block syntax highlighting using Highlight.js

          [highlight]
          enabled = true
          theme = "github"          # Available: github, monokai, atom-one-dark, vs2015, etc.
          use_cdn = true            # Set to false to use local assets

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
          # Default meta tags for social sharing
          # Page-level settings (front matter) override these defaults

          [og]
          default_image = "/images/og-default.png"   # Default image for social sharing
          type = "article"                           # OpenGraph type (website, article, etc.)
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

      def self.permalinks(commented : Bool = false) : String
        if commented
          <<-TOML

          # =============================================================================
          # Permalinks (Optional)
          # =============================================================================
          # Override the output path for specific sections or taxonomies

          # [permalinks]
          # posts = "/posts/:year/:month/:slug/"
          # tags = "/topic/:slug/"

          TOML
        else
          <<-TOML

          # =============================================================================
          # Permalinks (Optional)
          # =============================================================================
          # Override the output path for specific sections or taxonomies.
          # Placeholders: :year, :month, :day, :title, :slug, :section

          # [permalinks]
          # posts = "/posts/:year/:month/:slug/"
          # tags = "/topic/:slug/"

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
          # background = "#1a1a2e"
          # text_color = "#ffffff"
          # accent_color = "#e94560"
          # font_size = 48
          # logo = "static/logo.png"
          # logo_position = "bottom-left"  # bottom-left, bottom-right, top-left, top-right
          # output_dir = "og-images"
          # show_title = true
          # style = "default"              # default, dots, grid, diagonal, gradient, waves, minimal
          # pattern_opacity = 0.15
          # pattern_scale = 1.0
          # background_image = ""          # Background image file path (embedded as base64)
          # overlay_opacity = 0.5
          # format = "svg"                 # svg or png

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

          TOML
        else
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

          TOML
        else
          <<-TOML

          # =============================================================================
          # Markdown Configuration (Optional)
          # =============================================================================
          # Configure markdown parser behavior

          [markdown]
          safe = false          # If true, raw HTML in markdown will be stripped (replaced by comments)
          lazy_loading = false  # If true, automatically add loading="lazy" to img tags
          emoji = false         # If true, convert emoji shortcodes (e.g. :smile:) to emoji characters

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
          # pattern = "^.+\\.css$"
          # cacheControl = "max-age=31536000"
          # gzip = true

          TOML
        end
      end

      # Convenience method for doctor --fix (all commented)
      def self.doctor_snippet_for(key : String) : String?
        case key
        when "plugins"               then plugins(commented: true)
        when "highlight"             then highlight(commented: true)
        when "og"                    then og(commented: true)
        when "search"                then search(commented: true)
        when "pagination"            then pagination(commented: true)
        when "series"                then series(commented: true)
        when "related"               then related(commented: true)
        when "markdown"              then markdown(commented: true)
        when "sitemap"               then sitemap(commented: true)
        when "robots"                then robots(commented: true)
        when "llms"                  then llms(commented: true)
        when "feeds"                 then feeds(commented: true)
        when "build"                 then build(commented: true)
        when "permalinks"            then permalinks(commented: true)
        when "auto_includes"         then auto_includes(commented: true)
        when "assets"                then assets(commented: true)
        when "deployment"            then deployment(commented: true)
        when "image_processing"      then image_processing(commented: true)
        when "pwa"                   then pwa(commented: true)
        when "amp"                   then amp(commented: true)
        when "doctor"                then doctor(commented: true)
        when "content.files"         then content_files
        when "og.auto_image"         then og_auto_image
        when "image_processing.lqip" then image_processing_lqip
        else                              nil
        end
      end
    end
  end
end
