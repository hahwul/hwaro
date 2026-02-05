# HTML processor for passthrough and optional minification
#
# This processor handles HTML files, optionally minifying them
# by removing unnecessary whitespace.

require "./base"

module Hwaro
  module Content
    module Processors
      # HTML processor implementation
      class Html < Base
        property minify : Bool

        def initialize(@minify : Bool = false)
        end

        def name : String
          "html"
        end

        def extensions : Array(String)
          [".html", ".htm"]
        end

        def priority : Int32
          50 # Lower priority than markdown
        end

        def process(content : String, context : ProcessorContext) : ProcessorResult
          result = if @minify
                     minify_html(content)
                   else
                     content
                   end
          ProcessorResult.new(content: result)
        rescue ex
          ProcessorResult.error("HTML processing failed: #{ex.message}")
        end

        # Conservative HTML minification that preserves whitespace in sensitive elements
        # Preserves content inside: <pre>, <code>, <textarea>, <script>, <style>
        # Also cleans up template-induced whitespace around nested tags (e.g., <pre>\n  <code>)
        private def minify_html(html : String) : String
          # First, clean up template-induced whitespace inside pre blocks
          # This handles cases like: <pre>\n  <code>content</code>\n</pre>
          # Converting to: <pre><code>content</code></pre>
          cleaned = html
            .gsub(/<pre([^>]*)>\s*<code/, "<pre\\1><code")  # <pre>\n  <code> -> <pre><code>
            .gsub(/<\/code>\s*<\/pre>/, "</code></pre>")     # </code>\n</pre> -> </code></pre>

          # Regex pattern for whitespace-sensitive tags (non-greedy, handles nesting)
          # We process pre blocks first as they may contain code blocks
          preserve_pattern = /(<(?:pre|textarea|script|style)[^>]*>)(.*?)(<\/(?:pre|textarea|script|style)>)/mi

          # Extract and replace sensitive blocks with placeholders
          preserved_blocks = [] of String
          placeholder_prefix = "HWARO-PRESERVE-BLOCK-"

          protected_html = cleaned.gsub(preserve_pattern) do |match|
            open_tag = $1
            content = $2
            close_tag = $3
            placeholder = "#{placeholder_prefix}#{preserved_blocks.size}"
            preserved_blocks << "#{open_tag}#{content}#{close_tag}"
            placeholder
          end

          # Apply conservative minification to non-sensitive content:
          # - Remove leading/trailing whitespace on lines
          # - Collapse multiple blank lines into single newline
          # - Keep single newlines to preserve block-level element spacing
          minified = protected_html
            .gsub(/^[ \t]+/, "")      # Remove leading spaces/tabs on each line
            .gsub(/[ \t]+$/, "")      # Remove trailing spaces/tabs on each line
            .gsub(/\n{3,}/, "\n\n")   # Collapse 3+ newlines to 2
            .gsub(/>\s*\n\s*</, ">\n<") # Clean up whitespace between tags but keep newline
            .strip

          # Restore preserved blocks
          preserved_blocks.each_with_index do |block, index|
            minified = minified.gsub("#{placeholder_prefix}#{index}", block)
          end

          minified
        end
      end

      # Register the HTML processor
      Registry.register(Html.new)
    end
  end
end
