# Doctor Service
#
# Diagnoses configuration and content issues in a Hwaro site.
# Checks config.toml for invalid settings and content files
# for missing metadata, accessibility issues, and parse errors.

require "json"
require "yaml"
require "toml"
require "../models/config"
require "../utils/logger"

module Hwaro
  module Services
    # Represents a single diagnostic issue found by the doctor
    record Issue, level : Symbol, category : String, file : String?, message : String do
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
      YAML_DELIMITER = "---"
      TOML_DELIMITER = "+++"

      TOML_FRONTMATTER_RE = /\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?/m
      YAML_FRONTMATTER_RE = /\A---\s*\n(.*?\n?)^---\s*$\n?/m

      VALID_CHANGEFREQS    = %w[always hourly daily weekly monthly yearly never]
      VALID_SEARCH_FORMATS = %w[fuse_json fuse_javascript elasticlunr_json elasticlunr_javascript]

      # Config sections that can be auto-added by --fix.
      # Only includes sections with a config_snippet_for entry.
      # Core sections (sitemap, robots, og, highlight, etc.) are created by
      # `hwaro init` and are not reported — only newer/optional sections are tracked.
      KNOWN_CONFIG_SECTIONS = {
        "pwa"        => "Progressive Web App (manifest.json, service worker)",
        "amp"        => "AMP page generation",
        "series"     => "Series grouping",
        "related"    => "Related posts",
        "search"     => "Client-side search index",
        "pagination" => "Pagination settings",
        "markdown"   => "Markdown parser options",
        "assets"     => "Asset pipeline (bundling, minification)",
        "deployment" => "Deployment targets",
      }

      # Config sections that include sub-sections users should know about
      KNOWN_SUB_SECTIONS = {
        {"og", "auto_image"} => "Auto-generated OG images",
      }

      @content_dir : String
      @config_path : String
      @templates_dir : String

      def initialize(@content_dir : String = "content", @config_path : String = "config.toml", @templates_dir : String = "templates")
      end

      def run : Array(Issue)
        issues = [] of Issue
        check_config(issues)
        check_templates(issues)
        check_content(issues)
        check_directory_structure(issues)
        issues
      end

      # Returns the list of config section keys missing from the user's config.toml
      def missing_config_sections : Array(String)
        return [] of String unless File.exists?(@config_path)

        begin
          raw = TOML.parse_file(@config_path)
        rescue
          return [] of String
        end

        missing = [] of String

        KNOWN_CONFIG_SECTIONS.each_key do |key|
          unless raw.has_key?(key)
            missing << key
          end
        end

        # Check sub-sections (only when parent section exists)
        KNOWN_SUB_SECTIONS.each_key do |parent, child|
          if parent_hash = raw[parent]?.try(&.as_h?)
            unless parent_hash.has_key?(child)
              missing << "#{parent}.#{child}"
            end
          end
          # If parent doesn't exist at all, don't report sub-section
        end

        missing
      end

      # Append missing config sections to config.toml.
      # Returns the list of sections that were added.
      def fix_config : Array(String)
        return [] of String unless File.exists?(@config_path)

        missing = missing_config_sections
        return [] of String if missing.empty?

        snippets = [] of String
        added = [] of String

        missing.each do |key|
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
        case key
        when "pwa"
          <<-TOML

          # =============================================================================
          # PWA (Progressive Web App) (Optional)
          # =============================================================================
          # Generate manifest.json and service worker for offline access

          # [pwa]
          # enabled = true
          # name = "My Site"
          # short_name = "Site"
          # theme_color = "#ffffff"
          # background_color = "#ffffff"
          # display = "standalone"
          # icons = ["static/icon-192.png", "static/icon-512.png"]

          TOML
        when "amp"
          <<-TOML

          # =============================================================================
          # AMP (Accelerated Mobile Pages) (Optional)
          # =============================================================================
          # Generate AMP-compliant versions of content pages

          # [amp]
          # enabled = true
          # path_prefix = "amp"
          # sections = ["posts"]

          TOML
        when "og.auto_image"
          <<-TOML

          # =============================================================================
          # Auto OG Images (Optional)
          # =============================================================================
          # Auto-generate Open Graph preview images for social sharing

          # [og.auto_image]
          # enabled = true
          # background = "#1a1a2e"
          # text_color = "#ffffff"
          # accent_color = "#e94560"
          # font_size = 48
          # logo = "static/logo.png"
          # output_dir = "og-images"

          TOML
        when "series"
          <<-TOML

          # =============================================================================
          # Series (Optional)
          # =============================================================================
          # Group posts into ordered series

          # [series]
          # enabled = true

          TOML
        when "related"
          <<-TOML

          # =============================================================================
          # Related Posts (Optional)
          # =============================================================================
          # Recommend related content based on shared taxonomy terms

          # [related]
          # enabled = true
          # limit = 5
          # taxonomies = ["tags"]

          TOML
        when "search"
          <<-TOML

          # =============================================================================
          # Search (Optional)
          # =============================================================================
          # Generate search index for client-side search

          # [search]
          # enabled = true
          # format = "fuse_json"
          # fields = ["title", "content"]

          TOML
        when "pagination"
          <<-TOML

          # =============================================================================
          # Pagination (Optional)
          # =============================================================================

          # [pagination]
          # enabled = false
          # per_page = 10

          TOML
        when "markdown"
          <<-TOML

          # =============================================================================
          # Markdown (Optional)
          # =============================================================================

          # [markdown]
          # safe = false
          # lazy_loading = false
          # emoji = false

          TOML
        when "assets"
          <<-TOML

          # =============================================================================
          # Asset Pipeline (Optional)
          # =============================================================================

          # [assets]
          # enabled = true
          # minify = true
          # fingerprint = true

          TOML
        when "deployment"
          <<-TOML

          # =============================================================================
          # Deployment (Optional)
          # =============================================================================

          # [deployment]
          # target = "prod"
          # source_dir = "public"
          #
          # [[deployment.targets]]
          # name = "prod"
          # url = "file://./out"

          TOML
        else
          nil # Unknown section — skip
        end
      end

      private def check_config(issues : Array(Issue))
        unless File.exists?(@config_path)
          issues << Issue.new(level: :warning, category: "config", file: @config_path, message: "Config file not found")
          return
        end

        begin
          config = Models::Config.load(@config_path)
        rescue ex
          issues << Issue.new(level: :error, category: "config", file: @config_path, message: "Failed to parse config: #{ex.message}")
          return
        end

        # base_url check
        if config.base_url.empty?
          issues << Issue.new(level: :warning, category: "config", file: @config_path, message: "base_url is not set")
        else
          unless config.base_url.starts_with?("http://") || config.base_url.starts_with?("https://")
            issues << Issue.new(level: :warning, category: "config", file: @config_path,
              message: "base_url should start with http:// or https://")
          end
          if config.base_url.ends_with?("/")
            issues << Issue.new(level: :warning, category: "config", file: @config_path,
              message: "base_url should not end with a trailing slash")
          end
        end

        # title check
        if config.title == "Hwaro Site"
          issues << Issue.new(level: :warning, category: "config", file: @config_path, message: "title is still the default value \"Hwaro Site\"")
        end

        # feeds: enabled but filename empty
        if config.feeds.enabled && config.feeds.filename.empty?
          issues << Issue.new(level: :warning, category: "config", file: @config_path, message: "feeds.enabled is true but feeds.filename is not set")
        end

        # sitemap changefreq validity
        unless VALID_CHANGEFREQS.includes?(config.sitemap.changefreq)
          issues << Issue.new(level: :warning, category: "config", file: @config_path,
            message: "sitemap.changefreq \"#{config.sitemap.changefreq}\" is not valid (expected: #{VALID_CHANGEFREQS.join(", ")})")
        end

        # sitemap priority range
        unless 0.0 <= config.sitemap.priority <= 1.0
          issues << Issue.new(level: :warning, category: "config", file: @config_path,
            message: "sitemap.priority #{config.sitemap.priority} is out of range (expected: 0.0–1.0)")
        end

        # taxonomy name duplicates
        taxonomy_names = config.taxonomies.map(&.name)
        duplicates = taxonomy_names.tally.select { |_, count| count > 1 }.keys
        duplicates.each do |name|
          issues << Issue.new(level: :warning, category: "config", file: @config_path,
            message: "Duplicate taxonomy name: \"#{name}\"")
        end

        # search format validity
        if config.search.enabled && !VALID_SEARCH_FORMATS.includes?(config.search.format)
          issues << Issue.new(level: :warning, category: "config", file: @config_path,
            message: "search.format \"#{config.search.format}\" is not supported (expected: #{VALID_SEARCH_FORMATS.join(", ")})")
        end

        # duplicate language codes
        lang_codes = config.languages.keys
        lang_duplicates = lang_codes.tally.select { |_, count| count > 1 }.keys
        lang_duplicates.each do |code|
          issues << Issue.new(level: :warning, category: "config", file: @config_path,
            message: "Duplicate language code: \"#{code}\"")
        end

        # Check for missing config sections
        check_missing_config_sections(issues)
      end

      private def check_missing_config_sections(issues : Array(Issue))
        missing = missing_config_sections
        return if missing.empty?

        missing.each do |key|
          desc = KNOWN_CONFIG_SECTIONS[key]? || KNOWN_SUB_SECTIONS.find { |k, _| "#{k[0]}.#{k[1]}" == key }.try(&.last) || key
          issues << Issue.new(level: :info, category: "config_missing", file: @config_path,
            message: "Missing config section [#{key}] (#{desc}) — run 'hwaro tool doctor --fix' to add it")
        end
      end

      private def check_content(issues : Array(Issue))
        return unless Dir.exists?(@content_dir)

        files = find_content_files
        files.each do |file_path|
          check_content_file(file_path, issues)
        end
      end

      private def find_content_files : Array(String)
        files = [] of String
        Dir.glob(File.join(@content_dir, "**", "*.md")) { |f| files << f }
        Dir.glob(File.join(@content_dir, "**", "*.markdown")) { |f| files << f }
        files.sort
      end

      private def check_content_file(file_path : String, issues : Array(Issue))
        content = File.read(file_path)

        frontmatter = parse_frontmatter(file_path, content, issues)
        return unless frontmatter

        title = frontmatter["title"]?
        description = frontmatter["description"]?
        date = frontmatter["date"]?
        draft = frontmatter["draft"]?

        # title check
        if title.nil? || title == "Untitled"
          issues << Issue.new(level: :warning, category: "content", file: file_path,
            message: title.nil? ? "Missing title in frontmatter" : "Title is \"Untitled\"")
        end

        # description check
        if description.nil?
          issues << Issue.new(level: :warning, category: "content", file: file_path,
            message: "Missing description in frontmatter")
        end

        # draft info
        if draft == true
          issues << Issue.new(level: :info, category: "content", file: file_path,
            message: "File is marked as draft")
        end

        # image alt text check
        check_image_alt(file_path, content, issues)

        # internal link check
        check_internal_links(file_path, content, issues)
      rescue ex
        issues << Issue.new(level: :error, category: "content", file: file_path,
          message: "Failed to read file: #{ex.message}")
      end

      # Parse frontmatter and return a hash of key-value pairs.
      # Returns nil if no frontmatter found. Reports parse errors as issues.
      private def parse_frontmatter(file_path : String, content : String, issues : Array(Issue)) : Hash(String, FrontmatterValue)?
        if match = content.match(TOML_FRONTMATTER_RE)
          begin
            toml_data = TOML.parse(match[1])
            result = {} of String => FrontmatterValue
            toml_data.each do |key, value|
              case raw = value.raw
              when String  then result[key] = raw
              when Bool    then result[key] = raw
              when Int64   then result[key] = raw
              when Float64 then result[key] = raw
              when Time    then result[key] = raw.to_s
              end
            end
            return result
          rescue ex
            issues << Issue.new(level: :error, category: "content", file: file_path,
              message: "TOML frontmatter parse error: #{ex.message}")
            return nil
          end
        elsif match = content.match(YAML_FRONTMATTER_RE)
          begin
            yaml_data = YAML.parse(match[1])
            if h = yaml_data.as_h?
              result = {} of String => FrontmatterValue
              h.each do |key, value|
                k = key.as_s? || next
                if s = value.as_s?
                  result[k] = s
                elsif b = value.as_bool?
                  result[k] = b
                elsif i = value.as_i?
                  result[k] = i.to_i64
                elsif f = value.as_f?
                  result[k] = f
                elsif t = value.as_time?
                  result[k] = t.to_s
                end
              end
              return result
            end
            return nil
          rescue ex
            issues << Issue.new(level: :error, category: "content", file: file_path,
              message: "YAML frontmatter parse error: #{ex.message}")
            return nil
          end
        end

        nil
      end

      # Check for images with empty alt text: ![](url)
      private def check_image_alt(file_path : String, content : String, issues : Array(Issue))
        # Extract body after frontmatter, stripping code blocks
        body = strip_code_blocks(extract_body(content))
        body.scan(/!\[\s*\]\([^\)]+\)/) do |match|
          issues << Issue.new(level: :warning, category: "content", file: file_path,
            message: "Image missing alt text: #{match[0]}")
        end
      end

      # Strip frontmatter from content to get body only
      private def extract_body(content : String) : String
        content.sub(TOML_FRONTMATTER_RE, "").sub(YAML_FRONTMATTER_RE, "")
      end

      # Strip fenced code blocks and inline code from text to avoid false positives
      private def strip_code_blocks(text : String) : String
        text.gsub(/(?ms)^(`{3,}|~{3,})[^\n]*\n.*?^\1\s*$/, "")
          .gsub(/`[^`]+`/, "")
      end

      # Check for broken internal links (@/ prefixed) in markdown body
      private def check_internal_links(file_path : String, content : String, issues : Array(Issue))
        body = strip_code_blocks(extract_body(content))
        # Match markdown links [text](url) — only check @/ prefixed internal links
        body.scan(/(?<!!)\[([^\]]*)\]\(([^\)]+)\)/) do |match|
          raw_url = match[2].strip
          next unless raw_url.starts_with?("@/")

          # Strip @/ prefix and anchors/query params
          path = raw_url.lchop("@/").split("#").first.split("?").first.strip
          next if path.empty?

          target = File.join(@content_dir, path)

          # Check if target exists as file or directory (with _index.md or index.md)
          exists = File.exists?(target) ||
                   File.exists?(target + ".md") ||
                   File.exists?(File.join(target, "_index.md")) ||
                   File.exists?(File.join(target, "index.md"))

          unless exists
            issues << Issue.new(level: :warning, category: "content", file: file_path,
              message: "Possible broken internal link: #{raw_url}")
          end
        end
      end

      # Check templates directory for required files
      private def check_templates(issues : Array(Issue))
        unless Dir.exists?(@templates_dir)
          issues << Issue.new(level: :warning, category: "template", file: nil,
            message: "Templates directory not found: #{@templates_dir}")
          return
        end

        %w[page.html section.html].each do |required|
          path = File.join(@templates_dir, required)
          unless File.exists?(path)
            issues << Issue.new(level: :warning, category: "template", file: path,
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
          issues << Issue.new(level: :warning, category: "template", file: file_path,
            message: "Possible unclosed template block tag (#{opens} opened, #{closes} closed)")
        end

        # Check for unclosed variable tags
        open_vars = stripped.scan(/\{\{/).size
        close_vars = stripped.scan(/\}\}/).size
        if open_vars != close_vars
          issues << Issue.new(level: :warning, category: "template", file: file_path,
            message: "Mismatched {{ }} variable tags (#{open_vars} opened, #{close_vars} closed)")
        end
      rescue ex
        issues << Issue.new(level: :error, category: "template", file: file_path,
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
            issues << Issue.new(level: :info, category: "structure", file: child,
              message: "Section directory missing _index.md: #{entry}/")
          end
        end
      end

      alias FrontmatterValue = String | Bool | Int64 | Float64 | Nil
    end
  end
end
