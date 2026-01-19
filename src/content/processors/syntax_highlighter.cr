# Syntax Highlighter for code blocks
#
# This module provides syntax highlighting for code blocks in HTML content
# using the tartrazine library. It processes <pre><code> elements and
# applies syntax highlighting based on the language specified in the
# class attribute (e.g., class="language-crystal").
#
# Usage:
#   html = SyntaxHighlighter.highlight(html_content, theme: "monokai")

require "xml"
require "tartrazine"

module Hwaro
  module Content
    module Processors
      # Configuration for syntax highlighting
      class SyntaxHighlighterConfig
        property enabled : Bool
        property theme : String
        property line_numbers : Bool

        def initialize(
          @enabled : Bool = true,
          @theme : String = "monokai",
          @line_numbers : Bool = false,
        )
        end
      end

      # Syntax highlighter for code blocks in HTML content
      module SyntaxHighlighter
        extend self

        # Default theme to use if none specified
        DEFAULT_THEME = "monokai"

        # Highlight code blocks in HTML content
        #
        # This method finds all <pre><code class="language-xxx"> elements
        # and replaces them with syntax-highlighted versions.
        #
        # Parameters:
        #   html - The HTML content to process
        #   theme - The color theme to use (default: "monokai")
        #   line_numbers - Whether to include line numbers (default: false)
        #
        # Returns:
        #   The HTML content with syntax-highlighted code blocks
        def highlight(
          html : String,
          theme : String = DEFAULT_THEME,
          line_numbers : Bool = false,
        ) : String
          return html if html.empty?

          # Quick check: if no code blocks, return as-is
          return html unless html.includes?("<code")

          # Use regex-based replacement to avoid XML parsing issues
          highlight_with_regex(html, theme, line_numbers)
        end

        # Highlight a single code block
        #
        # Parameters:
        #   code - The source code to highlight
        #   language - The programming language
        #   theme - The color theme to use
        #   line_numbers - Whether to include line numbers
        #
        # Returns:
        #   HTML string with syntax-highlighted code
        def highlight_code(
          code : String,
          language : String,
          theme : String = DEFAULT_THEME,
          line_numbers : Bool = false,
        ) : String
          begin
            Tartrazine.to_html(
              code,
              language: language,
              theme: theme,
              standalone: false,
              line_numbers: line_numbers
            )
          rescue ex
            # If highlighting fails (unknown language, etc.), return escaped code
            Logger.debug "Syntax highlighting failed for language '#{language}': #{ex.message}"
            "<pre><code>#{escape_html(code)}</code></pre>"
          end
        end

        # Process HTML content and highlight code blocks using regex
        private def highlight_with_regex(
          html : String,
          theme : String,
          line_numbers : Bool,
        ) : String
          # Match <pre><code class="language-xxx">...</code></pre> patterns
          # The regex captures:
          # 1. The language name from class="language-xxx"
          # 2. The code content between <code> and </code>
          pattern = /<pre><code\s+class="language-([^"]+)">(.*?)<\/code><\/pre>/m

          html.gsub(pattern) do |match|
            language = $1
            code = $2

            # Decode HTML entities in the code
            decoded_code = decode_html_entities(code)

            begin
              highlighted = Tartrazine.to_html(
                decoded_code,
                language: language,
                theme: theme,
                standalone: false,
                line_numbers: line_numbers
              )
              highlighted
            rescue ex
              Logger.debug "Syntax highlighting failed for language '#{language}': #{ex.message}"
              # Return original match if highlighting fails
              match
            end
          end
        end

        # Escape HTML special characters
        private def escape_html(text : String) : String
          text
            .gsub("&", "&amp;")
            .gsub("<", "&lt;")
            .gsub(">", "&gt;")
            .gsub("\"", "&quot;")
            .gsub("'", "&#39;")
        end

        # Decode common HTML entities
        private def decode_html_entities(text : String) : String
          text
            .gsub("&amp;", "&")
            .gsub("&lt;", "<")
            .gsub("&gt;", ">")
            .gsub("&quot;", "\"")
            .gsub("&#39;", "'")
            .gsub("&nbsp;", " ")
        end
      end
    end
  end
end
