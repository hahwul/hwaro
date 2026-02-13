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

        # Very conservative HTML minification
        # Only removes: HTML comments, trailing whitespace on lines, excessive blank lines
        # Preserves: all meaningful whitespace, newlines, indentation structure
        private def minify_html(html : String) : String
          # Clean up template-induced whitespace inside pre blocks
          # This handles cases like: <pre>\n  <code>content</code>\n</pre>
          # Converting to: <pre><code>content</code></pre>
          cleaned = html
            .gsub(/<pre([^>]*)>\s*<code/, "<pre\\1><code") # <pre>\n  <code> -> <pre><code>
            .gsub(/<\/code>\s*<\/pre>/, "</code></pre>")   # </code>\n</pre> -> </code></pre>

          # Remove HTML comments (but not conditional comments like <!--[if IE]>)
          # Also preserve <!-- more --> markers used for content summaries
          minified = cleaned.gsub(/<!--(?!\[if|\s*more\s*-->).*?-->/m, "")

          # Remove trailing whitespace on each line
          minified = minified.gsub(/[ \t]+$/m, "")

          # Collapse 3+ consecutive blank lines to 2
          minified = minified.gsub(/\n{3,}/, "\n\n")

          minified.strip
        end
      end

      # Register the HTML processor
      Registry.register(Html.new)
    end
  end
end
