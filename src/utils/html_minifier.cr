# HTML minification utilities
#
# Aggressively shrinks rendered HTML while staying visually equivalent
# to the input. Two ideas keep it safe:
#
#   1. Whitespace-sensitive elements (<pre>, <textarea>, <script>,
#      <style>, <code>, <svg>, <math>, <noscript>) are extracted as
#      opaque blocks before any whitespace pass touches the document
#      and restored verbatim at the end. Each tag is handled in its
#      own pass so a stray alternation in non-greedy matching can't
#      pair an open <pre> with a close </script>.
#
#   2. Inter-tag whitespace is collapsed by classifying both
#      neighboring tag names. Between two block-level tags whitespace
#      is removed entirely; otherwise it collapses to a single space,
#      preserving the visible gap between adjacent inline elements
#      (e.g. `<a>x</a> <a>y</a>`).
#
# What is NOT done: variable renaming, attribute rewriting, or
# entity collapsing. For more aggressive output shrinking, post-process
# with a dedicated tool (`html-minifier-terser`, `minify-html`).

module Hwaro
  module Utils
    module HtmlMinifier
      extend self

      # HTML block-level elements. Whitespace between two block-level
      # neighbors has no visual effect (the user agent renders them on
      # separate lines anyway), so it is safe to strip entirely.
      # Anything not listed here is treated as inline, where whitespace
      # between siblings collapses to a single rendered space and must
      # therefore be kept as one literal space.
      BLOCK_TAGS = Set{
        "address", "article", "aside", "base", "blockquote", "body",
        "caption", "col", "colgroup", "dd", "details", "dialog",
        "div", "dl", "dt", "fieldset", "figcaption", "figure",
        "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
        "head", "header", "hgroup", "hr", "html", "iframe",
        "li", "link", "main", "meta", "nav", "noscript",
        "ol", "p", "picture", "pre", "script", "section",
        "source", "style", "summary", "table", "tbody", "td",
        "tfoot", "th", "thead", "title", "tr", "track", "ul",
        "video", "audio", "canvas",
      }

      # Tags whose content must be preserved verbatim. Extracted into
      # placeholders before any whitespace pass and restored afterward.
      # `code` is included because inline-code snippets often carry
      # whitespace that authors expect to ship unchanged.
      PROTECTED_TAGS = %w[pre textarea script style code svg math noscript]

      # Sentinel format for protected blocks. `\x00` is illegal in HTML,
      # so the placeholder cannot collide with author content.
      private PRESERVE_PREFIX = "\x00HW_HTML_P_"
      private PRESERVE_SUFFIX = "\x00"

      # Regex constants
      private REGEX_COMMENTS       = /<!--(?!\[if|#|\s*more\s*-->).*?-->/m
      private REGEX_TRAILING_SPACE = /[ \t]+$/m
      # Match a complete tag immediately followed by whitespace and
      # lookahead at the next tag. Captures:
      #   $1 = "/" or "" on the prior tag
      #   $2 = prior tag's name
      #   $3 = prior tag's attribute slice (may contain a self-closing /)
      #   $4 = whitespace run
      #   $5 = "/" or "" on the next tag
      #   $6 = next tag's name
      private REGEX_INTERTAG_WS    = /(<\/?)([A-Za-z][\w-]*)([^>]*)>(\s+)(?=<(\/?)([A-Za-z][\w-]*))/
      private REGEX_BLANK_LINES    = /\n{2,}/
      private REGEX_PRESERVE_TOKEN = /\x00HW_HTML_P_(\d+)\x00/

      # Minify the given HTML.
      #
      # Example:
      #   minify("<div>\n  <p>Hello</p>\n</div>")
      #   # => "<div><p>Hello</p></div>"
      #
      #   minify("<span>x</span>\n<span>y</span>")
      #   # => "<span>x</span> <span>y</span>"
      def minify(html : String) : String
        preserves = [] of String
        result = protect_sensitive_blocks(html, preserves)
        result = result.gsub(REGEX_COMMENTS, "")
        result = result.gsub(REGEX_TRAILING_SPACE, "")
        result = collapse_inter_tag_whitespace(result)
        result = result.gsub(REGEX_BLANK_LINES, "\n")
        result = restore_sensitive_blocks(result, preserves)
        result.strip
      end

      # Extract whitespace-sensitive elements one tag at a time. A
      # single regex with alternation in the open/close tag (e.g.
      # `<(pre|script)>...</(pre|script)>`) does not enforce that both
      # sides reference the same tag, which let prior implementations
      # pair `<pre>` openers with `</script>` closers when the document
      # mixed both. One pass per tag avoids that whole class of bug.
      private def protect_sensitive_blocks(html : String, preserves : Array(String)) : String
        result = html
        PROTECTED_TAGS.each do |tag|
          pattern = Regex.new(
            "<#{tag}\\b[^>]*>.*?</#{tag}\\s*>",
            Regex::Options::IGNORE_CASE | Regex::Options::MULTILINE
          )
          result = result.gsub(pattern) do |match|
            idx = preserves.size
            preserves << match
            "#{PRESERVE_PREFIX}#{idx}#{PRESERVE_SUFFIX}"
          end
        end
        result
      end

      private def restore_sensitive_blocks(html : String, preserves : Array(String)) : String
        html.gsub(REGEX_PRESERVE_TOKEN) do
          idx = $1.to_i
          idx < preserves.size ? preserves[idx] : $0
        end
      end

      # Collapse whitespace between two tags according to neighbor type.
      # Both block-level → strip entirely. Otherwise → single space, so
      # adjacent inline siblings keep their visible gap.
      private def collapse_inter_tag_whitespace(html : String) : String
        html.gsub(REGEX_INTERTAG_WS) do
          slash_prev = $1
          name_prev = $2
          attrs_prev = $3
          # $4 = whitespace run (discarded)
          name_next = $6

          rebuilt = "#{slash_prev}#{name_prev}#{attrs_prev}>"
          if BLOCK_TAGS.includes?(name_prev.downcase) && BLOCK_TAGS.includes?(name_next.downcase)
            rebuilt
          else
            "#{rebuilt} "
          end
        end
      end
    end
  end
end
