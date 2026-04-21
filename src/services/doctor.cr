# Doctor Service
#
# Diagnoses configuration, template, and structure issues in a Hwaro site.
# For content validation, use ContentValidator (hwaro tool validate).

require "json"
require "yaml"
require "toml"
require "../models/config"
require "../utils/logger"
require "./config_snippets"

module Hwaro
  module Services
    # Represents a single diagnostic issue found by the doctor
    record Issue, id : String, level : Symbol, category : String, file : String?, message : String do
      include JSON::Serializable

      @[JSON::Field(converter: Hwaro::Services::Issue::SymbolConverter)]
      getter level : Symbol

      module SymbolConverter
        def self.to_json(value : Symbol, json : JSON::Builder)
          json.string(value.to_s)
        end

        def self.from_json(pull : JSON::PullParser) : Symbol
          pull.read_string.to_s
        end
      end
    end

    class Doctor
      VALID_CHANGEFREQS    = %w[always hourly daily weekly monthly yearly never]
      VALID_SEARCH_FORMATS = %w[fuse_json fuse_javascript elasticlunr_json elasticlunr_javascript]

      # Delegate to ConfigSnippets for the single source of truth
      KNOWN_CONFIG_SECTIONS = ConfigSnippets::KNOWN_SECTIONS
      KNOWN_SUB_SECTIONS    = ConfigSnippets::KNOWN_SUB_SECTIONS

      @content_dir : String
      @config_path : String
      @templates_dir : String

      def initialize(@content_dir : String = "content", @config_path : String = "config.toml", @templates_dir : String = "templates")
      end

      def run : Array(Issue)
        issues = [] of Issue
        config = check_config(issues)
        check_templates(issues)
        check_directory_structure(issues)
        ignore = config.try(&.doctor.ignore) || [] of String
        issues.reject { |i| ignore.includes?(i.id) }
      end

      # Returns the list of config section keys missing from the user's config.toml
      def missing_config_sections : Array(String)
        return [] of String unless File.exists?(@config_path)

        raw_text = begin
          File.read(@config_path)
        rescue ex : IO::Error | File::Error
          Logger.debug "Doctor: cannot read #{@config_path}: #{ex.message}"
          return [] of String
        end

        begin
          raw = TOML.parse(raw_text)
        rescue
          return [] of String
        end

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
      def fix_config(minimal : Bool = false) : Array(String)
        return [] of String unless File.exists?(@config_path)

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

        unless snippets.empty?
          # Ensure existing file ends with a newline before appending
          existing = File.read(@config_path)
          File.open(@config_path, "a") do |f|
            f.print("\n") unless existing.ends_with?("\n")
            snippets.each { |s| f.print(s) }
          end
        end

        added
      end

      # Get the TOML snippet for a missing config section
      private def config_snippet_for(key : String) : String?
        ConfigSnippets.doctor_snippet_for(key)
      end

      private def check_config(issues : Array(Issue)) : Models::Config?
        unless File.exists?(@config_path)
          issues << Issue.new(id: "config-not-found", level: :warning, category: "config", file: @config_path, message: "Config file not found")
          return
        end

        begin
          config = Models::Config.load(@config_path)
        rescue ex
          issues << Issue.new(id: "config-parse-error", level: :error, category: "config", file: @config_path, message: "Failed to parse config: #{ex.message}")
          return
        end

        # base_url check
        if config.base_url.empty?
          issues << Issue.new(id: "base-url-missing", level: :warning, category: "config", file: @config_path, message: "base_url is not set")
        else
          unless config.base_url.starts_with?("http://") || config.base_url.starts_with?("https://")
            issues << Issue.new(id: "base-url-scheme", level: :warning, category: "config", file: @config_path,
              message: "base_url should start with http:// or https://")
          end
          if config.base_url.ends_with?("/")
            issues << Issue.new(id: "base-url-trailing-slash", level: :warning, category: "config", file: @config_path,
              message: "base_url should not end with a trailing slash")
          end
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

      # Check templates directory for required files
      private def check_templates(issues : Array(Issue))
        unless Dir.exists?(@templates_dir)
          issues << Issue.new(id: "template-dir-missing", level: :warning, category: "template", file: nil,
            message: "Templates directory not found: #{@templates_dir}")
          return
        end

        %w[page.html section.html].each do |required|
          path = File.join(@templates_dir, required)
          unless File.exists?(path)
            issues << Issue.new(id: "template-required-missing", level: :warning, category: "template", file: path,
              message: "Required template file missing: #{required}")
          end
        end

        # Check template files for basic syntax errors
        Dir.glob(File.join(@templates_dir, "**", "*.html")) do |tpl_path|
          check_template_syntax(tpl_path, issues)
        end
      end

      # Basic template syntax check — unclosed tags
      private def check_template_syntax(file_path : String, issues : Array(Issue))
        content = File.read(file_path)

        # Strip Jinja comments {# ... #} and HTML comments before counting,
        # to avoid false positives from commented-out template code
        stripped = content.gsub(/\{#.*?#\}/m, "").gsub(/<!--.*?-->/m, "")

        # Check for unclosed block tags
        opens = stripped.scan(/\{%[-\s]*\b(if|for|block|macro)\b/).size
        closes = stripped.scan(/\{%[-\s]*\bend(if|for|block|macro)\b/).size
        if opens != closes
          issues << Issue.new(id: "template-unclosed-block", level: :warning, category: "template", file: file_path,
            message: "Possible unclosed template block tag (#{opens} opened, #{closes} closed)")
        end

        # Check for unclosed variable tags
        open_vars = stripped.scan(/\{\{/).size
        close_vars = stripped.scan(/\}\}/).size
        if open_vars != close_vars
          issues << Issue.new(id: "template-mismatched-vars", level: :warning, category: "template", file: file_path,
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
    end
  end
end
