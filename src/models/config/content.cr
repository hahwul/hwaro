# Config section — [content], [pagination], [series], [related], [links], [git], [permalinks].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    # Internal link handling configuration
    class LinksConfig
      # How unresolved `@/path.md` internal links are treated during the
      # render phase: "warn" (default) logs a warning and leaves the markup
      # unchanged; "error" fails the build with a single aggregated list of
      # every offender. Unknown values fall back to "warn".
      property broken_internal : String

      def initialize
        @broken_internal = "warn"
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

    # `[git]` — per-page commit metadata (see Core::Build::GitInfo).
    class GitConfig
      property enabled : Bool
      # Fill `page.updated` from the latest commit when front matter has none.
      property use_lastmod : Bool
      # Fill `page.date` from the first commit when front matter has none.
      property use_date : Bool

      def initialize
        @enabled = false
        @use_lastmod = true
        @use_date = false
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
        @allow_extensions.present?
      end

      def publish?(relative_path : String) : Bool
        normalized_path = ContentFilesConfig.normalize_path(relative_path)
        ext = File.extname(normalized_path).downcase
        return false if ext.empty?
        return false if ext == ".md"
        return false unless @allow_extensions.includes?(ext)
        return false if @disallow_extensions.includes?(ext)
        @disallow_paths.each do |pattern|
          # A malformed glob is treated as non-matching by glob_match?, so a
          # config typo can't crash the build; other patterns still apply.
          return false if Utils::PathUtils.glob_match?(pattern, normalized_path)
        end
        true
      end

      def self.normalize_extensions(values : Array(String)) : Array(String)
        values.compact_map do |ext|
          normalize_extension(ext)
        end.uniq!
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
        return if ext.empty?
        ext.starts_with?(".") ? ext : ".#{ext}"
      end
    end

    # Automatic summary fallback (`[content] summary_length` /
    # `summary_ellipsis`). When a page has neither a `<!-- more -->` marker
    # nor a `description`, `page.summary` is filled from the first
    # `length` words of the rendered body (characters ×2 for CJK-dominant
    # text — see Utils::TextUtils.truncate_excerpt). `length = 0` disables
    # the fallback entirely, restoring the pre-0.21 behaviour where such
    # pages had no summary at all.
    class SummaryConfig
      DEFAULT_LENGTH   = 70
      DEFAULT_ELLIPSIS = "\u2026"

      property length : Int32
      property ellipsis : String

      def initialize
        @length = DEFAULT_LENGTH
        @ellipsis = DEFAULT_ELLIPSIS
      end

      def enabled? : Bool
        @length > 0
      end
    end

    # `hwaro new` content scaffolding configuration.
    #
    # Controls what `hwaro new` writes when there is no matching archetype:
    #   - `front_matter_format` — "toml" (default) or "yaml"
    #   - `default_fields`      — extra front matter keys (e.g. "description")
    #     emitted with empty values so users can fill them in without having
    #     to remember them.
    #   - `bundle`              — when true, new pages default to the
    #     leaf-bundle layout (`foo/index.md`) instead of a single file
    #     (`foo.md`), which is the shape needed for multilingual siblings
    #     and colocated page assets. Overridden by an archetype's own
    #     `<!-- hwaro: bundle -->` directive, and by `--bundle`/`--no-bundle`
    #     on the CLI (CLI > archetype > config).
    #
    # Fields listed in `default_fields` that overlap with built-ins
    # (`title`, `date`, `draft`, `tags`) are ignored because those have
    # dedicated handling and values.
    class ContentNewConfig
      FORMAT_TOML    = "toml"
      FORMAT_YAML    = "yaml"
      FORMAT_JSON    = "json"
      VALID_FORMATS  = {FORMAT_TOML, FORMAT_YAML, FORMAT_JSON}
      BUILTIN_FIELDS = {"title", "date", "draft", "tags"}

      property front_matter_format : String
      property default_fields : Array(String)
      property bundle : Bool

      def initialize
        @front_matter_format = FORMAT_TOML
        @default_fields = ["description"]
        @bundle = false
      end

      def toml? : Bool
        @front_matter_format == FORMAT_TOML
      end

      def yaml? : Bool
        @front_matter_format == FORMAT_YAML
      end

      def json? : Bool
        @front_matter_format == FORMAT_JSON
      end

      # Extra fields, with built-ins filtered out and duplicates removed,
      # preserving configured order.
      def extra_fields : Array(String)
        @default_fields.reject { |f| BUILTIN_FIELDS.includes?(f) }.uniq!
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
  end
end

