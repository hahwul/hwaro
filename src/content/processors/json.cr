# JSON processor for minification
#
# This processor handles JSON files, minifying them
# by removing unnecessary whitespace.

require "json"
require "./base"

module Hwaro
  module Content
    module Processors
      # JSON processor implementation
      class Json < Base
        property minify : Bool

        def initialize(@minify : Bool = true)
        end

        def name : String
          "json"
        end

        def extensions : Array(String)
          [".json"]
        end

        def priority : Int32
          50
        end

        def process(content : String, context : ProcessorContext) : ProcessorResult
          result = if @minify
                     minify_json(content)
                   else
                     content
                   end
          ProcessorResult.new(content: result)
        rescue ex : JSON::ParseException
          ProcessorResult.error("JSON parsing failed: #{ex.message}")
        rescue ex
          ProcessorResult.error("JSON processing failed: #{ex.message}")
        end

        # Minify JSON by parsing and re-serializing without whitespace
        private def minify_json(json_str : String) : String
          parsed = JSON.parse(json_str)
          parsed.to_json
        end
      end

      # Register the JSON processor
      Registry.register(Json.new)
    end
  end
end
