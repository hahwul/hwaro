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

      def pages_for_section(section_name : String, language : String?, items : Array(Page)? = nil) : Array(Page)
        result = [] of Page
        # Normalize section name: remove leading/trailing slashes and handle root
        normalized_name = section_name.strip.gsub(/^\/|\/$/, "")

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
