# Content Lister Service
#
# This service provides functionality to list content files
# based on their publication status (all, drafts, published).

require "yaml"
require "toml"
require "../utils/logger"

module Hwaro
  module Services
    # Filter type for listing content
    enum ContentFilter
      All
      Drafts
      Published
    end

    # Information about a content file
    struct ContentInfo
      property path : String
      property title : String
      property draft : Bool
      property date : Time?

      def initialize(
        @path : String,
        @title : String = "Untitled",
        @draft : Bool = false,
        @date : Time? = nil
      )
      end
    end

    # Content Lister lists content files based on their status
    class ContentLister
      YAML_DELIMITER = "---"
      TOML_DELIMITER = "+++"

      # Content directory path
      @content_dir : String

      def initialize(@content_dir : String = "content")
      end

      # List all content files
      def list_all : Array(ContentInfo)
        list_content(ContentFilter::All)
      end

      # List only draft content files
      def list_drafts : Array(ContentInfo)
        list_content(ContentFilter::Drafts)
      end

      # List only published content files
      def list_published : Array(ContentInfo)
        list_content(ContentFilter::Published)
      end

      # List content files based on filter
      def list_content(filter : ContentFilter) : Array(ContentInfo)
        unless Dir.exists?(@content_dir)
          Logger.error "Content directory '#{@content_dir}' not found"
          return [] of ContentInfo
        end

        files = find_content_files
        contents = [] of ContentInfo

        files.each do |file_path|
          info = parse_content_info(file_path)
          next unless info

          case filter
          when ContentFilter::All
            contents << info
          when ContentFilter::Drafts
            contents << info if info.draft
          when ContentFilter::Published
            contents << info unless info.draft
          end
        end

        # Sort by date (newest first), then by path
        contents.sort_by! do |info|
          {info.date.try(&.to_unix) || 0_i64, info.path}
        end.reverse!

        contents
      end

      # Display content list in a formatted table
      def display(filter : ContentFilter)
        contents = list_content(filter)

        filter_name = case filter
                      when ContentFilter::All       then "All"
                      when ContentFilter::Drafts    then "Drafts"
                      when ContentFilter::Published then "Published"
                      else                               "Unknown"
                      end

        Logger.info "Listing #{filter_name.downcase} content in '#{@content_dir}'..."
        Logger.info ""

        if contents.empty?
          Logger.info "  No content found."
          return
        end

        # Calculate column widths
        max_path_width = [contents.map(&.path.size).max, 40].min
        max_title_width = [contents.map(&.title.size).max, 30].min

        # Print header
        header = String.build do |str|
          str << "  "
          str << "Status".ljust(10)
          str << "Date".ljust(12)
          str << "Title".ljust(max_title_width + 2)
          str << "Path"
        end
        Logger.info header
        Logger.info "  " + "-" * (10 + 12 + max_title_width + 2 + max_path_width)

        # Print each content item
        contents.each do |info|
          status = info.draft ? "draft" : "published"
          status_display = info.draft ? "[draft]" : "[pub]"
          date_display = info.date.try(&.to_s("%Y-%m-%d")) || "-"
          title_display = truncate(info.title, max_title_width)
          path_display = truncate(info.path, max_path_width)

          line = String.build do |str|
            str << "  "
            str << status_display.ljust(10)
            str << date_display.ljust(12)
            str << title_display.ljust(max_title_width + 2)
            str << path_display
          end
          Logger.info line
        end

        Logger.info ""
        Logger.info "Total: #{contents.size} file(s)"
      end

      private def find_content_files : Array(String)
        files = [] of String

        Dir.glob(File.join(@content_dir, "**", "*.md")) do |file|
          files << file
        end

        Dir.glob(File.join(@content_dir, "**", "*.markdown")) do |file|
          files << file
        end

        files.sort
      end

      private def parse_content_info(file_path : String) : ContentInfo?
        content = File.read(file_path)

        title = "Untitled"
        draft = false
        date : Time? = nil

        # Try TOML Front Matter (+++)
        if match = content.match(/\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?/m)
          begin
            toml_fm = TOML.parse(match[1])
            title = toml_fm["title"]?.try(&.as_s) || title
            draft = toml_fm["draft"]?.try(&.as_bool) || false
            # TOML parser may return Time directly or String
            if date_val = toml_fm["date"]?
              raw = date_val.raw
              if raw.is_a?(Time)
                date = raw
              elsif raw.is_a?(String)
                date = parse_time(raw)
              end
            end
          rescue
            # Ignore parsing errors
          end
        # Try YAML Front Matter (---)
        elsif match = content.match(/\A---\s*\n(.*?\n?)^---\s*$\n?/m)
          begin
            yaml_fm = YAML.parse(match[1])
            if yaml_fm.as_h?
              title = yaml_fm["title"]?.try(&.as_s?) || title
              draft = yaml_fm["draft"]?.try(&.as_bool?) || false
              # YAML parser may return Time directly or String
              if date_val = yaml_fm["date"]?
                if time_val = date_val.as_time?
                  date = time_val
                elsif str_val = date_val.as_s?
                  date = parse_time(str_val)
                end
              end
            end
          rescue
            # Ignore parsing errors
          end
        end

        ContentInfo.new(
          path: file_path,
          title: title,
          draft: draft,
          date: date
        )
      rescue
        nil
      end

      private def parse_time(time_str : String?) : Time?
        return nil unless time_str

        formats = [
          "%Y-%m-%d %H:%M:%S",
          "%Y-%m-%dT%H:%M:%S",
          "%Y-%m-%d",
        ]

        formats.each do |fmt|
          begin
            return Time.parse(time_str, fmt, Time::Location.local)
          rescue
            next
          end
        end

        # Try ISO 8601 parsing as last resort
        begin
          return Time.parse_rfc3339(time_str)
        rescue
          nil
        end
      end

      private def truncate(str : String, max_length : Int32) : String
        if str.size > max_length
          str[0, max_length - 3] + "..."
        else
          str
        end
      end
    end
  end
end