module Hwaro
  module Models
    class Config
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

      # Loads `hwaro new` scaffold settings from `[content.new]` (preferred)
      # or falls back to flat keys on `[content]` so short configs like
      # `[content]\nfront_matter_format = "yaml"` also work. The fallback is
      # scoped to the two recognised keys so unrelated `[content]` sub-tables
      # (e.g. `[content.files]`) can never be misread as `new`-scaffold input.
      private def self.load_content_new(config : Config)
        return unless content_section = config.raw["content"]?.try(&.as_h?)

        nested = content_section["new"]?.try(&.as_h?)
        format_any = nested.try(&.[]?("front_matter_format")) || content_section["front_matter_format"]?
        fields_any = nested.try(&.[]?("default_fields")) || content_section["default_fields"]?
        bundle_any = nested.try(&.[]?("bundle")) || content_section["bundle"]?

        if format = format_any.try(&.as_s?)
          normalized = format.downcase
          if ContentNewConfig::VALID_FORMATS.includes?(normalized)
            config.content_new.front_matter_format = normalized
          else
            Logger.warn "Unknown content.new.front_matter_format '#{format}', keeping '#{config.content_new.front_matter_format}'"
          end
        end

        if fields = fields_any.try(&.as_a?)
          config.content_new.default_fields = fields.compact_map(&.as_s?)
        end

        if bundle = bundle_any.try(&.as_bool?)
          config.content_new.bundle = bundle
        end
      end

      private def self.load_pagination(config : Config)
        return unless s = config.raw["pagination"]?.try(&.as_h?)

        config.pagination.enabled = bool_value(s["enabled"]?, config.pagination.enabled)
        config.pagination.per_page = int_value(s["per_page"]?, config.pagination.per_page)
      end

      # `[content] summary_length` / `summary_ellipsis` — the automatic
      # summary fallback (see SummaryConfig). Flat keys on `[content]`, next
      # to the other content-wide knobs; a negative length is clamped to 0
      # (disabled) with a warning rather than crashing a slice later.
      private def self.load_content_summary(config : Config)
        return unless content_section = config.raw["content"]?.try(&.as_h?)

        length = int_value(content_section["summary_length"]?, config.summary.length)
        if length < 0
          Logger.warn "config: [content] summary_length must be >= 0 (got #{length}); disabling the automatic summary"
          length = 0
        end
        config.summary.length = length

        if raw = content_section["summary_ellipsis"]?
          if ellipsis = raw.as_s?
            config.summary.ellipsis = ellipsis
          else
            Logger.warn "config: [content] summary_ellipsis must be a string; keeping #{config.summary.ellipsis.inspect}"
          end
        end
      end

      private def self.load_series(config : Config)
        return unless s = config.raw["series"]?.try(&.as_h?)

        config.series.enabled = bool_value(s["enabled"]?, config.series.enabled)
      end

      private def self.load_related(config : Config)
        return unless s = config.raw["related"]?.try(&.as_h?)

        config.related.enabled = bool_value(s["enabled"]?, config.related.enabled)
        # Clamp at the source so every consumer sees a sane value. A negative
        # limit reaches `Array#first(limit)` in the incremental related-posts
        # rebuild (transform.cr) and raises `ArgumentError: Negative count`,
        # crashing `serve` watch rebuilds (the full build guards `limit <= 0`,
        # the incremental path did not — clamping fixes both uniformly).
        config.related.limit = int_value(s["limit"]?, config.related.limit).clamp(0, Int32::MAX)
        if taxonomies = s["taxonomies"]?.try(&.as_a?)
          config.related.taxonomies = taxonomies.compact_map(&.as_s?)
        end
      end

      private def self.load_git(config : Config)
        return unless s = config.raw["git"]?.try(&.as_h?)

        config.git.enabled = bool_value(s["enabled"]?, config.git.enabled)
        config.git.use_lastmod = bool_value(s["use_lastmod"]?, config.git.use_lastmod)
        config.git.use_date = bool_value(s["use_date"]?, config.git.use_date)
        s.each_key do |key|
          next if key.in?("enabled", "use_lastmod", "use_date")
          Logger.warn "[git]: unknown key '#{key}' — hwaro does not read it."
        end
      end

      private def self.load_links(config : Config)
        return unless s = config.raw["links"]?.try(&.as_h?)

        if mode = s["broken_internal"]?.try(&.as_s?)
          if mode == "warn" || mode == "error"
            config.links.broken_internal = mode
          else
            Logger.warn "Unknown [links] broken_internal value '#{mode}' — expected \"warn\" or \"error\"; keeping \"warn\"."
          end
        end
      end

      private def self.load_permalinks(config : Config)
        return unless s = config.raw["permalinks"]?.try(&.as_h?)

        s.each do |k, v|
          if target = v.as_s?
            # Token patterns (e.g. "/:year/:month/:slug/") rebuild whole
            # URLs at resolve time. Validate tokens up front so a typo'd
            # `:tokne` fails the config load instead of emitting literal
            # `:tokne` path segments.
            Utils::PermalinkResolver.validate_pattern!(k, target) if Utils::PermalinkResolver.pattern?(target)
            # Strip surrounding slashes from BOTH the source key and the
            # target — only the OUTER slashes; interior structure (pattern
            # or remap) must survive verbatim. The resolver matches against
            # slash-free directory paths and interpolates the target as
            # `/#{effective_dir}/`, so a key or target written with
            # leading/trailing slashes (e.g. `"/blog/"`) would otherwise
            # silently never match (source) or produce double-slash URLs
            # like `http://host//blog//p/` (target).
            config.permalinks[k.strip("/")] = target.strip("/")
          end
        end
      end
    end
  end
end
