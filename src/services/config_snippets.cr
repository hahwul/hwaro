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
        "pwa"              => "Progressive Web App (manifest.json, service worker)",
        "amp"              => "AMP page generation",
        "series"           => "Series grouping",
        "related"          => "Related posts",
        "search"           => "Client-side search index",
        "pagination"       => "Pagination settings",
        "markdown"         => "Markdown parser options",
        "assets"           => "Asset pipeline (bundling, minification)",
        "deployment"       => "Deployment targets",
        "image_processing" => "Image resizing and LQIP placeholder generation",
      }

      # Sub-sections that doctor checks when the parent section exists
      KNOWN_SUB_SECTIONS = {
        {"og", "auto_image"}         => "Auto-generated OG images",
        {"image_processing", "lqip"} => "Low-Quality Image Placeholder (LQIP) generation",
      }

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
        when "pwa"                   then pwa(commented: true)
        when "amp"                   then amp(commented: true)
        when "og.auto_image"         then og_auto_image
        when "series"                then series(commented: true)
        when "related"               then related(commented: true)
        when "search"                then search(commented: true)
        when "pagination"            then pagination(commented: true)
        when "markdown"              then markdown(commented: true)
        when "assets"                then assets(commented: true)
        when "deployment"            then deployment(commented: true)
        when "image_processing"      then image_processing(commented: true)
        when "image_processing.lqip" then image_processing_lqip
        else                              nil
        end
      end
    end
  end
end
