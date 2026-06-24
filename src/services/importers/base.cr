require "file_utils"
require "../../config/options/import_options"
require "../../utils/file_safe"
require "../../utils/logger"
require "../../utils/text_utils"
require "../../utils/path_utils"
require "../../utils/output_guard"

module Hwaro
  module Services
    module Importers
      struct ImportResult
        property success : Bool
        property message : String
        property imported_count : Int32
        property skipped_count : Int32
        property error_count : Int32

        def initialize(
          @success : Bool = true,
          @message : String = "",
          @imported_count : Int32 = 0,
          @skipped_count : Int32 = 0,
          @error_count : Int32 = 0,
        )
        end
      end

      abstract class Base
        abstract def run(options : Config::Options::ImportOptions) : ImportResult

        # Generate TOML frontmatter string from fields hash
        protected def generate_frontmatter(fields : Hash(String, (String | Bool | Array(String))?)) : String
          lines = [] of String
          lines << "+++"

          fields.each do |key, value|
            case value
            when Nil
              next
            when Bool
              lines << "#{key} = #{value}"
            when String
              next if value.empty?
              lines << "#{key} = #{value.inspect}"
            when Array(String)
              next if value.empty?
              formatted = value.map(&.inspect).join(", ")
              lines << "#{key} = [#{formatted}]"
            end
          end

          lines << "+++"
          lines.join("\n")
        end

        # Convert title to a URL-safe slug
        protected def slugify(title : String) : String
          Utils::TextUtils.slugify(title)
        end

        # If the imported body's first non-blank line is an H1 matching the
        # front-matter title, drop it. Hwaro page templates render
        # `<h1>{{ page.title }}</h1>` themselves, so keeping the body H1
        # produces two H1 elements on the same page — same problem that
        # gh#525 fixed for `hwaro new`. Importers from Hugo/Jekyll/Obsidian
        # all hit this because those engines typically render the title from
        # the body H1 rather than from front matter.
        protected def strip_redundant_title_h1(body : String, title : String?) : String
          return body if title.nil? || title.empty?
          # Match `# Title`, ATX-style only — setext H1 (`=====` underline)
          # is rare in imported content and ambiguous to detect without a
          # second-line peek. Authors using setext can clean up by hand.
          normalized_title = title.strip
          # `chomp: false` keeps the trailing `\n` on each line so joining
          # afterwards reproduces the original byte sequence exactly — the
          # default behavior strips newlines and would smash paragraphs
          # together when we rejoin.
          lines = body.lines(chomp: false)
          # Skip leading blank lines so a body that begins with `\n# Title` works.
          idx = 0
          while idx < lines.size && lines[idx].strip.empty?
            idx += 1
          end
          return body if idx >= lines.size

          first = lines[idx]
          if match = first.match(/\A#\s+(.+?)\s*#*\s*\z/)
            return body if match[1].strip != normalized_title
            # Drop the H1 line and exactly one trailing blank line if present,
            # so the body doesn't gain a leading blank gap.
            lines.delete_at(idx)
            lines.delete_at(idx) if idx < lines.size && lines[idx].strip.empty?
            return lines.join
          end
          body
        end

        # Write a content file. Skips if it already exists unless `force`
        # is true, in which case the existing file is overwritten. Returns
        # true when a file was written, false when it was skipped.
        protected def write_content_file(
          output_dir : String,
          section : String,
          slug : String,
          frontmatter : String,
          body : String,
          verbose : Bool = false,
          force : Bool = false,
        ) : Bool
          # Importers consume third-party exports, so `section` and `slug` are
          # UNTRUSTED. A malicious WordPress `<wp:post_name>` or Hugo front
          # matter `slug` of "../../../etc/x" would otherwise let `File.write`
          # escape `output_dir` and plant or overwrite files anywhere the
          # running user can write. Neutralise traversal at this single sink so
          # every current and future importer is protected.
          safe_section = Utils::PathUtils.sanitize_path(section)
          safe_slug = safe_filename_component(slug)
          if safe_slug.empty?
            Logger.warn "Skipped (unsafe slug #{slug.inspect})" if verbose
            return false
          end

          dir = safe_section.empty? ? output_dir : File.join(output_dir, safe_section)

          filename = safe_slug.ends_with?(".md") ? safe_slug : "#{safe_slug}.md"
          path = File.join(dir, filename)

          # Belt-and-suspenders: refuse to write outside output_dir even if a
          # component slipped past the sanitisers above.
          unless Utils::OutputGuard.within_output_dir?(path, output_dir)
            Logger.warn "Skipped (escapes output directory): #{path}"
            return false
          end

          Hwaro::Utils::FileSafe.mkdir_p(dir) unless Dir.exists?(dir)

          if File.exists?(path) && !force
            Logger.warn "Skipped (already exists): #{path}" if verbose
            return false
          end

          content = "#{frontmatter}\n\n#{body}\n"
          File.write(path, content)
          if verbose
            Logger.debug(force ? "Overwrote: #{path}" : "Imported: #{path}")
          end
          true
        end

        # Collapse an untrusted slug to a single safe filename component so it
        # can never traverse out of the section directory. Drops null bytes,
        # splits on both `/` and `\` separators, removes "."/".."/empty
        # segments, and keeps the last remaining segment (which may legitimately
        # carry a trailing ".md"). Unicode is preserved. We intentionally do NOT
        # URL-decode: the filesystem treats `%2f` as a literal, so decoding
        # would only manufacture separators that aren't really there.
        protected def safe_filename_component(value : String) : String
          value.delete(Char::ZERO)
            .split(/[\/\\]/)
            .reject { |seg| seg.empty? || seg == "." || seg == ".." }
            .last? || ""
        end

        # Parse a date string in common formats, returns nil on failure
        protected def parse_date(date_str : String) : Time?
          formats = [
            "%Y-%m-%d %H:%M:%S",
            "%Y-%m-%dT%H:%M:%S",
            "%Y-%m-%dT%H:%M:%S%z",
            "%Y-%m-%dT%H:%M:%S%:z",
            "%Y-%m-%d",
            "%B %d, %Y",
            # RFC 822 (WordPress <pubDate>, RSS feeds)
            "%a, %d %b %Y %H:%M:%S %z",
          ]

          formats.each do |fmt|
            return Time.parse(date_str.strip, fmt, Time::Location::UTC)
          rescue Time::Format::Error
            next
          end

          nil
        end

        # Format a Time to the standard frontmatter date format
        protected def format_date(time : Time) : String
          time.to_s("%Y-%m-%d %H:%M:%S")
        end
      end
    end
  end
end
