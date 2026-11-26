require "./page"

module Hwaro
  module Models
    class Section < Page
      # Section-specific Front Matter Properties
      property paginate : Int32?          # Override per_page count for this section
      property pagination_enabled : Bool? # Override pagination enabled/disabled for this section
      property sort_by : String?          # e.g., "date", "published", "weight", "title"
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

      # `paginate_path` as it appears in the pager URLs (`paginator.next`,
      # the nav, `<link rel="next">`): escaped like `page.url`, so a `#` or
      # `?` in it (`paginate_path = "p#2"`) no longer ends the path and links
      # `/blog/p`. The pager pages themselves are still written under the raw
      # `paginate_path` directory, which the escaped URL addresses.
      def paginate_url_path : String
        Page.url_form(@paginate_path)
      end

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
    end
  end
end
