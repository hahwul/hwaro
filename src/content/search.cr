require "../models/page"
require "../models/config"
require "../utils/logger"
require "../utils/text_utils"
require "./processors/markdown"
require "json"
require "uri"

module Hwaro
  module Content
    class Search
      def self.generate(pages : Array(Models::Page), config : Models::Config, output_dir : String, verbose : Bool = false, skip_if_unchanged : Bool = false)
        return unless config.search.enabled

        if skip_if_unchanged
          search_path = File.join(output_dir, File.basename(config.search.filename))
          if File.exists?(search_path)
            Logger.debug "  Search index unchanged (cache hit), skipping."
            return
          end
        end

        # Filter out draft pages and pages with in_search_index = false
        search_pages = pages.reject { |p| p.draft || !p.in_search_index }

        # Deduplicate by URL (keep last occurrence, matching build behavior)
        seen_urls = Set(String).new
        search_pages = search_pages.reverse.select { |p| seen_urls.add?(p.url) }.reverse!

        # Filter out excluded paths
        unless config.search.exclude.empty?
          excluded_paths = config.search.exclude.map do |path|
            path.starts_with?('/') ? path : "/#{path}"
          end

          search_pages.reject! do |page|
            page_url = page.url.starts_with?('/') ? page.url : "/#{page.url}"
            excluded_paths.any? { |excluded| page_url == excluded || page_url.starts_with?(excluded.ends_with?("/") ? excluded : excluded + "/") }
          end
        end

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
                    Logger.warn "Unknown search format '#{config.search.format}'. Defaulting to 'fuse_json'."
                    generate_json(search_data)
                  end

        # Write search file
        filename = File.basename(config.search.filename)
        search_path = File.join(output_dir, filename)
        File.write(search_path, content)
        Logger.action :create, search_path if verbose
        Logger.info "  Generated search index with #{search_pages.size} pages."
      end

      private def self.build_search_data(pages : Array(Models::Page), config : Models::Config) : Array(Hash(String, String | Array(String)))
        # Pre-lowercase field names once instead of per-page per-field
        fields = config.search.fields.map(&.downcase)
        cjk = config.search.tokenize_cjk

        # Extract base path from base_url for subpath deployments
        base_path = if config.base_url.empty?
                      ""
                    else
                      URI.parse(config.base_url).path.rstrip("/")
                    end

        pages.map do |page|
          data = {} of String => String | Array(String)

          fields.each do |field|
            case field
            when "title"
              title = Utils::TextUtils.strip_html(page.title)
              data["title"] = cjk ? Utils::TextUtils.tokenize_cjk(title) : title
            when "content"
              # Convert markdown to plain text
              # Optimization: Reuse rendered content if available
              if !page.content.empty?
                html_content = page.content
              else
                html_content, _ = Processor::Markdown.render(page.raw_content)
              end

              # Strip HTML tags to get plain text
              text_content = Utils::TextUtils.strip_html(html_content)
              data["content"] = cjk ? Utils::TextUtils.tokenize_cjk(text_content) : text_content
            when "tags"
              data["tags"] = page.tags
            when "url"
              data["url"] = base_path + page.url
            when "section"
              data["section"] = page.section
            when "description"
              desc = page.description || ""
              data["description"] = cjk ? Utils::TextUtils.tokenize_cjk(desc) : desc
            end
          end

          # Always include URL even if not in fields list
          data["url"] = base_path + page.url unless data.has_key?("url")

          data
        end
      end

      private def self.generate_json(search_data : Array(Hash(String, String | Array(String)))) : String
        search_data.to_json
      end

      private def self.generate_javascript(search_data : Array(Hash(String, String | Array(String)))) : String
        json_str = search_data.to_json
        # Avoid double-alloc: skip gsub when no </script> escape is needed (common case)
        if json_str.includes?("</")
          "var searchData = #{json_str.gsub("</", "<\\/")};"
        else
          "var searchData = #{json_str};"
        end
      end
    end
  end
end
