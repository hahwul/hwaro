require "./page"

module Hwaro
  module Models
    class Section < Page
      # Section-specific Front Matter Properties
      property paginate : Int32?
      property sort_by : String? # e.g., "date", "weight", "title"
      property reverse : Bool?
      property transparent : Bool
      property generate_feeds : Bool

      def initialize(path : String)
        super(path)
        @transparent = false
        @generate_feeds = false
      end
    end
  end
end
