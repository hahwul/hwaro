# Syntax Highlighter for code blocks
#
# This module provides syntax highlighting support by rendering
# code blocks with proper classes for client-side highlighting
# using Highlight.js or similar libraries.
#
# Usage:
#   - Enable in config.toml with [highlight] section
#   - Include CSS/JS in templates using highlight_css and highlight_js helpers
#   - Code blocks will be rendered with language-* classes

require "markd"

module Hwaro
  module Content
    module Processors
      # Custom HTML renderer that adds syntax highlighting support
      # Extends Markd's HTMLRenderer to customize code block output
      class HighlightingRenderer < Markd::HTMLRenderer
        @highlight_enabled : Bool

        def initialize(options : Markd::Options, @highlight_enabled : Bool = true)
          super(options)
        end

        # Override code_block to add highlighting-specific attributes
        def code_block(node : Markd::Node, entering : Bool)
          languages = node.fence_language ? node.fence_language.split : nil
          code_tag_attrs = attrs(node)
          pre_tag_attrs = nil

          lang = code_block_language(languages)

          if @highlight_enabled && lang
            # Add classes for highlight.js
            code_tag_attrs ||= {} of String => String
            code_tag_attrs["class"] = "language-#{escape_lang(lang)} hljs"
          elsif lang
            code_tag_attrs ||= {} of String => String
            code_tag_attrs["class"] = "language-#{escape_lang(lang)}"
          end

          newline
          tag("pre", pre_tag_attrs) do
            tag("code", code_tag_attrs) do
              code_block_body(node, lang)
            end
          end
          newline
        end

        # Escape special HTML characters in language name
        private def escape_lang(text : String) : String
          text
            .gsub("&", "&amp;")
            .gsub("<", "&lt;")
            .gsub(">", "&gt;")
            .gsub("\"", "&quot;")
        end
      end

      # Syntax highlighter module for rendering markdown with highlighting support
      module SyntaxHighlighter
        extend self

        # Render markdown to HTML with syntax highlighting enabled
        # @param content - markdown content to render
        # @param highlight - whether to enable syntax highlighting for code blocks
        # @param safe - if true, raw HTML will not be passed through (replaced by comments)
        def render(content : String, highlight : Bool = true, safe : Bool = false) : String
          options = Markd::Options.new(safe: safe)
          document = Markd::Parser.parse(content, options)
          renderer = HighlightingRenderer.new(options, highlight)
          renderer.render(document)
        end

        # Check if content has code blocks that might benefit from highlighting
        def has_code_blocks?(content : String) : Bool
          content.includes?("```") || content.includes?("~~~")
        end

        # List of supported languages for highlight.js (common ones)
        SUPPORTED_LANGUAGES = %w[
          bash c cpp csharp css crystal dart diff dockerfile elixir elm
          erlang go graphql groovy haskell html http ini java javascript
          json julia kotlin latex less lisp lua makefile markdown matlab
          nginx nim nix objectivec ocaml perl php plaintext powershell
          python r ruby rust scala scss shell sql swift toml typescript
          vim xml yaml zig
        ]

        # Check if a language is supported
        def language_supported?(lang : String) : Bool
          SUPPORTED_LANGUAGES.includes?(lang.downcase)
        end

        # Get CSS themes available for highlight.js
        THEMES = %w[
          default a11y-dark a11y-light agate androidstudio an-old-hope
          arduino-light arta ascetic atom-one-dark atom-one-dark-reasonable
          atom-one-light brown-paper codepen-embed color-brewer dark
          devibeans docco far foundation github github-dark github-dark-dimmed
          googlecode gradient-dark gradient-light grayscale hybrid idea
          intellij-light ir-black isbl-editor-dark isbl-editor-light
          kimbie-dark kimbie-light lightfair lioshi magula mono-blue monokai
          monokai-sublime night-owl nnfx-dark nnfx-light nord obsidian ocean
          paraiso-dark paraiso-light panda-syntax-dark panda-syntax-light
          pojoaque purebasic qtcreator-dark qtcreator-light rainbow school-book
          shades-of-purple srcery stackoverflow-dark stackoverflow-light sunburst
          tokyo-night-dark tokyo-night-light tomorrow-night-blue
          tomorrow-night-bright vs vs2015 xcode xt256 zenburn
        ]

        # Check if a theme is valid
        def theme_valid?(theme : String) : Bool
          THEMES.includes?(theme.downcase)
        end
      end
    end
  end
end
