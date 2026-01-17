module Hwaro
  module Schemas
    class Page
      # Front Matter Properties
      property title : String
      property description : String?
      property date : Time?
      property template : String?
      property draft : Bool
      property tags : Array(String)
      property weight : Int32

      # Runtime / Computed Properties
      property content : String
      property raw_content : String
      property path : String       # Relative path from content/ (e.g. "projects/a.md")
      property section : String    # First directory component (e.g. "projects")
      property url : String        # Calculated relative URL (e.g. "/projects/a/")
      property is_index : Bool     # Is this an index file?

      def initialize(@path : String)
        @title = "Untitled"
        @draft = false
        @tags = [] of String
        @weight = 0
        @content = ""
        @raw_content = ""
        @section = ""
        @url = ""
        @is_index = false
      end
    end
  end
end
