module Hwaro
  module Models
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
      property weight : Int32
      property in_sitemap : Bool
      property toc : Bool

      # Runtime / Computed Properties
      property content : String
      property raw_content : String
      property path : String    # Relative path from content/ (e.g. "projects/a.md")
      property section : String # First directory component (e.g. "projects")
      property url : String     # Calculated relative URL (e.g. "/projects/a/")
      property is_index : Bool  # Is this an index file?

      def initialize(@path : String)
        @title = "Untitled"
        @draft = false
        @render = true
        @tags = [] of String
        @aliases = [] of String
        @weight = 0
        @content = ""
        @raw_content = ""
        @section = ""
        @url = ""
        @is_index = false
        @in_sitemap = true
        @toc = false
      end
    end
  end
end
