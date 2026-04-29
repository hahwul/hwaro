# Doctor Service
#
# Diagnoses configuration, template, and structure issues in a Hwaro site.
# For content validation, use ContentValidator (hwaro tool validate).

require "json"
require "yaml"
require "toml"
require "../models/config"
require "../utils/errors"
require "../utils/logger"
require "../content/processors/markdown"
require "./config_snippets"

module Hwaro
  module Services
    # Represents a single diagnostic issue found by the doctor
    record Issue, id : String, level : Symbol, category : String, file : String?, message : String do
      include JSON::Serializable

      @[JSON::Field(converter: Hwaro::Services::Issue::SymbolConverter)]
      getter level : Symbol

      # Issue is JSON-serialized for `hwaro doctor --json`. We don't currently
      # consume that JSON back into Issue values, but the converter still needs
      # a correct `from_json` so a future round-trip (or third-party tooling
      # that reuses the schema) doesn't blow up. The previous implementation
      # returned `String` from a `Symbol`-typed method.
      module SymbolConverter
        def self.to_json(value : Symbol, json : JSON::Builder)
          json.string(value.to_s)
        end

        def self.from_json(pull : JSON::PullParser) : Symbol
          case raw = pull.read_string
          when "error"   then :error
          when "warning" then :warning
          when "info"    then :info
          else
            raise JSON::ParseException.new("Unknown issue level: #{raw.inspect}", *pull.location)
          end
        end
      end
    end

    # A named diagnostic check: a human label paired with the set of
    # issue IDs that, when present, count against this check. The CLI
    # uses this to render inline ✓/⚠/✗ lines in human output.
    record CheckSpec, label : String, issue_ids : Array(String)

    # A logical group of checks, surfaced under one heading in the CLI.
    # `:config` is rendered with the runtime config_path; other keys use
    # `default_heading` verbatim.
    record CheckGroup, key : Symbol, default_heading : String, checks : Array(CheckSpec)

    # Single source of truth for the inline status lines emitted by
    # `hwaro doctor`. Anything that adds a new diagnostic to
    # `Services::Doctor` should also list its issue id(s) here so the
    # check shows up in human output. The previous duplication —
    # one list in this service and another in the CLI command — is
    # gone, so updating one place is enough.
    CHECK_GROUPS = [
      CheckGroup.new(
        key: :config,
        default_heading: "config.toml",
        checks: [
          CheckSpec.new("file present & parseable",
            ["config-not-found", "config-parse-error"]),
          CheckSpec.new("base_url, title",
            ["base-url-missing", "base-url-trailing-slash", "title-default"]),
          CheckSpec.new("sitemap (changefreq, priority)",
            ["sitemap-changefreq-invalid", "sitemap-priority-range"]),
          CheckSpec.new("taxonomies (duplicates)",
            ["taxonomy-duplicate", "language-duplicate"]),
          CheckSpec.new("search (format)",
            ["search-format-invalid"]),
        ],
      ),
      CheckGroup.new(
        key: :templates,
        default_heading: "templates/",
        checks: [
          CheckSpec.new("required files (page.html, section.html)",
            ["template-dir-missing", "template-required-missing"]),
          CheckSpec.new("template syntax",
            ["template-unclosed-block", "template-mismatched-vars", "template-read-error"]),
        ],
      ),
      CheckGroup.new(
        key: :content,
        default_heading: "content/",
        checks: [
          CheckSpec.new("front matter (TOML/YAML parse)",
            ["content-frontmatter-invalid", "content-read-error"]),
        ],
      ),
    ]

    class Doctor
      VALID_CHANGEFREQS    = %w[always hourly daily weekly monthly yearly never]
      VALID_SEARCH_FORMATS = %w[fuse_json fuse_javascript elasticlunr_json elasticlunr_javascript]

      # Delegate to ConfigSnippets for the single source of truth
      KNOWN_CONFIG_SECTIONS = ConfigSnippets::KNOWN_SECTIONS
      KNOWN_SUB_SECTIONS    = ConfigSnippets::KNOWN_SUB_SECTIONS

      @content_dir : String
      @config_path : String
      @templates_dir : String
      @static_dir : String

      def initialize(@content_dir : String = "content", @config_path : String = "config.toml", @templates_dir : String = "templates", @static_dir : String = "static")
      end

      def run : Array(Issue)
        issues = [] of Issue
        config = check_config(issues)
        check_templates(issues)
        check_directory_structure(issues)
        check_content_frontmatter(issues)
        check_referenced_paths(issues, config) if config
        ignore = config.try(&.doctor.ignore) || [] of String
        # `[doctor].ignore` exists to silence advisory noise. We refuse to
        # silence build-blocking errors here so a stray entry can't disable
        # CI gating — the `:error` level is reserved for issues that will
        # later fail `hwaro build` regardless.
        issues.reject { |i| i.level != :error && ignore.includes?(i.id) }
      end

      # Returns the list of config section keys missing from the user's config.toml.
      # On I/O or TOML parse failure, returns an empty array — those paths are
      # already reported by `check_config` as classified issues, so silent-empty
      # here lets the main run loop carry on without double-reporting. Callers
      # that need a clearer signal (e.g. `fix_config`) should probe the file
      # directly via `readable_config_toml` / `parse_config_toml`.
      def missing_config_sections : Array(String)
        raw_text = readable_config_toml
        return [] of String unless raw_text

        raw = parse_config_toml(raw_text)
        return [] of String unless raw

        # Collect commented section headers (e.g. "# [pwa]", "# [og.auto_image]")
        commented_sections = Set(String).new
        raw_text.each_line do |line|
          if match = line.match(/^\s*#\s*\[(?!\[)([^\]]+)\]/)
            commented_sections << match[1]
          end
        end

        missing = [] of String

        KNOWN_CONFIG_SECTIONS.each_key do |key|
          unless raw.has_key?(key) || commented_sections.includes?(key)
            missing << key
          end
        end

        # Check sub-sections (only when parent section exists)
        KNOWN_SUB_SECTIONS.each_key do |parent, child|
          sub_key = "#{parent}.#{child}"
          if parent_hash = raw[parent]?.try(&.as_h?)
            unless parent_hash.has_key?(child) || commented_sections.includes?(sub_key)
              missing << sub_key
            end
          end
          # If parent doesn't exist at all, don't report sub-section
        end

        missing
      end

      # Sections that are advanced/niche — skipped when minimal: true
      OPTIONAL_SECTIONS = Set{"pwa", "amp", "assets", "deployment", "image_processing", "og.auto_image", "image_processing.lqip", "build", "permalinks", "auto_includes"}

      # Append missing config sections to config.toml.
      # When minimal is true, skip advanced optional sections (pwa, amp, assets, etc.)
      # Returns the list of sections that were added.
      #
      # Raises `HwaroError` when the config cannot be read or parsed so
      # `--fix` refuses to append to a broken file (prior behaviour was
      # to silently say "Config is up to date"), and when the atomic
      # write fails (temp file + rename; see below).
      def fix_config(minimal : Bool = false) : Array(String)
        unless File.exists?(@config_path)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Config file not found: #{@config_path}",
            hint: "Run 'hwaro init' to scaffold a project, or cd into a directory containing config.toml.",
          )
        end

        raw_text = readable_config_toml
        unless raw_text
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: "Cannot read #{@config_path}",
            hint: "Check file permissions and retry.",
          )
        end

        raw = parse_config_toml(raw_text)
        unless raw
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "#{@config_path} has TOML parse errors; refusing to --fix.",
            hint: "Fix the TOML syntax first (run 'hwaro doctor' to see the parse error), then re-run 'hwaro doctor --fix'.",
          )
        end

        missing = missing_config_sections
        return [] of String if missing.empty?

        snippets = [] of String
        added = [] of String

        missing.each do |key|
          next if minimal && OPTIONAL_SECTIONS.includes?(key)
          if snippet = config_snippet_for(key)
            snippets << snippet
            added << key
          end
        end

        return added if snippets.empty?

        # Write atomically: compose the final file contents in a temp
        # file beside `config.toml`, then `File.rename` into place so a
        # mid-write interruption (SIGINT, disk full) can't leave a
        # partially-appended config behind.
        tmp_path = "#{@config_path}.hwaro-tmp"
        begin
          File.open(tmp_path, "w") do |f|
            f.print(raw_text)
            f.print("\n") unless raw_text.ends_with?("\n")
            snippets.each { |s| f.print(s) }
          end
          File.rename(tmp_path, @config_path)
        rescue ex : IO::Error | File::Error
          # Clean the half-written temp file so re-running isn't blocked.
          File.delete(tmp_path) if File.exists?(tmp_path)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: "Failed to update #{@config_path}: #{ex.message}",
            hint: "Check file permissions and available disk space, then retry.",
          )
        end

        added
      end

      # Read `config.toml` as text. Returns nil on I/O failure
      # (permission denied, missing file, etc.) so callers can branch
      # without nesting another begin/rescue.
      private def readable_config_toml : String?
        return unless File.exists?(@config_path)
        File.read(@config_path)
      rescue ex : IO::Error | File::Error
        Logger.debug "Doctor: cannot read #{@config_path}: #{ex.message}"
        nil
      end

      # Parse the raw `config.toml` text. Returns nil on TOML parse
      # failure; callers already downstream of `check_config` have seen
      # the classified error so silent-nil here avoids double-reporting.
      # The rescue is narrowed to `TOML::ParseException` so any other
      # unexpected error propagates rather than being silently swallowed.
      private def parse_config_toml(raw_text : String) : TOML::Table?
        TOML.parse(raw_text)
      rescue ex : TOML::ParseException
        Logger.debug "Doctor: TOML parse error in #{@config_path}: #{ex.message}"
        nil
      end

      # Get the TOML snippet for a missing config section
      private def config_snippet_for(key : String) : String?
        ConfigSnippets.doctor_snippet_for(key)
      end

      private def check_config(issues : Array(Issue)) : Models::Config?
        unless File.exists?(@config_path)
          # Missing config.toml blocks every build path (`Config.load`
          # raises `HWARO_E_CONFIG`), so surface it as an error — not an
          # advisory — so CI can gate on `doctor`'s exit code.
          issues << Issue.new(id: "config-not-found", level: :error, category: "config", file: @config_path, message: "Config file not found")
          return
        end

        begin
          config = Models::Config.load(@config_path)
        rescue ex
          issues << Issue.new(id: "config-parse-error", level: :error, category: "config", file: @config_path, message: "Failed to parse config: #{ex.message}")
          return
        end

        # base_url check
        #
        # Scheme/host validity is enforced at `Models::Config.load` time via
        # `validate_base_url!`, so any base_url reaching this point is either
        # empty or a well-formed http(s) URL. We only cover the remaining
        # style advisories here.
        if config.base_url.empty?
          issues << Issue.new(id: "base-url-missing", level: :warning, category: "config", file: @config_path, message: "base_url is not set")
        elsif config.base_url.ends_with?("/")
          issues << Issue.new(id: "base-url-trailing-slash", level: :warning, category: "config", file: @config_path,
            message: "base_url should not end with a trailing slash")
        end

        # title check
        if config.title == "Hwaro Site"
          issues << Issue.new(id: "title-default", level: :warning, category: "config", file: @config_path, message: "title is still the default value \"Hwaro Site\"")
        end

        # sitemap changefreq validity
        unless VALID_CHANGEFREQS.includes?(config.sitemap.changefreq)
          issues << Issue.new(id: "sitemap-changefreq-invalid", level: :warning, category: "config", file: @config_path,
            message: "sitemap.changefreq \"#{config.sitemap.changefreq}\" is not valid (expected: #{VALID_CHANGEFREQS.join(", ")})")
        end

        # sitemap priority range
        unless 0.0 <= config.sitemap.priority <= 1.0
          issues << Issue.new(id: "sitemap-priority-range", level: :warning, category: "config", file: @config_path,
            message: "sitemap.priority #{config.sitemap.priority} is out of range (expected: 0.0–1.0)")
        end

        # taxonomy name duplicates
        taxonomy_names = config.taxonomies.map(&.name)
        duplicates = taxonomy_names.tally.select { |_, count| count > 1 }.keys
        duplicates.each do |name|
          issues << Issue.new(id: "taxonomy-duplicate", level: :warning, category: "config", file: @config_path,
            message: "Duplicate taxonomy name: \"#{name}\"")
        end

        # search format validity
        if config.search.enabled && !VALID_SEARCH_FORMATS.includes?(config.search.format)
          issues << Issue.new(id: "search-format-invalid", level: :warning, category: "config", file: @config_path,
            message: "search.format \"#{config.search.format}\" is not supported (expected: #{VALID_SEARCH_FORMATS.join(", ")})")
        end

        # duplicate language codes
        lang_codes = config.languages.keys
        lang_duplicates = lang_codes.tally.select { |_, count| count > 1 }.keys
        lang_duplicates.each do |code|
          issues << Issue.new(id: "language-duplicate", level: :warning, category: "config", file: @config_path,
            message: "Duplicate language code: \"#{code}\"")
        end

        # Check for missing config sections
        check_missing_config_sections(issues)

        config
      end

      private def check_missing_config_sections(issues : Array(Issue))
        missing = missing_config_sections
        return if missing.empty?

        missing.each do |key|
          desc = KNOWN_CONFIG_SECTIONS[key]? || KNOWN_SUB_SECTIONS.find { |k, _| "#{k[0]}.#{k[1]}" == key }.try(&.last) || key
          issues << Issue.new(id: "missing-config-#{key}", level: :info, category: "config_missing", file: @config_path,
            message: "Missing config section [#{key}] (#{desc}) — run 'hwaro doctor --fix' to add it")
        end
      end

      # Check templates directory for required files.
      #
      # All template-level problems here are build-blocking — Crinja
      # refuses to render if templates are missing or have syntax
      # errors — so they're emitted at `:error` level so CI gates on
      # `doctor`'s exit code catch them before `hwaro build` runs.
      private def check_templates(issues : Array(Issue))
        unless Dir.exists?(@templates_dir)
          issues << Issue.new(id: "template-dir-missing", level: :error, category: "template", file: nil,
            message: "Templates directory not found: #{@templates_dir}")
          return
        end

        %w[page.html section.html].each do |required|
          path = File.join(@templates_dir, required)
          unless File.exists?(path)
            issues << Issue.new(id: "template-required-missing", level: :error, category: "template", file: path,
              message: "Required template file missing: #{required}")
          end
        end

        # Check template files for basic syntax errors
        Dir.glob(File.join(@templates_dir, "**", "*.html")) do |tpl_path|
          check_template_syntax(tpl_path, issues)
        end
      end

      # Basic template syntax check — unclosed tags.
      # Unclosed tags raise `HWARO_E_TEMPLATE` during render, so flag
      # them at :error level rather than :warning.
      private def check_template_syntax(file_path : String, issues : Array(Issue))
        content = File.read(file_path)

        # Strip Jinja comments {# ... #} and HTML comments before counting,
        # to avoid false positives from commented-out template code
        stripped = content.gsub(/\{#.*?#\}/m, "").gsub(/<!--.*?-->/m, "")

        # Check for unclosed block tags
        opens = stripped.scan(/\{%[-\s]*\b(if|for|block|macro)\b/).size
        closes = stripped.scan(/\{%[-\s]*\bend(if|for|block|macro)\b/).size
        if opens != closes
          issues << Issue.new(id: "template-unclosed-block", level: :error, category: "template", file: file_path,
            message: "Possible unclosed template block tag (#{opens} opened, #{closes} closed)")
        end

        # Check for unclosed variable tags
        open_vars = stripped.scan(/\{\{/).size
        close_vars = stripped.scan(/\}\}/).size
        if open_vars != close_vars
          issues << Issue.new(id: "template-mismatched-vars", level: :error, category: "template", file: file_path,
            message: "Mismatched {{ }} variable tags (#{open_vars} opened, #{close_vars} closed)")
        end
      rescue ex
        issues << Issue.new(id: "template-read-error", level: :error, category: "template", file: file_path,
          message: "Failed to read template: #{ex.message}")
      end

      # Check directory structure — sections should have _index.md
      private def check_directory_structure(issues : Array(Issue))
        return unless Dir.exists?(@content_dir)

        Dir.each_child(@content_dir) do |entry|
          child = File.join(@content_dir, entry)
          next unless File.directory?(child)
          # Skip hidden directories
          next if entry.starts_with?(".")

          has_index = File.exists?(File.join(child, "_index.md")) ||
                      File.exists?(File.join(child, "_index.markdown"))
          unless has_index
            issues << Issue.new(id: "structure-missing-index", level: :info, category: "structure", file: child,
              message: "Section directory missing _index.md: #{entry}/")
          end
        end
      end

      # Parse every markdown file's front matter so doctor flags what
      # would otherwise only surface at `hwaro build` time. Reuses the
      # canonical `Processor::Markdown.parse` so the check stays in
      # sync with the parser used by the build pipeline — any
      # front-matter shape the builder rejects as `HWARO_E_CONTENT`
      # appears here as an `:error` issue.
      private def check_content_frontmatter(issues : Array(Issue))
        return unless Dir.exists?(@content_dir)

        Dir.glob(File.join(@content_dir, "**", "*.{md,markdown}")) do |path|
          # Skip things that aren't regular files (symlink to nowhere,
          # directory matching the glob, etc.).
          next unless File.file?(path)

          raw = begin
            File.read(path)
          rescue ex : IO::Error | File::Error
            issues << Issue.new(id: "content-read-error", level: :error, category: "content", file: path,
              message: "Failed to read content file: #{ex.message}")
            next
          end

          begin
            Processor::Markdown.parse(raw, path)
          rescue ex : Hwaro::HwaroError
            first_line = (ex.message || "Invalid front matter").lines.first?.to_s.strip
            issues << Issue.new(id: "content-frontmatter-invalid", level: :error, category: "content", file: path,
              message: first_line.empty? ? "Invalid front matter" : first_line)
          end
        end
      end

      # Validate that path-shaped fields in `config.toml` actually point at
      # files that exist on disk. The build pipeline doesn't fail when a
      # referenced asset is missing — it just emits a 404 in production —
      # so a typoed `[og] default_image` would otherwise only surface in
      # the wild. Each missing path becomes a `[warn]` issue under the
      # `config-path-missing` id (suppressible via `[doctor] ignore = [...]`).
      # See https://github.com/hahwul/hwaro/issues/489.
      private def check_referenced_paths(issues : Array(Issue), config : Models::Config)
        emit = ->(label : String, value : String) do
          return if value.empty?
          return if path_resolves?(value)
          issues << Issue.new(
            id: "config-path-missing",
            level: :warning,
            category: "config",
            file: @config_path,
            message: "#{label}: #{value} — file not found",
          )
        end

        config.og.default_image.try { |v| emit.call("[og] default_image", v) }
        config.og.auto_image.logo.try { |v| emit.call("[og.auto_image] logo", v) }
        config.og.auto_image.background_image.try { |v| emit.call("[og.auto_image] background_image", v) }
        config.pwa.offline_page.try { |v| emit.call("[pwa] offline_page", v) }
        config.pwa.icons.each_with_index do |icon, idx|
          emit.call("[pwa] icons[#{idx}]", icon)
        end
      end

      # Decide whether a config-shaped path string points at an existing
      # file. Authors write these in three flavors:
      # - URL-style (`/images/og.png`) → resolved against `static/`
      # - `static/foo.png` → already rooted under static/ (use as-is)
      # - `content/foo.md` or any other repo-relative path → use as-is
      private def path_resolves?(path : String) : Bool
        candidates = [path]
        if path.starts_with?("/")
          candidates << File.join(@static_dir, path.lchop("/"))
        elsif !path.starts_with?("#{@static_dir}#{File::SEPARATOR}") && !path.starts_with?("#{@content_dir}#{File::SEPARATOR}")
          candidates << File.join(@static_dir, path)
        end
        candidates.any? { |c| File.exists?(c) }
      end
    end
  end
end
