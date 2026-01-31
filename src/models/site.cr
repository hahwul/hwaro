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

        # 1. Get direct pages (excluding index pages)
        content_list.each do |p|
          next unless p.language == language
          next if p.is_index

          # Use path-based check to determine if the page belongs directly to this section
          p_dir = Path[p.path].dirname
          p_dir = "" if p_dir == "."

          if p_dir == section_name
            effective_pages << p
          end
        end

        # 2. Find subsections
        sections.each do |s|
          next unless s.language == language

          s_dir = Path[s.path].dirname
          s_dir = "" if s_dir == "."

          # Skip if it's the section itself
          next if s_dir == section_name

          next unless is_direct_subsection?(s_dir, section_name)

          if s.transparent
            # If transparent, include its pages recursively
            effective_pages.concat(pages_for_section(s_dir, language, content_list))
          end
          # Note: Non-transparent subsections are NOT added to the pages list
          # as requested by the user ("articles like 2025 should not be included").
        end

        effective_pages
      end

      # Check if a directory is a direct subdirectory of another
      private def is_direct_subsection?(sub_dir : String, parent_dir : String) : Bool
        if parent_dir.empty?
          !sub_dir.empty? && !sub_dir.includes?("/")
        else
          sub_dir.starts_with?("#{parent_dir}/") && !sub_dir.sub("#{parent_dir}/", "").includes?("/")
        end
      end
    end
  end
end
