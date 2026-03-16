require "xml"

module Hwaro
  module Services
    module Importers
      # Lightweight HTML-to-Markdown converter.
      # Handles common HTML elements produced by WordPress and other CMS exports.
      module HtmlToMarkdown
        def self.convert(html : String) : String
          return "" if html.empty?

          result = html

          # Normalize line endings
          result = result.gsub("\r\n", "\n")

          # Convert block elements first (order matters)

          # Headings
          (1..6).each do |level|
            prefix = "#" * level
            result = result.gsub(/<h#{level}[^>]*>(.*?)<\/h#{level}>/mi) { "#{prefix} #{$1.strip}\n\n" }
          end

          # Code blocks: <pre><code>...</code></pre> or <pre>...</pre>
          result = result.gsub(/<pre[^>]*>\s*<code[^>]*>(.*?)<\/code>\s*<\/pre>/mi) do
            code = decode_html_entities($1)
            "```\n#{code.strip}\n```\n\n"
          end
          result = result.gsub(/<pre[^>]*>(.*?)<\/pre>/mi) do
            code = decode_html_entities($1)
            "```\n#{code.strip}\n```\n\n"
          end

          # Blockquotes
          result = result.gsub(/<blockquote[^>]*>(.*?)<\/blockquote>/mi) do
            inner = $1.strip
            # Strip inner <p> tags
            inner = inner.gsub(/<\/?p[^>]*>/i, "")
            lines = inner.split("\n").map { |l| "> #{l.strip}" }
            lines.join("\n") + "\n\n"
          end

          # Ordered lists
          result = result.gsub(/<ol[^>]*>(.*?)<\/ol>/mi) do
            items = $1.scan(/<li[^>]*>(.*?)<\/li>/mi)
            items.map_with_index { |m, i| "#{i + 1}. #{strip_tags(m[1]).strip}" }.join("\n") + "\n\n"
          end

          # Unordered lists
          result = result.gsub(/<ul[^>]*>(.*?)<\/ul>/mi) do
            items = $1.scan(/<li[^>]*>(.*?)<\/li>/mi)
            items.map { |m| "- #{strip_tags(m[1]).strip}" }.join("\n") + "\n\n"
          end

          # Horizontal rules
          result = result.gsub(/<hr\s*\/?>/, "\n---\n\n")

          # Paragraphs
          result = result.gsub(/<p[^>]*>(.*?)<\/p>/mi) { "#{$1.strip}\n\n" }

          # Line breaks
          result = result.gsub(/<br\s*\/?>/, "  \n")

          # Inline elements

          # Images (before links to avoid nested match issues)
          result = result.gsub(/<img[^>]*\bsrc=["']([^"']+)["'][^>]*\balt=["']([^"']*)["'][^>]*\/?>/i) { "![#{$2}](#{$1})" }
          result = result.gsub(/<img[^>]*\balt=["']([^"']*)["'][^>]*\bsrc=["']([^"']+)["'][^>]*\/?>/i) { "![#{$1}](#{$2})" }
          result = result.gsub(/<img[^>]*\bsrc=["']([^"']+)["'][^>]*\/?>/i) { "![](#{$1})" }

          # Links
          result = result.gsub(/<a[^>]*\bhref=["']([^"']+)["'][^>]*>(.*?)<\/a>/mi) { "[#{$2}](#{$1})" }

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

          # Clean up whitespace
          result = result.gsub(/\n{3,}/, "\n\n") # Max 2 consecutive newlines
          result.strip
        end

        private def self.strip_tags(html : String) : String
          html.gsub(/<[^>]*>/, "")
        end

        private def self.decode_html_entities(text : String) : String
          text
            .gsub("&amp;", "&")
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
              code = $1.to_i
              # Validate Unicode range (exclude surrogates 0xD800..0xDFFF)
              if code > 0 && code <= 0x10FFFF && !(0xD800 <= code <= 0xDFFF)
                code.chr.to_s
              else
                ""
              end
            end
        end
      end
    end
  end
end
