require "xml"
require "../../utils/logger"
require "../../content/processors/inline_markdown"

module Hwaro
  module Services
    module Importers
      # Lightweight HTML-to-Markdown converter.
      # Handles common HTML elements produced by WordPress and other CMS exports.
      module HtmlToMarkdown
        # Above this size the regex pipeline's lazy quantifiers (e.g. the anchor
        # body `(.*?)</a>`) degrade to O(n^2) on adversarial markup (many
        # unclosed tags). Imported exports are untrusted, so fall back to a
        # cheap linear tag-strip rather than spend minutes of CPU on a single
        # crafted item. The threshold is far above any real blog post.
        MAX_REGEX_HTML_BYTES = 4 * 1024 * 1024

        # Longest anchor TEXT the link conversion will match. Bounding the lazy
        # body is what actually makes an unclosed-anchor document linear — see
        # the anchor pass below. Far above any real inline link.
        MAX_INLINE_BODY_CHARS = 4096

        # Cheap short-circuit for the anchor pass: a document with no closing
        # anchor tag has no link to convert. Exposed so the skip is assertable
        # without a wall-clock measurement.
        ANCHOR_CLOSE_RE = /<\/a>/i
        ANCHOR_RE       = Regex.new(
          "<a[^>]*\\bhref=[\"']([^\"']+)[\"'][^>]*>(.{0,#{MAX_INLINE_BODY_CHARS}}?)</a>",
          Regex::Options::IGNORE_CASE | Regex::Options::MULTILINE
        )

        # True when `convert` will run the (bounded) anchor conversion pass on
        # this document.
        def self.anchor_pass_applicable?(html : String) : Bool
          html.matches?(ANCHOR_CLOSE_RE)
        end

        def self.convert(html : String) : String
          return "" if html.empty?

          if html.bytesize > MAX_REGEX_HTML_BYTES
            Logger.warn "HTML content is very large (#{html.bytesize} bytes); converting as plain text to avoid excessive processing time."
            return html.gsub(/<[^>]*>/, " ").gsub(/[ \t]+/, " ").strip
          end

          result = html

          # Normalize line endings
          result = result.gsub("\r\n", "\n")

          # Convert block elements first (order matters)

          # Headings
          (1..6).each do |level|
            prefix = "#" * level
            result = result.gsub(/<h#{level}[^>]*>(.*?)<\/h#{level}>/mi) { "#{prefix} #{$1.strip}\n\n" }
          end

          # Code blocks: <pre><code>...</code></pre> or <pre>...</pre>.
          # Stash the finished fences behind placeholders until the very end:
          # every later pass (lists, <p>, <a>, strip_tags, the final entity
          # decode) would otherwise run INSIDE the code sample, converting or
          # stripping the HTML it demonstrates and double-decoding entities.
          code_stash = [] of String
          result = result.gsub(/<pre[^>]*>\s*<code[^>]*>(.*?)<\/code>\s*<\/pre>/mi) do
            code = decode_html_entities($1)
            code_stash << "```\n#{code.strip}\n```\n\n"
            code_placeholder(code_stash.size - 1)
          end
          result = result.gsub(/<pre[^>]*>(.*?)<\/pre>/mi) do
            code = decode_html_entities($1)
            code_stash << "```\n#{code.strip}\n```\n\n"
            code_placeholder(code_stash.size - 1)
          end

          # Blockquotes
          result = result.gsub(/<blockquote[^>]*>(.*?)<\/blockquote>/mi) do
            inner = $1.strip
            # Strip inner <p> tags
            inner = inner.gsub(/<\/?p[^>]*>/i, "")
            lines = inner.split("\n").map { |l| "> #{l.strip}" }
            lines.join("\n") + "\n\n"
          end

          # Lists — innermost first, so a nested <ul> inside an <li> is
          # converted before its parent. The old single outer pass stopped at
          # the INNER </ul>, garbling nested lists and dropping trailing items.
          # A converted list opens with a newline and each item's continuation
          # lines are indented: by the time an OUTER list is converted, the
          # inner one is already Markdown sitting inside the parent `<li>`,
          # so without those two things `<li>b<ul><li>b1</li></ul></li>`
          # collapsed to the single line `- b- b1` (and `2. second1. s1` for
          # ordered lists), which renders as literal text.
          innermost_list = /<(ul|ol)[^>]*>((?:(?!<[uo]l[^>]*>).)*?)<\/\1>/mi
          while result.matches?(innermost_list)
            result = result.gsub(innermost_list) do
              kind = $1.downcase
              items = $2.scan(/<li[^>]*>(.*?)<\/li>/mi)
              lines = items.map_with_index do |m, i|
                marker = kind == "ol" ? "#{i + 1}. " : "- "
                "#{marker}#{indent_continuation(strip_tags(m[1]).strip, marker.size)}"
              end
              "\n" + lines.join("\n") + "\n\n"
            end
          end

          # Tables — convert <table> into Markdown pipe-tables. Uses the
          # first row as the header (typical for WXR exports, which wrap
          # headers in <thead><tr><th>). If no <th> is present the first
          # row is still promoted to a header so the table is legal
          # Markdown. Nested tables fall through strip_tags (the inner
          # table text is flattened) — WP blog posts rarely nest tables.
          result = result.gsub(/<table[^>]*>(.*?)<\/table>/mi) do
            inner = $1
            rows = inner.scan(/<tr[^>]*>(.*?)<\/tr>/mi).map do |m|
              m[1].scan(/<(?:th|td)[^>]*>(.*?)<\/(?:th|td)>/mi).map do |cell|
                strip_tags(cell[1]).strip.gsub(/\s+/, " ").gsub("|", "\\|")
              end
            end
            rows.reject!(&.empty?)
            if rows.empty?
              ""
            else
              width = rows.max_of(&.size)
              header = rows.shift
              header += [""] * (width - header.size)
              lines = [] of String
              lines << "| #{header.join(" | ")} |"
              lines << "| #{(["---"] * width).join(" | ")} |"
              rows.each do |row|
                padded = row + [""] * (width - row.size)
                lines << "| #{padded.join(" | ")} |"
              end
              lines.join("\n") + "\n\n"
            end
          end

          # Horizontal rules (attribute-bearing and uppercase forms included —
          # Gutenberg emits `<hr class="wp-block-separator …"/>`)
          result = result.gsub(/<hr\b[^>]*>/i, "\n---\n\n")

          # Paragraphs
          result = result.gsub(/<p[^>]*>(.*?)<\/p>/mi) { "#{$1.strip}\n\n" }

          # Line breaks
          result = result.gsub(/<br\b[^>]*>/i, "  \n")

          # Inline elements

          # Images (before links to avoid nested match issues).
          # Drop the URL (keep the alt text) when the scheme is unsafe so an
          # untrusted export can't smuggle a live `javascript:`/`data:` src
          # into content — the importer stays safe regardless of the markdown
          # renderer's `safe` flag.
          result = result.gsub(/<img[^>]*\bsrc=["']([^"']+)["'][^>]*\balt=["']([^"']*)["'][^>]*\/?>/i) { safe_media($1, $2, image: true) }
          result = result.gsub(/<img[^>]*\balt=["']([^"']*)["'][^>]*\bsrc=["']([^"']+)["'][^>]*\/?>/i) { safe_media($2, $1, image: true) }
          result = result.gsub(/<img[^>]*\bsrc=["']([^"']+)["'][^>]*\/?>/i) { safe_media($1, "", image: true) }

          # Links — likewise drop a dangerous href but keep the link text.
          #
          # The body is BOUNDED (`{0,MAX_INLINE_BODY_CHARS}?`) rather than an
          # open `(.*?)`. An open lazy body rescans every remaining character
          # from each `<a href=…>` that never closes, so a document of n
          # unclosed anchors costs O(n^2): measured 1.4 s for 20k anchors and
          # 6.0 s for 40k, while the same count of CLOSED anchors — a 1.4x
          # LARGER document — takes 0.07 s. `MAX_REGEX_HTML_BYTES` did not
          # bound that as its comment claims: ~175k unclosed anchors still fit
          # under the 4 MB cap, i.e. minutes of CPU inside one import of an
          # untrusted WXR export. With the bound, each anchor start costs a
          # fixed scan instead of a scan to end-of-document.
          #
          # The `</a>` probe stays as a cheap short-circuit for the common
          # no-anchor document, but it is an optimization, not the guard: a
          # single `</a>` anywhere re-enables the pass, which is why the bound
          # has to carry the cost argument. It is case-insensitive because the
          # conversion is: `</A>` closes a real anchor.
          #
          # Trade-off: an anchor whose text runs longer than the bound is left
          # as HTML and its text is kept by `strip_tags` below — the link
          # markup is lost, no content is. Real inline anchors are orders of
          # magnitude shorter.
          if result.matches?(ANCHOR_CLOSE_RE)
            result = result.gsub(ANCHOR_RE) { safe_media($1, $2, image: false) }
          end

          # Bold
          result = result.gsub(/<(?:strong|b)>(.*?)<\/(?:strong|b)>/mi) { "**#{$1}**" }

          # Italic
          result = result.gsub(/<(?:em|i)>(.*?)<\/(?:em|i)>/mi) { "*#{$1}*" }

          # Inline code
          result = result.gsub(/<code>(.*?)<\/code>/mi) { "`#{$1}`" }

          # Strikethrough
          result = result.gsub(/<(?:del|s|strike)>(.*?)<\/(?:del|s|strike)>/mi) { "~~#{$1}~~" }

          # Strip remaining HTML tags
          result = strip_tags(result)

          # Decode HTML entities
          result = decode_html_entities(result)

          # Restore stashed code fences (already entity-decoded exactly once).
          code_stash.each_with_index do |block, i|
            result = result.sub(code_placeholder(i), block)
          end

          # Clean up whitespace
          result = result.gsub(/\n{3,}/, "\n\n") # Max 2 consecutive newlines
          result.strip
        end

        # NUL-delimited placeholder: survives every regex pass (no `<>`, no
        # `&…;`) and can't occur in real exported content (XML forbids NUL).
        private def self.code_placeholder(index : Int32) : String
          "\u0000hwaro-code-#{index}\u0000"
        end

        private def self.strip_tags(html : String) : String
          html.gsub(/<[^>]*>/, "")
        end

        # Indent every line after the first to the item's content column so an
        # already converted nested list stays nested under its parent item.
        # The width is the marker's own width (`- ` → 2, `10. ` → 4), which is
        # what CommonMark requires for a child block. Blank lines are left
        # alone (trailing whitespace would survive into the imported Markdown).
        private def self.indent_continuation(text : String, width : Int32) : String
          return text unless text.includes?('\n')
          pad = " " * width
          text.lines(chomp: false).map_with_index do |line, i|
            i.zero? || line.strip.empty? ? line : "#{pad}#{line}"
          end.join
        end

        # Emit a markdown link/image only when the URL scheme is safe; otherwise
        # drop the URL and keep just the text/alt. Reuses the single source of
        # truth for URL-scheme sanitisation so imported content can never carry
        # a live `javascript:`/`vbscript:`/`file:`/non-image-`data:` reference.
        private def self.safe_media(url : String, text : String, image : Bool) : String
          return text unless Hwaro::Content::Processors::InlineMarkdown.safe_url?(url)
          image ? "![#{text}](#{url})" : "[#{text}](#{url})"
        end

        private def self.decode_html_entities(text : String) : String
          text
            .gsub("&lt;", "<")
            .gsub("&gt;", ">")
            .gsub("&quot;", "\"")
            .gsub("&#39;", "'")
            .gsub("&apos;", "'")
            .gsub("&nbsp;", " ")
            .gsub("&#8211;", "-")
            .gsub("&#8212;", "--")
            .gsub("&#8216;", "'")
            .gsub("&#8217;", "'")
            .gsub("&#8220;", "\"")
            .gsub("&#8221;", "\"")
            .gsub("&#8230;", "...")
            .gsub(/&#(\d+);/) do
              # to_i? (not to_i): a numeric entity whose digits exceed Int32
              # (e.g. &#99999999999999999999;) must be dropped, not crash the
              # import. The range check below already rejects it, but to_i
              # would raise before we ever get there.
              code = $1.to_i?
              # Validate Unicode range (exclude surrogates 0xD800..0xDFFF)
              if code && code > 0 && code <= 0x10FFFF && !(0xD800 <= code <= 0xDFFF)
                code.chr.to_s
              else
                ""
              end
            end
            .gsub(/&#[xX]([0-9a-fA-F]+);/) do
              code = $1.to_i?(16)
              if code && code > 0 && code <= 0x10FFFF && !(0xD800 <= code <= 0xDFFF)
                code.chr.to_s
              else
                ""
              end
            end
            .gsub("&amp;", "&")
          # `&amp;` LAST: decoding it first turned `&amp;lt;` (a literal
          # "&lt;" in the source text) into a real `<` — the classic
          # double-unescape.
        end
      end
    end
  end
end
