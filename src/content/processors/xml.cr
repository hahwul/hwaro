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

        # CDATA sections and comments extracted as opaque placeholders
        # before minification. `\x00` is illegal in XML, so the token
        # cannot collide with author content.
        private CDATA_COMMENT_RE  = /<!\[CDATA\[.*?\]\]>|<!--.*?-->/m
        private PRESERVE_TOKEN_RE = /\x00HWXMLP(\d+)\x00/

        # Simple XML minification - removes excess whitespace
        # Only removes whitespace-only text nodes between tags (preserves mixed content)
        private def minify_xml(xml : String) : String
          # CDATA sections and comments are raw character data — the
          # cross-line collapse below must never reach inside them (a
          # CDATA body containing `</a>\n<em>` is content, not markup).
          # Stash them behind placeholders and restore verbatim at the end.
          preserved = [] of String
          work = xml.gsub(CDATA_COMMENT_RE) do |m|
            preserved << m
            "\x00HWXMLP#{preserved.size - 1}\x00"
          end
          result = work
            .gsub(/>\s*\n\s*</, "><") # Remove whitespace-only text between tags (cross-line only)
            .gsub(/<[^>]+>/) do |tag|
              # Never touch comments or CDATA sections: their bytes are
              # significant character data (RSS <content:encoded>, embedded
              # scripts, pre-formatted code), not attribute formatting, so
              # collapsing internal whitespace would silently corrupt them.
              next tag if tag.starts_with?("<!--") || tag.starts_with?("<![CDATA[")
              # Collapse whitespace runs only BETWEEN attributes; leave whitespace
              # inside quoted attribute values intact (e.g. `title="a    b"`),
              # otherwise the minifier silently corrupts attribute content.
              tag.gsub(/("[^"]*"|'[^']*')|\s{2,}/) do |m|
                (m.starts_with?('"') || m.starts_with?('\'')) ? m : " "
              end
            end
            .strip
          return result if preserved.empty?
          result.gsub(PRESERVE_TOKEN_RE) do
            # to_i? bounds-guards a counterfeit token (NUL is illegal in
            # XML, but be defensive): emit it unchanged instead of raising.
            idx = $1.to_i?
            idx && idx < preserved.size ? preserved[idx] : $0
          end
        end
      end

      # Register the XML processor
      Registry.register(Xml.new)
    end
  end
end
