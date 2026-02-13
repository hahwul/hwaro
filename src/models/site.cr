require "crinja"
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

      # New properties for data and authors
      property data : Hash(String, Crinja::Value)
      property authors : Hash(String, Crinja::Value)

      # Lookup indices for performance
      property pages_by_section : Hash(String, Array(Page))
      property sections_by_parent : Hash(String, Array(Section))
      property pages_for_section_cache : Hash(Tuple(String, String?), Array(Page))
      @lookup_index_built : Bool = false

      def initialize(@config : Config)
        @pages = [] of Page
        @sections = [] of Section
        @taxonomies = {} of String => Hash(String, Array(Page))

        @data = {} of String => Crinja::Value
        @authors = {} of String => Crinja::Value

        @pages_by_section = {} of String => Array(Page)
        @sections_by_parent = {} of String => Array(Section)
        @pages_for_section_cache = {} of Tuple(String, String?) => Array(Page)
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

      def build_lookup_index
        @pages_by_section.clear
        @sections_by_parent.clear
        @pages_for_section_cache.clear

        @pages.each do |p|
          list = @pages_by_section[p.section]?
          unless list
            list = [] of Page
            @pages_by_section[p.section] = list
          end
          list << p
        end

        @sections.each do |s|
          # s.section is the section this object represents (e.g. "blog").
          # We want to index it by its PARENT section (e.g. "").
          current_section = s.section
          next if current_section.empty? # Root section has no parent

          parent_section = Path[current_section].parent.to_s
          parent_section = "" if parent_section == "."

          list = @sections_by_parent[parent_section]?
          unless list
            list = [] of Section
            @sections_by_parent[parent_section] = list
          end
          list << s
        end

        @lookup_index_built = true
      end

      def pages_for_section(section_name : String, language : String?, items : Array(Page)? = nil) : Array(Page)
        # Normalize section name: remove leading/trailing slashes and handle root
        normalized_name = section_name.strip.gsub(/^\/|\/$/, "")

        if @lookup_index_built && items.nil?
          cache_key = {normalized_name, language}
          if cached = @pages_for_section_cache[cache_key]?
            return cached
          end

          result = [] of Page

          # 1. Add direct pages
          if pages = @pages_by_section[normalized_name]?
            pages.each do |p|
              result << p if p.language == language
            end
          end

          # 2. Add subsections (handling transparency)
          if subsections = @sections_by_parent[normalized_name]?
            subsections.each do |s|
              next unless s.language == language

              if s.transparent
                # Recursive bubble up: get pages from this sub-section
                # The subsection name matches the directory of the section file
                subsection_name = Path[s.path].dirname.to_s
                subsection_name = "" if subsection_name == "."

                result.concat(pages_for_section(subsection_name, language))
              else
                # Non-transparent sections are included as Section (Page) objects
                result << s
              end
            end
          end

          @pages_for_section_cache[cache_key] = result
          return result
        end

        result = [] of Page

        # Initial call: filter by language and collect all content to improve performance
        content_items = items || all_content.select { |p| p.language == language }

        content_items.each do |p|
          if p.is_a?(Section)
            # p.path is relative to content/ (e.g., "blog/_index.md" or "blog/archive/_index.md")
            p_dirname = Path[p.path].dirname
            p_dirname = "" if p_dirname == "."

            # Skip the section's own index page
            next if p_dirname == normalized_name

            # Check if this section is a direct child of the target section
            parent_dir = Path[p_dirname].parent.to_s
            parent_dir = "" if parent_dir == "."

            if parent_dir == normalized_name
              if p.transparent
                # Recursive bubble up: get pages from this sub-section
                result.concat(pages_for_section(p_dirname, language, content_items))
              else
                # Non-transparent sections are included as Section (Page) objects
                result << p
              end
            end
          else
            # Regular Page (not a Section)
            # p.section is already normalized by the builder (e.g., "blog" or "blog/archive")
            if p.section == normalized_name
              result << p
            end
          end
        end

        result
      end
    end
  end
end
