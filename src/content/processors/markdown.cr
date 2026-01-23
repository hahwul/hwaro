# Markdown processor for converting Markdown to HTML
#
# This processor handles:
# - TOML and YAML front matter parsing
# - Markdown to HTML conversion using Markd
# - Table of Contents generation with header IDs
# - Syntax highlighting support via HighlightingRenderer

require "markd"
require "yaml"
require "toml"
require "xml"
require "./base"
require "./syntax_highlighter"
require "../../models/toc"
require "../../utils/logger"
require "../../utils/text_utils"

module Hwaro
  module Content
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
        # @param highlight - whether to enable syntax highlighting for code blocks
        # @param safe - if true, raw HTML will not be passed through (replaced by comments)
        def render(content : String, highlight : Bool = true, safe : Bool = false) : Tuple(String, Array(Models::TocHeader))
          # Use SyntaxHighlighter for rendering with highlighting support
          html = SyntaxHighlighter.render(content, highlight, safe)

          # Optimization: If no headers, don't parse XML
          unless html.includes?("<h")
            return {html, [] of Models::TocHeader}
          end

          process_html_headers(html)
        rescue ex
          # Fallback in case of XML parsing error
          {(html || ""), [] of Models::TocHeader}
        end

        # Returns parsed metadata and content
        def parse(raw_content : String, file_path : String = "")
          markdown_content = raw_content
          title = "Untitled"
          description = nil.as(String?)
          image = nil.as(String?)
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
          taxonomies = {} of String => Array(String)
          front_matter_keys = [] of String
          transparent = false
          generate_feeds = false
          paginate = nil.as(Int32?)
          pagination_enabled = nil.as(Bool?)

          # Try TOML Front Matter (+++)
          if match = raw_content.match(/\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?(.*)\z/m)
            begin
              toml_fm = TOML.parse(match[1])
              title = toml_fm["title"]?.try(&.as_s) || title
              description = toml_fm["description"]?.try(&.as_s)
              image = toml_fm["image"]?.try(&.as_s)
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

              # Section-specific pagination settings
              if toml_fm.has_key?("paginate")
                paginate = toml_fm["paginate"].as_i
              end
              if toml_fm.has_key?("pagination_enabled")
                pagination_enabled = toml_fm["pagination_enabled"].as_bool
              end

              slug = toml_fm["slug"]?.try(&.as_s)
              custom_path = toml_fm["path"]?.try(&.as_s)

              if toml_fm.has_key?("aliases")
                aliases = toml_fm["aliases"].as_a.map(&.as_s)
              end
              front_matter_keys = toml_fm.keys
              taxonomies = extract_taxonomies(toml_fm, front_matter_keys)
              if toml_fm.has_key?("tags")
                tags = toml_fm["tags"].as_a.map(&.as_s)
              end
              taxonomies["tags"] = tags if tags.any?
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
                description = yaml_fm["description"]?.try(&.as_s?)
                image = yaml_fm["image"]?.try(&.as_s?)
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

                # Section-specific pagination settings
                if (val = yaml_fm["paginate"]?)
                  int_val = val.as_i?
                  paginate = int_val unless int_val.nil?
                end

                if (val = yaml_fm["pagination_enabled"]?)
                  bool_val = val.as_bool?
                  pagination_enabled = bool_val unless bool_val.nil?
                end

                slug = yaml_fm["slug"]?.try(&.as_s?)
                custom_path = yaml_fm["path"]?.try(&.as_s?)

                if (val = yaml_fm["aliases"]?)
                  aliases = val.as_a?.try { |a| a.map(&.as_s) } || [] of String
                end

                front_matter_keys = yaml_fm.as_h?.try(&.keys).try { |ks| ks.compact_map(&.as_s?) } || [] of String
                taxonomies = extract_taxonomies(yaml_fm, front_matter_keys)
                if (val = yaml_fm["tags"]?)
                  tags = val.as_a?.try { |a| a.map(&.as_s) } || [] of String
                end
                taxonomies["tags"] = tags if tags.any?
              end
            rescue ex
              Logger.warn "  [WARN] Invalid YAML in #{file_path}: #{ex.message}" unless file_path.empty?
            end
            markdown_content = match[2]
          end

          {
            title:              title,
            description:        description,
            image:              image,
            content:            markdown_content,
            draft:              is_draft,
            layout:             layout,
            in_sitemap:         in_sitemap,
            toc:                toc,
            date:               date,
            updated:            updated,
            render:             render,
            slug:               slug,
            custom_path:        custom_path,
            aliases:            aliases,
            tags:               tags,
            taxonomies:         taxonomies,
            front_matter_keys:  front_matter_keys,
            transparent:        transparent,
            generate_feeds:     generate_feeds,
            paginate:           paginate,
            pagination_enabled: pagination_enabled,
          }
        end

        private def process_html_headers(html : String) : Tuple(String, Array(Models::TocHeader))
          # XML.parse_html wraps content in <html><body>...</body></html>
          doc = XML.parse_html(html)
          body = doc.xpath_node("//body")

          return {html, [] of Models::TocHeader} unless body

          headers = [] of {XML::Node, Models::TocHeader}
          roots = [] of Models::TocHeader
          stack = [] of Models::TocHeader

          # Iterate through h1-h6 tags
          body.xpath_nodes("//*[starts-with(name(), 'h') and string-length(name()) = 2]").each do |node|
            next unless node.name =~ /^h[1-6]$/

            level = node.name[1].to_i
            title = node.content

            # Generate ID
            existing_id = node["id"]?
            id = existing_id || Utils::TextUtils.slugify(title)

            unless existing_id
              node["id"] = id
            end

            permalink = "##{id}"

            toc_item = Models::TocHeader.new(
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
            "%Y-%m-%d",
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

        private def extract_taxonomies(front_matter : TOML::Table | YAML::Any, keys : Array(String)) : Hash(String, Array(String))
          taxonomies = {} of String => Array(String)

          if front_matter.is_a?(TOML::Table)
            front_matter.each do |key, value|
              next if key == "tags"
              # TOML values are wrapped in TOML::Any, need to check as_a?
              if arr = value.as_a?
                values = arr.compact_map { |v| v.as_s? }
                taxonomies[key] = values
              end
            end
          else
            if fm_hash = front_matter.as_h?
              fm_hash.each do |key_any, value|
                key = key_any.as_s?
                next unless key
                next if key == "tags"
                values = value.as_a?.try { |arr| arr.compact_map(&.as_s?) } || [] of String
                taxonomies[key] = values
              end
            end
          end

          keys.each do |key|
            next if key == "tags"
            next if taxonomies.has_key?(key)
            taxonomies[key] = [] of String
          end

          taxonomies
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
      @@instance = Content::Processors::Markdown.new

      # Renders Markdown to HTML and generates a Table of Contents
      # @param highlight - whether to enable syntax highlighting for code blocks
      # @param safe - if true, raw HTML will not be passed through (replaced by comments)
      def render(content : String, highlight : Bool = true, safe : Bool = false) : Tuple(String, Array(Models::TocHeader))
        @@instance.render(content, highlight, safe)
      end

      # Returns parsed metadata and content
      def parse(raw_content : String, file_path : String = "")
        @@instance.parse(raw_content, file_path)
      end
    end
  end
end
