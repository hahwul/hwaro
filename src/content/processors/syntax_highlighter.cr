# Syntax Highlighter for code blocks
#
# This module provides syntax highlighting support by rendering
# code blocks with proper classes for client-side highlighting
# using Highlight.js or similar libraries.
#
# With `[highlight] mode = "server"`, code is highlighted at build time
# instead: Tartrazine lexers tokenize the code and tokens are emitted as
# spans with Highlight.js-compatible CSS classes, so existing hljs themes
# keep working and no JavaScript ships to the browser.
#
# Usage:
#   - Enable in config.toml with [highlight] section
#   - Include CSS/JS in templates using highlight_css and highlight_js helpers
#   - Code blocks will be rendered with language-* classes

require "markd"
require "tartrazine"
require "./table_parser"
require "./markdown_extensions"
require "set"

module Hwaro
  module Content
    module Processors
      # Build-time highlighter: Tartrazine lexers + hljs-compatible classes.
      module ServerHighlighter
        extend self

        # Pygments/Chroma token-type prefixes mapped to Highlight.js classes,
        # checked in order — first matching prefix wins, so more specific
        # prefixes must precede their generic parent (KeywordType before Keyword).
        TOKEN_CLASS_PREFIXES = [
          {"CommentPreproc", "hljs-meta"},
          {"Comment", "hljs-comment"},
          {"KeywordConstant", "hljs-literal"},
          {"KeywordType", "hljs-type"},
          {"Keyword", "hljs-keyword"},
          {"NameKeyword", "hljs-keyword"},
          {"NameAttribute", "hljs-attr"},
          {"NameBuiltin", "hljs-built_in"},
          {"NameClass", "hljs-title class_"},
          {"NameConstant", "hljs-variable constant_"},
          {"NameDecorator", "hljs-meta"},
          {"NameEntity", "hljs-symbol"},
          {"NameException", "hljs-title class_"},
          {"NameFunction", "hljs-title function_"},
          {"NameLabel", "hljs-symbol"},
          {"NameNamespace", "hljs-title class_"},
          {"NameProperty", "hljs-property"},
          {"NameTag", "hljs-name"},
          {"NameVariable", "hljs-variable"},
          {"NameOperator", "hljs-operator"},
          {"LiteralDate", "hljs-string"},
          {"LiteralNumber", "hljs-number"},
          {"LiteralStringEscape", "hljs-string"},
          {"LiteralStringInterpol", "hljs-subst"},
          {"LiteralStringRegex", "hljs-regexp"},
          {"LiteralStringSymbol", "hljs-symbol"},
          {"LiteralStringDoc", "hljs-doctag"},
          {"LiteralString", "hljs-string"},
          {"Literal", "hljs-literal"},
          {"OperatorWord", "hljs-keyword"},
          {"Operator", "hljs-operator"},
          {"Punctuation", "hljs-punctuation"},
          {"GenericDeleted", "hljs-deletion"},
          {"GenericInserted", "hljs-addition"},
          {"GenericHeading", "hljs-section"},
          {"GenericSubheading", "hljs-section"},
          {"GenericEmph", "hljs-emphasis"},
          {"GenericStrong", "hljs-strong"},
          {"GenericPrompt", "hljs-meta prompt_"},
        ]

        # Precomputed token-type → hljs class for every known token type.
        # Built once at program start from Tartrazine's own type list, so
        # lookups during parallel rendering are read-only and fiber-safe.
        TOKEN_CLASSES = begin
          map = {} of String => String?
          Tartrazine::Abbreviations.each_key do |token_type|
            map[token_type] = resolve_class(token_type)
          end
          map
        end

        # Languages Tartrazine has no lexer for — remembered to avoid
        # re-raising on every code block of that language.
        @@unknown_languages = Set(String).new
        @@unknown_mutex = Mutex.new

        # Highlight `code` as `lang`, returning HTML-escaped markup with
        # hljs-class spans — or nil when no lexer exists for the language
        # (callers fall back to plain client-style output).
        def highlight(code : String, lang : String) : String?
          normalized = lang.downcase
          return if @@unknown_mutex.synchronize { @@unknown_languages.includes?(normalized) }

          lexer = begin
            Tartrazine.lexer(normalized)
          rescue
            @@unknown_mutex.synchronize { @@unknown_languages << normalized }
            Logger.debug "Server highlight: no lexer for '#{normalized}', falling back to plain output"
            return
          end

          String.build do |io|
            lexer.tokenizer(code).each do |token|
              value = HTML.escape(token[:value])
              if css_class = class_for(token[:type])
                io << %(<span class=") << css_class << %(">) << value << "</span>"
              else
                io << value
              end
            end
          end
        rescue ex
          # A lexer bug must never take down the build — degrade to plain.
          Logger.debug "Server highlight failed for '#{lang}': #{ex.message}"
          nil
        end

        private def class_for(token_type : String) : String?
          return TOKEN_CLASSES[token_type] if TOKEN_CLASSES.has_key?(token_type)
          resolve_class(token_type)
        end

        private def resolve_class(token_type : String) : String?
          TOKEN_CLASS_PREFIXES.each do |prefix, css_class|
            return css_class if token_type.starts_with?(prefix)
          end
          nil
        end
      end

      # Custom HTML renderer that adds syntax highlighting support
      # Extends Markd's HTMLRenderer to customize code block output
      class HighlightingRenderer < Markd::HTMLRenderer
        @highlight_enabled : Bool
        @server_mode : Bool

        def initialize(options : Markd::Options, @highlight_enabled : Bool = true, @server_mode : Bool = false)
          super(options)
        end

        # In server mode, emit pre-highlighted spans instead of plain escaped
        # text. Falls back to the default escaped output when the language has
        # no lexer (the `language-*` class is still present for styling).
        def code_block_body(node : Markd::Node, lang : String?)
          if @highlight_enabled && @server_mode && lang
            if highlighted = ServerHighlighter.highlight(node.text, lang)
              return literal(highlighted)
            end
          end
          super
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
          HTML.escape(text)
        end
      end

      # Syntax highlighter module for rendering markdown with highlighting support
      module SyntaxHighlighter
        extend self

        # Build-wide highlighting mode, set from `[highlight] mode` when the
        # build initializes. Read-only during rendering, so parallel render
        # fibers can consult it without synchronization.
        @@server_mode = false

        def server_mode=(value : Bool)
          @@server_mode = value
        end

        def server_mode? : Bool
          @@server_mode
        end

        # Render markdown to HTML with syntax highlighting enabled
        # @param content - markdown content to render
        # @param highlight - whether to enable syntax highlighting for code blocks
        # @param safe - if true, raw HTML will not be passed through (replaced by comments)
        def render(content : String, highlight : Bool = true, safe : Bool = false) : String
          # Pre-process tables before passing to markd (markd doesn't support GFM tables)
          processed_content = TableParser.process(content)

          options = Markd::Options.new(safe: safe)
          document = Markd::Parser.parse(processed_content, options)
          renderer = HighlightingRenderer.new(options, highlight, @@server_mode)
          renderer.render(document)
        end

        # Check if content has code blocks that might benefit from highlighting
        def has_code_blocks?(content : String) : Bool
          content.includes?("```") || content.includes?("~~~")
        end

        # List of supported languages for highlight.js (common ones)
        SUPPORTED_LANGUAGES = Set.new(%w[
          bash c cpp csharp css crystal dart diff dockerfile elixir elm
          erlang go graphql groovy haskell html http ini java javascript
          json julia kotlin latex less lisp lua makefile markdown matlab
          nginx nim nix objectivec ocaml perl php plaintext powershell
          python r ruby rust scala scss shell sql swift toml typescript
          vim xml yaml zig
        ])

        # Check if a language is supported
        def language_supported?(lang : String) : Bool
          SUPPORTED_LANGUAGES.includes?(lang.downcase)
        end

        # Get CSS themes available for highlight.js
        THEMES = Set.new(%w[
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
        ])

        # Check if a theme is valid
        def theme_valid?(theme : String) : Bool
          THEMES.includes?(theme.downcase)
        end
      end
    end
  end
end
