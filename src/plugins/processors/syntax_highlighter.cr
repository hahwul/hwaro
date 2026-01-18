# Syntax Highlighter processor for highlighting code blocks
#
# This processor handles:
# - Syntax highlighting using Tartrazine
# - Theme support for different color schemes
# - Integration with markdown code blocks

require "tartrazine"
require "xml"
require "./base"
require "../../utils/logger"

module Hwaro
  module Plugins
    module Processors
      # Syntax Highlighter processor implementation
      class SyntaxHighlighter < Base
        property enabled : Bool
        property theme : String

        def initialize(@enabled : Bool = false, @theme : String = "github")
        end

        def name : String
          "syntax_highlighter"
        end

        def extensions : Array(String)
          [] of String # This processor works on HTML content, not specific file extensions
        end

        def priority : Int32
          90 # High priority, but lower than markdown
        end

        def process(content : String, context : ProcessorContext) : ProcessorResult
          return ProcessorResult.new(content: content) unless @enabled

          highlighted = highlight_code_blocks(content)
          ProcessorResult.new(content: highlighted)
        rescue ex
          Logger.warn "  [WARN] Syntax highlighting failed: #{ex.message}"
          ProcessorResult.new(content: content) # Return original content on error
        end

        # Highlights all code blocks in HTML content
        def highlight_code_blocks(html : String) : String
          # Parse HTML to find code blocks
          doc = XML.parse_html(html)
          body = doc.xpath_node("//body")

          return html unless body

          # Collect replacements to perform
          replacements = [] of {XML::Node, String}

          # Find all <pre><code> blocks
          body.xpath_nodes("//pre/code").each do |code_node|
            # Get language from class attribute (e.g., "language-ruby")
            class_attr = code_node["class"]?
            language = extract_language(class_attr)

            # Get code content
            code_content = code_node.content

            # Highlight the code
            if language && !language.empty?
              highlighted_html = highlight_code(code_content, language)
              
              if highlighted_html
                replacements << {code_node, highlighted_html}
              end
            end
          end

          # Perform replacements
          replacements.each do |code_node, highlighted_html|
            # Remove existing content
            code_node.children.each(&.unlink)
            
            # Create a temporary document to parse the highlighted HTML
            temp_html = "<div>#{highlighted_html}</div>"
            temp_doc = XML.parse_html(temp_html)
            temp_body = temp_doc.xpath_node("//body")
            temp_div = temp_body.try(&.first_element_child)
            
            # Add the parsed highlighted content as children
            if temp_div
              temp_div.children.each do |child|
                # Use clone/dup to avoid ownership issues
                cloned = child.dup
                code_node << cloned
              end
            end
          end

          # Return the modified HTML - use to_s for HTML output
          body.children.to_s
        rescue ex
          Logger.warn "  [WARN] Error processing code blocks: #{ex.message}"
          html
        end

        # Extracts language from class attribute
        private def extract_language(class_attr : String?) : String?
          return nil unless class_attr

          # Handle common formats: "language-ruby", "lang-ruby", "ruby"
          if match = class_attr.match(/(?:language-|lang-)?([\w+]+)/)
            match[1]
          else
            nil
          end
        end

        # Highlights code with the specified language and theme
        private def highlight_code(code : String, language : String) : String?
          # Use Tartrazine high-level API
          html = Tartrazine.to_html(
            code,
            language: language,
            theme: @theme,
            standalone: false,
            line_numbers: false
          )
          html
        rescue ex
          Logger.warn "  [WARN] Failed to highlight #{language} code: #{ex.message}"
          nil
        end
      end

      # Note: Don't register by default - registration should be controlled by configuration
    end
  end
end
