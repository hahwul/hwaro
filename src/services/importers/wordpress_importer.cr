require "html"
require "uri"
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

          reset_written_paths

          # `File.file?`, not `File.exists?`: a directory passes the latter
          # and then crashes File.read with a bare "Is a directory".
          unless File.file?(wxr_path)
            message = Dir.exists?(wxr_path) ? "WXR path is a directory, not a file: #{wxr_path}" : "WXR file not found: #{wxr_path}"
            return ImportResult.new(
              success: false,
              message: message
            )
          end

          # `scrub` because the export is third-party bytes: a single invalid
          # UTF-8 byte made the DOCTYPE guard's regex below raise
          # ArgumentError, aborting the whole import.
          xml_content = File.read(wxr_path).scrub

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

          items = find_items(doc)
          @attachments = attachment_urls(items)

          import_each(items, "WordPress", wrapped_note: "contained WordPress shortcodes ([gallery], [contact-form-7], …). They were kept as literal text — replace them by hand.") do |item|
            process_item(item, output_dir, include_drafts, verbose, force)
          end
        end

        # Attachment URL by `wp:post_id`, so a post's `_thumbnail_id` can be
        # resolved to its featured image.
        @attachments = Hash(String, String).new

        # A shortcode WordPress expanded at render time and hwaro cannot:
        # one with attributes (`[gallery ids="1,2"]`) or a closing tag.
        # `[caption]` is converted by HtmlToMarkdown before this runs.
        SHORTCODE_RE = /\[[a-z][\w-]*\s+[\w-]+\s*=[^\]]*\]|\[\/[a-z][\w-]*\]/i

        private def attachment_urls(items : Array(XML::Node)) : Hash(String, String)
          urls = Hash(String, String).new
          items.each do |item|
            id = ""
            url = ""
            item.children.each do |child|
              next unless child.element?
              case child.name
              when "post_id"        then id = child.content.strip
              when "attachment_url" then url = child.content.strip
              end
            end
            urls[id] = url unless id.empty? || url.empty?
          end
          urls
        end

        # The path of an item's original `<link>` when the imported page will
        # not live there, so old inbound links keep working as aliases.
        private def old_url_alias(link : String, new_path : String) : String?
          return if link.empty?
          uri = URI.parse(link)
          path = uri.path
          return if uri.query || path.empty? || path == "/"
          path = URI.decode(path).scrub
          path = "#{path}/" unless path.ends_with?('/') || File.extname(path) != ""
          path == new_path ? nil : path
        rescue URI::Error
          nil
        end

        protected def import_error_message(item : XML::Node, ex : Exception) : String
          "Error processing item: #{ex.message}"
        end

        protected def summary_message(engine : String, imported : Int32, skipped : Int32, errors : Int32) : String
          "Imported #{imported} items, skipped #{skipped}, errors #{errors}"
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

        # True when the XML declares one or more entities in its DOCTYPE
        # (`<!DOCTYPE ... [ <!ENTITY ... > ]>`). We extract the full DOCTYPE
        # declaration, skipping quoted SYSTEM/PUBLIC literals and tracking the
        # `[ ... ]` internal subset so the terminating `>` is the real one, then
        # scan only that span for `<!ENTITY`. Scoping to the DOCTYPE span (a)
        # closes a bypass where a `]` inside a SYSTEM literal would truncate a
        # naive `[`-to-`]` search, and (b) avoids false positives on `<!ENTITY`
        # text in a post body, which lives after the DOCTYPE. DOCTYPE sits at
        # the top of the file, so a bounded window keeps the scan cheap and
        # linear.
        private def declares_xml_entities?(xml : String) : Bool
          start = xml.index(/<!DOCTYPE/i)
          return false unless start

          # A real DOCTYPE can only live in the prolog, before the root
          # element. A `<!DOCTYPE` mention inside a post body (a DTD tutorial,
          # escaped markup) must not seed the scan: its surrounding prose can
          # hold unbalanced brackets/quotes that would never "close" and get
          # the whole file refused.
          if root = xml.index(/<[A-Za-z]/)
            return false if start > root
          end

          window = xml[start, 1 << 16]
          in_quote : Char? = nil
          depth = 0
          closed = false
          doctype = String.build do |io|
            window.each_char do |c|
              io << c
              if q = in_quote
                in_quote = nil if c == q
              elsif c == '"' || c == '\''
                in_quote = c
              elsif c == '['
                depth += 1
              elsif c == ']'
                depth -= 1 if depth > 0
              elsif c == '>' && depth == 0
                closed = true
                break
              end
            end
          end
          # The DOCTYPE never terminated inside the scan window, so an
          # internal subset longer than the window could smuggle its
          # `<!ENTITY` declarations past the scan. No legitimate WXR carries
          # a DOCTYPE anywhere near this size — treat it as if it declared
          # entities and refuse.
          return true unless closed
          doctype.matches?(/<!ENTITY/i)
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
          author = ""
          link = ""
          modified = ""
          thumbnail_id = ""
          tags = [] of String
          categories = [] of String

          item.children.each do |child|
            next unless child.element?

            ns_href = child.namespace.try(&.href)

            case child.name
            when "title"
              title = child.content.strip
            when "link"
              link = child.content.strip if ns_href.nil?
            when "post_modified"
              modified = child.content.strip
            when "postmeta"
              meta_key = child.children.find { |c| c.element? && c.name == "meta_key" }
              meta_value = child.children.find { |c| c.element? && c.name == "meta_value" }
              thumbnail_id = meta_value.content.strip if meta_key && meta_value && meta_key.content.strip == "_thumbnail_id"
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
            when "creator"
              # <dc:creator> — carry author attribution across.
              author = child.content.strip
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
                tags << HTML.unescape(value)
              when "category"
                categories << HTML.unescape(value) unless value == "Uncategorized"
              end
            end
          end

          # Only handle posts and pages; trashed items are gone content.
          return :skipped unless post_type == "post" || post_type == "page"
          return :skipped if status == "trash"

          # Anything not published — draft, private, pending, future — must
          # not silently become public content on the next build. An "All
          # content" WXR export includes all of these.
          is_draft = status != "publish"
          if is_draft && !include_drafts
            return :skipped
          end

          # Determine slug. WordPress stores non-ASCII slugs percent-encoded
          # (`sanitize_title`); decode so the filename matches what servers
          # and browsers will show for the URL. Traversal is neutralized at
          # the write_content_file sink.
          slug = post_name.empty? ? file_slug(title) : URI.decode(post_name)
          return :skipped if slug.empty?

          # Determine section
          section = post_type == "post" ? "posts" : ""

          # Parse and format date — prefer the precise `<wp:post_date>`
          # (local time, no TZ noise) and fall back to RFC 822 `<pubDate>`.
          date_str : String? = nil
          if !post_date.empty? && (parsed = Utils::DateUtils.parse_import(post_date))
            date_str = format_date(parsed)
          elsif !pub_date.empty? && (parsed = Utils::DateUtils.parse_import(pub_date))
            date_str = format_date(parsed)
          end

          # Build frontmatter fields
          fields = {} of String => FieldValue
          fields["title"] = title unless title.empty?
          fields["date"] = date_str
          # A modification time earlier than (or equal to) the post date is
          # WordPress's default for an unedited post; only a real edit is
          # `updated`.
          if !modified.empty? && !modified.starts_with?("0000") && (changed = Utils::DateUtils.parse_import(modified)) && (published = Utils::DateUtils.parse_import(post_date.empty? ? pub_date : post_date)) && changed > published
            fields["updated"] = format_date(changed)
          end
          if (featured = @attachments[thumbnail_id]?) && !thumbnail_id.empty?
            fields["image"] = featured
          end
          new_path = section.empty? ? "/#{slug}/" : "/#{section}/#{slug}/"
          if old = old_url_alias(link, new_path)
            fields["aliases"] = [old]
          end
          fields["description"] = excerpt unless excerpt.empty?
          fields["draft"] = true if is_draft
          fields["tags"] = tags.uniq unless tags.empty?
          fields["categories"] = categories.uniq unless categories.empty?
          fields["authors"] = [author] unless author.empty?

          frontmatter = generate_frontmatter(fields)

          # Convert HTML content to Markdown
          body = HtmlToMarkdown.convert(content_html)
          body = strip_redundant_title_h1(body, fields["title"]?.as?(String))

          written = write_content_file(output_dir, section, slug, frontmatter, body, verbose, force)
          return :skipped unless written
          if body.matches?(SHORTCODE_RE)
            Logger.warn "WordPress shortcodes in #{title.empty? ? slug : title.inspect} were kept as literal text — replace them by hand."
            return :imported_wrapped
          end
          :imported
        end
      end
    end
  end
end
