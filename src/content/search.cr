require "../models/page"
require "../models/config"
require "../utils/logger"
require "./processors/markdown"
require "json"

module Hwaro
  module Content
    class Search
      def self.generate(pages : Array(Models::Page), config : Models::Config, output_dir : String, verbose : Bool = false)
        return unless config.search.enabled

        # Filter out draft pages and pages with in_search_index = false
        search_pages = pages.reject { |p| p.draft || !p.in_search_index }

        if search_pages.empty?
          Logger.info "  No pages to include in search index."
          return
        end

        # Build search data based on format
        search_data = build_search_data(search_pages, config)

        # Both libraries use the same array for now, so Hwaro generates a common format and lets the client build the index.
        # We've kept the names distinct to respect user intent and stay ready for library-specific optimizations later.
        content = case config.search.format.downcase
                  when "fuse_javascript"
                    generate_javascript(search_data)
                  when "fuse_json"
                    generate_json(search_data)
                  when "elasticlunr_json"
                    generate_json(search_data)
                  when "elasticlunr_javascript"
                    generate_javascript(search_data)
                  else
                    Logger.warn "  [WARN] Unknown search format '#{config.search.format}'. Defaulting to 'fuse_json'."
                    generate_json(search_data)
                  end

        # Write search file
        filename = config.search.filename
        search_path = File.join(output_dir, filename)
        File.write(search_path, content)
        Logger.action :create, search_path if verbose
        Logger.info "  Generated search index with #{search_pages.size} pages."
      end

      private def self.build_search_data(pages : Array(Models::Page), config : Models::Config) : Array(Hash(String, String | Array(String)))
        fields = config.search.fields

        pages.map do |page|
          data = {} of String => String | Array(String)

          fields.each do |field|
            case field.downcase
            when "title"
              data["title"] = page.title
            when "content"
              # Convert markdown to plain text
              # Optimization: Reuse rendered content if available
              if !page.content.empty?
                html_content = page.content
              else
                html_content, _ = Processor::Markdown.render(page.raw_content)
              end

              # Strip HTML tags to get plain text
              text_content = html_content.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
              data["content"] = text_content
            when "tags"
              data["tags"] = page.tags
            when "url"
              data["url"] = page.url
            when "section"
              data["section"] = page.section
            when "description"
              data["description"] = page.description || ""
            end
          end

          # Always include URL even if not in fields list
          data["url"] = page.url unless data.has_key?("url")

          data
        end
      end

      private def self.generate_json(search_data : Array(Hash(String, String | Array(String)))) : String
        search_data.to_json
      end

      private def self.generate_javascript(search_data : Array(Hash(String, String | Array(String)))) : String
        json_data = search_data.to_json
        "var searchData = #{json_data};"
      end
    end
  end
end
