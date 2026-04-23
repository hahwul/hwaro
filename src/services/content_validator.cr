# Content Validator Service
#
# Validates content files for frontmatter completeness, accessibility,
# and structural correctness. Checks title/description presence,
# image alt text, internal link validity, date formats, and tag conventions.

require "json"
require "yaml"
require "toml"
require "./doctor"
require "../utils/errors"
require "../utils/frontmatter_scanner"
require "../utils/logger"

module Hwaro
  module Services
    class ContentValidator
      TOML_FRONTMATTER_RE = /\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?/m
      YAML_FRONTMATTER_RE = /\A---\s*\n(.*?\n?)^---\s*$\n?/m

      alias FrontmatterValue = String | Bool | Int64 | Float64?

      @content_dir : String

      def initialize(@content_dir : String = "content")
      end

      def run : Array(Issue)
        # Inability to validate at all (e.g. the content directory does
        # not exist) is classified as HWARO_E_CONTENT — the validator
        # cannot produce findings, so the caller needs a distinct failure
        # signal rather than an empty "looks good" result.
        unless Dir.exists?(@content_dir)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONTENT,
            message: "Content directory '#{@content_dir}' does not exist",
            hint: "Create it or pass --content-dir DIR to point at your content root.",
          )
        end

        issues = [] of Issue
        find_content_files.each do |file_path|
          validate_file(file_path, issues)
        end

        issues
      end

      private def find_content_files : Array(String)
        files = [] of String
        Dir.glob(File.join(@content_dir, "**", "*.md")) { |f| files << f }
        Dir.glob(File.join(@content_dir, "**", "*.markdown")) { |f| files << f }
        files.sort
      end

      private def validate_file(file_path : String, issues : Array(Issue))
        content = File.read(file_path)

        frontmatter = parse_frontmatter(file_path, content, issues)
        return unless frontmatter

        title = frontmatter["title"]?
        description = frontmatter["description"]?
        date = frontmatter["date"]?
        draft = frontmatter["draft"]?
        tags = frontmatter["_tags"]?

        # title check
        if title.nil? || title == "Untitled"
          issues << Issue.new(id: "content-title-missing", level: :warning, category: "content", file: file_path,
            message: title.nil? ? "Missing title in frontmatter" : "Title is \"Untitled\"")
        end

        # description check
        if description.nil?
          issues << Issue.new(id: "content-description-missing", level: :warning, category: "content", file: file_path,
            message: "Missing description in frontmatter")
        end

        # draft info
        if draft == true
          issues << Issue.new(id: "content-draft", level: :info, category: "content", file: file_path,
            message: "File is marked as draft")
        end

        # date format check
        if date.is_a?(String) && !date.as(String).empty?
          check_date_format(file_path, date.as(String), issues)
        end

        # tag convention check (mixed-case warning)
        if tags.is_a?(String) && !tags.as(String).empty?
          check_tag_conventions(file_path, tags.as(String), issues)
        end

        # image alt text check
        check_image_alt(file_path, content, issues)

        # internal link check
        check_internal_links(file_path, content, issues)
      rescue ex
        issues << Issue.new(id: "content-read-error", level: :error, category: "content", file: file_path,
          message: "Failed to read file: #{ex.message}")
      end

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
            # Extract tags as comma-separated string for convention check
            if tags_val = toml_data["tags"]?
              raw = tags_val.raw
              if raw.is_a?(Array)
                tag_strs = raw.compact_map { |item| item.as(TOML::Any).raw.as?(String) }
                result["_tags"] = tag_strs.join(",") unless tag_strs.empty?
              end
            end
            return result
          rescue ex
            issues << Issue.new(id: "content-frontmatter-toml-error", level: :error, category: "content", file: file_path,
              message: "TOML frontmatter parse error: #{ex.message}")
            return
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
              # Extract tags for convention check
              if tags_node = h[YAML::Any.new("tags")]?
                if arr = tags_node.as_a?
                  tag_strs = arr.compact_map(&.as_s?)
                  result["_tags"] = tag_strs.join(",") unless tag_strs.empty?
                end
              end
              return result
            end
            return
          rescue ex
            issues << Issue.new(id: "content-frontmatter-yaml-error", level: :error, category: "content", file: file_path,
              message: "YAML frontmatter parse error: #{ex.message}")
            return
          end
        elsif content.starts_with?('{')
          end_idx = Utils::FrontmatterScanner.find_json_end(content)
          unless end_idx
            issues << Issue.new(id: "content-frontmatter-json-error", level: :error, category: "content", file: file_path,
              message: "JSON frontmatter parse error: unbalanced braces")
            return
          end
          begin
            json_data = JSON.parse(content[0, end_idx])
            if h = json_data.as_h?
              result = {} of String => FrontmatterValue
              h.each do |k, value|
                if s = value.as_s?
                  result[k] = s
                elsif b = value.as_bool?
                  result[k] = b
                elsif i = value.as_i?
                  result[k] = i.to_i64
                elsif f = value.as_f?
                  result[k] = f
                end
              end
              if tags_node = h["tags"]?
                if arr = tags_node.as_a?
                  tag_strs = arr.compact_map(&.as_s?)
                  result["_tags"] = tag_strs.join(",") unless tag_strs.empty?
                end
              end
              return result
            end
            return
          rescue ex
            issues << Issue.new(id: "content-frontmatter-json-error", level: :error, category: "content", file: file_path,
              message: "JSON frontmatter parse error: #{ex.message}")
            return
          end
        end

        nil
      end

      private def check_date_format(file_path : String, date_str : String, issues : Array(Issue))
        formats = [
          "%Y-%m-%d %H:%M:%S",
          "%Y-%m-%dT%H:%M:%S",
          "%Y-%m-%dT%H:%M:%S%z",
          "%Y-%m-%dT%H:%M:%S%:z",
          "%Y-%m-%d",
        ]

        parsed = false
        formats.each do |fmt|
          begin
            Time.parse(date_str, fmt, Time::Location::UTC)
            parsed = true
            break
          rescue
            next
          end
        end

        # Try RFC 3339 as last resort
        unless parsed
          begin
            Time.parse_rfc3339(date_str)
            parsed = true
          rescue
          end
        end

        unless parsed
          issues << Issue.new(id: "content-date-invalid", level: :warning, category: "content", file: file_path,
            message: "Date format may be invalid: \"#{date_str}\"")
        end
      end

      private def check_tag_conventions(file_path : String, tags_csv : String, issues : Array(Issue))
        tags = tags_csv.split(",")
        mixed = tags.select { |tag| tag != tag.downcase && tag != tag.upcase }
        mixed.each do |tag|
          issues << Issue.new(id: "content-tag-mixed-case", level: :info, category: "content", file: file_path,
            message: "Tag has mixed case: \"#{tag}\" (consider lowercase)")
        end
      end

      # Check for images with empty alt text: ![](url)
      private def check_image_alt(file_path : String, content : String, issues : Array(Issue))
        body = strip_code_blocks(extract_body(content))
        body.scan(/!\[\s*\]\([^\)]+\)/) do |match|
          issues << Issue.new(id: "content-alt-text-missing", level: :warning, category: "content", file: file_path,
            message: "Image missing alt text: #{match[0]}")
        end
      end

      # Check for broken internal links (@/ prefixed) in markdown body
      private def check_internal_links(file_path : String, content : String, issues : Array(Issue))
        body = strip_code_blocks(extract_body(content))
        body.scan(/(?<!!)\[([^\]]*)\]\(([^\)]+)\)/) do |match|
          raw_url = match[2].strip
          next unless raw_url.starts_with?("@/")

          path = raw_url.lchop("@/").split("#").first.split("?").first.strip
          next if path.empty?

          target = File.join(@content_dir, path)

          exists = File.exists?(target) ||
                   File.exists?(target + ".md") ||
                   File.exists?(File.join(target, "_index.md")) ||
                   File.exists?(File.join(target, "index.md"))

          unless exists
            issues << Issue.new(id: "content-internal-link-broken", level: :warning, category: "content", file: file_path,
              message: "Possible broken internal link: #{raw_url}")
          end
        end
      end

      private def extract_body(content : String) : String
        content.sub(TOML_FRONTMATTER_RE, "").sub(YAML_FRONTMATTER_RE, "")
      end

      private def strip_code_blocks(text : String) : String
        text.gsub(/(?ms)^(`{3,}|~{3,})[^\n]*\n.*?^\1\s*$/, "")
          .gsub(/`[^`]+`/, "")
      end
    end
  end
end
