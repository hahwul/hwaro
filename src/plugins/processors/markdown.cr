# Markdown processor for converting Markdown to HTML
#
# This processor handles:
# - TOML and YAML front matter parsing
# - Markdown to HTML conversion using Markd
# - Table of Contents generation with header IDs

require "markd"
require "yaml"
require "toml"
require "xml"
require "./base"
require "../../schemas/toc"
require "../../utils/logger"

module Hwaro
  module Plugins
    module Processors
      # Markdown processor implementation
      class Markdown < Base
        def name : String
          "markdown"
        end

        def extensions : Array(String)
          [".md", ".markdown"]
        end

        def priority : Int32
          100 # High priority as primary content processor
        end

        def process(content : String, context : ProcessorContext) : ProcessorResult
          html, _toc = render(content)
          ProcessorResult.new(content: html)
        rescue ex
          ProcessorResult.error("Markdown processing failed: #{ex.message}")
        end

        # Renders Markdown to HTML and generates a Table of Contents
        # Returns {html_content, toc_headers}
        def render(content : String) : Tuple(String, Array(Schemas::TocHeader))
          html = Markd.to_html(content)

          # Optimization: If no headers, don't parse XML
          unless html.includes?("<h")
            return {html, [] of Schemas::TocHeader}
          end

          process_html_headers(html)
        rescue ex
          # Fallback in case of XML parsing error
          {(html || ""), [] of Schemas::TocHeader}
        end

        # Returns parsed metadata and content
        def parse(raw_content : String, file_path : String = "")
          markdown_content = raw_content
          title = "Untitled"
          is_draft = false
          layout = nil
          in_sitemap = true
          toc = false
          date = nil
          updated = nil
          render = true
          slug = nil
          custom_path = nil
          aliases = [] of String
          tags = [] of String
          transparent = false
          generate_feeds = false

          # Try TOML Front Matter (+++)
          if match = raw_content.match(/\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?(.*)\z/m)
            begin
              toml_fm = TOML.parse(match[1])
              title = toml_fm["title"]?.try(&.as_s) || title
              is_draft = toml_fm["draft"]?.try(&.as_bool) || false
              layout = toml_fm["layout"]?.try(&.as_s)
              if toml_fm.has_key?("in_sitemap")
                in_sitemap = toml_fm["in_sitemap"].as_bool
              end
              toc = toml_fm["toc"]?.try(&.as_bool) || false

              date = parse_time(toml_fm["date"]?.try(&.as_s))
              updated = parse_time(toml_fm["updated"]?.try(&.as_s))

              if toml_fm.has_key?("render")
                render = toml_fm["render"].as_bool
              end

              if toml_fm.has_key?("transparent")
                transparent = toml_fm["transparent"].as_bool
              end
              if toml_fm.has_key?("generate_feeds")
                generate_feeds = toml_fm["generate_feeds"].as_bool
              end

              slug = toml_fm["slug"]?.try(&.as_s)
              custom_path = toml_fm["path"]?.try(&.as_s)

              if toml_fm.has_key?("aliases")
                aliases = toml_fm["aliases"].as_a.map(&.as_s)
              end
              if toml_fm.has_key?("tags")
                tags = toml_fm["tags"].as_a.map(&.as_s)
              end
            rescue ex
              Logger.warn "  [WARN] Invalid TOML in #{file_path}: #{ex.message}" unless file_path.empty?
            end
            markdown_content = match[2]
          # Try YAML Front Matter (---)
          elsif match = raw_content.match(/\A---\s*\n(.*?\n?)^---\s*$\n?(.*)\z/m)
            begin
              yaml_fm = YAML.parse(match[1])
              if yaml_fm.as_h?
                title = yaml_fm["title"]?.try(&.as_s?) || title
                is_draft = yaml_fm["draft"]?.try(&.as_bool?) || false
                layout = yaml_fm["layout"]?.try(&.as_s?)
                if (val = yaml_fm["in_sitemap"]?)
                  bool_val = val.as_bool?
                  in_sitemap = bool_val unless bool_val.nil?
                end
                toc = yaml_fm["toc"]?.try(&.as_bool?) || false

                date = parse_time(yaml_fm["date"]?.try(&.as_s?))
                updated = parse_time(yaml_fm["updated"]?.try(&.as_s?))

                if (val = yaml_fm["render"]?)
                  bool_val = val.as_bool?
                  render = bool_val unless bool_val.nil?
                end

                if (val = yaml_fm["transparent"]?)
                  bool_val = val.as_bool?
                  transparent = bool_val unless bool_val.nil?
                end

                if (val = yaml_fm["generate_feeds"]?)
                  bool_val = val.as_bool?
                  generate_feeds = bool_val unless bool_val.nil?
                end

                slug = yaml_fm["slug"]?.try(&.as_s?)
                custom_path = yaml_fm["path"]?.try(&.as_s?)

                if (val = yaml_fm["aliases"]?)
                  aliases = val.as_a?.try { |a| a.map(&.as_s) } || [] of String
                end

                if (val = yaml_fm["tags"]?)
                  tags = val.as_a?.try { |a| a.map(&.as_s) } || [] of String
                end
              end
            rescue ex
              Logger.warn "  [WARN] Invalid YAML in #{file_path}: #{ex.message}" unless file_path.empty?
            end
            markdown_content = match[2]
          end

          {
            title: title,
            content: markdown_content,
            draft: is_draft,
            layout: layout,
            in_sitemap: in_sitemap,
            toc: toc,
            date: date,
            updated: updated,
            render: render,
            slug: slug,
            custom_path: custom_path,
            aliases: aliases,
            tags: tags,
            transparent: transparent,
            generate_feeds: generate_feeds
          }
        end

        private def process_html_headers(html : String) : Tuple(String, Array(Schemas::TocHeader))
          # XML.parse_html wraps content in <html><body>...</body></html>
          doc = XML.parse_html(html)
          body = doc.xpath_node("//body")

          return {html, [] of Schemas::TocHeader} unless body

          headers = [] of {XML::Node, Schemas::TocHeader}
          roots = [] of Schemas::TocHeader
          stack = [] of Schemas::TocHeader

          # Iterate through h1-h6 tags
          body.xpath_nodes("//*[starts-with(name(), 'h') and string-length(name()) = 2]").each do |node|
            next unless node.name =~ /^h[1-6]$/

            level = node.name[1].to_i
            title = node.content

            # Generate ID
            existing_id = node["id"]?
            id = existing_id || slugify(title)

            unless existing_id
              node["id"] = id
            end

            permalink = "##{id}"

            toc_item = Schemas::TocHeader.new(
              level: level,
              id: id,
              title: title,
              permalink: permalink
            )

            # Build Tree
            while stack.any? && stack.last.level >= level
              stack.pop
            end

            if stack.empty?
              roots << toc_item
            else
              stack.last.children << toc_item
            end
            stack.push(toc_item)
          end

          final_html = body.children.map(&.to_xml).join

          {final_html, roots}
        end

        private def parse_time(time_str : String?) : Time?
          return nil unless time_str

          formats = [
            "%Y-%m-%d %H:%M:%S",
            "%Y-%m-%dT%H:%M:%S",
            "%Y-%m-%d"
          ]

          formats.each do |fmt|
            begin
              return Time.parse(time_str, fmt, Time::Location.local)
            rescue
              next
            end
          end

          # Try ISO 8601 parsing as last resort
          begin
             return Time.parse_rfc3339(time_str)
          rescue
             nil
          end
        end

        private def slugify(text : String) : String
          text.downcase
              .gsub(/[^a-z0-9\s-]/, "") # Remove non-alphanumeric chars except space and hyphen
              .gsub(/\s+/, "-")         # Replace spaces with hyphens
              .strip("-")               # Trim leading/trailing hyphens
        end
      end

      # Register the markdown processor by default
      Registry.register(Markdown.new)
    end
  end
end

# Backward compatibility module alias
module Hwaro
  module Processor
    module Markdown
      extend self

      # Create shared instance for module-level access
      @@instance = Plugins::Processors::Markdown.new

      # Renders Markdown to HTML and generates a Table of Contents
      def render(content : String) : Tuple(String, Array(Schemas::TocHeader))
        @@instance.render(content)
      end

      # Returns parsed metadata and content
      def parse(raw_content : String, file_path : String = "")
        @@instance.parse(raw_content, file_path)
      end
    end
  end
end
