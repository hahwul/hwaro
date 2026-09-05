# Config section — [versions] and [[versions.list]].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    # One documentation version (`[[versions.list]]`). Versions are
    # directory-based, modeled on languages: every content file under
    # `content/<path>/` belongs to the version, and the build maps that
    # directory to a URL prefix (see `url_dir`).
    class VersionConfig
      property name : String
      property label : String
      # Content directory, relative to `content/` (no leading/trailing
      # slash). Defaults to `name`.
      property path : String
      property latest : Bool

      def initialize(@name : String, @label : String = name, @path : String = name, @latest : Bool = false)
      end

      # Parent directory of `path` ("" for a top-level version directory).
      # `content/docs/v2` → "docs"; `content/v2` → "".
      def parent_dir : String
        idx = @path.rindex('/')
        idx ? @path[0, idx] : ""
      end

      # Content-relative directory this version PUBLISHES under. The latest
      # version renders at its parent's natural location when
      # `latest_at_root` is on (`docs/v2` → `docs`); every other version
      # keeps a `/<name>/` segment under the parent (`docs/v1` → `docs/v1`,
      # or `docs/one` when name != basename of path).
      def url_dir(latest_at_root : Bool) : String
        parent = parent_dir
        return parent if @latest && latest_at_root
        parent.empty? ? @name : "#{parent}/#{@name}"
      end

      # Path of `content_path` relative to this version's directory, or nil
      # when the file is not inside it. `docs/v2/install.md` → "install.md".
      def relative_path(content_path : String) : String?
        return unless content_path.starts_with?("#{@path}/")
        content_path[(@path.size + 1)..]
      end

      # True when `content_path` (content-relative) lives inside this version.
      def contains?(content_path : String) : Bool
        content_path == @path || content_path.starts_with?("#{@path}/")
      end
    end

    # `[versions]` — versioned documentation. Disabled (no effect on the
    # build) until at least one `[[versions.list]]` entry is declared.
    class VersionsConfig
      # Latest version renders at its parent's natural URL (`/docs/`); older
      # versions get a `/<name>/` segment. When false every version keeps its
      # segment and the parent URL becomes a redirect stub to the latest.
      property latest_at_root : Bool
      # Older versions emit `<meta name="robots" content="noindex">` next to a
      # canonical pointing at the latest counterpart (when one exists).
      property noindex_old : Bool
      # "latest" | "all": which versions enter search.json AND sitemap.xml.
      property search : String
      # "latest" | "all": which versions feed RSS/Atom.
      property feeds : String
      # "latest" | "all": which versions taxonomy term pages collect from.
      property taxonomies : String
      property list : Array(VersionConfig)

      SWITCH_VALUES = {"latest", "all"}

      def initialize
        @latest_at_root = true
        @noindex_old = true
        @search = "latest"
        @feeds = "latest"
        @taxonomies = "latest"
        @list = [] of VersionConfig
      end

      def enabled? : Bool
        !@list.empty?
      end

      # The single `latest = true` entry (the loader guarantees exactly one
      # when the list is non-empty).
      def latest : VersionConfig?
        @list.find(&.latest)
      end

      def find(name : String) : VersionConfig?
        @list.find { |v| v.name == name }
      end

      # The version owning a content-relative path (file or directory), or
      # nil for unversioned content. Version directories never nest (the
      # loader rejects that), so at most one entry matches.
      def for_path(content_path : String) : VersionConfig?
        return if @list.empty?
        @list.find(&.contains?(content_path))
      end

      # Site-relative root URL of `version` (no base_path), e.g. "/docs/",
      # "/docs/v1/", "/ko/docs/v1/" — `lang_prefix` is "" or "/<code>".
      def root_url(version : VersionConfig, lang_prefix : String = "") : String
        dir = version.url_dir(@latest_at_root)
        dir.empty? ? "#{lang_prefix}/" : "#{lang_prefix}/#{dir}/"
      end

      # --- Discovery-surface switches -----------------------------------
      # Unversioned pages always pass; versioned pages pass when they belong
      # to the latest version or the switch is "all".

      def in_search?(page : Page) : Bool
        allowed?(page, @search)
      end

      def in_feeds?(page : Page) : Bool
        allowed?(page, @feeds)
      end

      def in_taxonomies?(page : Page) : Bool
        allowed?(page, @taxonomies)
      end

      # llms.txt is latest-only by design (no switch).
      def in_llms?(page : Page) : Bool
        allowed?(page, "latest")
      end

      private def allowed?(page : Page, switch : String) : Bool
        version = page.version
        return true unless version
        switch == "all" || version.latest
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      # `[versions]` (switches) + `[[versions.list]]` (entries). TOML cannot
      # make one key both a table and an array of tables, so a bare
      # `[[versions]]` array is accepted too: entries only, default switches.
      #
      # Validation is strict — a misconfigured version silently publishing
      # docs at the wrong URL is worse than a failed build:
      #   - `name` required, URL-safe, unique
      #   - `path` (defaults to name) content-relative, unique, non-nested
      #   - exactly one `latest = true` (none → the first entry is latest)
      #   - search / feeds / taxonomies ∈ {"latest", "all"}
      VERSION_NAME_RE = /\A[A-Za-z0-9][A-Za-z0-9._~-]*\z/

      private def self.load_versions(config : Config)
        raw = config.raw["versions"]?
        return unless raw

        versions = VersionsConfig.new
        entries = [] of TOML::Any
        if table = raw.as_h?
          versions.latest_at_root = bool_value(table["latest_at_root"]?, versions.latest_at_root)
          versions.noindex_old = bool_value(table["noindex_old"]?, versions.noindex_old)
          versions.search = version_switch_value(table, "search", versions.search)
          versions.feeds = version_switch_value(table, "feeds", versions.feeds)
          versions.taxonomies = version_switch_value(table, "taxonomies", versions.taxonomies)
          if list = table["list"]?
            entries = list.as_a? || raise_versions_error("[versions] list must be an array of tables ([[versions.list]])")
          end
        elsif array = raw.as_a?
          entries = array
        else
          raise_versions_error("[versions] must be a table (with [[versions.list]] entries) or an array of tables")
        end

        seen_names = Set(String).new
        entries.each do |entry|
          hash = entry.as_h? || raise_versions_error("every [[versions.list]] entry must be a table with a `name`")
          name = hash["name"]?.try(&.as_s?).try(&.strip) || ""
          raise_versions_error("a [[versions.list]] entry is missing `name`") if name.empty?
          unless name.matches?(VERSION_NAME_RE)
            raise_versions_error("version name #{name.inspect} is not URL-safe — use ASCII letters, digits, `-`, `_`, `.` or `~` (e.g. \"v2\", \"2.x\")")
          end
          raise_versions_error("version name #{name.inspect} is declared twice") unless seen_names.add?(name)

          path = normalize_version_path(hash["path"]?.try(&.as_s?) || name, name)
          label = hash["label"]?.try(&.as_s?).try(&.strip)
          label = name if label.nil? || label.empty?
          versions.list << VersionConfig.new(name, label, path, bool_value(hash["latest"]?, false))
        end

        return if versions.list.empty?

        versions.list.each_with_index do |a, i|
          versions.list.each_with_index do |b, j|
            next if i >= j
            if a.path == b.path
              raise_versions_error("versions #{a.name.inspect} and #{b.name.inspect} share the content path #{a.path.inspect}")
            end
            if a.contains?(b.path) || b.contains?(a.path)
              raise_versions_error("version paths must not nest: #{a.path.inspect} (#{a.name}) and #{b.path.inspect} (#{b.name})")
            end
          end
        end

        latest = versions.list.select(&.latest)
        if latest.size > 1
          names = latest.map(&.name).join(", ")
          raise_versions_error("only one version can be `latest = true`, got #{latest.size}: #{names}")
        elsif latest.empty?
          versions.list.first.latest = true
        end

        config.versions = versions
      end

      private def self.version_switch_value(table : Hash(String, TOML::Any), key : String, default : String) : String
        raw = table[key]?
        return default unless raw
        value = raw.as_s?.try(&.strip.downcase)
        unless value && VersionsConfig::SWITCH_VALUES.includes?(value)
          raise_versions_error("[versions] #{key} must be \"latest\" or \"all\", got #{raw.raw.inspect}")
        end
        value
      end

      # Content-relative, forward-slash, no leading `./`/`/`, no trailing
      # `/`, no `.`/`..` segments — the path is compared against page paths
      # byte-for-byte, so it has to be in the same shape ReadContent emits.
      private def self.normalize_version_path(value : String, name : String) : String
        path = value.strip.gsub('\\', '/')
        while path.starts_with?("./")
          path = path.lchop("./")
        end
        path = path.lstrip('/').rstrip('/')
        segments = path.split('/')
        if path.empty? || segments.any? { |seg| seg.empty? || seg == "." || seg == ".." }
          raise_versions_error("version #{name.inspect} has an invalid path #{value.inspect} — use a directory relative to content/, such as \"docs/#{name}\"")
        end
        path
      end

      private def self.raise_versions_error(message : String) : NoReturn
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: message,
          hint: "See https://hwaro.hahwul.com/features/versioned-docs/ for the [versions] reference.",
        )
      end
    end
  end
end
