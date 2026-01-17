require "./config"
require "./page"
require "./section"

module Hwaro
  module Schemas
    class Site
      property config : Config
      property pages : Array(Page)
      property sections : Array(Section)

      def initialize(@config : Config)
        @pages = [] of Page
        @sections = [] of Section
      end
    end
  end
end
