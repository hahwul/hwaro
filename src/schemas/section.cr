require "./page"

module Hwaro
  module Schemas
    class Section < Page
      # Section-specific Front Matter Properties
      property paginate : Int32?
      property sort_by : String? # e.g., "date", "weight", "title"
      property reverse : Bool?

      def initialize(path : String)
        super(path)
      end
    end
  end
end
