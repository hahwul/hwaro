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

      # Front-matter [cascade] table: default values inherited by descendant
      # pages and sections (the section itself is not affected). Deeper
      # cascades override shallower ones; a page's own front matter always wins.
      property cascade : Hash(String, ExtraValue)

      # New: Paginate path - custom path pattern for pagination (e.g., "page", "p")
      property paginate_path : String

      # Pages in this section
      property pages : Array(Page) = [] of Page

      # New: Subsections - child sections
      property subsections : Array(Section)

      def initialize(path : String)
        super(path)
        @transparent = false
        @generate_feeds = false
        @page_template = nil
        @paginate_path = "page"
        @subsections = [] of Section
        @cascade = {} of String => ExtraValue
      end

      # Add a subsection
      def add_subsection(section : Section)
        @subsections << section
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
