# Doctor Service
#
# Diagnoses configuration, template, and structure issues in a Hwaro site.
# For content validation, use ContentValidator (hwaro tool validate).

require "json"
require "yaml"
require "toml"
require "crinja"
require "../models/config"
require "../utils/errors"
require "../utils/logger"
require "../content/processors/markdown"
require "../core/build/parallel"
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
          CheckSpec.new("languages (default_language resolves)",
            ["default-language-undefined"]),
          CheckSpec.new("markdown / pwa (valid enums)",
            ["markdown-math-engine-invalid", "pwa-cache-strategy-invalid"]),
          CheckSpec.new("deployment / related (refs resolve)",
            ["deployment-target-undefined", "related-taxonomy-undefined"]),
          CheckSpec.new("referenced files & dirs",
            ["config-path-missing", "config-dir-missing"]),
        ],
      ),
      CheckGroup.new(
        key: :templates,
        default_heading: "templates/",
        checks: [
          CheckSpec.new("required files (page.html, section.html)",
            ["template-dir-missing", "template-required-missing"]),
          CheckSpec.new("template syntax",
            ["template-syntax-error", "template-read-error"]),
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
      # Mirrors `MarkdownConfig#initialize` defaults — only katex/mathjax
      # render math at runtime; other strings load nothing.
      VALID_MATH_ENGINES = %w[katex mathjax]

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
        check_content_frontmatter(issues, config)
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
        # For dotted keys like "serve.headers", we also record the parent ("serve")
        # so that top-level container sections are not repeatedly re-added by doctor --fix.
        commented_sections = Set(String).new
        raw_text.each_line do |line|
          if match = line.match(/^\s*#\s*\[(?!\[)([^\]]+)\]/)
            dotted = match[1]
            commented_sections << dotted
            if dotted.includes?(".")
              parent = dotted.split(".")[0]
              commented_sections << parent
            end
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

      # Sections that are advanced/niche or low-value for most users.
      # These are now treated as opt-in by default (not auto-suggested in normal doctor,
      # and not added by plain --fix unless the user explicitly wants them).
      #
      # Goal: Reduce config bloat and the "you should add all these things" pressure.
      OPTIONAL_SECTIONS = Set{
        # Very specialized / rarely needed for most sites
        "pwa", "amp",
        # Advanced/optional image features
        "image_processing", "image_processing.lqip", "og.auto_image",
        # Power-user / deployment related
        "build", "deployment", "permalinks", "auto_includes",
        # Asset pipeline (many prefer manual or external bundlers)
        "assets",
        # Useful but not essential to nag about
        "related", "series", "pagination",
        # Navigation menus — many sites hardcode nav in the theme instead
        "menus",
        # Content authoring niceties
        "content.new",
        # Nice-to-have SEO / crawler files (most people can add manually if needed)
        "robots", "llms",
        # Dev server customization (only needed when reproducing specific headers)
        "serve",
      }

      # Broad full-text check to prevent appending a duplicate commented section.
      # Used as a final safety net in fix_config even after missing_config_sections
      # has already filtered the list.
      private def would_cause_duplicate_section?(text : String, key : String) : Bool
        lowered = text.downcase
        section = "[#{key.downcase}]"

        # Check for active section
        return true if lowered.includes?(section)

        # Check for common commented forms
        # "# [key]", "#[key]", "  #   [key]", etc.
        commented_variants = [
          "# #{section}",
          "##{section}",
          " # #{section}",
          "\t# #{section}",
        ]

        commented_variants.any? { |v| lowered.includes?(v) }
      end

      # A surgical edit `--fix` applied to an existing config value.
      # Distinct from "section appends" because it modifies the user's
      # real configuration rather than adding commented documentation.
      record ValueFix, field : String, before : String, after : String do
        include JSON::Serializable
      end

      # Outcome of `fix_config`. `dry_run = true` populates the same
      # fields without writing, so the CLI can show a preview.
      record FixSummary,
        sections_added : Array(String) = [] of String,
        value_fixes : Array(ValueFix) = [] of ValueFix,
        dry_run : Bool = false do
        include JSON::Serializable

        def empty? : Bool
          sections_added.empty? && value_fixes.empty?
        end
      end

      # Apply real fixes (Phase 1: value corrections like base_url trailing slash)
      # and optionally approve/add recommended config sections (Phase 2).
      #
      # - approve_sections: When true, doctor will add the recommended/optional
      #   config sections as commented documentation.
      # - When false (default with plain --fix), only real value fixes are performed.
      #
      # This separation makes --fix focused on corrections, while --approve / --full
      # controls bringing in the larger set of recommendations.
      def fix_config(approve_sections : Bool = false, dry_run : Bool = false) : FixSummary
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

        # Phase 1: surgical value edits. Operate on the raw text so we
        # preserve formatting, comments, and ordering — the parsed TOML
        # tree has no high-fidelity round-trip writer in stdlib.
        current_text = raw_text
        value_fixes = [] of ValueFix

        if applied = trim_base_url_trailing_slash(current_text)
          current_text = applied[:text]
          value_fixes << applied[:fix]
        end

        if applied = clamp_sitemap_priority(current_text)
          current_text = applied[:text]
          value_fixes << applied[:fix]
        end

        # Phase 2: section appends.
        missing = missing_config_sections
        snippets = [] of String
        added = [] of String

        missing.each do |key|
          # With the new --fix / --approve model:
          # - Plain --fix only performs real value corrections (Phase 1).
          # - Adding recommended/optional sections (Phase 2) only happens when
          #   approve_sections is true (i.e. user used --approve or --full).
          #
          # This is the key change to stop over-injection of dozens of commented sections.
          unless approve_sections
            next
          end

          # Extra safety net against duplication (from earlier work)
          if would_cause_duplicate_section?(current_text, key)
            next
          end

          if snippet = config_snippet_for(key)
            snippets << snippet
            added << key
          end
        end

        summary = FixSummary.new(sections_added: added, value_fixes: value_fixes, dry_run: dry_run)
        return summary if summary.empty?
        return summary if dry_run

        # Write atomically: compose the final file contents in a temp
        # file beside `config.toml`, then `File.rename` into place so a
        # mid-write interruption (SIGINT, disk full) can't leave a
        # partially-appended config behind.
        tmp_path = "#{@config_path}.hwaro-tmp"
        begin
          File.open(tmp_path, "w") do |f|
            f.print(current_text)
            f.print("\n") unless current_text.ends_with?("\n")
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

        summary
      end

      # Strip trailing slashes from a top-level `base_url = "..."` line.
      # Top-level only — anything past the first `[section]` header is
      # left alone. Returns nil when no edit is needed (no match, empty
      # value, or already slash-free) so the caller can skip emitting a
      # spurious ValueFix.
      private def trim_base_url_trailing_slash(text : String) : NamedTuple(text: String, fix: ValueFix)?
        lines = text.split('\n', remove_empty: false)
        lines.each_with_index do |line, idx|
          break if line =~ /^\s*\[/ # entered a section table; base_url is top-level only
          next unless m = line.match(/^([ \t]*)base_url([ \t]*=[ \t]*)"([^"]*)"(.*)$/)
          url = m[3]
          next if url.empty?
          next unless url.ends_with?("/")
          trimmed = url.rstrip('/')
          next if trimmed.empty? # avoid mangling oddities like base_url = "/"
          lines[idx] = "#{m[1]}base_url#{m[2]}\"#{trimmed}\"#{m[4]}"
          return {text: lines.join('\n'), fix: ValueFix.new("base_url", url, trimmed)}
        end
        nil
      end

      # Clamp `priority = N` under `[sitemap]` to [0.0, 1.0]. Walks the
      # file line-by-line so we only ever rewrite the priority that
      # belongs to the [sitemap] table — a top-level `priority = …` or
      # `[other_section] priority = …` is left intact.
      private def clamp_sitemap_priority(text : String) : NamedTuple(text: String, fix: ValueFix)?
        lines = text.split('\n', remove_empty: false)
        in_sitemap = false
        lines.each_with_index do |line, idx|
          if header = line.match(/^\s*\[([^\[\]]+)\]\s*$/)
            in_sitemap = (header[1] == "sitemap")
            next
          end
          next unless in_sitemap
          next unless m = line.match(/^([ \t]*)priority([ \t]*=[ \t]*)([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)(.*)$/)
          val = m[3].to_f?
          next unless val
          next if 0.0 <= val <= 1.0
          clamped = val.clamp(0.0, 1.0)
          # Render the clamped value with at least one fractional digit
          # so it stays a TOML float (mirrors how the scaffolded snippet
          # writes it: `priority = 0.5`).
          after = clamped == clamped.to_i ? "#{clamped.to_i}.0" : clamped.to_s
          lines[idx] = "#{m[1]}priority#{m[2]}#{after}#{m[4]}"
          return {text: lines.join('\n'), fix: ValueFix.new("sitemap.priority", m[3], after)}
        end
        nil
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
        # `config.base_url` is normalized (trailing slash stripped) on load, so
        # inspect the RAW config value for the trailing-slash advisory — the
        # build is already correct, but `--fix` still tidies the file.
        raw_base_url = config.raw["base_url"]?.try(&.as_s?)
        if config.base_url.empty?
          issues << Issue.new(id: "base-url-missing", level: :warning, category: "config", file: @config_path, message: "base_url is not set")
        elsif raw_base_url && raw_base_url.ends_with?("/")
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

        # default_language must resolve to a `[languages.<code>]` table.
        # Without this check a typo silently falls through to untranslated
        # content with broken hreflang tags and a feed that omits the
        # default locale.
        if !config.default_language.empty? && !config.languages.empty? && !config.languages.has_key?(config.default_language)
          known = config.languages.keys.sort!.join(", ")
          issues << Issue.new(id: "default-language-undefined", level: :warning, category: "config", file: @config_path,
            message: "default_language \"#{config.default_language}\" has no matching [languages.#{config.default_language}] block (defined: #{known})")
        end

        # markdown.math_engine only renders when set to a value the
        # build pipeline actually loads; other strings silently produce
        # no math. Skip when math is off — the field is a no-op there.
        if config.markdown.math && !VALID_MATH_ENGINES.includes?(config.markdown.math_engine)
          issues << Issue.new(id: "markdown-math-engine-invalid", level: :warning, category: "config", file: @config_path,
            message: "markdown.math_engine \"#{config.markdown.math_engine}\" is not supported (expected: #{VALID_MATH_ENGINES.join(", ")})")
        end

        # PWA cache_strategy is enforced at runtime via VALID_STRATEGIES.
        # `Models::Config.load` silently coerces an unknown value back
        # to "cache-first" (with a `Logger.warn` the user often misses
        # during build), so we read the user-typed value from the raw
        # TOML tree before that coercion kicks in.
        raw_pwa = config.raw["pwa"]?.try(&.as_h?)
        if raw_pwa && (raw_strategy = raw_pwa["cache_strategy"]?.try(&.as_s?))
          unless Models::PwaConfig::VALID_STRATEGIES.includes?(raw_strategy)
            issues << Issue.new(id: "pwa-cache-strategy-invalid", level: :warning, category: "config", file: @config_path,
              message: "pwa.cache_strategy \"#{raw_strategy}\" is not supported (expected: #{Models::PwaConfig::VALID_STRATEGIES.join(", ")})")
          end
        end

        # `[deployment].target` selects which `[[deployment.targets]]`
        # block `hwaro deploy` uses. Pointing at an undefined name
        # makes `deploy` fail at runtime with a "target not found"
        # error — catching it here surfaces the typo before the
        # operator runs the actual deploy.
        if (selected = config.deployment.target) && !selected.empty?
          unless config.deployment.targets.any? { |t| t.name == selected }
            known = config.deployment.targets.map(&.name).reject(&.empty?).sort!.join(", ")
            known_hint = known.empty? ? "no [[deployment.targets]] defined" : "defined: #{known}"
            issues << Issue.new(id: "deployment-target-undefined", level: :warning, category: "config", file: @config_path,
              message: "deployment.target \"#{selected}\" has no matching [[deployment.targets]] block (#{known_hint})")
          end
        end

        # `[related].taxonomies` references taxonomy names from
        # `[[taxonomies]]`. A typo silently produces zero related
        # posts on every page without any user-visible signal — the
        # feature just looks broken.
        if config.related.enabled
          known_taxonomies = config.taxonomies.map(&.name)
          config.related.taxonomies.each do |name|
            next if known_taxonomies.includes?(name)
            known_hint = known_taxonomies.empty? ? "no [[taxonomies]] defined" : "defined: #{known_taxonomies.sort!.join(", ")}"
            issues << Issue.new(id: "related-taxonomy-undefined", level: :warning, category: "config", file: @config_path,
              message: "[related] taxonomies references \"#{name}\" but no [[taxonomies]] block defines it (#{known_hint})")
          end
        end

        # `[[menus.<name>]]` entries may set `parent` to another entry's
        # `identifier` within the SAME menu (global or per-language). A typo
        # silently falls through to Content::Menus's "promoted to root"
        # fallback at build time with only a build-log warning — surface it
        # here so it's caught before build. Per-language menu sets fully
        # replace the global one (no per-language override ⇒ `menus` is
        # `nil`, inheriting the global set already checked), so each is
        # validated independently against its OWN identifiers.
        check_menu_parent_undefined(issues, "", config.menus)
        config.languages.keys.sort!.each do |code|
          lang_menus = config.languages[code].menus
          check_menu_parent_undefined(issues, code, lang_menus) if lang_menus
        end

        # Check for missing config sections
        check_missing_config_sections(issues)

        config
      end

      private def check_menu_parent_undefined(issues : Array(Issue), lang_code : String, menus : Hash(String, Array(Models::MenuItemConfig)))
        menus.each do |menu_name, items|
          identifiers = items.map(&.identifier).to_set
          scope = lang_code.empty? ? "[[menus.#{menu_name}]]" : "[[languages.#{lang_code}.menus.#{menu_name}]]"
          items.each do |item|
            parent = item.parent
            next if parent.nil? || parent.empty?
            next if identifiers.includes?(parent)
            issues << Issue.new(id: "menu-parent-undefined", level: :warning, category: "config", file: @config_path,
              message: "#{scope} entry \"#{item.name}\" has parent \"#{parent}\" but no entry in that menu declares identifier \"#{parent}\"")
          end
        end
      end

      private def check_missing_config_sections(issues : Array(Issue))
        missing = missing_config_sections
        return if missing.empty?

        missing.each do |key|
          # Niche/advanced sections are intentionally skipped by `--fix` in its
          # minimal mode (see `fix_config`), so flagging them here would tell
          # users to run a command that won't add them. Stay silent for those —
          # users opt in by manually configuring the section.
          next if OPTIONAL_SECTIONS.includes?(key)
          desc = KNOWN_CONFIG_SECTIONS[key]? || KNOWN_SUB_SECTIONS.find { |k, _| "#{k[0]}.#{k[1]}" == key }.try(&.last) || key
          issues << Issue.new(id: "missing-config-#{key}", level: :info, category: "config_missing", file: @config_path,
            message: "Optional section [#{key}] not present (#{desc}). Add it manually if needed, or use 'hwaro doctor --full' for recommendations.")
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

      # Template syntax check, delegated to the actual Crinja parser used
      # by the build pipeline. The previous regex-based approach
      # (counting `{% if %}` vs `{% endif %}` etc.) couldn't catch:
      #  - paired tags it didn't enumerate (autoescape/raw/with/filter/…)
      #  - reordered close-before-open mistakes that still balanced
      #  - end tags whose name didn't match the opener
      # By instantiating `Crinja::Template` with `run_parser: true` we
      # surface every syntax error the build itself will hit, with line
      # and column numbers when Crinja attaches them. We do NOT render —
      # parse errors are the only failure class we want to gate on here.
      #
      # Unknown tags like {% details %} or {% my_custom %} are tolerated
      # (they are almost always project-specific shortcodes demonstrated
      # inside docs templates). Real syntax errors still fail hard.
      private def check_template_syntax(file_path : String, issues : Array(Issue))
        content = File.read(file_path)

        begin
          Crinja::Template.new(content, env: template_parse_env, filename: file_path, run_parser: true)
        rescue ex : Crinja::TemplateSyntaxError | Crinja::TemplateError
          issues << Issue.new(
            id: "template-syntax-error",
            level: :error,
            category: "template",
            file: file_path,
            message: format_crinja_error(ex),
          )
        end
      rescue ex
        msg = ex.message.to_s
        # Custom shortcodes (e.g. {% details %}, {% gallery %}) used inside
        # template files for documentation/demo purposes are expected to be
        # unknown to the bare Crinja parser used by doctor. These are not
        # real template syntax errors — the project provides the shortcode
        # implementation at build time via templates/shortcodes/*.html.
        if msg.includes?("no tag with name") && msg.includes?("registered")
          return
        end

        issues << Issue.new(id: "template-read-error", level: :error, category: "template", file: file_path,
          message: "Failed to read template: #{ex.message}")
      end

      # Reusable Crinja env for parse-only checks. We never render, so
      # the env can be a default instance — loaders/extensions that the
      # production builder configures aren't needed to detect tag/syntax
      # mistakes.
      @template_parse_env : Crinja?

      private def template_parse_env : Crinja
        @template_parse_env ||= Crinja.new
      end

      private def format_crinja_error(ex : Crinja::Error) : String
        msg = (ex.message || ex.class.name).lines.first?.try(&.strip) || ex.class.name
        loc = ex.location_start
        loc ? "Template syntax error at line #{loc.line}, column #{loc.column}: #{msg}" : "Template syntax error: #{msg}"
      end

      # Recursively flag content directories that look like sections
      # but lack an `_index.md`. A directory is treated as a section
      # candidate when it contains at least one markdown file (anywhere
      # underneath it); directories that are pure attachment folders —
      # `images/`, `assets/`, etc. — are skipped automatically. Hidden
      # (`.`) and underscore-prefixed (`_`) directories are also skipped
      # so private/draft trees stay quiet. Issued at `:info` level so
      # CI doesn't gate on it.
      private def check_directory_structure(issues : Array(Issue))
        return unless Dir.exists?(@content_dir)
        walk_section_dirs(@content_dir, issues)
      end

      private def walk_section_dirs(root : String, issues : Array(Issue))
        Dir.each_child(root) do |entry|
          next if entry.starts_with?(".") || entry.starts_with?("_")
          child = File.join(root, entry)
          next unless File.directory?(child)
          next unless dir_contains_markdown?(child)

          has_index = File.exists?(File.join(child, "_index.md")) ||
                      File.exists?(File.join(child, "_index.markdown"))

          # Many documentation sites use page bundles (index.md directly in
          # a folder) for individual guides rather than true sections with
          # _index.md. Only warn when the folder actually contains other
          # markdown content beneath it (suggesting it intends to be a section).
          has_nested_content = dir_has_markdown_in_subdirs?(child)

          if !has_index && has_nested_content
            relative = child.lchop(@content_dir).lchop(File::SEPARATOR)
            issues << Issue.new(id: "structure-missing-index", level: :info, category: "structure", file: child,
              message: "Section directory missing _index.md: #{relative}/")
          end

          walk_section_dirs(child, issues)
        end
      end

      # Quick "is there content under here?" check used to filter out
      # plain attachment directories. Returns on the first hit so we
      # don't enumerate the entire subtree.
      private def dir_contains_markdown?(dir : String) : Bool
        Dir.glob(File.join(dir, "**", "*.{md,markdown}")) { |_| return true }
        false
      end

      # Returns true if the directory contains markdown files anywhere
      # besides a direct top-level index.md / index.markdown (page bundle).
      # This helps avoid noisy warnings on documentation-style sites that
      # organize guides as page bundles rather than true sections.
      private def dir_has_markdown_in_subdirs?(dir : String) : Bool
        # Any markdown deeper than direct children of this dir?
        Dir.glob(File.join(dir, "*/*.{md,markdown}")) { |_| return true }

        # Any direct markdown file that is *not* an index page?
        Dir.glob(File.join(dir, "*.{md,markdown}")) do |path|
          b = File.basename(path)
          return true unless b == "index.md" || b == "index.markdown"
        end

        false
      end

      # Parse every markdown file's front matter so doctor flags what
      # would otherwise only surface at `hwaro build` time. Reuses the
      # canonical `Processor::Markdown.parse` so the check stays in
      # sync with the parser used by the build pipeline — any
      # front-matter shape the builder rejects as `HWARO_E_CONTENT`
      # appears here as an `:error` issue.
      #
      # Sites in the wild can have thousands of markdown files; this
      # used to scan them serially with a fresh `File.read` +
      # `Processor::Markdown.parse` per entry. Routed through the
      # existing `ParallelHelper.map` which already powers the build
      # pipeline so I/O overlaps and (on `-Dpreview_mt`) parsing
      # actually runs concurrently across cores. Each worker returns
      # the file's issue list (size 0 or 1) so we never share a
      # mutable issues array across fibers.
      private def check_content_frontmatter(issues : Array(Issue), config : Models::Config?)
        return unless Dir.exists?(@content_dir)

        files = [] of String
        Dir.glob(File.join(@content_dir, "**", "*.{md,markdown}")) do |path|
          # Skip things that aren't regular files (symlink to nowhere,
          # directory matching the glob, etc.).
          files << path if File.file?(path)
        end
        return if files.empty?

        # Only front matter `menus`/`menu` names get cross-checked against
        # `config.menus` — and only when the config declares at least one
        # menu at all. A site with NO `[[menus.*]]` anywhere is legitimately
        # using front-matter-only, fully ad-hoc menus (Content::Menus builds
        # them regardless of whether config declares that name), so nagging
        # about "undeclared" menus there would be a false positive on a
        # supported, legal setup.
        known_menu_names = config.try(&.menus.keys) || [] of String

        per_file = Hwaro::Core::Build::ParallelHelper.map(files) do |path|
          scan_content_file_for_frontmatter(path, known_menu_names)
        end
        per_file.each { |arr| arr.each { |i| issues << i } }
      end

      # Pure function: read + parse one markdown file, return any issue
      # produced as a small array. Fiber-safe because it touches no
      # shared state. `known_menu_names` is empty when config declares no
      # `[[menus.*]]` at all — see `check_content_frontmatter`.
      private def scan_content_file_for_frontmatter(path : String, known_menu_names : Array(String)) : Array(Issue)
        raw = begin
          File.read(path)
        rescue ex : IO::Error | File::Error
          return [Issue.new(id: "content-read-error", level: :error, category: "content", file: path,
            message: "Failed to read content file: #{ex.message}")]
        end

        data = begin
          Processor::Markdown.parse(raw, path)
        rescue ex : Hwaro::HwaroError
          first_line = (ex.message || "Invalid front matter").lines.first?.to_s.strip
          return [Issue.new(id: "content-frontmatter-invalid", level: :error, category: "content", file: path,
            message: first_line.empty? ? "Invalid front matter" : first_line)]
        end

        issues = [] of Issue
        unless known_menu_names.empty?
          data[:menus].each_key do |menu_name|
            next if known_menu_names.includes?(menu_name)
            issues << Issue.new(id: "menu-undeclared", level: :warning, category: "content", file: path,
              message: "Front matter registers menu \"#{menu_name}\" but no [[menus.#{menu_name}]] is declared in config.toml (defined: #{known_menu_names.sort.join(", ")})")
          end
        end
        issues
      end

      # Validate that path-shaped fields in `config.toml` actually point at
      # files (or directories) that exist on disk. The build pipeline
      # doesn't fail when a referenced asset is missing — it just emits a
      # 404 in production — so a typoed `[og] default_image` would
      # otherwise only surface in the wild. Each missing path becomes a
      # `[warn]` issue under `config-path-missing` (file) or
      # `config-dir-missing` (directory), both suppressible via
      # `[doctor] ignore = [...]`. See
      # https://github.com/hahwul/hwaro/issues/489.
      # Emit a "<kind> not found" config warning for `value` unless it's blank
      # or `resolver` reports it resolves. `id`/`kind` are passed independently
      # so route checks can keep the "config-path-missing"/"file" pairing.
      private def emit_missing(issues : Array(Issue), label : String, value : String, *, resolver : String -> Bool, id : String, kind : String)
        stripped = strip_query_hash(value)
        return if stripped.empty?
        return if resolver.call(stripped)
        issues << Issue.new(
          id: id,
          level: :warning,
          category: "config",
          file: @config_path,
          message: "#{label}: #{value} — #{kind} not found",
        )
      end

      private def check_referenced_paths(issues : Array(Issue), config : Models::Config)
        emit_file = ->(label : String, value : String) do
          emit_missing(issues, label, value, resolver: ->(s : String) { path_resolves?(s) }, id: "config-path-missing", kind: "file")
        end

        emit_dir = ->(label : String, value : String) do
          emit_missing(issues, label, value, resolver: ->(s : String) { dir_resolves?(s) }, id: "config-dir-missing", kind: "directory")
        end

        # PWA offline_page / precache_urls are routes, not just static files:
        # `/about/` builds to `public/about/index.html` from `content/about.md`,
        # so resolving them against `static/` alone yields false "file not
        # found" warnings. Use a route-aware check that also accepts a matching
        # content source or a built output page.
        emit_route = ->(label : String, value : String) do
          emit_missing(issues, label, value, resolver: ->(s : String) { path_resolves?(s) || route_resolves?(s) }, id: "config-path-missing", kind: "file")
        end

        config.og.default_image.try { |v| emit_file.call("[og] default_image", v) }
        config.og.auto_image.logo.try { |v| emit_file.call("[og.auto_image] logo", v) }
        config.og.auto_image.background_image.try { |v| emit_file.call("[og.auto_image] background_image", v) }
        config.pwa.offline_page.try { |v| emit_route.call("[pwa] offline_page", v) }
        config.pwa.precache_urls.each_with_index do |url, idx|
          # Only validate site-internal routes; external URLs aren't ours.
          next if url.starts_with?("http://") || url.starts_with?("https://")
          emit_route.call("[pwa] precache_urls[#{idx}]", url)
        end
        config.pwa.icons.each_with_index do |icon, idx|
          emit_file.call("[pwa] icons[#{idx}]", icon)
        end

        # auto_includes.dirs are directory paths the build globs at runtime;
        # a missing entry produces no link tags and silently ships an
        # incomplete page.
        if config.auto_includes.enabled
          config.auto_includes.dirs.each_with_index do |dir, idx|
            emit_dir.call("[auto_includes] dirs[#{idx}]", dir)
          end
        end

        # assets pipeline only matters when enabled; bundle inputs live
        # under assets.source_dir.
        if config.assets.enabled
          source_dir = config.assets.source_dir
          emit_dir.call("[assets] source_dir", source_dir) unless source_dir.empty?

          config.assets.bundles.each_with_index do |bundle, b_idx|
            label_prefix = bundle.name.empty? ? "[[assets.bundles]][#{b_idx}]" : "[[assets.bundles]] #{bundle.name}"
            bundle.files.each_with_index do |file, f_idx|
              # Bundle file paths are resolved against assets.source_dir
              # at build time, so check there directly rather than going
              # through path_resolves?'s static/ heuristic.
              candidate = source_dir.empty? ? file : File.join(source_dir, file)
              next if File.exists?(candidate)
              issues << Issue.new(
                id: "config-path-missing",
                level: :warning,
                category: "config",
                file: @config_path,
                message: "#{label_prefix} files[#{f_idx}]: #{file} — file not found under #{source_dir.empty? ? "(repo root)" : source_dir}/",
              )
            end
          end
        end
      end

      # Strip query string and fragment off a config-style path so values
      # like `/images/og.png?v=2` or `/og.png#anchor` resolve against the
      # underlying file rather than failing.
      private def strip_query_hash(path : String) : String
        path.split('?', 2).first.split('#', 2).first
      end

      # Decide whether a config-shaped path string points at an existing
      # file. Authors write these in three flavors:
      # - URL-style (`/images/og.png`) → resolved against `static/`
      # - `static/foo.png` → already rooted under static/ (use as-is)
      # - `content/foo.md` or any other repo-relative path → use as-is
      private def path_resolves?(path : String) : Bool
        candidates(path).any? { |c| File.exists?(c) }
      end

      # Same lookup strategy as `path_resolves?`, but for directories.
      private def dir_resolves?(path : String) : Bool
        candidates(path).any? { |c| Dir.exists?(c) }
      end

      # Decide whether a route-shaped value (e.g. `/about/`, `/offline.html`)
      # corresponds to a page the site builds, even when no matching static
      # file exists. A route is considered valid when:
      #   - a content source exists (`content/about.md` or
      #     `content/about/index.md` for `/about/`), or
      #   - the built output page exists (`public/about/index.html`).
      # This keeps doctor from flagging valid routes as "file not found" while
      # still catching genuinely-missing pages.
      private def route_resolves?(path : String) : Bool
        # Normalize to a slug: drop a leading slash, strip a trailing slash,
        # and remove a trailing `index.html` so `/about/` and
        # `/about/index.html` resolve the same way.
        slug = path.lchop("/")
        slug = slug.rchop("index.html") if slug.ends_with?("index.html")
        slug = slug.rstrip("/")

        # Content sources that would render to this route.
        content_candidates = if slug.empty?
                               ["_index.md", "_index.markdown", "index.md", "index.markdown"]
                             else
                               [
                                 "#{slug}.md",
                                 "#{slug}.markdown",
                                 File.join(slug, "index.md"),
                                 File.join(slug, "index.markdown"),
                                 File.join(slug, "_index.md"),
                                 File.join(slug, "_index.markdown"),
                               ]
                             end
        return true if content_candidates.any? { |c| File.exists?(File.join(@content_dir, c)) }

        # A prior build's output (conventionally `public/`): a pretty route lands
        # at `<slug>/index.html`, while an explicit file (an `.html` alias or a
        # pipeline-built asset such as `/css/app.css`) lands at the path itself.
        if Dir.exists?("public")
          return true if File.exists?(File.join("public", slug, "index.html"))
          return true if File.exists?(File.join("public", path.lchop("/")))
        end

        # Otherwise it's a pretty route or listing (taxonomy/section page)
        # produced at build time — doctor runs BEFORE the build (often on a clean
        # checkout) so it can't see these. Treat route-style values as valid
        # rather than false-positive; the build-time PWA precache validation is
        # authoritative for genuinely-missing entries.
        path.ends_with?("/") || File.extname(slug).empty?
      end

      private def candidates(path : String) : Array(String)
        result = [path]
        if path.starts_with?("/")
          result << File.join(@static_dir, path.lchop("/"))
        elsif !path.starts_with?("#{@static_dir}#{File::SEPARATOR}") && !path.starts_with?("#{@content_dir}#{File::SEPARATOR}")
          result << File.join(@static_dir, path)
        end
        result
      end
    end
  end
end
