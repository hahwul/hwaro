# HTML minification utilities
#
# Provides conservative HTML minification that only removes
# clearly unnecessary content while preserving meaningful whitespace.
#
# Conservative-by-default is a deliberate choice: prior attempts at
# aggressive whitespace collapsing (leading-whitespace strip, inter-tag
# whitespace collapse, etc.) broke content rendering even with
# `<pre>/<textarea>/<script>/<style>` protection. If more aggressive
# output shrinking is required, post-process with an external tool.
#
# Operations:
# - Clean up template-induced whitespace inside <pre> blocks
# - Remove HTML comments (preserving conditional and <!--more--> markers)
# - Strip trailing whitespace from each line
# - Collapse excessive blank lines

module Hwaro
  module Utils
    module HtmlMinifier
      extend self

      # Regex constants for HTML minification
      private REGEX_PRE_OPEN       = /<pre([^>]*)>\s*<code/
      private REGEX_PRE_CLOSE      = /<\/code>\s*<\/pre>/
      private REGEX_COMMENTS       = /<!--(?!\[if|#|\s*more\s*-->).*?-->/m
      private REGEX_TRAILING_SPACE = /[ \t]+$/m
      private REGEX_BLANK_LINES    = /\n{3,}/

      # Perform conservative HTML minification
      #
      # Only removes: HTML comments, trailing whitespace on lines, excessive blank lines
      # Preserves: all meaningful whitespace, newlines, indentation structure
      #
      # Example:
      #   minify("<p>Hello</p>\n\n\n\n<p>World</p>")  # => "<p>Hello</p>\n\n<p>World</p>"
      #
      def minify(html : String) : String
        # Clean up template-induced whitespace inside pre blocks
        # This handles cases like: <pre>\n  <code>content</code>\n</pre>
        # Converting to: <pre><code>content</code></pre>
        cleaned = html
          .gsub(REGEX_PRE_OPEN, "<pre\\1><code")
          .gsub(REGEX_PRE_CLOSE, "</code></pre>")

        # Remove HTML comments (but not conditional comments like <!--[if IE]>)
        # Also preserve <!-- more --> markers used for content summaries
        minified = cleaned.gsub(REGEX_COMMENTS, "")

        # Strip trailing whitespace from each line. Trailing spaces have no
        # rendering effect in HTML anywhere — including inside <pre>, where
        # line-ending whitespace is invisible — so this is safe regardless
        # of context.
        minified = minified.gsub(REGEX_TRAILING_SPACE, "")

        # Collapse 3+ consecutive blank lines to 2
        minified = minified.gsub(REGEX_BLANK_LINES, "\n\n")

        minified.strip
      end
    end
  end
end
