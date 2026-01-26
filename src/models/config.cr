require "toml"

module Hwaro
  module Models
    class SitemapConfig
      property enabled : Bool
      property filename : String
      property changefreq : String
      property priority : Float64

      def initialize
        @enabled = false
        @filename = "sitemap.xml"
        @changefreq = "weekly"
        @priority = 0.5
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

      def initialize
        @enabled = false
        @format = "fuse_json"
        @fields = ["title", "content"]
        @filename = "search.json"
      end
    end

    class FeedConfig
      property enabled : Bool
      property filename : String
      property type : String
      property truncate : Int32
      property limit : Int32
      property sections : Array(String)

      def initialize
        @enabled = false
        @filename = ""
        @type = "rss"
        @truncate = 0
        @limit = 10
        @sections = [] of String
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
        path = path.sub(/\A\//, "")
        path = path.sub(/\Acontent\//, "")
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
      def css_tags(base_url : String = "") : String
        return "" unless @enabled
        return "" if @dirs.empty?

        tags = [] of String
        @dirs.each do |dir|
          static_dir = File.join("static", dir)
          next unless Dir.exists?(static_dir)

          Dir.glob(File.join(static_dir, "**", "*.css")).sort.each do |file|
            # Convert static/assets/css/style.css to /assets/css/style.css
            relative_path = file.sub(/^static\/?/, "/")
            tags << %(<link rel="stylesheet" href="#{base_url}#{relative_path}">)
          end
        end
        tags.join("\n")
      end

      # Generate JS script tags for files in configured directories
      def js_tags(base_url : String = "") : String
        return "" unless @enabled
        return "" if @dirs.empty?

        tags = [] of String
        @dirs.each do |dir|
          static_dir = File.join("static", dir)
          next unless Dir.exists?(static_dir)

          Dir.glob(File.join(static_dir, "**", "*.js")).sort.each do |file|
            # Convert static/assets/js/main.js to /assets/js/main.js
            relative_path = file.sub(/^static\/?/, "/")
            tags << %(<script src="#{base_url}#{relative_path}"></script>)
          end
        end
        tags.join("\n")
      end

      # Generate both CSS and JS tags
      def all_tags(base_url : String = "") : String
        css = css_tags(base_url)
        js = js_tags(base_url)
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

    # OpenGraph and Twitter Card configuration
    class OpenGraphConfig
      property default_image : String?
      property twitter_card : String
      property twitter_site : String?
      property twitter_creator : String?
      property fb_app_id : String?
      property og_type : String

      def initialize
        @default_image = nil
        @twitter_card = "summary_large_image"
        @twitter_site = nil
        @twitter_creator = nil
        @fb_app_id = nil
        @og_type = "article"
      end

      # Generate OG meta tags
      def og_tags(
        title : String,
        description : String?,
        url : String,
        image : String?,
        base_url : String,
      ) : String
        tags = [] of String

        tags << %(<meta property="og:title" content="#{escape_html(title)}">)
        tags << %(<meta property="og:type" content="#{@og_type}">)
        tags << %(<meta property="og:url" content="#{base_url}#{url}">)

        if desc = description
          tags << %(<meta property="og:description" content="#{escape_html(desc)}">)
        end

        # Use page image or fall back to default
        if img = (image || @default_image)
          # Make image URL absolute
          img_url = img.starts_with?("http") ? img : "#{base_url}#{img.starts_with?("/") ? img : "/#{img}"}"
          tags << %(<meta property="og:image" content="#{img_url}">)
        end

        if fb_id = @fb_app_id
          tags << %(<meta property="fb:app_id" content="#{fb_id}">)
        end

        tags.join("\n")
      end

      # Generate Twitter Card meta tags
      def twitter_tags(
        title : String,
        description : String?,
        image : String?,
        base_url : String,
      ) : String
        tags = [] of String

        tags << %(<meta name="twitter:card" content="#{@twitter_card}">)
        tags << %(<meta name="twitter:title" content="#{escape_html(title)}">)

        if desc = description
          tags << %(<meta name="twitter:description" content="#{escape_html(desc)}">)
        end

        # Use page image or fall back to default
        if img = (image || @default_image)
          img_url = img.starts_with?("http") ? img : "#{base_url}#{img.starts_with?("/") ? img : "/#{img}"}"
          tags << %(<meta name="twitter:image" content="#{img_url}">)
        end

        if site = @twitter_site
          tags << %(<meta name="twitter:site" content="#{site}">)
        end

        if creator = @twitter_creator
          tags << %(<meta name="twitter:creator" content="#{creator}">)
        end

        tags.join("\n")
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

      private def escape_html(text : String) : String
        text.gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub("\"", "&quot;")
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
      def css_tag : String
        return "" unless @enabled
        if @use_cdn
          %(<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/#{@theme}.min.css">)
        else
          %(<link rel="stylesheet" href="/assets/css/highlight/#{@theme}.min.css">)
        end
      end

      # Generate the JS script tag for highlighting
      def js_tag : String
        return "" unless @enabled
        if @use_cdn
          %(<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>\n<script>hljs.highlightAll();</script>)
        else
          %(<script src="/assets/js/highlight.min.js"></script>\n<script>hljs.highlightAll();</script>)
        end
      end

      # Generate both CSS and JS tags
      def tags : String
        return "" unless @enabled
        "#{css_tag}\n#{js_tag}"
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
      property safe : Bool # If true, raw HTML will not be passed through (replaced by comments)

      def initialize
        @safe = false
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
      property raw : Hash(String, TOML::Any)

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
        @raw = Hash(String, TOML::Any).new
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

      def self.load(config_path : String = "config.toml") : Config
        config = new
        if File.exists?(config_path)
          config.raw = TOML.parse_file(config_path)
          config.title = config.raw["title"]?.try(&.as_s?) || config.title
          config.description = config.raw["description"]?.try(&.as_s?) || config.description
          config.base_url = config.raw["base_url"]?.try(&.as_s?) || config.base_url

          # Load Sitemap configuration
          # Handle backward compatibility where sitemap was just a boolean
          if sitemap_bool = config.raw["sitemap"]?.try(&.as_bool?)
            config.sitemap.enabled = sitemap_bool
          elsif sitemap_section = config.raw["sitemap"]?.try(&.as_h?)
            config.sitemap.enabled = sitemap_section["enabled"]?.try(&.as_bool?) || config.sitemap.enabled
            config.sitemap.filename = sitemap_section["filename"]?.try(&.as_s?) || config.sitemap.filename
            config.sitemap.changefreq = sitemap_section["changefreq"]?.try(&.as_s?) || config.sitemap.changefreq
            config.sitemap.priority = sitemap_section["priority"]?.try { |v| v.as_f? || v.as_i?.try(&.to_f) } || config.sitemap.priority
          end

          # Load Robots configuration
          if robots_section = config.raw["robots"]?.try(&.as_h?)
            config.robots.enabled = robots_section["enabled"]?.try(&.as_bool?) || config.robots.enabled
            config.robots.filename = robots_section["filename"]?.try(&.as_s?) || config.robots.filename

            if rules = robots_section["rules"]?.try(&.as_a?)
              config.robots.rules = rules.compact_map do |rule_any|
                if rule_h = rule_any.as_h?
                  user_agent = rule_h["user_agent"]?.try(&.as_s?) || "*"
                  rule = RobotsRule.new(user_agent)

                  if allow = rule_h["allow"]?
                    if allow_arr = allow.as_a?
                      rule.allow = allow_arr.compact_map(&.as_s?)
                    elsif allow_str = allow.as_s?
                      rule.allow = [allow_str]
                    end
                  end

                  if disallow = rule_h["disallow"]?
                    if disallow_arr = disallow.as_a?
                      rule.disallow = disallow_arr.compact_map(&.as_s?)
                    elsif disallow_str = disallow.as_s?
                      rule.disallow = [disallow_str]
                    end
                  end
                  rule
                else
                  nil
                end
              end
            end
          end

          # Load LLMs configuration
          if llms_section = config.raw["llms"]?.try(&.as_h?)
            config.llms.enabled = llms_section["enabled"]?.try(&.as_bool?) || config.llms.enabled
            config.llms.filename = llms_section["filename"]?.try(&.as_s?) || config.llms.filename
            config.llms.instructions = llms_section["instructions"]?.try(&.as_s?) || config.llms.instructions
            config.llms.full_enabled = llms_section["full_enabled"]?.try(&.as_bool?) || config.llms.full_enabled
            config.llms.full_filename = llms_section["full_filename"]?.try(&.as_s?) || config.llms.full_filename
          end

          # Load Feeds configuration
          if feeds_section = config.raw["feeds"]?.try(&.as_h?)
            # Backward compatibility for 'generate' property
            enabled = feeds_section["enabled"]?.try(&.as_bool?)
            generate = feeds_section["generate"]?.try(&.as_bool?)

            if !enabled.nil?
              config.feeds.enabled = enabled
            elsif !generate.nil?
              config.feeds.enabled = generate
            end

            config.feeds.filename = feeds_section["filename"]?.try(&.as_s?) || config.feeds.filename
            config.feeds.type = feeds_section["type"]?.try(&.as_s?) || config.feeds.type
            config.feeds.truncate = feeds_section["truncate"]?.try { |v| v.as_i? || v.as_f?.try(&.to_i) } || config.feeds.truncate
            config.feeds.limit = feeds_section["limit"]?.try { |v| v.as_i? || v.as_f?.try(&.to_i) } || config.feeds.limit
            if sections = feeds_section["sections"]?.try(&.as_a?)
              config.feeds.sections = sections.compact_map(&.as_s?)
            end
          end

          # Load search configuration
          if search_section = config.raw["search"]?.try(&.as_h?)
            config.search.enabled = search_section["enabled"]?.try(&.as_bool?) || config.search.enabled
            config.search.format = search_section["format"]?.try(&.as_s?) || config.search.format
            config.search.filename = search_section["filename"]?.try(&.as_s?) || config.search.filename
            if fields = search_section["fields"]?.try(&.as_a?)
              config.search.fields = fields.compact_map(&.as_s?)
            end
          end

          # Load plugins configuration
          if plugins_section = config.raw["plugins"]?.try(&.as_h?)
            if processors = plugins_section["processors"]?.try(&.as_a?)
              config.plugins.processors = processors.compact_map(&.as_s?)
            end
          end

          # Load content files publishing configuration
          if content_section = config.raw["content"]?.try(&.as_h?)
            if files_section = content_section["files"]?.try(&.as_h?)
              allow_any = files_section["allow_extensions"]? || files_section["extensions"]?
              disallow_any = files_section["disallow_extensions"]?
              disallow_paths_any = files_section["disallow_paths"]?

              if allow_any
                values = allow_any.as_a?.try(&.compact_map(&.as_s?)) ||
                         allow_any.as_s?.try { |s| [s] } ||
                         ([] of String)
                config.content_files.allow_extensions = ContentFilesConfig.normalize_extensions(values)
              end

              if disallow_any
                values = disallow_any.as_a?.try(&.compact_map(&.as_s?)) ||
                         disallow_any.as_s?.try { |s| [s] } ||
                         ([] of String)
                config.content_files.disallow_extensions = ContentFilesConfig.normalize_extensions(values)
              end

              if disallow_paths_any
                values = disallow_paths_any.as_a?.try(&.compact_map(&.as_s?)) ||
                         disallow_paths_any.as_s?.try { |s| [s] } ||
                         ([] of String)
                config.content_files.disallow_paths = ContentFilesConfig.normalize_paths(values)
              end
            end
          end

          # Load pagination configuration
          if pagination_section = config.raw["pagination"]?.try(&.as_h?)
            config.pagination.enabled = pagination_section["enabled"]?.try(&.as_bool?) || config.pagination.enabled
            config.pagination.per_page = pagination_section["per_page"]?.try { |v| v.as_i? || v.as_f?.try(&.to_i) } || config.pagination.per_page
          end

          # Load highlight (syntax highlighting) configuration
          if highlight_section = config.raw["highlight"]?.try(&.as_h?)
            if highlight_section.has_key?("enabled")
              enabled_val = highlight_section["enabled"]?.try(&.as_bool?)
              config.highlight.enabled = enabled_val unless enabled_val.nil?
            end
            config.highlight.theme = highlight_section["theme"]?.try(&.as_s?) || config.highlight.theme
            if highlight_section.has_key?("use_cdn")
              use_cdn_val = highlight_section["use_cdn"]?.try(&.as_bool?)
              config.highlight.use_cdn = use_cdn_val unless use_cdn_val.nil?
            end
          end

          # Load auto_includes configuration
          if auto_includes_section = config.raw["auto_includes"]?.try(&.as_h?)
            config.auto_includes.enabled = auto_includes_section["enabled"]?.try(&.as_bool?) || config.auto_includes.enabled
            if dirs = auto_includes_section["dirs"]?.try(&.as_a?)
              config.auto_includes.dirs = dirs.compact_map(&.as_s?)
            end
          end

          # Load OpenGraph configuration
          if og_section = config.raw["og"]?.try(&.as_h?)
            config.og.default_image = og_section["default_image"]?.try(&.as_s?)
            config.og.twitter_card = og_section["twitter_card"]?.try(&.as_s?) || config.og.twitter_card
            config.og.twitter_site = og_section["twitter_site"]?.try(&.as_s?)
            config.og.twitter_creator = og_section["twitter_creator"]?.try(&.as_s?)
            config.og.fb_app_id = og_section["fb_app_id"]?.try(&.as_s?)
            config.og.og_type = og_section["type"]?.try(&.as_s?) || config.og.og_type
          end

          # Load taxonomies configuration
          if taxonomies_section = config.raw["taxonomies"]?.try(&.as_a?)
            config.taxonomies = taxonomies_section.compact_map do |taxonomy_any|
              taxonomy_hash = taxonomy_any.as_h?
              next unless taxonomy_hash

              name = taxonomy_hash["name"]?.try(&.as_s?)
              next unless name

              taxonomy = TaxonomyConfig.new(name)
              taxonomy.feed = taxonomy_hash["feed"]?.try(&.as_bool?) || taxonomy.feed
              taxonomy.sitemap = taxonomy_hash["sitemap"]?.try(&.as_bool?) || taxonomy.sitemap
              taxonomy.paginate_by = taxonomy_hash["paginate_by"]?.try { |v| v.as_i? || v.as_f?.try(&.to_i) }
              taxonomy
            end
          end

          # Load default language
          config.default_language = config.raw["default_language"]?.try(&.as_s?) || config.default_language

          # Load languages configuration
          if languages_section = config.raw["languages"]?.try(&.as_h?)
            languages_section.each do |lang_code, lang_data|
              next unless lang_hash = lang_data.as_h?

              lang_config = LanguageConfig.new(lang_code)
              lang_config.language_name = lang_hash["language_name"]?.try(&.as_s?) || lang_code
              lang_config.weight = lang_hash["weight"]?.try { |v| v.as_i? || v.as_f?.try(&.to_i) } || lang_config.weight
              lang_config.generate_feed = lang_hash["generate_feed"]?.try(&.as_bool?) || lang_config.generate_feed
              lang_config.build_search_index = lang_hash["build_search_index"]?.try(&.as_bool?) || lang_config.build_search_index

              if taxonomies = lang_hash["taxonomies"]?.try(&.as_a?)
                lang_config.taxonomies = taxonomies.compact_map(&.as_s?)
              end

              config.languages[lang_code] = lang_config
            end
          end

          # Load build configuration (hooks)
          if build_section = config.raw["build"]?.try(&.as_h?)
            if hooks_section = build_section["hooks"]?.try(&.as_h?)
              if pre_hooks = hooks_section["pre"]?.try(&.as_a?)
                config.build.hooks.pre = pre_hooks.compact_map(&.as_s?)
              end
              if post_hooks = hooks_section["post"]?.try(&.as_a?)
                config.build.hooks.post = post_hooks.compact_map(&.as_s?)
              end
            end
          end

          # Load markdown configuration
          if markdown_section = config.raw["markdown"]?.try(&.as_h?)
            if markdown_section.has_key?("safe")
              safe_val = markdown_section["safe"]?.try(&.as_bool?)
              config.markdown.safe = safe_val unless safe_val.nil?
            end
          end
        end
        config
      end
    end
  end
end
