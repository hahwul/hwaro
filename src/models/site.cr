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

      def all_content : Array(Page)
        (pages + sections.map { |s| s.as(Page) }).sort_by! { |p| p.path }
      end

      # Get all pages belonging to a section, including those from transparent sub-sections
      def pages_for_section(section_name : String, language : String?) : Array(Page)
        pages_for_section(section_name, language, all_content)
      end

      # Overloaded version that takes a pre-calculated content list for efficiency
      def pages_for_section(section_name : String, language : String?, content_list : Array(Page)) : Array(Page)
        effective_pages = [] of Page

        # 1. Get direct pages (excluding index pages of this section)
        content_list.each do |p|
          next unless p.language == language
          if p.section == section_name
            if p.is_index
              next
            end
            effective_pages << p
          end
        end

        # 2. Find subsections
        sections.each do |s|
          next unless s.language == language
          next unless is_direct_subsection?(s.section, section_name)

          if s.transparent
            # If transparent, include its pages recursively
            effective_pages.concat(pages_for_section(s.section, language, content_list))
          else
            # If not transparent, include the section index itself as an item
            effective_pages << s
          end
        end

        effective_pages
      end

      # Check if a section is a direct subsection of another
      private def is_direct_subsection?(sub : String, parent : String) : Bool
        if parent.empty?
          !sub.empty? && !sub.includes?("/")
        else
          sub.starts_with?("#{parent}/") && !sub.sub("#{parent}/", "").includes?("/")
        end
      end
    end
  end
end
