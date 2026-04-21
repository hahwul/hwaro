require "file_utils"
require "../../config/options/import_options"
require "../../utils/logger"
require "../../utils/text_utils"

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

        # Write a content file, skipping if it already exists
        protected def write_content_file(
          output_dir : String,
          section : String,
          slug : String,
          frontmatter : String,
          body : String,
          verbose : Bool = false,
        ) : Bool
          dir = section.empty? ? output_dir : File.join(output_dir, section)
          FileUtils.mkdir_p(dir) unless Dir.exists?(dir)

          filename = slug.ends_with?(".md") ? slug : "#{slug}.md"
          path = File.join(dir, filename)

          if File.exists?(path)
            Logger.warn "Skipped (already exists): #{path}" if verbose
            return false
          end

          content = "#{frontmatter}\n\n#{body}\n"
          File.write(path, content)
          Logger.debug "Imported: #{path}" if verbose
          true
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
          ]

          formats.each do |fmt|
            begin
              return Time.parse(date_str.strip, fmt, Time::Location::UTC)
            rescue
              next
            end
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
