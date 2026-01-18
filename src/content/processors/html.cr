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

        # Simple HTML minification - removes excess whitespace
        private def minify_html(html : String) : String
          html
            .gsub(/>\s+</, "><")           # Remove whitespace between tags
            .gsub(/\n\s*/, " ")            # Replace newlines with single space
            .gsub(/\s{2,}/, " ")           # Collapse multiple spaces
            .strip
        end
      end

      # Register the HTML processor
      Registry.register(Html.new)
    end
  end
end
