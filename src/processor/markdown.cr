require "markd"
require "yaml"
require "toml"
require "xml"
require "../schemas/toc"

module Hwaro
  module Processor
    module Markdown
      extend self

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

      # Returns {title, content, draft, layout, in_sitemap, toc}
      def parse(raw_content : String, file_path : String = "") : Tuple(String, String, Bool, String?, Bool, Bool)?
        markdown_content = raw_content
        title = "Untitled"
        is_draft = false
        layout = nil
        in_sitemap = true
        toc = false

        # Try TOML Front Matter (+++)
        if match = raw_content.match(/\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?(.*)\z/m)
          begin
            toml_fm = TOML.parse(match[1])
            title = toml_fm["title"]?.try(&.as_s) || title
            is_draft = toml_fm["draft"]?.try(&.as_bool) || false
            layout = toml_fm["layout"]?.try(&.as_s)
            in_sitemap = toml_fm["in_sitemap"]?.try(&.as_bool) || true
            toc = toml_fm["toc"]?.try(&.as_bool) || false
          rescue ex
            puts "  [WARN] Invalid TOML in #{file_path}: #{ex.message}" unless file_path.empty?
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
              in_sitemap = yaml_fm["in_sitemap"]?.try(&.as_bool?) || true
              toc = yaml_fm["toc"]?.try(&.as_bool?) || false
            end
          rescue ex
            puts "  [WARN] Invalid YAML in #{file_path}: #{ex.message}" unless file_path.empty?
          end
          markdown_content = match[2]
        end

        {title, markdown_content, is_draft, layout, in_sitemap, toc}
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
        # Note: We select them in document order
        body.xpath_nodes("//*[starts-with(name(), 'h') and string-length(name()) = 2]").each do |node|
          next unless node.name =~ /^h[1-6]$/

          level = node.name[1].to_i
          title = node.content

          # Generate ID
          existing_id = node["id"]?
          id = existing_id || slugify(title)

          # Ensure ID uniqueness could be handled here if needed,
          # but sticking to simple slugify for now.
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

        # Return inner HTML of body
        # XML::Node#to_xml or #to_s includes the tag itself for the node,
        # but we want the *content* of body, which contains our modified headers.
        # However, body.children.map(&.to_xml).join is safer to preserve structure.
        final_html = body.children.map(&.to_xml).join

        {final_html, roots}
      end

      private def slugify(text : String) : String
        text.downcase
            .gsub(/[^a-z0-9\s-]/, "") # Remove non-alphanumeric chars except space and hyphen
            .gsub(/\s+/, "-")         # Replace spaces with hyphens
            .strip("-")               # Trim leading/trailing hyphens
      end
    end
  end
end
