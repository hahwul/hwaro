# Config section — [build], [serve], [static], [outputs], [doctor], [plugins].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    # Plugin configuration for extensibility
    class PluginConfig
      property processors : Array(String)

      def initialize
        @processors = ["markdown"] # Default processor
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

      # Track template extends/include/import dependencies so a template
      # edit only invalidates the pages that actually render it (cached
      # builds and `hwaro serve`). Set to false to restore the previous
      # behavior: any template change rebuilds every page.
      property template_deps : Bool = true

      # Defaults for the matching `hwaro build` flags. Nil means the key is
      # absent from config.toml, which is what keeps the precedence chain
      # honest: a command-line flag beats config.toml, config.toml beats the
      # built-in default, and an absent key changes nothing. See
      # `Config::Options::BuildOptions#apply_build_config!` for the merge.
      property output_dir : String? = nil
      property drafts : Bool? = nil
      property parallel : Bool? = nil
      property cache : Bool? = nil

      def initialize
        @hooks = BuildHooksConfig.new
      end
    end

    # Serve (development server) configuration
    #
    # Currently used to configure custom response headers that are injected
    # on every request while running `hwaro serve`. This makes it easy to
    # reproduce production reverse-proxy / CDN header behaviour locally.
    class ServeConfig
      # Custom HTTP response headers applied to *all* responses during
      # `hwaro serve` (including 404s, redirects, and static assets).
      property headers : Hash(String, String)

      # When true, `hwaro serve` will behave as if `--fast` was passed
      # (skips heavy OG image generation and image processing by default).
      # CLI flags can still override this.
      property fast : Bool = false

      def initialize
        @headers = {} of String => String
        @fast = false
      end
    end

    class DoctorConfig
      property ignore : Array(String)

      def initialize
        @ignore = [] of String
      end
    end

    # `[static]` — controls which files under `static/` get published.
    #
    # `static/` is copied verbatim into the site root, so OS/editor/VCS cruft
    # placed there (`.DS_Store`, `Thumbs.db`, `.git/`, vim swap files, …) would
    # otherwise be deployed. A built-in denylist filters the common offenders;
    # `exclude` adds project-specific patterns — a glob like `*.bak` filters at
    # any depth, `drafts/**` scopes a subtree, and a literal name is anchored to
    # an exact file or directory (`drafts` drops `drafts/…`) — and
    # `use_default_excludes = false` opts out of the built-in list entirely.
    #
    # Note: this only filters *cruft*. Legitimate dot-paths such as
    # `.well-known/` are NOT in the denylist and are always published.
    class StaticConfig
      # Exact file/dir names that should essentially never be published.
      # Matched per path segment, so an entry like `.git` filters that
      # directory (and everything under it) at any depth.
      DEFAULT_EXCLUDE_NAMES = Set{
        ".DS_Store", ".AppleDouble", ".LSOverride", ".Spotlight-V100",
        ".Trashes", ".fseventsd", ".DocumentRevisions-V100", ".TemporaryItems",
        ".VolumeIcon.icns", "__MACOSX",
        "Thumbs.db", "ehthumbs.db", "ehthumbs_vista.db", "desktop.ini", ".directory",
        ".git", ".gitignore", ".gitattributes", ".gitmodules", ".gitkeep",
        ".svn", ".hg", ".bzr",
      }

      # Suffixes for vim swap files, matched against the leaf file name only.
      # Kept deliberately narrow: a name ending in `.swp`/`.swo` is never a
      # legitimate published asset, so the always-on default denylist can't
      # silently drop real content. Emacs-style `~` backups are intentionally
      # NOT here — a trailing tilde is a legal file name, so filtering it is
      # left to an explicit `exclude` pattern.
      DEFAULT_EXCLUDE_SUFFIXES = [".swp", ".swo"]

      # Glob metacharacters that distinguish an `exclude` glob from a literal
      # path/name.
      GLOB_METACHARS = /[*?\[{]/

      property exclude : Array(String)
      property use_default_excludes : Bool

      def initialize
        @exclude = [] of String
        @use_default_excludes = true
      end

      # Whether `relative_path` (relative to `static/`) should be filtered out
      # of the published output.
      #
      # `exclude` entries match two ways depending on their shape:
      # - a glob (contains `* ? [ {`) matches the relative path, and — when it
      #   has no `/` — the bare file name too, so `*.bak` filters at any depth
      #   while `drafts/**` scopes to a subtree;
      # - a literal is anchored: it matches that exact path or, when it names a
      #   directory, the whole subtree under it. So `drafts` drops `drafts/...`
      #   but `config` only drops a top-level `config`, never a same-named file
      #   nested elsewhere.
      def excluded?(relative_path : String) : Bool
        normalized = Path[relative_path].to_posix.to_s
        return false if normalized.empty? || normalized == "."

        if @use_default_excludes
          segments = normalized.split('/')
          # Exact-name cruft (`.git`, `.DS_Store`, …) filters at any depth; the
          # swap-file suffix check applies to the leaf name only, so a directory
          # whose name happens to end in `.swp` doesn't take its subtree with it.
          return true if segments.any? { |segment| DEFAULT_EXCLUDE_NAMES.includes?(segment) }
          return true if DEFAULT_EXCLUDE_SUFFIXES.any? { |suffix| segments.last.ends_with?(suffix) }
        end

        return false if @exclude.empty?
        basename = File.basename(normalized)
        @exclude.any? { |pattern| pattern_matches?(pattern, normalized, basename) }
      end

      private def pattern_matches?(pattern : String, normalized : String, basename : String) : Bool
        if GLOB_METACHARS.matches?(pattern)
          # Glob: match the full relative path, plus the bare name for a
          # path-less glob so it applies at any depth. A malformed glob (e.g.
          # an unclosed `[` class) makes File.match? raise File::BadPatternError;
          # treat it as non-matching rather than crashing the whole build on a
          # single config typo.
          Utils::PathUtils.glob_match?(pattern, normalized) ||
            (!pattern.includes?('/') && Utils::PathUtils.glob_match?(pattern, basename))
        else
          # Literal: an exact file, or a directory subtree rooted at it.
          normalized == pattern || normalized.starts_with?("#{pattern}/")
        end
      end
    end

    # `[outputs]` — declares extra per-page/per-section output formats
    # beyond HTML (sibling `index.<fmt>` files rendered from a user-supplied
    # `templates/<name>.<fmt>.jinja` template). See
    # docs/content/features/output-formats.md for the full selection chain
    # and front matter override (`page.extra["outputs"]`).
    class OutputsConfig
      VALID_FORMATS = %w[json txt xml csv]

      # Formats every regular page emits (unless overridden by front matter).
      property page : Array(String)
      # Formats every section index emits (unless overridden by front matter).
      property section : Array(String)
      # Optional allowlist of section names formats apply to; empty = all
      # sections. Matches a section name or any of its descendants, mirroring
      # `FeedConfig#sections`.
      property sections : Array(String)

      def initialize
        @page = [] of String
        @section = [] of String
        @sections = [] of String
      end

      # Whether any format is configured at all (page or section).
      def any? : Bool
        @page.present? || @section.present?
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      private def self.load_plugins(config : Config)
        return unless s = config.raw["plugins"]?.try(&.as_h?)

        if processors = s["processors"]?.try(&.as_a?)
          config.plugins.processors = processors.compact_map(&.as_s?)
        end
      end

      # A `[build]` boolean, or nil when the key is absent. A present-but-wrong
      # type warns rather than no-opping: `cache = "true"` (quoting a bool is
      # an easy TOML slip) would otherwise leave caching off with no feedback,
      # while the sibling `output_dir` branch does report what it refuses.
      private def self.build_bool_value(s : Hash(String, TOML::Any), key : String) : Bool?
        return unless raw = s[key]?
        if value = raw.as_bool?
          return value
        end
        # `as_bool?` returns nil for `false`, so distinguish a real false from a
        # type mismatch before warning.
        return false if raw.raw == false
        Logger.warn "Ignoring non-boolean [build] #{key} value #{raw.raw.inspect}; expected true or false."
        nil
      end

      # A `[build] output_dir`, or nil when it is unusable. Both rejections keep
      # `hwaro build` and `hwaro serve` pointed at the same directory:
      # an empty value resolves to the site root, which a cold build wipes, and
      # a `..` path escapes the project — which the dev server refuses to serve
      # from (`Server#sanitize_output_dir`) even though the build would write
      # there, leaving serve publishing one tree and serving another.
      private def self.build_output_dir_value(raw : TOML::Any) : String?
        value = raw.as_s?
        unless value
          Logger.warn "Ignoring non-string [build] output_dir value #{raw.raw.inspect}; expected a directory path."
          return
        end

        trimmed = value.strip
        if trimmed.empty?
          Logger.warn "Ignoring empty [build] output_dir in config; using the default."
          return
        end

        if Path[trimmed].normalize.to_s.starts_with?("..")
          Logger.warn "Ignoring [build] output_dir #{trimmed.inspect}: it points outside the project. Using the default."
          return
        end

        trimmed
      end

      private def self.load_build(config : Config)
        return unless s = config.raw["build"]?.try(&.as_h?)

        config.build.template_deps = bool_value(s["template_deps"]?, config.build.template_deps)

        # Left nil when absent so the CLI/default layers below stay in charge.
        if raw_output = s["output_dir"]?
          config.build.output_dir = build_output_dir_value(raw_output)
        end
        config.build.drafts = build_bool_value(s, "drafts")
        config.build.parallel = build_bool_value(s, "parallel")
        config.build.cache = build_bool_value(s, "cache")

        if hooks_section = s["hooks"]?.try(&.as_h?)
          if pre_hooks = hooks_section["pre"]?.try(&.as_a?)
            config.build.hooks.pre = pre_hooks.compact_map(&.as_s?)
          end
          if post_hooks = hooks_section["post"]?.try(&.as_a?)
            config.build.hooks.post = post_hooks.compact_map(&.as_s?)
          end
        end
      end

      private def self.load_serve(config : Config)
        return unless s = config.raw["serve"]?.try(&.as_h?)

        if headers_table = s["headers"]?.try(&.as_h?)
          headers_table.each do |name, value|
            next unless str = value.as_s?
            next if name.each_char.any? { |c| c.ascii_control? || c == ':' } ||
                    str.each_char.any?(&.ascii_control?)

            config.serve.headers[name] = str
          end
        end

        # Fast dev mode default (can be overridden by CLI flags like --fast or explicit --skip-*)
        config.serve.fast = bool_value(s["fast"]?, config.serve.fast)
      end

      private def self.load_doctor(config : Config)
        return unless s = config.raw["doctor"]?.try(&.as_h?)

        if ignore = s["ignore"]?.try(&.as_a?)
          config.doctor.ignore = ignore.compact_map(&.as_s?)
        end
      end

      private def self.load_static(config : Config)
        return unless s = config.raw["static"]?.try(&.as_h?)

        config.static.use_default_excludes = bool_value(s["use_default_excludes"]?, config.static.use_default_excludes)
        if exclude_any = s["exclude"]?
          config.static.exclude = string_or_array(exclude_any)
        end
      end

      private def self.load_outputs(config : Config)
        return unless s = config.raw["outputs"]?.try(&.as_h?)

        if page_any = s["page"]?
          config.outputs.page = validate_output_formats(string_or_array(page_any))
        end
        if section_any = s["section"]?
          config.outputs.section = validate_output_formats(string_or_array(section_any))
        end
        if sections = s["sections"]?.try(&.as_a?)
          config.outputs.sections = sections.compact_map(&.as_s?)
        end
      end

      # Validate `[outputs]` format names against `OutputsConfig::VALID_FORMATS`.
      # Raises a classified `HWARO_E_CONFIG` error (rather than warning and
      # falling back) because an unknown format silently produces no output —
      # a user who typos "jso" for "json" deserves a build failure, not a
      # quietly-missing file.
      private def self.validate_output_formats(formats : Array(String)) : Array(String)
        formats.each do |fmt|
          next if OutputsConfig::VALID_FORMATS.includes?(fmt)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Unknown output format '#{fmt}' in [outputs]. Valid formats: #{OutputsConfig::VALID_FORMATS.join(", ")}.",
            hint: "Use one of: #{OutputsConfig::VALID_FORMATS.join(", ")}.",
          )
        end
        formats
      end
    end
  end
end
