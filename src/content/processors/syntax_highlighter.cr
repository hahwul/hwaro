# Syntax Highlighter for code blocks
#
# This module provides syntax highlighting for code blocks in HTML content
# using the tartrazine library. It processes <pre><code> elements and
# applies syntax highlighting based on the language specified in the
# class attribute (e.g., class="language-crystal").
#
# Usage:
#   html = SyntaxHighlighter.highlight(html_content, theme: "monokai")

require "tartrazine"

module Hwaro
  module Content
    module Processors
      # Syntax highlighter for code blocks in HTML content
      module SyntaxHighlighter
        extend self

        # Default theme to use if none specified
        DEFAULT_THEME = "monokai"

        # Regex pattern for matching code blocks with language specification
        #
        # Pattern breakdown:
        #   <pre><code\s+         - Match opening <pre><code with whitespace
        #   class="               - Start of class attribute
        #   (?:[^"]*\s)?          - Optional: any text followed by space (for additional classes before language-)
        #   language-             - The language- prefix
        #   (?<lang>[^\s"]+)      - Named capture: the language identifier (no spaces or quotes)
        #   (?:\s[^"]*)?          - Optional: space followed by additional class names
        #   "                     - End of class attribute value
        #   [^>]*>                - Any other attributes until closing >
        #   (?<code>.*?)          - Named capture: the code content (non-greedy)
        #   <\/code><\/pre>       - Closing tags
        #
        # The /m flag enables multiline mode so .*? matches across newlines
        CODE_BLOCK_PATTERN = /<pre><code\s+class="(?:[^"]*\s)?language-(?<lang>[^\s"]+)(?:\s[^"]*)?"[^>]*>(?<code>.*?)<\/code><\/pre>/m

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
          apply_highlighting(code, language, theme, line_numbers) do
            "<pre><code>#{escape_html(code)}</code></pre>"
          end
        end

        # Process HTML content and highlight code blocks using regex
        private def highlight_with_regex(
          html : String,
          theme : String,
          line_numbers : Bool,
        ) : String
          html.gsub(CODE_BLOCK_PATTERN) do |match, match_data|
            language = match_data["lang"]
            code = match_data["code"]

            # Decode HTML entities in the code
            decoded_code = decode_html_entities(code)

            apply_highlighting(decoded_code, language, theme, line_numbers) do
              # Return original match if highlighting fails
              match
            end
          end
        end

        # Apply syntax highlighting to code using Tartrazine
        # Yields to block on failure for custom fallback behavior
        private def apply_highlighting(
          code : String,
          language : String,
          theme : String,
          line_numbers : Bool,
          &fallback : -> String,
        ) : String
          Tartrazine.to_html(
            code,
            language: language,
            theme: theme,
            standalone: false,
            line_numbers: line_numbers
          )
        rescue ex
          Hwaro::Logger.debug "Syntax highlighting failed for language '#{language}': #{ex.message}"
          yield
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
