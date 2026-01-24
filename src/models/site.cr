require "./config"
require "./page"
require "./section"

module Hwaro
  module Models
    class Site
      property config : Config
      property pages : Array(Page)
      property sections : Array(Section)
      property taxonomies : Hash(String, Hash(String, Array(Page)))

      def initialize(@config : Config)
        @pages = [] of Page
        @sections = [] of Section
        @taxonomies = {} of String => Hash(String, Array(Page))
      end

      def taxonomy_terms(name : String) : Array(String)
        terms = @taxonomies[name]?
        return [] of String unless terms
        terms.keys.sort
      end

      def taxonomy_pages(name : String, term : String) : Array(Page)
        @taxonomies[name]?.try(&.[term]?) || [] of Page
      end
    end
  end
end
