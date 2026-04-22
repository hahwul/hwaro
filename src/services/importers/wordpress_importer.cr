require "xml"
require "./base"
require "./html_to_markdown"

module Hwaro
  module Services
    module Importers
      class WordPressImporter < Base
        def run(options : Config::Options::ImportOptions) : ImportResult
          wxr_path = options.path
          output_dir = options.output_dir
          include_drafts = options.drafts
          verbose = options.verbose
          force = options.force

          unless File.exists?(wxr_path)
            return ImportResult.new(
              success: false,
              message: "WXR file not found: #{wxr_path}"
            )
          end

          xml_content = File.read(wxr_path)
          doc = XML.parse(xml_content)

          imported = 0
          skipped = 0
          errors = 0

          items = find_items(doc)

          items.each do |item|
            begin
              result = process_item(item, output_dir, include_drafts, verbose, force)
              case result
              when :imported
                imported += 1
              when :skipped
                skipped += 1
              end
            rescue ex
              errors += 1
              Logger.warn "Error processing item: #{ex.message}"
            end
          end

          ImportResult.new(
            success: imported > 0 || errors == 0,
            message: "Imported #{imported} items, skipped #{skipped}, errors #{errors}",
            imported_count: imported,
            skipped_count: skipped,
            error_count: errors
          )
        end

        private def find_items(doc : XML::Node) : Array(XML::Node)
          items = [] of XML::Node
          collect_items(doc, items)
          items
        end

        private def collect_items(node : XML::Node, items : Array(XML::Node))
          if node.element? && node.name == "item"
            items << node
          end
          node.children.each { |child| collect_items(child, items) }
        end

        CONTENT_NS = "http://purl.org/rss/1.0/modules/content/"
        EXCERPT_NS = "http://wordpress.org/export/1.2/excerpt/"

        private def process_item(
          item : XML::Node,
          output_dir : String,
          include_drafts : Bool,
          verbose : Bool,
          force : Bool,
        ) : Symbol
          title = ""
          post_date = ""
          status = ""
          post_type = ""
          post_name = ""
          content_html = ""
          excerpt = ""
          tags = [] of String
          categories = [] of String

          item.children.each do |child|
            next unless child.element?

            ns_href = child.namespace.try(&.href)

            case child.name
            when "title"
              title = child.content.strip
            when "post_date"
              post_date = child.content.strip
            when "status"
              status = child.content.strip
            when "post_type"
              post_type = child.content.strip
            when "post_name"
              post_name = child.content.strip
            when "encoded"
              if ns_href == CONTENT_NS
                content_html = child.content
              elsif ns_href == EXCERPT_NS
                excerpt = child.content.strip
              end
            when "category"
              # WXR encodes both tags and categories as <category> elements
              # distinguished by the `domain` attribute. Keep them as
              # separate taxonomies so the import matches hwaro's scaffold
              # shape (tags + categories distinct). Default WordPress
              # category "Uncategorized" is skipped — it's a placeholder
              # rather than a real classification.
              domain = child["domain"]?
              value = child.content.strip
              next if value.empty?
              case domain
              when "post_tag"
                tags << value
              when "category"
                categories << value unless value == "Uncategorized"
              end
            end
          end

          # Only handle posts and pages
          return :skipped unless post_type == "post" || post_type == "page"

          # Handle draft status
          is_draft = status == "draft"
          if is_draft && !include_drafts
            return :skipped
          end

          # Determine slug
          slug = post_name.empty? ? slugify(title) : post_name
          return :skipped if slug.empty?

          # Determine section
          section = post_type == "post" ? "posts" : ""

          # Parse and format date
          date_str : String? = nil
          unless post_date.empty?
            parsed = parse_date(post_date)
            date_str = format_date(parsed) if parsed
          end

          # Build frontmatter fields
          fields = {} of String => (String | Bool | Array(String))?
          fields["title"] = title unless title.empty?
          fields["date"] = date_str
          fields["description"] = excerpt unless excerpt.empty?
          fields["draft"] = true if is_draft
          fields["tags"] = tags.uniq unless tags.empty?
          fields["categories"] = categories.uniq unless categories.empty?

          frontmatter = generate_frontmatter(fields)

          # Convert HTML content to Markdown
          body = HtmlToMarkdown.convert(content_html)

          written = write_content_file(output_dir, section, slug, frontmatter, body, verbose, force)
          written ? :imported : :skipped
        end
      end
    end
  end
end
