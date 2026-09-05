# Content Validator Service
#
# Validates content files for frontmatter completeness, accessibility,
# and structural correctness. Checks title/description presence,
# image alt text, internal link validity, date formats, and tag conventions.

require "json"
require "yaml"
require "toml"
require "./content_lister"
require "./doctor"
require "../utils/errors"
require "../utils/frontmatter_scanner"
require "../utils/logger"
require "../utils/text_utils"

module Hwaro
  module Services
    class ContentValidator
      TOML_FRONTMATTER_RE = Utils::FrontmatterScanner::TOML_FRONTMATTER_RE
      YAML_FRONTMATTER_RE = Utils::FrontmatterScanner::YAML_FRONTMATTER_RE

      alias FrontmatterValue = String | Bool | Int64 | Float64?

      # Parsed front matter plus the tag list carried OUT-OF-BAND. Tags
      # used to be smuggled through the field hash under a fake "_tags"
      # key joined with commas, so a real front matter key named `_tags`
      # triggered bogus mixed-case tag warnings for non-tag data, and
      # genuine tags containing commas were split apart before the
      # convention check ever saw them.
      private record ParsedFrontmatter,
        fields : Hash(String, FrontmatterValue),
        tags : Array(String) = [] of String

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

      # Unfollowable symlinks are dropped here (see `ContentWalk`): there is no
      # frontmatter to judge behind a link that resolves to nothing, and
      # reporting one as an author-fixable `content-read-error` made
      # `hwaro tool validate` fail (exit 5) on a tree `hwaro build` publishes
      # fine. The skip is announced by `ContentWalk`, so the summary's counts
      # are never quietly short of a file the caller can see on disk.
      private def find_content_files : Array(String)
        ContentWalk.find_content_files(@content_dir)
      end

      private def validate_file(file_path : String, issues : Array(Issue))
        # Match the build's frontmatter reader (see TextUtils.strip_bom) so a
        # BOM'd file isn't reported as missing every front matter field.
        content = Utils::TextUtils.strip_bom(File.read(file_path))

        parsed = parse_frontmatter(file_path, content, issues)
        frontmatter = parsed.try(&.fields) || {} of String => FrontmatterValue
        tags = parsed.try(&.tags) || [] of String

        title = frontmatter["title"]?
        description = frontmatter["description"]?
        date = frontmatter["date"]?
        draft = frontmatter["draft"]?

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
        check_tag_conventions(file_path, tags, issues) unless tags.empty?

        # image alt text check
        check_image_alt(file_path, content, issues)

        # internal link check
        check_internal_links(file_path, content, issues)
      rescue ex : IO::Error | File::Error
        issues << Issue.new(id: "content-read-error", level: :error, category: "content", file: file_path,
          message: "Failed to read file: #{ex.message}")
      rescue ex
        # A readable file can still blow up the scanners — invalid UTF-8
        # makes the front-matter regex raise ArgumentError. Calling that a
        # read failure pointed authors at permissions/disk when the
        # problem is the file's encoding or structure.
        issues << Issue.new(id: "content-read-error", level: :error, category: "content", file: file_path,
          message: "Cannot process file (invalid encoding or malformed content): #{ex.message}")
      end

      private def parse_frontmatter(file_path : String, content : String, issues : Array(Issue)) : ParsedFrontmatter?
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
            # Extract tags as comma-separated string for convention check.
            # The `[taxonomies] tags` table is the scaffold's own (and Zola's)
            # way of declaring them, and the build falls back to it when no
            # top-level `tags` exists — without the same fallback here, those
            # sites were never tag-checked at all.
            tag_strs = toml_tag_list(toml_data["tags"]?)
            tag_strs = toml_tag_list(toml_data["taxonomies"]?.try(&.as_h?).try(&.["tags"]?)) if tag_strs.empty?
            return ParsedFrontmatter.new(result, tag_strs)
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
                elsif !(b = value.as_bool?).nil?
                  # `elsif b = value.as_bool?` DROPPED every `false` value —
                  # Crystal treats the returned `false` as a failed match — so
                  # a `draft: false` (or any other false flag) never reached
                  # the checks below.
                  result[k] = b
                elsif i = value.as_i64?
                  # 64-bit accessor: `as_i?` only type-checks (`@raw.as(Int).to_i`),
                  # so a YAML integer above Int32::MAX raised OverflowError and the
                  # rescue below reported a bogus "YAML frontmatter parse error"
                  # for a file that parsed perfectly well.
                  result[k] = i
                elsif f = value.as_f?
                  result[k] = f
                elsif t = value.as_time?
                  result[k] = t.to_s
                end
              end
              # Extract tags for convention check (same `[taxonomies]`
              # fallback the build applies).
              tag_strs = yaml_tag_list(h[YAML::Any.new("tags")]?)
              if tag_strs.empty?
                tag_strs = yaml_tag_list(h[YAML::Any.new("taxonomies")]?.try(&.as_h?).try(&.[YAML::Any.new("tags")]?))
              end
              return ParsedFrontmatter.new(result, tag_strs)
            end
            # Empty or non-mapping YAML frontmatter (e.g. `---\n---`) is valid
            # YAML but carries no title/description. Return an empty hash (not
            # nil) so the missing-field checks still fire — matching empty TOML,
            # which already reaches them via its `{}` result.
            return ParsedFrontmatter.new({} of String => FrontmatterValue)
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
            # find_json_end returns a BYTE offset; byte_slice avoids flagging
            # valid multibyte JSON frontmatter as a parse error.
            json_data = JSON.parse(content.byte_slice(0, end_idx))
            if h = json_data.as_h?
              result = {} of String => FrontmatterValue
              h.each do |k, value|
                if s = value.as_s?
                  result[k] = s
                elsif !(b = value.as_bool?).nil?
                  # Same falsy-drop as the YAML branch above.
                  result[k] = b
                elsif i = value.as_i64?
                  # Same Int32 overflow hazard as the YAML branch above.
                  result[k] = i
                elsif f = value.as_f?
                  result[k] = f
                end
              end
              tag_strs = json_tag_list(h["tags"]?)
              tag_strs = json_tag_list(h["taxonomies"]?.try(&.as_h?).try(&.["tags"]?)) if tag_strs.empty?
              return ParsedFrontmatter.new(result, tag_strs)
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

      private def toml_tag_list(value : TOML::Any?) : Array(String)
        raw = value.try(&.raw)
        return [] of String unless raw.is_a?(Array)
        raw.compact_map { |item| item.as(TOML::Any).raw.as?(String) }
      end

      private def yaml_tag_list(value : YAML::Any?) : Array(String)
        value.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
      end

      private def json_tag_list(value : JSON::Any?) : Array(String)
        value.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
      end

      private def check_date_format(file_path : String, date_str : String, issues : Array(Issue))
        unless date_str.matches?(/^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:?\d{2}| [A-Z][A-Za-z]*| [+-]\d{2}:?\d{2})?)?$/)
          issues << Issue.new(id: "content-date-invalid", level: :warning, category: "content", file: file_path,
            message: "Date format may be invalid: \"#{date_str}\"")
          return
        end

        formats = [
          "%Y-%m-%d %H:%M:%S",
          "%Y-%m-%dT%H:%M:%S",
          "%Y-%m-%dT%H:%M:%S%z",
          "%Y-%m-%dT%H:%M:%S%:z",
          "%Y-%m-%d",
        ]

        parsed = false
        formats.each do |fmt|
          Time.parse(date_str, fmt, Time::Location::UTC)
          parsed = true
          break
        rescue Time::Format::Error | ArgumentError
          next
        end

        # Try RFC 3339 as last resort
        unless parsed
          begin
            Time.parse_rfc3339(date_str)
            parsed = true
          rescue Time::Format::Error | ArgumentError
          end
        end

        unless parsed
          issues << Issue.new(id: "content-date-invalid", level: :warning, category: "content", file: file_path,
            message: "Date format may be invalid: \"#{date_str}\"")
        end
      end

      private def check_tag_conventions(file_path : String, tags : Array(String), issues : Array(Issue))
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
        Utils::FrontmatterScanner.strip_frontmatter(content)
      end

      private def strip_code_blocks(text : String) : String
        # Strip fenced blocks then inline spans. NOTE: indented (4-space/tab)
        # code blocks are intentionally NOT stripped — a regex can't tell an
        # indented code block from a list-item continuation (which is also
        # indented), so stripping them silently dropped genuine broken-link /
        # alt-text warnings inside list items, and a long contiguous indented
        # run blew PCRE2's JIT stack. The minor false positive on example
        # markdown shown via an indented block is the lesser evil.
        text.gsub(/(?ms)^(`{3,}|~{3,})[^\n]*\n.*?^\1\s*$/, "")
          .gsub(/`[^`]+`/, "")
      end
    end
  end
end
