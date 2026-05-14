# Shared inline-markdown renderer.
#
# Used by table cells (`table_parser.cr`), definition lists, and footnote bodies
# (`markdown_extensions.cr`) — places where Markd's block parser doesn't run but
# we still want `**bold**`/`*em*`/`` `code` ``/`[link](url)`/`![alt](url)`/`~~del~~`.
# Keeping the renderer in one module prevents the implementations from drifting
# apart (e.g. one supporting strikethrough, another not).
#
# `safe_url?` is also the single source of truth for URL-scheme sanitization
# used in markdown-generated `<a>`/`<img>` tags.

require "html"
require "uri"

module Hwaro
  module Content
    module Processors
      module InlineMarkdown
        extend self

        # Schemes that must be blocked in `<a href="…">` / `<img src="…">` even
        # when Markd's `safe` option is off. `data:` is allowed only for image
        # MIME types (matching Markd's own `UNSAFE_DATA_PROTOCOL`).
        UNSAFE_PROTOCOL_RE      = /^\s*(javascript|vbscript|file|data):/i
        UNSAFE_DATA_PROTOCOL_RE = /^\s*data:image\/(?:png|gif|jpeg|webp)/i

        INLINE_CODE_SPAN_RE         = /`([^`]+)`/
        INLINE_IMAGE_RE             = /!\[([^\]]*)\]\(([^)]*)\)/
        INLINE_LINK_RE              = /\[([^\]]+)\]\(([^)]*)\)/
        INLINE_BOLD_ASTERISK_RE     = /\*\*(.+?)\*\*/
        INLINE_BOLD_UNDERSCORE_RE   = /__(.+?)__/
        INLINE_ITALIC_ASTERISK_RE   = /\*(.+?)\*/
        INLINE_ITALIC_UNDERSCORE_RE = /(?<![a-zA-Z0-9])_(.+?)_(?![a-zA-Z0-9])/
        INLINE_STRIKETHROUGH_RE     = /~~(.+?)~~/

        # Render a small inline-markdown subset over already-HTML-escaped or
        # raw text. Code spans are extracted first so their content survives
        # the other passes verbatim.
        def render(text : String) : String
          result = HTML.escape(text)

          code_spans = [] of String
          result = result.gsub(INLINE_CODE_SPAN_RE) do
            code_spans << $1
            "\x00CODESPAN#{code_spans.size - 1}\x00"
          end

          result = result.gsub(INLINE_IMAGE_RE) do
            alt = $1
            url = $2
            if safe_url?(url)
              %(<img src="#{HTML.escape(url)}" alt="#{HTML.escape(alt)}">)
            else
              "![#{alt}](#{url})"
            end
          end

          result = result.gsub(INLINE_LINK_RE) do
            link_text = $1
            url = $2
            if safe_url?(url)
              %(<a href="#{HTML.escape(url)}">#{link_text}</a>)
            else
              "[#{link_text}](#{url})"
            end
          end

          result = result.gsub(INLINE_BOLD_ASTERISK_RE) { "<strong>#{$1}</strong>" }
          result = result.gsub(INLINE_BOLD_UNDERSCORE_RE) { "<strong>#{$1}</strong>" }
          result = result.gsub(INLINE_ITALIC_ASTERISK_RE) { "<em>#{$1}</em>" }
          result = result.gsub(INLINE_ITALIC_UNDERSCORE_RE) { "<em>#{$1}</em>" }
          result = result.gsub(INLINE_STRIKETHROUGH_RE) { "<del>#{$1}</del>" }

          code_spans.each_with_index do |content, idx|
            result = result.gsub("\x00CODESPAN#{idx}\x00", "<code>#{content}</code>")
          end

          result
        end

        # Returns true for URLs we're willing to emit in a generated `href`/`src`.
        # Reject `javascript:`, `vbscript:`, `file:`, and non-image `data:` URIs.
        # Percent-decode first so encodings like `java%73cript:` don't slip past.
        def safe_url?(url : String) : Bool
          decoded = URI.decode(url.strip)
          return true if UNSAFE_DATA_PROTOCOL_RE.matches?(decoded)
          !UNSAFE_PROTOCOL_RE.matches?(decoded)
        end
      end
    end
  end
end
