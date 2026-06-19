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

          # Guard against XML entity-expansion / recursive-entity DoS. A
          # malicious WXR can declare nested internal entities (e.g.
          # `<!ENTITY a "&b;&b;">`); libxml2 (with NOENT off, NONET on — the
          # Crystal default, so no XXE file-read/SSRF) still materialises a
          # deeply nested / cyclic entity-reference node tree, and our recursive
          # `collect_items` walk then overflows the stack (a fatal, unrescuable
          # signal). Legitimate WordPress exports never declare custom entities,
          # so refuse any WXR whose DOCTYPE internal subset declares one.
          if declares_xml_entities?(xml_content)
            return ImportResult.new(
              success: false,
              message: "WXR file declares XML entities (<!ENTITY> in DOCTYPE), which is unsupported and unsafe. Aborting import."
            )
          end

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

        # Maximum node depth for the item-collection walk. A real WXR nests
        # only a handful of levels (rss > channel > item > field); a cap this
        # generous never trips on legitimate input but stops a pathologically
        # deep node tree from overflowing the stack.
        MAX_NODE_DEPTH = 256

        private def collect_items(node : XML::Node, items : Array(XML::Node), depth : Int32 = 0)
          return if depth > MAX_NODE_DEPTH
          if node.element? && node.name == "item"
            items << node
          end
          node.children.each { |child| collect_items(child, items, depth + 1) }
        end

        # True when the XML declares one or more entities in a DOCTYPE internal
        # subset (`<!DOCTYPE ... [ <!ENTITY ... > ]>`). Scoped to the internal
        # subset so a post that merely *mentions* the text "<!ENTITY" in its
        # CDATA body is not a false positive. Linear-time (negated char
        # classes only — no catastrophic backtracking on the guard itself).
        private def declares_xml_entities?(xml : String) : Bool
          doctype = xml.index(/<!DOCTYPE/i)
          return false unless doctype
          window = xml[doctype, Math.min(xml.size - doctype, 1 << 16)]
          open_bracket = window.index('[')
          return false unless open_bracket
          close = window.index(']', open_bracket) || window.size
          window[open_bracket, close - open_bracket].matches?(/<!ENTITY/i)
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
          pub_date = ""
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
            when "pubDate"
              # RFC 822. Fallback when <wp:post_date> is missing (some
              # exporters omit it and only populate the RSS pubDate).
              pub_date = child.content.strip
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

          # Parse and format date — prefer the precise `<wp:post_date>`
          # (local time, no TZ noise) and fall back to RFC 822 `<pubDate>`.
          date_str : String? = nil
          if !post_date.empty? && (parsed = parse_date(post_date))
            date_str = format_date(parsed)
          elsif !pub_date.empty? && (parsed = parse_date(pub_date))
            date_str = format_date(parsed)
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
          body = strip_redundant_title_h1(body, fields["title"]?.as?(String))

          written = write_content_file(output_dir, section, slug, frontmatter, body, verbose, force)
          written ? :imported : :skipped
        end
      end
    end
  end
end
