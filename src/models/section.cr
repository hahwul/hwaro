require "./page"

module Hwaro
  module Models
    class Section < Page
      # Section-specific Front Matter Properties
      property paginate : Int32?          # Override per_page count for this section
      property pagination_enabled : Bool? # Override pagination enabled/disabled for this section
      property sort_by : String?          # e.g., "date", "weight", "title"
      property reverse : Bool?
      property transparent : Bool
      property generate_feeds : Bool

      # New: Page template - default template for pages in this section
      property page_template : String?

      # New: Paginate path - custom path pattern for pagination (e.g., "page", "p")
      property paginate_path : String

      # New: Redirect to - URL to redirect this section to
      property redirect_to : String?

      # Pages in this section
      property pages : Array(Page) = [] of Page

      # New: Subsections - child sections
      property subsections : Array(Section)

      # New: Assets - static files in this section directory
      property assets : Array(String)

      def initialize(path : String)
        super(path)
        @transparent = false
        @generate_feeds = false
        @page_template = nil
        @paginate_path = "page"
        @redirect_to = nil
        @subsections = [] of Section
        @assets = [] of String
      end

      # Check if section has redirect
      def has_redirect? : Bool
        !@redirect_to.nil? && !@redirect_to.try(&.empty?)
      end

      # Get effective page template (for pages in this section)
      def effective_page_template : String?
        @page_template
      end

      # Collect assets from section directory
      def collect_assets(content_dir : String) : Array(String)
        section_dir = File.join(content_dir, @section)
        return [] of String unless Dir.exists?(section_dir)

        @assets = Dir.glob(File.join(section_dir, "*")).select do |file|
          File.file?(file) && !file.ends_with?(".md") && !file.ends_with?(".markdown")
        end.map do |file|
          File.basename(file)
        end

        @assets
      end

      # Add a subsection
      def add_subsection(section : Section)
        @subsections << section
      end

      # Find subsection by name
      def find_subsection(name : String) : Section?
        @subsections.find { |s| s.section == name || s.title.downcase == name.downcase }
      end

      # Get all pages including from subsections (recursive)
      def all_pages(include_drafts : Bool = false) : Array(Page)
        result = include_drafts ? @pages.dup : @pages.reject(&.draft)

        @subsections.each do |subsection|
          result.concat(subsection.all_pages(include_drafts))
        end

        result
      end

      # Generate pagination URL for a specific page number
      def pagination_url(page_number : Int32) : String
        base = @url.rstrip("/")
        if page_number == 1
          "#{base}/"
        else
          "#{base}/#{@paginate_path}/#{page_number}/"
        end
      end
    end
  end
end
