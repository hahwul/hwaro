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
        # Regex for matching h1-h6 tags with IDs to insert anchor links
        ANCHOR_LINK_REGEX = /<(h[1-6])([^>]*id="([^"]+)"[^>]*)>(.*?)<\/\1>/m
        # Regex for TOML front matter
        TOML_FRONT_MATTER_REGEX = /\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?(.*)\z/m

        # Regex for YAML front matter
        YAML_FRONT_MATTER_REGEX = /\A---\s*\n(.*?\n?)^---\s*$\n?(.*)\z/m

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
        # @param lazy_loading - if true, adds loading="lazy" to img tags
        def render(content : String, highlight : Bool = true, safe : Bool = false, lazy_loading : Bool = false) : Tuple(String, Array(Models::TocHeader))
          # Use SyntaxHighlighter for rendering with highlighting support
          html = SyntaxHighlighter.render(content, highlight, safe)

          has_headers = html.includes?("<h")
          has_images = lazy_loading && html.includes?("<img")

          # Optimization: If no headers and no images (or lazy loading disabled), don't parse XML
          unless has_headers || has_images
            return {html, [] of Models::TocHeader}
          end

          post_process_html(html, has_headers, has_images)
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
          template = nil
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
          sort_by = nil.as(String?)
          reverse = nil.as(Bool?)

          # New fields
          authors = [] of String
          extra = {} of String => String | Bool | Int64 | Float64 | Array(String)
          in_search_index = true
          insert_anchor_links = false
          page_template = nil.as(String?)
          paginate_path = "page"
          redirect_to = nil.as(String?)
          weight = 0

          # Try TOML Front Matter (+++)
          if match = raw_content.match(TOML_FRONT_MATTER_REGEX)
            begin
              toml_fm = TOML.parse(match[1])
              title = toml_fm["title"]?.try(&.as_s) || title
              description = toml_fm["description"]?.try(&.as_s)
              image = toml_fm["image"]?.try(&.as_s)
              is_draft = toml_fm["draft"]?.try(&.as_bool) || false
              template = toml_fm["template"]?.try(&.as_s)
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
              if toml_fm.has_key?("sort_by")
                sort_by = toml_fm["sort_by"].as_s
              end
              if toml_fm.has_key?("reverse")
                reverse = toml_fm["reverse"].as_bool
              end

              slug = toml_fm["slug"]?.try(&.as_s)
              custom_path = toml_fm["path"]?.try(&.as_s)

              if toml_fm.has_key?("aliases")
                aliases = toml_fm["aliases"].as_a.map(&.as_s)
              end

              # New fields parsing for TOML
              if toml_fm.has_key?("authors")
                authors = toml_fm["authors"].as_a.map(&.as_s)
              end
              if toml_fm.has_key?("in_search_index")
                in_search_index = toml_fm["in_search_index"].as_bool
              end
              if toml_fm.has_key?("insert_anchor_links")
                insert_anchor_links = toml_fm["insert_anchor_links"].as_bool
              end
              if toml_fm.has_key?("page_template")
                page_template = toml_fm["page_template"].as_s
              end
              if toml_fm.has_key?("paginate_path")
                paginate_path = toml_fm["paginate_path"].as_s
              end
              if toml_fm.has_key?("redirect_to")
                redirect_to = toml_fm["redirect_to"].as_s
              end
              if toml_fm.has_key?("weight")
                weight = toml_fm["weight"].as_i
              end

              # Extract extra fields (all keys not in known list)
              known_keys = ["title", "description", "image", "draft", "template", "in_sitemap",
                            "toc", "date", "updated", "render", "slug", "path", "aliases", "tags",
                            "transparent", "generate_feeds", "paginate", "pagination_enabled",
                            "sort_by", "reverse", "authors", "in_search_index", "insert_anchor_links",
                            "page_template", "paginate_path", "redirect_to", "weight", "categories"]
              toml_fm.each do |key, value|
                next if known_keys.includes?(key)
                extra[key] = extract_extra_value(value)
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
          elsif match = raw_content.match(YAML_FRONT_MATTER_REGEX)
            begin
              yaml_fm = YAML.parse(match[1])
              if yaml_fm.as_h?
                title = yaml_fm["title"]?.try(&.as_s?) || title
                description = yaml_fm["description"]?.try(&.as_s?)
                image = yaml_fm["image"]?.try(&.as_s?)
                is_draft = yaml_fm["draft"]?.try(&.as_bool?) || false
                template = yaml_fm["template"]?.try(&.as_s?)
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
                if (val = yaml_fm["sort_by"]?)
                  sort_by = val.as_s?
                end
                if (val = yaml_fm["reverse"]?)
                  bool_val = val.as_bool?
                  reverse = bool_val unless bool_val.nil?
                end

                slug = yaml_fm["slug"]?.try(&.as_s?)
                custom_path = yaml_fm["path"]?.try(&.as_s?)

                if (val = yaml_fm["aliases"]?)
                  aliases = val.as_a?.try { |a| a.map(&.as_s) } || [] of String
                end

                # New fields parsing for YAML
                if (val = yaml_fm["authors"]?)
                  authors = val.as_a?.try { |a| a.map(&.as_s) } || [] of String
                end
                if (val = yaml_fm["in_search_index"]?)
                  bool_val = val.as_bool?
                  in_search_index = bool_val unless bool_val.nil?
                end
                if (val = yaml_fm["insert_anchor_links"]?)
                  bool_val = val.as_bool?
                  insert_anchor_links = bool_val unless bool_val.nil?
                end
                if (val = yaml_fm["page_template"]?)
                  page_template = val.as_s?
                end
                if (val = yaml_fm["paginate_path"]?)
                  paginate_path = val.as_s? || "page"
                end
                if (val = yaml_fm["redirect_to"]?)
                  redirect_to = val.as_s?
                end
                if (val = yaml_fm["weight"]?)
                  int_val = val.as_i?
                  weight = int_val unless int_val.nil?
                end

                # Extract extra fields for YAML
                known_keys = ["title", "description", "image", "draft", "template", "in_sitemap",
                              "toc", "date", "updated", "render", "slug", "path", "aliases", "tags",
                              "transparent", "generate_feeds", "paginate", "pagination_enabled",
                              "sort_by", "reverse", "authors", "in_search_index", "insert_anchor_links",
                              "page_template", "paginate_path", "redirect_to", "weight", "categories"]
                if fm_hash = yaml_fm.as_h?
                  fm_hash.each do |key_any, value|
                    key = key_any.as_s?
                    next unless key
                    next if known_keys.includes?(key)
                    extra[key] = extract_extra_value_yaml(value)
                  end
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
            template:           template,
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
            sort_by:            sort_by,
            reverse:            reverse,
            # New fields
            authors:             authors,
            extra:               extra,
            in_search_index:     in_search_index,
            insert_anchor_links: insert_anchor_links,
            page_template:       page_template,
            paginate_path:       paginate_path,
            redirect_to:         redirect_to,
            weight:              weight,
          }
        end

        # Extract extra value from TOML::Any
        private def extract_extra_value(value : TOML::Any) : String | Bool | Int64 | Float64 | Array(String)
          if str = value.as_s?
            str
          elsif bool = value.as_bool?
            bool
          elsif int = value.as_i?
            int.to_i64
          elsif float = value.as_f?
            float
          elsif arr = value.as_a?
            arr.compact_map(&.as_s?)
          else
            value.to_s
          end
        end

        # Extract extra value from YAML::Any
        private def extract_extra_value_yaml(value : YAML::Any) : String | Bool | Int64 | Float64 | Array(String)
          if str = value.as_s?
            str
          elsif bool = value.as_bool?
            bool
          elsif int = value.as_i?
            int.to_i64
          elsif float = value.as_f?
            float
          elsif arr = value.as_a?
            arr.compact_map(&.as_s?)
          else
            value.to_s
          end
        end

        # Render with anchor links inserted into headings
        def render_with_anchors(content : String, highlight : Bool = true, safe : Bool = false, anchor_style : String = "heading", lazy_loading : Bool = false) : Tuple(String, Array(Models::TocHeader))
          html, toc = render(content, highlight, safe, lazy_loading)
          html_with_anchors = insert_anchor_links_to_html(html, anchor_style)
          {html_with_anchors, toc}
        end

        # Insert anchor links into headings
        # Note: This modifies the HTML string directly since XML node manipulation is limited
        private def insert_anchor_links_to_html(html : String, style : String = "heading") : String
          return html unless html.includes?("<h")

          result = html

          # Match h1-h6 tags with id attributes and insert anchor links
          result = result.gsub(ANCHOR_LINK_REGEX) do |match|
            tag = $1
            attrs = $2
            id = $3
            content = $4

            anchor = %(<a class="anchor" href="##{id}" aria-hidden="true">🔗</a>)

            new_content = case style
                          when "before"
                            "#{anchor} #{content}"
                          when "after"
                            "#{content} #{anchor}"
                          else
                            content
                          end

            "<#{tag}#{attrs}>#{new_content}</#{tag}>"
          end

          result
        end

        private def post_process_html(html : String, generate_toc : Bool, process_images : Bool) : Tuple(String, Array(Models::TocHeader))
          # XML.parse_html wraps content in <html><body>...</body></html>
          doc = XML.parse_html(html)
          body = doc.xpath_node("//body")

          return {html, [] of Models::TocHeader} unless body

          if process_images
            body.xpath_nodes("//img").each do |node|
              unless node["loading"]?
                node["loading"] = "lazy"
              end
            end
          end

          roots = [] of Models::TocHeader

          if generate_toc
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
      # @param lazy_loading - if true, adds loading="lazy" to img tags
      def render(content : String, highlight : Bool = true, safe : Bool = false, lazy_loading : Bool = false) : Tuple(String, Array(Models::TocHeader))
        @@instance.render(content, highlight, safe, lazy_loading)
      end

      # Returns parsed metadata and content
      def parse(raw_content : String, file_path : String = "")
        @@instance.parse(raw_content, file_path)
      end
    end
  end
end
