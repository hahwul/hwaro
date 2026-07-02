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
      # Keyed by (section path, language) so a multilingual site's per-language
      # `_index.<lang>.md` files don't collide — previously a single
      # `Hash(String, Section)` kept only the first-globbed language, making
      # section title/description/sort_by/page_template resolve to the wrong
      # language. Use `section_for(name, language)` to look up with fallback.
      property sections_by_name : Hash(Tuple(String, String?), Section)
      property pages_for_section_cache : Hash(Tuple(String, String?), Array(Page))
      @lookup_index_built : Bool = false
      @all_content_cache : Array(Page)?
      # Guards the lazy memo Hashes above: pages_for_section runs inside
      # parallel render fibers (render_section_with_pagination), and an
      # unsynchronized Hash insert there is undefined behavior under
      # -Dpreview_mt. Held only around cache reads/writes — not the compute —
      # so the transparent-section recursion can't self-deadlock; a racy
      # duplicate compute is harmless (both fibers store the same result).
      @memo_mutex : Mutex = Mutex.new

      def initialize(@config : Config)
        @pages = [] of Page
        @sections = [] of Section
        @taxonomies = {} of String => Hash(String, Array(Page))

        @data = {} of String => Crinja::Value
        @authors = {} of String => Crinja::Value

        @pages_by_section = {} of String => Array(Page)
        @sections_by_parent = {} of String => Array(Section)
        @sections_by_name = {} of Tuple(String, String?) => Section
        @pages_for_section_cache = {} of Tuple(String, String?) => Array(Page)
      end

      # Resolve a section by path for a given language, falling back to the
      # language-neutral (default-language) index when no language-specific
      # `_index.<lang>.md` exists, then to the configured default language.
      def section_for(name : String, language : String?) : Section?
        @sections_by_name[{name, language}]? ||
          @sections_by_name[{name, nil}]? ||
          @sections_by_name[{name, @config.default_language}]?
      end

      def taxonomy_terms(name : String) : Array(String)
        terms = @taxonomies[name]?
        return [] of String unless terms
        terms.keys.sort!
      end

      def taxonomy_pages(name : String, term : String) : Array(Page)
        @taxonomies[name]?.try(&.[term]?) || [] of Page
      end

      def all_content : Array(Page)
        @memo_mutex.synchronize do
          @all_content_cache ||= (pages + sections.map { |s| s.as(Page) }).sort_by!(&.path)
        end
      end

      def build_lookup_index
        @pages_by_section.clear
        @sections_by_parent.clear
        @sections_by_name.clear
        @pages_for_section_cache.clear
        @all_content_cache = nil

        @pages.each do |p|
          list = @pages_by_section[p.section]?
          unless list
            list = [] of Page
            @pages_by_section[p.section] = list
          end
          list << p
        end

        @sections.each do |s|
          # Index by (section name, language) for O(1) language-aware lookup
          @sections_by_name[{s.section, s.language}] ||= s

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

      def pages_for_section(section_name : String, language : String?, items : Array(Page)? = nil, visited : Set(String)? = nil) : Array(Page)
        # Normalize section name: remove leading/trailing slashes and handle root
        normalized_name = section_name.strip.strip('/')

        # Guard against infinite recursion from circular transparent sections
        seen = visited || Set(String).new
        return [] of Page if seen.includes?(normalized_name)
        seen.add(normalized_name)

        if @lookup_index_built && items.nil?
          cache_key = {normalized_name, language}
          if cached = @memo_mutex.synchronize { @pages_for_section_cache[cache_key]? }
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

                result.concat(pages_for_section(subsection_name, language, nil, seen))
              else
                # Non-transparent sections are included as Section (Page) objects
                result << s
              end
            end
          end

          @memo_mutex.synchronize { @pages_for_section_cache[cache_key] = result }
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
                result.concat(pages_for_section(p_dirname, language, content_items, seen))
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
