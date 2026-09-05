require "toml"
require "uri"
require "./deployment"
require "../utils/errors"
require "../utils/text_utils"
require "../utils/permalink_resolver"
require "../utils/env_substitutor"
require "../utils/path_utils"
require "../content/processors/internal_link_resolver"

require "./config/seo"
require "./config/search"
require "./config/opengraph"
require "./config/highlight"
require "./config/markdown"
require "./config/versions"
require "./config/data_remote"
require "./config/content_generate"
require "./config/content"
require "./config/i18n"
require "./config/assets"
require "./config/build_serve"
require "./config/deployment"
require "./config/toml_helpers"

module Hwaro
  module Models
    # Cache-busting query suffix shared by the asset/highlight tag emitters.
    def self.cache_bust_suffix(value : String) : String
      value.empty? ? "" : "?v=#{HTML.escape(value)}"
    end

    # Join non-empty tag fragments with newlines.
    def self.join_tags(*parts : String) : String
      parts.reject(&.empty?).join("\n")
    end

    class Config
      property title : String
      property description : String
      getter base_url : String
      property sitemap : SitemapConfig
      property robots : RobotsConfig
      property llms : LlmsConfig
      property feeds : FeedConfig
      property search : SearchConfig
      property plugins : PluginConfig
      property content_files : ContentFilesConfig
      property content_new : ContentNewConfig
      property summary : SummaryConfig
      property pagination : PaginationConfig
      property highlight : HighlightConfig
      property auto_includes : AutoIncludesConfig
      property og : OpenGraphConfig
      property taxonomies : Array(TaxonomyConfig)
      property menus : Hash(String, Array(MenuItemConfig))
      property default_language : String
      property languages : Hash(String, LanguageConfig)
      property versions : VersionsConfig
      property build : BuildConfig
      property serve : ServeConfig
      property markdown : MarkdownConfig
      property series : SeriesConfig
      property related : RelatedConfig
      property git : GitConfig
      property deployment : DeploymentConfig
      property assets : AssetsConfig
      property sass : SassConfig
      property pwa : PwaConfig
      property amp : AmpConfig
      property image_processing : ImageProcessingConfig
      property doctor : DoctorConfig
      property static : StaticConfig
      property outputs : OutputsConfig
      property links : LinksConfig
      property data_remote : Array(RemoteDataConfig)
      property content_generate : Array(ContentGenerateConfig)
      property permalinks : Hash(String, String)
      property raw : Hash(String, TOML::Any)
      @base_url_stripped : String? = nil
      @base_path : String? = nil
      @multilingual : Bool? = nil

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
        @content_new = ContentNewConfig.new
        @summary = SummaryConfig.new
        @pagination = PaginationConfig.new
        @highlight = HighlightConfig.new
        @auto_includes = AutoIncludesConfig.new
        @og = OpenGraphConfig.new
        @taxonomies = [] of TaxonomyConfig
        @menus = {} of String => Array(MenuItemConfig)
        @default_language = "en"
        @languages = {} of String => LanguageConfig
        @versions = VersionsConfig.new
        @build = BuildConfig.new
        @serve = ServeConfig.new
        @markdown = MarkdownConfig.new
        @series = SeriesConfig.new
        @related = RelatedConfig.new
        @git = GitConfig.new
        @deployment = DeploymentConfig.new
        @assets = AssetsConfig.new
        @sass = SassConfig.new
        @pwa = PwaConfig.new
        @amp = AmpConfig.new
        @image_processing = ImageProcessingConfig.new
        @doctor = DoctorConfig.new
        @static = StaticConfig.new
        @outputs = OutputsConfig.new
        @links = LinksConfig.new
        @data_remote = [] of RemoteDataConfig
        @content_generate = [] of ContentGenerateConfig
        @permalinks = {} of String => String
        @raw = Hash(String, TOML::Any).new
      end

      # Normalize on assignment: a trailing slash makes `{{ base_url }}/path`
      # templates (and canonical/og URLs) emit `//`. Strip it so the build is
      # correct whether the trailing slash came from config.toml or `--base-url`
      # (previously only `doctor --fix` normalized this).
      def base_url=(value : String)
        @base_url = value.rstrip("/")
        @base_url_stripped = nil
        @base_path = nil
      end

      # Cached base_url with trailing slash stripped (avoids repeated rstrip per page)
      def base_url_stripped : String
        @base_url_stripped ||= @base_url.rstrip("/")
      end

      # Path component of `base_url`, used to make root-relative links work when
      # the site is deployed under a subpath (e.g. GitHub/GitLab project pages
      # served at `https://user.github.io/repo/`). For `https://x.com/repo` this
      # returns `/repo`; for a domain-root deployment (`https://x.com`) or an
      # empty `base_url` it returns `""`. Trailing slashes are stripped so callers
      # can build `base_path + page.url` without producing `//`.
      def base_path : String
        @base_path ||= begin
          stripped = base_url_stripped
          if stripped.empty?
            ""
          else
            path = URI.parse(stripped).path.rstrip("/")
            path == "/" ? "" : path
          end
        rescue URI::Error
          ""
        end
      end

      # Prefix a site-internal root-relative path (e.g. `/posts/x/`) with
      # `base_path` so generated URLs resolve under a subpath deployment.
      # Absolute `http(s)://` URLs and paths that are not root-relative are
      # returned unchanged; a no-op when `base_path` is "" (domain-root deploy).
      # Callers that may hold a path without a leading slash (e.g. some
      # `page.url` values) should normalize it first — this helper only
      # prefixes values that already start with "/".
      def with_base_path(path : String) : String
        return path if base_path.empty?
        return path if path.starts_with?("http://") || path.starts_with?("https://")
        # Protocol-relative URLs (`//cdn.example.com/x`) are external — leave
        # them untouched, matching how render.cr / internal_link_resolver treat
        # `//host`. Without this they'd become `/base//cdn.example.com/x`.
        return path if path.starts_with?("//")
        return path unless path.starts_with?("/")
        "#{base_path}#{path}"
      end

      # Check if site is multilingual. Memoized — this runs several times
      # per page during render, and the languages table only mutates during
      # config load, before the first call. The `languages=` /
      # `default_language=` setters invalidate; in-place mutation of the
      # languages Hash after the first call would not (don't do that).
      def multilingual? : Bool
        cached = @multilingual
        return cached unless cached.nil?

        codes = @languages.keys
        codes << @default_language unless @default_language.empty?
        @multilingual = codes.uniq.size > 1
      end

      def languages=(value : Hash(String, LanguageConfig))
        @multilingual = nil
        @languages = value
      end

      def default_language=(value : String)
        @multilingual = nil
        @default_language = value
      end

      # Get language config by code, returns nil if not found
      def language(code : String) : LanguageConfig?
        @languages[code]?
      end

      # Get sorted languages by weight
      def sorted_languages : Array(LanguageConfig)
        @languages.values.sort_by!(&.weight)
      end

      # Load and parse a `config.toml` into a populated `Config`.
      #
      # Raises `Hwaro::HwaroError(HWARO_E_CONFIG)` directly at the source for
      # file-not-found and TOML parse errors so every caller (build, deploy,
      # doctor, tool, services) gets a classified error with exit code 3
      # without having to do substring matching on the exception message.
      # File-not-found is classified as HWARO_E_CONFIG rather than HWARO_E_IO
      # because a missing `config.toml` is a config-level user error, not an
      # arbitrary IO failure.
      # Accepts an absolute `http(s)://host[:port][/path]` URL or the empty
      # string (which means "no absolute URL is configured"). Raises
      # ArgumentError on anything else so callers can wrap the failure in
      # whichever classified `HwaroError` code suits their context
      # (`HWARO_E_CONFIG` for config.toml, `HWARO_E_USAGE` for CLI flags).
      def self.validate_base_url!(value : String) : Nil
        return if value.empty?

        # Crystal's URI parser is lenient about whitespace and control
        # characters: `https://exam ple.com` and a value with an embedded
        # newline both parse with a non-empty host and pass every check below.
        # The RAW string — not the parsed URI — is what gets concatenated with
        # each page URL, so such a value is copied verbatim into <loc> in
        # sitemap.xml, into rss.xml, into every canonical/og:url and into
        # llms.txt. No absolute URL can legally contain these characters
        # (RFC 3986 requires them percent-encoded), so reject them here rather
        # than emit a whole site of unusable links.
        if value.each_char.any? { |c| c.ascii_whitespace? || c.ascii_control? }
          raise ArgumentError.new("Invalid base_url: #{value.inspect}. It must not contain whitespace or control characters.")
        end

        uri = begin
          URI.parse(value)
        rescue URI::Error
          raise ArgumentError.new("Invalid base_url: '#{value}'. Expected http(s)://host[/path].")
        end

        scheme = uri.scheme
        host = uri.host
        if scheme.nil? || !%w[http https].includes?(scheme.downcase) || host.nil? || host.empty?
          raise ArgumentError.new("Invalid base_url: '#{value}'. Expected http(s)://host[/path].")
        end
        # A query/fragment is not part of the origin+path that page URLs append
        # to. base_path parses with URI#path (dropping query/fragment), so the
        # raw base_url and the derived base_path would silently disagree and
        # corrupt absolute (base_url + page.url) links. Reject it at the source.
        unless (uri.query.nil? || uri.query.try(&.empty?)) && (uri.fragment.nil? || uri.fragment.try(&.empty?))
          raise ArgumentError.new("Invalid base_url: '#{value}'. base_url must not contain a query string or fragment.")
        end
      end

      # True when built-in Sass compilation is on and `relative_path` is an
      # SCSS source — such files compile to `.css` instead of publishing
      # verbatim through the static copy. The extension must be lowercase
      # `.scss`, matching what the compiler's glob picks up — other casings
      # keep publishing verbatim.
      def sass_source?(relative_path : String) : Bool
        sass.enabled && relative_path.ends_with?(".scss")
      end

      def self.load(config_path : String = "config.toml", env : String? = nil) : Config
        config = new

        unless File.exists?(config_path)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "config.toml not found at #{config_path}",
            hint: "Run 'hwaro init' to scaffold a project, or cd into a directory containing config.toml.",
          )
        end

        # Read file content and substitute environment variables before TOML parsing
        raw_content = File.read(config_path)
        substituted_content = Utils::EnvSubstitutor.substitute_with_warnings(raw_content, config_path)
        config.raw = parse_toml(substituted_content, config_path)

        # Merge environment-specific override (e.g. config.production.toml).
        # A missing override is recoverable (we just use the base config), but
        # it's the most common way to ship a localhost build to production by
        # accident (typo `--env prdo`, file not committed, etc.), so the warning
        # is intentionally explicit and names both the requested env and the
        # exact filename we looked for.
        if env_name = env
          env_path = config_path.sub(/\.toml$/, ".#{env_name}.toml")
          if File.exists?(env_path)
            env_content = File.read(env_path)
            env_substituted = Utils::EnvSubstitutor.substitute_with_warnings(env_content, env_path)
            env_raw = parse_toml(env_substituted, env_path)
            config.raw = deep_merge(config.raw, env_raw)
            Logger.info "Loaded environment config: #{env_path}"
          else
            Logger.warn "--env #{env_name}: override file '#{env_path}' not found; continuing with base #{config_path} only. If you intended to ship environment-specific settings (e.g. a production base_url), create #{env_path} or check for a typo in --env."
          end
        end

        warn_unknown_top_level_keys(config.raw, config_path)
        reject_null_bytes!(config.raw, config_path)

        config.title = string_or_default(config.raw, "title", config.title)
        config.description = string_or_default(config.raw, "description", config.description)
        if raw_base_url = config.raw["base_url"]?.try(&.as_s?)
          begin
            validate_base_url!(raw_base_url)
          rescue ex : ArgumentError
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONFIG,
              message: ex.message || "Invalid base_url in #{config_path}",
              hint: "Set base_url to an absolute URL such as \"https://example.com\" or \"http://localhost:3000\".",
            )
          end
          config.base_url = raw_base_url
        end
        config.default_language = config.raw["default_language"]?.try(&.as_s?) || config.default_language

        SECTION_LOADERS.each(&.load.call(config))

        config
      end

      # One entry per section loader: the top-level config.toml key(s) it
      # reads and the loader itself. This is the registry a new section
      # joins (see src/models/config/*.cr) — it drives both the load order and
      # the unknown-key warning, so a section can't be loaded without also
      # being recognised, or vice versa.
      #
      # Order matters for exactly three entries: `languages` reads the menus
      # and taxonomies already loaded (per-language overrides), `sass` reads
      # `auto_includes`, and `resolve_deployment_source_dir` reads `build` and
      # `deployment`. Everything else only reads `config.raw`.
      record SectionLoader, keys : Array(String), load : Proc(Config, Nil)

      SECTION_LOADERS = [
        SectionLoader.new(%w[sitemap], ->(c : Config) { load_sitemap(c) }),
        SectionLoader.new(%w[robots], ->(c : Config) { load_robots(c) }),
        SectionLoader.new(%w[llms], ->(c : Config) { load_llms(c) }),
        SectionLoader.new(%w[feeds], ->(c : Config) { load_feeds(c) }),
        SectionLoader.new(%w[search], ->(c : Config) { load_search(c) }),
        SectionLoader.new(%w[plugins], ->(c : Config) { load_plugins(c) }),
        SectionLoader.new(%w[content], ->(c : Config) { load_content_files(c) }),
        SectionLoader.new(%w[content], ->(c : Config) { load_content_new(c) }),
        SectionLoader.new(%w[content], ->(c : Config) { load_content_summary(c) }),
        SectionLoader.new(%w[pagination], ->(c : Config) { load_pagination(c) }),
        SectionLoader.new(%w[highlight], ->(c : Config) { load_highlight(c) }),
        SectionLoader.new(%w[auto_includes], ->(c : Config) { load_auto_includes(c) }),
        SectionLoader.new(%w[og], ->(c : Config) { load_og(c) }),
        SectionLoader.new(%w[menus], ->(c : Config) { load_menus(c) }),
        SectionLoader.new(%w[taxonomies], ->(c : Config) { load_taxonomies(c) }),
        SectionLoader.new(%w[languages], ->(c : Config) { load_languages(c) }),
        SectionLoader.new(%w[versions], ->(c : Config) { load_versions(c) }),
        SectionLoader.new(%w[build], ->(c : Config) { load_build(c) }),
        SectionLoader.new(%w[serve], ->(c : Config) { load_serve(c) }),
        SectionLoader.new(%w[markdown], ->(c : Config) { load_markdown(c) }),
        SectionLoader.new(%w[series], ->(c : Config) { load_series(c) }),
        SectionLoader.new(%w[related], ->(c : Config) { load_related(c) }),
        SectionLoader.new(%w[git], ->(c : Config) { load_git(c) }),
        SectionLoader.new(%w[permalinks], ->(c : Config) { load_permalinks(c) }),
        SectionLoader.new(%w[assets], ->(c : Config) { load_assets(c) }),
        SectionLoader.new(%w[sass], ->(c : Config) { load_sass(c) }),
        SectionLoader.new(%w[pwa], ->(c : Config) { load_pwa(c) }),
        SectionLoader.new(%w[amp], ->(c : Config) { load_amp(c) }),
        SectionLoader.new(%w[image_processing], ->(c : Config) { load_image_processing(c) }),
        SectionLoader.new(%w[doctor], ->(c : Config) { load_doctor(c) }),
        SectionLoader.new(%w[static], ->(c : Config) { load_static(c) }),
        SectionLoader.new(%w[deployment], ->(c : Config) { load_deployment(c) }),
        SectionLoader.new(%w[], ->(c : Config) { resolve_deployment_source_dir(c) }),
        SectionLoader.new(%w[outputs], ->(c : Config) { load_outputs(c) }),
        SectionLoader.new(%w[links], ->(c : Config) { load_links(c) }),
        SectionLoader.new(%w[data], ->(c : Config) { load_data_remote(c) }),
        SectionLoader.new(%w[content], ->(c : Config) { load_content_generate(c) }),
      ]

      # The four scalar keys `load` reads directly, ahead of any section.
      SCALAR_KEYS = %w[title description base_url default_language]

      # Every top-level key `load` reads (scalars + registered section keys).
      # Used to warn on unrecognized keys instead of silently ignoring them —
      # a typo'd `[markdonw]` or `titel =` otherwise disables a feature with
      # zero feedback. Templates cannot read arbitrary raw config keys (the
      # site/config objects expose structured fields only), so an unknown
      # top-level key is always dead configuration. Sorted, so "did you mean"
      # suggestions tie-break the same way regardless of load order.
      KNOWN_TOP_LEVEL_KEYS = SCALAR_KEYS + SECTION_LOADERS.flat_map(&.keys).uniq!.sort!

      private def self.warn_unknown_top_level_keys(raw : Hash(String, TOML::Any), config_path : String)
        raw.each_key do |key|
          next if KNOWN_TOP_LEVEL_KEYS.includes?(key)
          hint = Utils::CommandSuggester.suggest(key, KNOWN_TOP_LEVEL_KEYS).try { |s| " Did you mean '#{s}'?" } || ""
          Logger.warn "Unknown key '#{key}' in #{config_path} — hwaro does not read it.#{hint}"
        end
      end
    end
  end
end
