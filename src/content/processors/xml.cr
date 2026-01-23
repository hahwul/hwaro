# XML processor for minification
#
# This processor handles XML files, minifying them
# by removing unnecessary whitespace while preserving content.

require "./base"

module Hwaro
  module Content
    module Processors
      # XML processor implementation
      class Xml < Base
        property minify : Bool

        def initialize(@minify : Bool = true)
        end

        def name : String
          "xml"
        end

        def extensions : Array(String)
          [".xml"]
        end

        def priority : Int32
          40 # Lower priority than HTML
        end

        def process(content : String, context : ProcessorContext) : ProcessorResult
          result = if @minify
                     minify_xml(content)
                   else
                     content
                   end
          ProcessorResult.new(content: result)
        rescue ex
          ProcessorResult.error("XML processing failed: #{ex.message}")
        end

        # Simple XML minification - removes excess whitespace
        # Preserves whitespace within text content where significant
        private def minify_xml(xml : String) : String
          xml
            .gsub(/>\s+</, "><")           # Remove whitespace between tags
            .gsub(/^\s+/, "")              # Remove leading whitespace
            .gsub(/\s+$/, "")              # Remove trailing whitespace
            .gsub(/\n\s*/, "")             # Remove newlines and following spaces
            .gsub(/\s{2,}(?=[^<]*>)/, " ") # Collapse multiple spaces in attributes
            .strip
        end
      end

      # Register the XML processor
      Registry.register(Xml.new)
    end
  end
end
