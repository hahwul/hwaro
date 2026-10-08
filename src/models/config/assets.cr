# Config section — [assets], [sass], [auto_includes], [image_processing], [amp], [pwa].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    # Auto-includes configuration for automatic CSS/JS loading
    class AutoIncludesConfig
      property enabled : Bool
      property dirs : Array(String)
      # Set from [sass]; compiled SCSS outputs are invisible to the
      # source-tree scan in `collect_tags` without it.
      property sass_enabled : Bool

      def initialize
        @enabled = false
        @dirs = [] of String
        @sass_enabled = false
      end

      # Generate CSS link tags for files in configured directories.
      # `sri_root` (the build output directory) adds `integrity` attributes.
      def css_tags(base_url : String = "", cache_bust : String = "", sri_root : String? = nil, static_config : StaticConfig? = nil) : String
        collect_tags("css", base_url, cache_bust, sri_root, static_config) do |url, integrity|
          %(<link rel="stylesheet" href="#{url}"#{integrity}>)
        end
      end

      # Generate JS script tags for files in configured directories
      def js_tags(base_url : String = "", cache_bust : String = "", sri_root : String? = nil, static_config : StaticConfig? = nil) : String
        collect_tags("js", base_url, cache_bust, sri_root, static_config) do |url, integrity|
          %(<script src="#{url}"#{integrity}></script>)
        end
      end

      # `static_config` drops files `[static] exclude` keeps out of the build
      # (for compiled SCSS, the excluded `.scss` source), so no tag points at
      # a file that is never published.
      private def collect_tags(extension : String, base_url : String, cache_bust : String, sri_root : String?, static_config : StaticConfig?, & : String, String -> String) : String
        return "" unless @enabled
        return "" if @dirs.empty?

        suffix = Models.cache_bust_suffix(cache_bust)
        tags = [] of String
        @dirs.each do |dir|
          static_dir = File.join("static", dir)
          next unless Dir.exists?(static_dir)

          files = Dir.glob(File.join(Utils::PathUtils.glob_escape(static_dir), "**", "*.#{extension}"))
          files.reject! { |f| static_config.excluded?(Path[f].relative_to("static").to_s) } if static_config
          if extension == "css" && @sass_enabled
            # Compiled SCSS is written to the output tree, not `static/`,
            # so project each entry onto the `.css` it will produce.
            # Partials never produce output; a hand-written sibling of the
            # same name is already in `files`.
            Dir.glob(File.join(Utils::PathUtils.glob_escape(static_dir), "**", "*.scss")).each do |scss|
              next if File.basename(scss).starts_with?("_")
              next if static_config && static_config.excluded?(Path[scss].relative_to("static").to_s)
              compiled = scss.sub(/\.scss\z/, ".css")
              files << compiled unless files.includes?(compiled)
            end
          end

          files.sort.each do |file|
            relative_path = file.sub(/^static\/?/, "/")
            # Only the characters that end or corrupt a URL path are escaped
            # (a file really named `a#b.css` is requested as `a%23b.css`);
            # the SRI lookup keeps the on-disk name.
            href_path = relative_path.gsub(/[ %#?]/) { |c| "%%%02X" % c[0].ord }
            tags << yield(HTML.escape("#{base_url}#{href_path}#{suffix}"), Models.integrity_attr(sri_root, relative_path))
          end
        end
        tags.join("\n")
      end

      # Generate both CSS and JS tags
      def all_tags(base_url : String = "", cache_bust : String = "", sri_root : String? = nil, static_config : StaticConfig? = nil) : String
        css = css_tags(base_url, cache_bust, sri_root, static_config)
        js = js_tags(base_url, cache_bust, sri_root, static_config)
        Models.join_tags(css, js)
      end
    end

    # Asset bundle configuration
    class AssetBundleConfig
      property name : String
      property files : Array(String)

      def initialize(@name : String = "", @files : Array(String) = [] of String)
      end
    end

    # Asset pipeline configuration
    class AssetsConfig
      property enabled : Bool
      property minify : Bool
      property fingerprint : Bool
      property source_dir : String
      property output_dir : String
      property bundles : Array(AssetBundleConfig)
      # Subresource Integrity: the local `<link>`/`<script>` tags Hwaro emits
      # (auto-includes, self-hosted highlight assets) carry
      # `integrity="sha384-…"` over the emitted bytes. Independent of
      # `enabled`; `asset_integrity()` works either way.
      property sri : Bool

      def initialize
        @sri = false
        @enabled = false
        @minify = true
        @fingerprint = true
        @source_dir = "static"
        @output_dir = "assets"
        @bundles = [] of AssetBundleConfig
      end
    end

    # Built-in Sass/SCSS compilation (pure Crystal, no external tools).
    #
    # When enabled, non-partial `*.scss` files under the static dir compile
    # to sibling `.css` files in the output, `_*.scss` partials are only
    # reachable via @use/@import, and raw `.scss` sources are excluded from
    # the verbatim static copy.
    #
    # Config example (config.toml):
    #   [sass]
    #   enabled = true
    #   minify = true
    class SassConfig
      property enabled : Bool
      property minify : Bool

      def initialize
        @enabled = false
        @minify = true
      end
    end

    # Image processing configuration
    #
    # Enables automatic image resizing during build using stb (statically linked).
    # Supports JPG, PNG, BMP. No external tools required.
    #
    # Config example (config.toml):
    #   [image_processing]
    #   enabled = true
    #   widths = [320, 640, 1024, 1280]
    #   quality = 85
    #   dimensions = true   # intrinsic width/height on content <img>
    #                       # (independent of `enabled`)
    class ImageProcessingConfig
      property enabled : Bool
      property widths : Array(Int32)
      property quality : Int32
      property dimensions : Bool
      property lqip_enabled : Bool
      property lqip_width : Int32
      property lqip_quality : Int32

      def initialize
        @enabled = false
        @widths = [] of Int32
        @quality = 85
        @dimensions = false
        @lqip_enabled = false
        @lqip_width = 32
        @lqip_quality = 20
      end
    end

    # AMP (Accelerated Mobile Pages) configuration
    class AmpConfig
      property enabled : Bool
      property path_prefix : String
      property sections : Array(String)

      def initialize
        @enabled = false
        @path_prefix = "amp"
        @sections = [] of String
      end

      # Check if a page section should get an AMP version
      def section_enabled?(section : String) : Bool
        @sections.empty? || @sections.includes?(section)
      end
    end

    # PWA (Progressive Web App) configuration
    class PwaConfig
      property enabled : Bool
      property name : String?
      property short_name : String?
      property theme_color : String
      property background_color : String
      property display : String
      property start_url : String
      property icons : Array(String)
      property offline_page : String?
      property precache_urls : Array(String)
      property cache_strategy : String

      VALID_STRATEGIES = %w[cache-first network-first stale-while-revalidate]
      # Web App Manifest `display` members. Anything else makes browsers
      # silently fall back to `browser`, so an unknown value is coerced (with
      # a warning) the same way `cache_strategy` is.
      VALID_DISPLAYS = %w[fullscreen standalone minimal-ui browser]

      def initialize
        @enabled = false
        @name = nil
        @short_name = nil
        @theme_color = "#ffffff"
        @background_color = "#ffffff"
        @display = "standalone"
        @start_url = "/"
        @icons = [] of String
        @offline_page = nil
        @precache_urls = [] of String
        @cache_strategy = "cache-first"
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      private def self.load_auto_includes(config : Config)
        return unless s = config.raw["auto_includes"]?.try(&.as_h?)

        config.auto_includes.enabled = bool_value(s["enabled"]?, config.auto_includes.enabled)
        if dirs = string_list?(s["dirs"]?, "[auto_includes] dirs")
          config.auto_includes.dirs = dirs
        end
      end

      private def self.load_assets(config : Config)
        return unless s = config.raw["assets"]?.try(&.as_h?)

        config.assets.enabled = bool_value(s["enabled"]?, config.assets.enabled)
        config.assets.minify = bool_value(s["minify"]?, config.assets.minify)
        config.assets.fingerprint = bool_value(s["fingerprint"]?, config.assets.fingerprint)
        config.assets.sri = bool_value(s["sri"]?, config.assets.sri)
        config.assets.source_dir = s["source_dir"]?.try(&.as_s?) || config.assets.source_dir
        config.assets.output_dir = s["output_dir"]?.try(&.as_s?) || config.assets.output_dir

        if bundles = s["bundles"]?.try(&.as_a?)
          bundles.each do |bundle_any|
            next unless b = bundle_any.as_h?
            name = b["name"]?.try(&.as_s?) || ""
            next if name.empty?

            files = string_list?(b["files"]?, "[[assets.bundles]] files") || [] of String

            config.assets.bundles << AssetBundleConfig.new(name: name, files: files)
          end
        end
      end

      private def self.load_sass(config : Config)
        if s = config.raw["sass"]?.try(&.as_h?)
          config.sass.enabled = bool_value(s["enabled"]?, config.sass.enabled)
          config.sass.minify = bool_value(s["minify"]?, config.sass.minify)
        end
        # [auto_includes] enumerates the *source* tree, so it has to know
        # whether `.scss` entries will become sibling `.css` outputs.
        config.auto_includes.sass_enabled = config.sass.enabled
      end

      private def self.load_amp(config : Config)
        return unless s = config.raw["amp"]?.try(&.as_h?)

        config.amp.enabled = bool_value(s["enabled"]?, config.amp.enabled)
        config.amp.path_prefix = s["path_prefix"]?.try(&.as_s?) || config.amp.path_prefix
        if sections = string_list?(s["sections"]?, "[amp] sections")
          config.amp.sections = sections
        end
      end

      private def self.load_pwa(config : Config)
        return unless s = config.raw["pwa"]?.try(&.as_h?)

        config.pwa.enabled = bool_value(s["enabled"]?, config.pwa.enabled)
        config.pwa.name = s["name"]?.try(&.as_s?)
        config.pwa.short_name = s["short_name"]?.try(&.as_s?)
        config.pwa.theme_color = s["theme_color"]?.try(&.as_s?) || config.pwa.theme_color
        config.pwa.background_color = s["background_color"]?.try(&.as_s?) || config.pwa.background_color
        if display = s["display"]?.try(&.as_s?)
          if PwaConfig::VALID_DISPLAYS.includes?(display)
            config.pwa.display = display
          else
            Logger.warn "Unknown pwa.display '#{display}', using 'standalone'"
          end
        end
        config.pwa.start_url = s["start_url"]?.try(&.as_s?) || config.pwa.start_url
        config.pwa.offline_page = s["offline_page"]?.try(&.as_s?)
        if icons = string_list?(s["icons"]?, "[pwa] icons")
          config.pwa.icons = icons
        end
        if precache = string_list?(s["precache_urls"]?, "[pwa] precache_urls")
          config.pwa.precache_urls = precache
        end
        if strategy = s["cache_strategy"]?.try(&.as_s?)
          if PwaConfig::VALID_STRATEGIES.includes?(strategy)
            config.pwa.cache_strategy = strategy
          else
            Logger.warn "Unknown pwa.cache_strategy '#{strategy}', using 'cache-first'"
          end
        end
      end

      private def self.load_image_processing(config : Config)
        return unless s = config.raw["image_processing"]?.try(&.as_h?)

        config.image_processing.enabled = bool_value(s["enabled"]?, config.image_processing.enabled)
        config.image_processing.quality = int_value(s["quality"]?, config.image_processing.quality).clamp(1, 100)
        config.image_processing.dimensions = bool_value(s["dimensions"]?, config.image_processing.dimensions)
        if widths = s["widths"]?.try(&.as_a?)
          config.image_processing.widths = widths.compact_map { |w|
            val = int_or_nil(w)
            val && val > 0 ? val : nil
          }
        end

        # LQIP sub-config: [image_processing.lqip]
        if lqip = s["lqip"]?.try(&.as_h?)
          config.image_processing.lqip_enabled = bool_value(lqip["enabled"]?, config.image_processing.lqip_enabled)
          config.image_processing.lqip_width = int_value(lqip["width"]?, config.image_processing.lqip_width).clamp(8, 128)
          config.image_processing.lqip_quality = int_value(lqip["quality"]?, config.image_processing.lqip_quality).clamp(1, 100)
        end
      end
    end
  end
end
