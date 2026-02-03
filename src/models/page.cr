module Hwaro
  module Models
    struct TranslationLink
      property code : String
      property url : String
      property title : String
      property is_current : Bool
      property is_default : Bool

      def initialize(
        @code : String,
        @url : String,
        @title : String,
        @is_current : Bool = false,
        @is_default : Bool = false,
      )
      end
    end

    class Page
      # Front Matter Properties
      property title : String
      property description : String?
      property date : Time?
      property updated : Time?
      property template : String?
      property draft : Bool
      property render : Bool
      property slug : String?
      property custom_path : String?
      property aliases : Array(String)
      property tags : Array(String)
      property taxonomies : Hash(String, Array(String))
      property front_matter_keys : Array(String)
      property weight : Int32
      property taxonomy_name : String?
      property taxonomy_term : String?
      property in_sitemap : Bool
      property toc : Bool
      property generated : Bool
      property image : String?

      # New: Assets - static files in this page directory
      property assets : Array(String)

      # New: Authors field (array of author names)
      property authors : Array(String)

      # New: Extra field for arbitrary custom metadata from front matter
      property extra : Hash(String, String | Bool | Int64 | Float64 | Array(String))

      # New: Summary - content before <!-- more --> marker or auto-generated
      property summary : String?

      # New: In search index - whether to include in search index
      property in_search_index : Bool

      # New: Insert anchor links - whether to add anchor links to headings
      property insert_anchor_links : Bool

      # Runtime / Computed Properties
      property content : String
      property raw_content : String
      property path : String      # Relative path from content/ (e.g. "projects/a.md")
      property section : String   # First directory component (e.g. "projects")
      property url : String       # Calculated relative URL (e.g. "/projects/a/")
      property is_index : Bool    # Is this an index file?
      property language : String? # Language code (e.g. "en", "ko", nil for default)
      property translations : Array(TranslationLink)

      # New: Word count and reading time (computed)
      property word_count : Int32
      property reading_time : Int32 # in minutes

      # New: Permalink (absolute URL with base_url)
      property permalink : String?

      # New: Lower/Higher page references (previous/next in section)
      property lower : Page?  # Previous page (by date or weight)
      property higher : Page? # Next page (by date or weight)

      # New: Ancestors - parent sections chain
      property ancestors : Array(Page)

      def initialize(@path : String)
        @title = "Untitled"
        @draft = false
        @render = true
        @tags = [] of String
        @aliases = [] of String
        @taxonomies = {} of String => Array(String)
        @front_matter_keys = [] of String
        @weight = 0
        @taxonomy_name = nil
        @taxonomy_term = nil
        @generated = false
        @image = nil
        @content = ""
        @raw_content = ""
        @section = ""
        @url = ""
        @is_index = false
        @in_sitemap = true
        @toc = false
        @language = nil
        @translations = [] of TranslationLink
        @assets = [] of String

        # New field defaults
        @authors = [] of String
        @extra = {} of String => String | Bool | Int64 | Float64 | Array(String)
        @summary = nil
        @in_search_index = true
        @insert_anchor_links = false
        @word_count = 0
        @reading_time = 0
        @permalink = nil
        @lower = nil
        @higher = nil
        @ancestors = [] of Page
      end

      # Collect assets from page directory
      def collect_assets(content_dir : String) : Array(String)
        # Assets are only collected for page bundles (directories)
        # This usually means the page is an index.md (either _index.md or index.md)
        return [] of String unless @is_index

        # So we construct the directory path.
        page_dir = File.dirname(File.join(content_dir, @path))

        return [] of String unless Dir.exists?(page_dir)

        @assets = Dir.glob(File.join(page_dir, "**", "*")).select do |file|
          File.file?(file) &&
            !file.ends_with?(".md") &&
            !file.ends_with?(".markdown")
        end.map do |file|
          Path[file].relative_to(content_dir).to_s
        end

        @assets
      end

      # Calculate word count from raw content (excluding front matter)
      def calculate_word_count : Int32
        # Remove front matter
        content_only = @raw_content.gsub(/\A(\+\+\+|---)\s*\n.*?\n\1\s*\n/m, "")
        # Remove HTML tags
        content_only = content_only.gsub(/<[^>]+>/, " ")
        # Remove markdown syntax elements
        content_only = content_only.gsub(/[#*_`\[\]()~>|]/, " ")
        # Split by whitespace and count non-empty words
        words = content_only.split(/\s+/).reject(&.empty?)
        @word_count = words.size
        @word_count
      end

      # Calculate reading time in minutes (assuming ~200 words per minute)
      def calculate_reading_time(words_per_minute : Int32 = 200) : Int32
        calculate_word_count if @word_count == 0
        @reading_time = (@word_count.to_f / words_per_minute).ceil.to_i
        @reading_time = 1 if @reading_time < 1 && @word_count > 0
        @reading_time
      end

      # Extract summary from content using <!-- more --> marker
      # Returns content before the marker, or nil if no marker found
      def extract_summary : String?
        # Check for <!-- more --> marker in raw content
        if match = @raw_content.match(/\A(\+\+\+|---)\s*\n.*?\n\1\s*\n(.*?)<!--\s*more\s*-->/mi)
          summary_md = match[2].strip
          @summary = summary_md unless summary_md.empty?
        elsif match = @raw_content.match(/\A(.*?)<!--\s*more\s*-->/mi)
          # No front matter case
          summary_md = match[1].strip
          @summary = summary_md unless summary_md.empty?
        end
        @summary
      end

      # Generate permalink (absolute URL)
      def generate_permalink(base_url : String) : String
        base = base_url.rstrip("/")
        path = @url.starts_with?("/") ? @url : "/#{@url}"
        @permalink = "#{base}#{path}"
        @permalink.not_nil!
      end

      # Check if page has summary (either from <!-- more --> or description)
      def has_summary? : Bool
        !@summary.nil? || !@description.nil?
      end

      # Get effective summary (summary or description fallback)
      def effective_summary : String?
        @summary || @description
      end
    end
  end
end
