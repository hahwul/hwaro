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
              
              # Replace code node content with highlighted version
              if highlighted_html
                # Remove existing content
                code_node.children.each(&.unlink)
                
                # Parse highlighted HTML and add as child
                highlighted_doc = XML.parse_html(highlighted_html)
                highlighted_body = highlighted_doc.xpath_node("//body")
                
                if highlighted_body
                  highlighted_body.children.each do |child|
                    code_node << child.dup
                  end
                end
              end
            end
          end

          # Return the modified HTML
          body.children.map(&.to_xml).join
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
          # Use Tartrazine to highlight code
          lexer = Tartrazine.lexer(name: language)
          theme = Tartrazine.theme(name: @theme)
          
          formatter = Tartrazine::Html.new(
            standalone: false,
            classes: true
          )
          
          highlighted = formatter.format(code, lexer, theme)
          highlighted
        rescue ex
          Logger.warn "  [WARN] Failed to highlight #{language} code: #{ex.message}"
          nil
        end
      end

      # Note: Don't register by default - registration should be controlled by configuration
    end
  end
end
