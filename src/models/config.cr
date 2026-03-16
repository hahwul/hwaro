require "toml"
require "./deployment"
require "../utils/text_utils"
require "../utils/env_substitutor"

module Hwaro
  module Models
    class SitemapConfig
      property enabled : Bool
      property filename : String
      property changefreq : String
      property priority : Float64
      property exclude : Array(String)

      def initialize
        @enabled = false
        @filename = "sitemap.xml"
        @changefreq = "weekly"
        @priority = 0.5
        @exclude = [] of String
      end
    end

    class RobotsRule
      property user_agent : String
      property allow : Array(String)
      property disallow : Array(String)

      def initialize(user_agent : String)
        @user_agent = user_agent
        @allow = [] of String
        @disallow = [] of String
      end
    end

    class RobotsConfig
      property enabled : Bool
      property filename : String
      property rules : Array(RobotsRule)

      def initialize
        @enabled = true
        @filename = "robots.txt"
        @rules = [] of RobotsRule
      end
    end

    class LlmsConfig
      property enabled : Bool
      property filename : String
      property instructions : String
      property full_enabled : Bool
      property full_filename : String

      def initialize
        @enabled = true
        @filename = "llms.txt"
        @instructions = ""
        @full_enabled = false
        @full_filename = "llms-full.txt"
      end
    end

    class SearchConfig
      property enabled : Bool
      property format : String
      property fields : Array(String)
      property filename : String
      property exclude : Array(String)
      property tokenize_cjk : Bool

      def initialize
        @enabled = false
        @format = "fuse_json"
        @fields = ["title", "content"]
        @filename = "search.json"
        @exclude = [] of String
        @tokenize_cjk = false
      end
    end

    class FeedConfig
      property enabled : Bool
      property filename : String
      property type : String
      property truncate : Int32
      property limit : Int32
      property sections : Array(String)
      property default_language_only : Bool

      def initialize
        @enabled = false
        @filename = ""
        @type = "rss"
        @truncate = 0
        @limit = 10
        @sections = [] of String
        @default_language_only = true
      end
    end

    # Series configuration
    class SeriesConfig
      property enabled : Bool

      def initialize
        @enabled = false
      end
    end

    # Related posts configuration
    class RelatedConfig
      property enabled : Bool
      property limit : Int32
      property taxonomies : Array(String)

      def initialize
        @enabled = false
        @limit = 5
        @taxonomies = ["tags"]
      end
    end

    # Plugin configuration for extensibility
    class PluginConfig
      property processors : Array(String)

      def initialize
        @processors = ["markdown"] # Default processor
      end
    end

    # Content file publishing configuration
    #
    # Allows copying non-Markdown files from `content/` to the output directory
    # (e.g. `content/about/profile.jpg` -> `/about/profile.jpg`).
    class ContentFilesConfig
      property allow_extensions : Array(String)
      property disallow_extensions : Array(String)
      property disallow_paths : Array(String)

      def initialize
        @allow_extensions = [] of String
        @disallow_extensions = [] of String
        @disallow_paths = [] of String
      end

      def enabled? : Bool
        @allow_extensions.any?
      end

      def publish?(relative_path : String) : Bool
        normalized_path = ContentFilesConfig.normalize_path(relative_path)
        ext = File.extname(normalized_path).downcase
        return false if ext.empty?
        return false if ext == ".md"
        return false unless @allow_extensions.includes?(ext)
        return false if @disallow_extensions.includes?(ext)
        @disallow_paths.each do |pattern|
          return false if File.match?(pattern, normalized_path)
        end
        true
      end

      def self.normalize_extensions(values : Array(String)) : Array(String)
        values.compact_map do |ext|
          normalize_extension(ext)
        end.uniq
      end

      def self.normalize_paths(values : Array(String)) : Array(String)
        values.compact_map do |pattern|
          normalized = normalize_path(pattern)
          normalized.empty? ? nil : normalized
        end
      end

      def self.normalize_path(path : String) : String
        path = path.strip.gsub('\\', '/')
        path = path.lchop("/")
        path = path.lchop("content/")
        path
      end

      private def self.normalize_extension(ext : String) : String?
        ext = ext.strip.downcase
        return nil if ext.empty?
        ext.starts_with?(".") ? ext : ".#{ext}"
      end
    end

    # Auto-includes configuration for automatic CSS/JS loading
    class AutoIncludesConfig
      property enabled : Bool
      property dirs : Array(String)

      def initialize
        @enabled = false
        @dirs = [] of String
      end

      # Generate CSS link tags for files in configured directories
      def css_tags(base_url : String = "", cache_bust : String = "") : String
        collect_tags("css", base_url, cache_bust) do |url|
          %(<link rel="stylesheet" href="#{url}">)
        end
      end

      # Generate JS script tags for files in configured directories
      def js_tags(base_url : String = "", cache_bust : String = "") : String
        collect_tags("js", base_url, cache_bust) do |url|
          %(<script src="#{url}"></script>)
        end
      end

      private def collect_tags(extension : String, base_url : String, cache_bust : String, &block : String -> String) : String
        return "" unless @enabled
        return "" if @dirs.empty?

        suffix = cache_bust.empty? ? "" : "?v=#{HTML.escape(cache_bust)}"
        tags = [] of String
        @dirs.each do |dir|
          static_dir = File.join("static", dir)
          next unless Dir.exists?(static_dir)

          Dir.glob(File.join(static_dir, "**", "*.#{extension}")).sort.each do |file|
            relative_path = file.sub(/^static\/?/, "/")
            tags << yield(HTML.escape("#{base_url}#{relative_path}#{suffix}"))
          end
        end
        tags.join("\n")
      end

      # Generate both CSS and JS tags
      def all_tags(base_url : String = "", cache_bust : String = "") : String
        css = css_tags(base_url, cache_bust)
        js = js_tags(base_url, cache_bust)
        [css, js].reject(&.empty?).join("\n")
      end
    end

    # Pagination configuration
    class PaginationConfig
      property enabled : Bool
      property per_page : Int32

      def initialize
        @enabled = false
        @per_page = 10
      end
    end

    # Auto-generated OG image configuration
    class AutoImageConfig
      property enabled : Bool
      property background : String
      property text_color : String
      property accent_color : String
      property font_size : Int32
      property logo : String?
      property output_dir : String

      def initialize
        @enabled = false
        @background = "#1a1a2e"
        @text_color = "#ffffff"
        @accent_color = "#e94560"
        @font_size = 48
        @logo = nil
        @output_dir = "og-images"
      end
    end

    # OpenGraph and Twitter Card configuration
    class OpenGraphConfig
      property default_image : String?
      property twitter_card : String
      property twitter_site : String?
      property twitter_creator : String?
      property fb_app_id : String?
      property og_type : String
      property auto_image : AutoImageConfig

      def initialize
        @default_image = nil
        @twitter_card = "summary_large_image"
        @twitter_site = nil
        @twitter_creator = nil
        @fb_app_id = nil
        @og_type = "article"
        @auto_image = AutoImageConfig.new
      end

      # Generate OG meta tags
      def og_tags(
        title : String,
        description : String?,
        url : String,
        image : String?,
        base_url : String,
      ) : String
        String.build(256) do |str|
          str << %(<meta property="og:title" content="#{Utils::TextUtils.escape_xml(title)}">\n)
          str << %(<meta property="og:type" content="#{Utils::TextUtils.escape_xml(@og_type)}">\n)
          str << %(<meta property="og:url" content="#{Utils::TextUtils.escape_xml(base_url)}#{Utils::TextUtils.escape_xml(url)}">)
          if desc = description
            str << %(\n<meta property="og:description" content="#{Utils::TextUtils.escape_xml(desc)}">)
          end
          if img_url = resolve_image_url(image, base_url)
            str << %(\n<meta property="og:image" content="#{Utils::TextUtils.escape_xml(img_url)}">)
          end
          if fb_id = @fb_app_id
            str << %(\n<meta property="fb:app_id" content="#{Utils::TextUtils.escape_xml(fb_id)}">)
          end
        end
      end

      # Generate Twitter Card meta tags
      def twitter_tags(
        title : String,
        description : String?,
        image : String?,
        base_url : String,
      ) : String
        String.build(256) do |str|
          str << %(<meta name="twitter:card" content="#{Utils::TextUtils.escape_xml(@twitter_card)}">\n)
          str << %(<meta name="twitter:title" content="#{Utils::TextUtils.escape_xml(title)}">)
          if desc = description
            str << %(\n<meta name="twitter:description" content="#{Utils::TextUtils.escape_xml(desc)}">)
          end
          if img_url = resolve_image_url(image, base_url)
            str << %(\n<meta name="twitter:image" content="#{Utils::TextUtils.escape_xml(img_url)}">)
          end
          if site = @twitter_site
            str << %(\n<meta name="twitter:site" content="#{Utils::TextUtils.escape_xml(site)}">)
          end
          if creator = @twitter_creator
            str << %(\n<meta name="twitter:creator" content="#{Utils::TextUtils.escape_xml(creator)}">)
          end
        end
      end

      # Resolve an image path to an absolute URL, falling back to default_image
      private def resolve_image_url(image : String?, base_url : String) : String?
        img = image || @default_image
        return nil unless img
        img.starts_with?("http") ? img : "#{base_url}#{img.starts_with?("/") ? img : "/#{img}"}"
      end

      # Generate both OG and Twitter tags
      def all_tags(
        title : String,
        description : String?,
        url : String,
        image : String?,
        base_url : String,
      ) : String
        og = og_tags(title, description, url, image, base_url)
        twitter = twitter_tags(title, description, image, base_url)
        [og, twitter].reject(&.empty?).join("\n")
      end
    end

    # Syntax highlighting configuration
    class HighlightConfig
      property enabled : Bool
      property theme : String
      property use_cdn : Bool

      def initialize
        @enabled = true
        @theme = "github"
        @use_cdn = true
      end

      # Generate the CSS link tag for highlighting
      def css_tag(cache_bust : String = "") : String
        return "" unless @enabled
        safe_theme = HTML.escape(@theme)
        if @use_cdn
          %(<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/#{safe_theme}.min.css">)
        else
          suffix = cache_bust.empty? ? "" : "?v=#{HTML.escape(cache_bust)}"
          %(<link rel="stylesheet" href="/assets/css/highlight/#{safe_theme}.min.css#{suffix}">)
        end
      end

      # Generate the JS script tag for highlighting
      def js_tag(cache_bust : String = "") : String
        return "" unless @enabled
        if @use_cdn
          %(<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>\n<script>hljs.highlightAll();</script>)
        else
          suffix = cache_bust.empty? ? "" : "?v=#{HTML.escape(cache_bust)}"
          %(<script src="/assets/js/highlight.min.js#{suffix}"></script>\n<script>hljs.highlightAll();</script>)
        end
      end

      # Generate both CSS and JS tags
      def tags(cache_bust : String = "") : String
        return "" unless @enabled
        "#{css_tag(cache_bust)}\n#{js_tag(cache_bust)}"
      end
    end

    class TaxonomyConfig
      property name : String
      property feed : Bool
      property sitemap : Bool
      property paginate_by : Int32?

      def initialize(@name : String)
        @feed = false
        @sitemap = true
        @paginate_by = nil
      end
    end

    # Build hooks configuration for pre/post build commands
    class BuildHooksConfig
      property pre : Array(String)
      property post : Array(String)

      def initialize
        @pre = [] of String
        @post = [] of String
      end
    end

    # Build configuration section
    class BuildConfig
      property hooks : BuildHooksConfig

      def initialize
        @hooks = BuildHooksConfig.new
      end
    end

    # Markdown parser configuration
    # Maps to Markd::Options for controlling markdown parsing behavior
    class MarkdownConfig
      property safe : Bool             # If true, raw HTML will not be passed through (replaced by comments)
      property lazy_loading : Bool     # If true, adds loading="lazy" to img tags
      property emoji : Bool            # If true, converts emoji shortcodes (e.g. :smile:) to emoji characters
      property footnotes : Bool        # If true, enables footnote syntax ([^1])
      property task_lists : Bool       # If true, enables task list syntax (- [ ] / - [x])
      property definition_lists : Bool # If true, enables definition list syntax (Term\n: Definition)
      property mermaid : Bool          # If true, renders ```mermaid blocks as diagrams
      property math : Bool             # If true, enables math syntax ($...$ and $$...$$)
      property math_engine : String    # "katex" or "mathjax"

      def initialize
        @safe = false
        @lazy_loading = false
        @emoji = false
        @footnotes = false
        @task_lists = false
        @definition_lists = false
        @mermaid = false
        @math = false
        @math_engine = "katex"
      end
    end

    # Language configuration for multilingual sites
    class LanguageConfig
      property code : String
      property language_name : String
      property weight : Int32
      property generate_feed : Bool
      property build_search_index : Bool
      property taxonomies : Array(String)

      def initialize(@code : String)
        @language_name = code
        @weight = 1
        @generate_feed = true
        @build_search_index = true
        @taxonomies = ["tags", "categories"]
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

      def initialize
        @enabled = false
        @minify = true
        @fingerprint = true
        @source_dir = "static"
        @output_dir = "assets"
        @bundles = [] of AssetBundleConfig
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
    class ImageProcessingConfig
      property enabled : Bool
      property widths : Array(Int32)
      property quality : Int32

      def initialize
        @enabled = false
        @widths = [] of Int32
        @quality = 85
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
      end
    end

    class Config
      property title : String
      property description : String
      property base_url : String
      property sitemap : SitemapConfig
      property robots : RobotsConfig
      property llms : LlmsConfig
      property feeds : FeedConfig
      property search : SearchConfig
      property plugins : PluginConfig
      property content_files : ContentFilesConfig
      property pagination : PaginationConfig
      property highlight : HighlightConfig
      property auto_includes : AutoIncludesConfig
      property og : OpenGraphConfig
      property taxonomies : Array(TaxonomyConfig)
      property default_language : String
      property languages : Hash(String, LanguageConfig)
      property build : BuildConfig
      property markdown : MarkdownConfig
      property series : SeriesConfig
      property related : RelatedConfig
      property deployment : DeploymentConfig
      property assets : AssetsConfig
      property pwa : PwaConfig
      property amp : AmpConfig
      property image_processing : ImageProcessingConfig
      property permalinks : Hash(String, String)
      property raw : Hash(String, TOML::Any)
      @base_url_stripped : String? = nil

      def initialize
        @title = "Hwaro Site"
        @description = ""
        @base_url = ""
        @sitemap = SitemapConfig.new
        @robots = RobotsConfig.new
        @llms = LlmsConfig.new
        @feeds = FeedConfig.new
        @search = SearchConfig.new
        @plugins = PluginConfig.new
        @content_files = ContentFilesConfig.new
        @pagination = PaginationConfig.new
        @highlight = HighlightConfig.new
        @auto_includes = AutoIncludesConfig.new
        @og = OpenGraphConfig.new
        @taxonomies = [] of TaxonomyConfig
        @default_language = "en"
        @languages = {} of String => LanguageConfig
        @build = BuildConfig.new
        @markdown = MarkdownConfig.new
        @series = SeriesConfig.new
        @related = RelatedConfig.new
        @deployment = DeploymentConfig.new
        @assets = AssetsConfig.new
        @pwa = PwaConfig.new
        @amp = AmpConfig.new
        @image_processing = ImageProcessingConfig.new
        @permalinks = {} of String => String
        @raw = Hash(String, TOML::Any).new
      end

      # Cached base_url with trailing slash stripped (avoids repeated rstrip per page)
      def base_url_stripped : String
        @base_url_stripped ||= @base_url.rstrip("/")
      end

      # Check if site is multilingual
      def multilingual? : Bool
        codes = @languages.keys
        codes << @default_language unless @default_language.empty?
        codes.uniq.size > 1
      end

      # Get language config by code, returns nil if not found
      def language(code : String) : LanguageConfig?
        @languages[code]?
      end

      # Get sorted languages by weight
      def sorted_languages : Array(LanguageConfig)
        @languages.values.sort_by(&.weight)
      end

      def self.load(config_path : String = "config.toml", env : String? = nil) : Config
        config = new
        return config unless File.exists?(config_path)

        # Read file content and substitute environment variables before TOML parsing
        raw_content = File.read(config_path)
        substituted_content = Utils::EnvSubstitutor.substitute_with_warnings(raw_content, config_path)
        config.raw = TOML.parse(substituted_content)

        # Merge environment-specific override (e.g. config.production.toml)
        if env_name = env
          env_path = config_path.sub(/\.toml$/, ".#{env_name}.toml")
          if File.exists?(env_path)
            env_content = File.read(env_path)
            env_substituted = Utils::EnvSubstitutor.substitute_with_warnings(env_content, env_path)
            env_raw = TOML.parse(env_substituted)
            config.raw = deep_merge(config.raw, env_raw)
            Logger.info "Loaded environment config: #{env_path}"
          else
            Logger.warn "Environment config not found: #{env_path}"
          end
        end

        config.title = config.raw["title"]?.try(&.as_s?) || config.title
        config.description = config.raw["description"]?.try(&.as_s?) || config.description
        config.base_url = config.raw["base_url"]?.try(&.as_s?) || config.base_url
        config.default_language = config.raw["default_language"]?.try(&.as_s?) || config.default_language

        load_sitemap(config)
        load_robots(config)
        load_llms(config)
        load_feeds(config)
        load_search(config)
        load_plugins(config)
        load_content_files(config)
        load_pagination(config)
        load_highlight(config)
        load_auto_includes(config)
        load_og(config)
        load_taxonomies(config)
        load_languages(config)
        load_build(config)
        load_markdown(config)
        load_series(config)
        load_related(config)
        load_permalinks(config)
        load_assets(config)
        load_pwa(config)
        load_amp(config)
        load_image_processing(config)
        load_deployment(config)

        config
      end

      # --- Private helpers -----------------------------------------------------------

      # Deep-merge two TOML hashes.  Values in `override` take precedence.
      # Sub-tables (hashes) are merged recursively; all other types are replaced.
      private def self.deep_merge(
        base : Hash(String, TOML::Any),
        override : Hash(String, TOML::Any),
      ) : Hash(String, TOML::Any)
        merged = base.dup
        override.each do |key, value|
          if base_val = merged[key]?
            base_hash = base_val.as_h?
            over_hash = value.as_h?
            if base_hash && over_hash
              merged[key] = TOML::Any.new(deep_merge(base_hash, over_hash))
            else
              merged[key] = value
            end
          else
            merged[key] = value
          end
        end
        merged
      end

      # Safe boolean loader: returns the parsed Bool if present, otherwise the default.
      # This avoids the `||` pitfall where `false || default` silently ignores `false`.
      private def self.bool_value(raw : TOML::Any?, default : Bool) : Bool
        val = raw.try(&.as_bool?)
        val.nil? ? default : val
      end

      # Safe integer loader: handles both integer and float TOML values.
      private def self.int_value(raw : TOML::Any?, default : Int32) : Int32
        return default unless raw
        raw.as_i? || raw.as_f?.try(&.to_i) || default
      end

      # Safe float loader: handles both float and integer TOML values.
      private def self.float_value(raw : TOML::Any?, default : Float64) : Float64
        return default unless raw
        raw.as_f? || raw.as_i?.try(&.to_f) || default
      end

      # Extracts a string-or-array TOML value into an Array(String).
      private def self.string_or_array(raw : TOML::Any?) : Array(String)
        return [] of String unless raw
        raw.as_a?.try(&.compact_map(&.as_s?)) ||
          raw.as_s?.try { |v| [v] } ||
          [] of String
      end

      # --- Private section loaders ---------------------------------------------------

      private def self.load_sitemap(config : Config)
        # Handle backward compatibility where sitemap was just a boolean
        if sitemap_bool = config.raw["sitemap"]?.try(&.as_bool?)
          config.sitemap.enabled = sitemap_bool
        elsif s = config.raw["sitemap"]?.try(&.as_h?)
          config.sitemap.enabled = bool_value(s["enabled"]?, config.sitemap.enabled)
          config.sitemap.filename = s["filename"]?.try(&.as_s?) || config.sitemap.filename
          config.sitemap.changefreq = s["changefreq"]?.try(&.as_s?) || config.sitemap.changefreq
          config.sitemap.priority = float_value(s["priority"]?, config.sitemap.priority)
          if exclude_arr = s["exclude"]?.try(&.as_a?)
            config.sitemap.exclude = exclude_arr.compact_map(&.as_s?)
          end
        end
      end

      private def self.load_robots(config : Config)
        return unless s = config.raw["robots"]?.try(&.as_h?)

        config.robots.enabled = bool_value(s["enabled"]?, config.robots.enabled)
        config.robots.filename = s["filename"]?.try(&.as_s?) || config.robots.filename

        if rules = s["rules"]?.try(&.as_a?)
          config.robots.rules = rules.compact_map do |rule_any|
            if rule_h = rule_any.as_h?
              user_agent = rule_h["user_agent"]?.try(&.as_s?) || "*"
              rule = RobotsRule.new(user_agent)
              rule.allow = string_or_array(rule_h["allow"]?)
              rule.disallow = string_or_array(rule_h["disallow"]?)
              rule
            else
              nil
            end
          end
        end
      end

      private def self.load_llms(config : Config)
        return unless s = config.raw["llms"]?.try(&.as_h?)

        config.llms.enabled = bool_value(s["enabled"]?, config.llms.enabled)
        config.llms.filename = s["filename"]?.try(&.as_s?) || config.llms.filename
        config.llms.instructions = s["instructions"]?.try(&.as_s?) || config.llms.instructions
        config.llms.full_enabled = bool_value(s["full_enabled"]?, config.llms.full_enabled)
        config.llms.full_filename = s["full_filename"]?.try(&.as_s?) || config.llms.full_filename
      end

      private def self.load_feeds(config : Config)
        return unless s = config.raw["feeds"]?.try(&.as_h?)

        # Backward compatibility for 'generate' property
        enabled = s["enabled"]?.try(&.as_bool?)
        generate = s["generate"]?.try(&.as_bool?)

        if !enabled.nil?
          config.feeds.enabled = enabled
        elsif !generate.nil?
          config.feeds.enabled = generate
        end

        config.feeds.filename = s["filename"]?.try(&.as_s?) || config.feeds.filename
        config.feeds.type = s["type"]?.try(&.as_s?) || config.feeds.type
        config.feeds.truncate = int_value(s["truncate"]?, config.feeds.truncate)
        config.feeds.limit = int_value(s["limit"]?, config.feeds.limit)
        if sections = s["sections"]?.try(&.as_a?)
          config.feeds.sections = sections.compact_map(&.as_s?)
        end
        config.feeds.default_language_only = bool_value(s["default_language_only"]?, config.feeds.default_language_only)
      end

      private def self.load_search(config : Config)
        return unless s = config.raw["search"]?.try(&.as_h?)

        config.search.enabled = bool_value(s["enabled"]?, config.search.enabled)
        config.search.format = s["format"]?.try(&.as_s?) || config.search.format
        config.search.filename = s["filename"]?.try(&.as_s?) || config.search.filename
        if fields = s["fields"]?.try(&.as_a?)
          config.search.fields = fields.compact_map(&.as_s?)
        end
        if exclude_arr = s["exclude"]?.try(&.as_a?)
          config.search.exclude = exclude_arr.compact_map(&.as_s?)
        end
        config.search.tokenize_cjk = bool_value(s["tokenize_cjk"]?, config.search.tokenize_cjk)
      end

      private def self.load_plugins(config : Config)
        return unless s = config.raw["plugins"]?.try(&.as_h?)

        if processors = s["processors"]?.try(&.as_a?)
          config.plugins.processors = processors.compact_map(&.as_s?)
        end
      end

      private def self.load_content_files(config : Config)
        return unless content_section = config.raw["content"]?.try(&.as_h?)
        return unless s = content_section["files"]?.try(&.as_h?)

        allow_any = s["allow_extensions"]? || s["extensions"]?
        disallow_any = s["disallow_extensions"]?
        disallow_paths_any = s["disallow_paths"]?

        if allow_any
          config.content_files.allow_extensions = ContentFilesConfig.normalize_extensions(string_or_array(allow_any))
        end

        if disallow_any
          config.content_files.disallow_extensions = ContentFilesConfig.normalize_extensions(string_or_array(disallow_any))
        end

        if disallow_paths_any
          config.content_files.disallow_paths = ContentFilesConfig.normalize_paths(string_or_array(disallow_paths_any))
        end
      end

      private def self.load_pagination(config : Config)
        return unless s = config.raw["pagination"]?.try(&.as_h?)

        config.pagination.enabled = bool_value(s["enabled"]?, config.pagination.enabled)
        config.pagination.per_page = int_value(s["per_page"]?, config.pagination.per_page)
      end

      private def self.load_highlight(config : Config)
        return unless s = config.raw["highlight"]?.try(&.as_h?)

        config.highlight.enabled = bool_value(s["enabled"]?, config.highlight.enabled)
        config.highlight.theme = s["theme"]?.try(&.as_s?) || config.highlight.theme
        config.highlight.use_cdn = bool_value(s["use_cdn"]?, config.highlight.use_cdn)
      end

      private def self.load_auto_includes(config : Config)
        return unless s = config.raw["auto_includes"]?.try(&.as_h?)

        config.auto_includes.enabled = bool_value(s["enabled"]?, config.auto_includes.enabled)
        if dirs = s["dirs"]?.try(&.as_a?)
          config.auto_includes.dirs = dirs.compact_map(&.as_s?)
        end
      end

      private def self.load_og(config : Config)
        return unless s = config.raw["og"]?.try(&.as_h?)

        config.og.default_image = s["default_image"]?.try(&.as_s?)
        config.og.twitter_card = s["twitter_card"]?.try(&.as_s?) || config.og.twitter_card
        config.og.twitter_site = s["twitter_site"]?.try(&.as_s?)
        config.og.twitter_creator = s["twitter_creator"]?.try(&.as_s?)
        config.og.fb_app_id = s["fb_app_id"]?.try(&.as_s?)
        config.og.og_type = s["type"]?.try(&.as_s?) || config.og.og_type

        if ai = s["auto_image"]?.try(&.as_h?)
          config.og.auto_image.enabled = bool_value(ai["enabled"]?, config.og.auto_image.enabled)
          config.og.auto_image.background = ai["background"]?.try(&.as_s?) || config.og.auto_image.background
          config.og.auto_image.text_color = ai["text_color"]?.try(&.as_s?) || config.og.auto_image.text_color
          config.og.auto_image.accent_color = ai["accent_color"]?.try(&.as_s?) || config.og.auto_image.accent_color
          config.og.auto_image.font_size = int_value(ai["font_size"]?, config.og.auto_image.font_size)
          config.og.auto_image.logo = ai["logo"]?.try(&.as_s?)
          config.og.auto_image.output_dir = ai["output_dir"]?.try(&.as_s?) || config.og.auto_image.output_dir
        end
      end

      private def self.load_taxonomies(config : Config)
        return unless taxonomies_section = config.raw["taxonomies"]?.try(&.as_a?)

        config.taxonomies = taxonomies_section.compact_map do |taxonomy_any|
          taxonomy_hash = taxonomy_any.as_h?
          next unless taxonomy_hash

          name = taxonomy_hash["name"]?.try(&.as_s?)
          next unless name

          taxonomy = TaxonomyConfig.new(name)
          taxonomy.feed = bool_value(taxonomy_hash["feed"]?, taxonomy.feed)
          taxonomy.sitemap = bool_value(taxonomy_hash["sitemap"]?, taxonomy.sitemap)
          taxonomy.paginate_by = taxonomy_hash["paginate_by"]?.try { |v| v.as_i? || v.as_f?.try(&.to_i) }
          taxonomy
        end
      end

      private def self.load_languages(config : Config)
        return unless s = config.raw["languages"]?.try(&.as_h?)

        s.each do |lang_code, lang_data|
          next unless lang_hash = lang_data.as_h?

          lang_config = LanguageConfig.new(lang_code)
          lang_config.language_name = lang_hash["language_name"]?.try(&.as_s?) || lang_code
          lang_config.weight = int_value(lang_hash["weight"]?, lang_config.weight)
          lang_config.generate_feed = bool_value(lang_hash["generate_feed"]?, lang_config.generate_feed)
          lang_config.build_search_index = bool_value(lang_hash["build_search_index"]?, lang_config.build_search_index)

          if taxonomies = lang_hash["taxonomies"]?.try(&.as_a?)
            lang_config.taxonomies = taxonomies.compact_map(&.as_s?)
          end

          config.languages[lang_code] = lang_config
        end
      end

      private def self.load_build(config : Config)
        return unless s = config.raw["build"]?.try(&.as_h?)

        if hooks_section = s["hooks"]?.try(&.as_h?)
          if pre_hooks = hooks_section["pre"]?.try(&.as_a?)
            config.build.hooks.pre = pre_hooks.compact_map(&.as_s?)
          end
          if post_hooks = hooks_section["post"]?.try(&.as_a?)
            config.build.hooks.post = post_hooks.compact_map(&.as_s?)
          end
        end
      end

      private def self.load_markdown(config : Config)
        return unless s = config.raw["markdown"]?.try(&.as_h?)

        config.markdown.safe = bool_value(s["safe"]?, config.markdown.safe)
        config.markdown.lazy_loading = bool_value(s["lazy_loading"]?, config.markdown.lazy_loading)
        config.markdown.emoji = bool_value(s["emoji"]?, config.markdown.emoji)
        config.markdown.footnotes = bool_value(s["footnotes"]?, config.markdown.footnotes)
        config.markdown.task_lists = bool_value(s["task_lists"]?, config.markdown.task_lists)
        config.markdown.definition_lists = bool_value(s["definition_lists"]?, config.markdown.definition_lists)
        config.markdown.mermaid = bool_value(s["mermaid"]?, config.markdown.mermaid)
        config.markdown.math = bool_value(s["math"]?, config.markdown.math)
        if engine = s["math_engine"]?.try(&.as_s?)
          config.markdown.math_engine = engine
        end
      end

      private def self.load_series(config : Config)
        return unless s = config.raw["series"]?.try(&.as_h?)

        config.series.enabled = bool_value(s["enabled"]?, config.series.enabled)
      end

      private def self.load_related(config : Config)
        return unless s = config.raw["related"]?.try(&.as_h?)

        config.related.enabled = bool_value(s["enabled"]?, config.related.enabled)
        config.related.limit = int_value(s["limit"]?, config.related.limit)
        if taxonomies = s["taxonomies"]?.try(&.as_a?)
          config.related.taxonomies = taxonomies.compact_map(&.as_s?)
        end
      end

      private def self.load_permalinks(config : Config)
        return unless s = config.raw["permalinks"]?.try(&.as_h?)

        s.each do |k, v|
          if target = v.as_s?
            config.permalinks[k] = target
          end
        end
      end

      private def self.load_assets(config : Config)
        return unless s = config.raw["assets"]?.try(&.as_h?)

        config.assets.enabled = bool_value(s["enabled"]?, config.assets.enabled)
        config.assets.minify = bool_value(s["minify"]?, config.assets.minify)
        config.assets.fingerprint = bool_value(s["fingerprint"]?, config.assets.fingerprint)
        config.assets.source_dir = s["source_dir"]?.try(&.as_s?) || config.assets.source_dir
        config.assets.output_dir = s["output_dir"]?.try(&.as_s?) || config.assets.output_dir

        if bundles = s["bundles"]?.try(&.as_a?)
          bundles.each do |bundle_any|
            next unless b = bundle_any.as_h?
            name = b["name"]?.try(&.as_s?) || ""
            next if name.empty?

            files = if f = b["files"]?.try(&.as_a?)
                      f.compact_map(&.as_s?)
                    else
                      [] of String
                    end

            config.assets.bundles << AssetBundleConfig.new(name: name, files: files)
          end
        end
      end

      private def self.load_amp(config : Config)
        return unless s = config.raw["amp"]?.try(&.as_h?)

        config.amp.enabled = bool_value(s["enabled"]?, config.amp.enabled)
        config.amp.path_prefix = s["path_prefix"]?.try(&.as_s?) || config.amp.path_prefix
        if sections = s["sections"]?.try(&.as_a?)
          config.amp.sections = sections.compact_map(&.as_s?)
        end
      end

      private def self.load_pwa(config : Config)
        return unless s = config.raw["pwa"]?.try(&.as_h?)

        config.pwa.enabled = bool_value(s["enabled"]?, config.pwa.enabled)
        config.pwa.name = s["name"]?.try(&.as_s?)
        config.pwa.short_name = s["short_name"]?.try(&.as_s?)
        config.pwa.theme_color = s["theme_color"]?.try(&.as_s?) || config.pwa.theme_color
        config.pwa.background_color = s["background_color"]?.try(&.as_s?) || config.pwa.background_color
        config.pwa.display = s["display"]?.try(&.as_s?) || config.pwa.display
        config.pwa.start_url = s["start_url"]?.try(&.as_s?) || config.pwa.start_url
        config.pwa.offline_page = s["offline_page"]?.try(&.as_s?)
        if icons = s["icons"]?.try(&.as_a?)
          config.pwa.icons = icons.compact_map(&.as_s?)
        end
        if precache = s["precache_urls"]?.try(&.as_a?)
          config.pwa.precache_urls = precache.compact_map(&.as_s?)
        end
      end

      private def self.load_image_processing(config : Config)
        return unless s = config.raw["image_processing"]?.try(&.as_h?)

        config.image_processing.enabled = bool_value(s["enabled"]?, config.image_processing.enabled)
        config.image_processing.quality = int_value(s["quality"]?, config.image_processing.quality).clamp(1, 100)
        if widths = s["widths"]?.try(&.as_a?)
          config.image_processing.widths = widths.compact_map { |w|
            val = w.as_i? || w.as_f?.try(&.to_i)
            val && val > 0 ? val : nil
          }
        end
      end

      private def self.load_deployment(config : Config)
        return unless s = config.raw["deployment"]?.try(&.as_h?)

        config.deployment.target = s["target"]?.try(&.as_s?)
        config.deployment.confirm = bool_value(s["confirm"]?, config.deployment.confirm)

        dry_any = s["dryRun"]? || s["dry_run"]?
        if dry_val = dry_any.try(&.as_bool?)
          config.deployment.dry_run = dry_val
        end

        if force_val = s["force"]?.try(&.as_bool?)
          config.deployment.force = force_val
        end

        max_deletes_any = s["maxDeletes"]? || s["max_deletes"]?
        if max_deletes_val = max_deletes_any.try { |v| v.as_i? || v.as_f?.try(&.to_i) }
          config.deployment.max_deletes = max_deletes_val
        end

        if workers_val = s["workers"]?.try { |v| v.as_i? || v.as_f?.try(&.to_i) }
          config.deployment.workers = workers_val
        end

        source_any = s["source_dir"]? || s["source"]?
        if source_val = source_any.try(&.as_s?)
          config.deployment.source_dir = source_val
        end

        load_deployment_targets(config, s)
        load_deployment_matchers(config, s)
      end

      private def self.load_deployment_targets(config : Config, s : Hash(String, TOML::Any))
        return unless targets_any = s["targets"]?.try(&.as_a?)

        config.deployment.targets = targets_any.compact_map do |target_any|
          next unless target_h = target_any.as_h?

          name = target_h["name"]?.try(&.as_s?)
          next unless name

          target = DeploymentTarget.new
          target.name = name
          target.url = target_h["URL"]?.try(&.as_s?) || target_h["url"]?.try(&.as_s?) || ""
          target.command = target_h["command"]?.try(&.as_s?)
          target.include = target_h["include"]?.try(&.as_s?)
          target.exclude = target_h["exclude"]?.try(&.as_s?)

          strip_any = target_h["stripIndexHTML"]? || target_h["strip_index_html"]?
          if strip_val = strip_any.try(&.as_bool?)
            target.strip_index_html = strip_val
          end

          target
        end
      end

      private def self.load_deployment_matchers(config : Config, s : Hash(String, TOML::Any))
        return unless matchers_any = s["matchers"]?.try(&.as_a?)

        config.deployment.matchers = matchers_any.compact_map do |matcher_any|
          next unless matcher_h = matcher_any.as_h?

          pattern = matcher_h["pattern"]?.try(&.as_s?)
          next unless pattern

          matcher = DeploymentMatcher.new
          matcher.pattern = pattern
          matcher.cache_control = matcher_h["cacheControl"]?.try(&.as_s?) || matcher_h["cache_control"]?.try(&.as_s?)
          matcher.content_type = matcher_h["contentType"]?.try(&.as_s?) || matcher_h["content_type"]?.try(&.as_s?)
          if gzip_val = matcher_h["gzip"]?.try(&.as_bool?)
            matcher.gzip = gzip_val
          end
          if force_val = matcher_h["force"]?.try(&.as_bool?)
            matcher.force = force_val
          end
          matcher
        end
      end
    end
  end
end
