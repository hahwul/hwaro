# Doctor Service
#
# Diagnoses configuration and content issues in a Hwaro site.
# Checks config.toml for invalid settings and content files
# for missing metadata, accessibility issues, and parse errors.

require "yaml"
require "toml"
require "../models/config"
require "../utils/logger"

module Hwaro
  module Services
    # Represents a single diagnostic issue found by the doctor
    record Issue, level : Symbol, category : String, file : String?, message : String

    class Doctor
      YAML_DELIMITER = "---"
      TOML_DELIMITER = "+++"

      TOML_FRONTMATTER_RE = /\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?/m
      YAML_FRONTMATTER_RE = /\A---\s*\n(.*?\n?)^---\s*$\n?/m

      VALID_CHANGEFREQS    = %w[always hourly daily weekly monthly yearly never]
      VALID_SEARCH_FORMATS = %w[fuse_json fuse_javascript elasticlunr_json elasticlunr_javascript]

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

        # date check
        if date.nil?
          issues << Issue.new(level: :warning, category: "content", file: file_path,
            message: "Missing date in frontmatter")
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
        # Extract body after frontmatter
        body = extract_body(content)
        body.scan(/!\[\s*\]\([^\)]+\)/) do |match|
          issues << Issue.new(level: :warning, category: "content", file: file_path,
            message: "Image missing alt text: #{match[0]}")
        end
      end

      # Strip frontmatter from content to get body only
      private def extract_body(content : String) : String
        content.sub(TOML_FRONTMATTER_RE, "").sub(YAML_FRONTMATTER_RE, "")
      end

      # Check for internal broken links in markdown body
      private def check_internal_links(file_path : String, content : String, issues : Array(Issue))
        body = extract_body(content)
        # Match markdown links [text](url) — skip images (![...]), external, anchors-only, and mailto
        body.scan(/(?<!!)\[([^\]]*)\]\(([^\)]+)\)/) do |match|
          url = match[2].split("#").first.split("?").first.strip
          next if url.empty?
          next if url.starts_with?("http://") || url.starts_with?("https://")
          next if url.starts_with?("mailto:") || url.starts_with?("#")

          # Resolve relative path from the content file's directory
          base_dir = File.dirname(file_path)
          target = if url.starts_with?("/")
                     File.join(@content_dir, url.lstrip("/"))
                   else
                     File.join(base_dir, url)
                   end

          # Check if target exists as file or directory (with _index.md or index.md)
          exists = File.exists?(target) ||
                   File.exists?(target + ".md") ||
                   File.exists?(File.join(target, "_index.md")) ||
                   File.exists?(File.join(target, "index.md"))

          unless exists
            issues << Issue.new(level: :warning, category: "content", file: file_path,
              message: "Possible broken internal link: #{match[2]}")
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

        # Check for unclosed block tags
        opens = content.scan(/\{%[-\s]*\b(if|for|block|macro)\b/).size
        closes = content.scan(/\{%[-\s]*\bend(if|for|block|macro)\b/).size
        if opens != closes
          issues << Issue.new(level: :warning, category: "template", file: file_path,
            message: "Possible unclosed template block tag (#{opens} opened, #{closes} closed)")
        end

        # Check for unclosed variable tags
        open_vars = content.scan(/\{\{/).size
        close_vars = content.scan(/\}\}/).size
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
