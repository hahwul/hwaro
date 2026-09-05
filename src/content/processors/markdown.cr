# Markdown processor for converting Markdown to HTML
#
# This processor handles:
# - TOML, YAML, and JSON front matter parsing
# - Markdown to HTML conversion using Markd
# - Table of Contents generation with header IDs
# - Syntax highlighting support via HighlightingRenderer

require "markd"
require "yaml"
require "toml"
require "json"
require "xml"
require "html"
require "digest/md5"
require "./base"
require "./table_parser"
require "./syntax_highlighter"
require "./markdown_extensions"
require "./heading_ids"
require "./render_hooks"
require "../../models/toc"
require "../../utils/date_utils"
require "../../utils/errors"
require "../../utils/frontmatter_scanner"
require "../../utils/logger"
require "../../utils/path_utils"
require "../../utils/text_utils"

require "./markdown/frontmatter"
require "./markdown/frontmatter_fields"
require "./markdown/html_post"

module Hwaro
  module Content
    module Processors
      # Markdown processor implementation
      class Markdown < Base
        def name : String
          "markdown"
        end

        def extensions : Array(String)
          [".md", ".markdown"]
        end

        def priority : Int32
          100 # High priority as primary content processor
        end

        def process(content : String, context : ProcessorContext) : ProcessorResult
          html, _toc = render(content)
          ProcessorResult.new(content: html)
        rescue ex
          ProcessorResult.error("Markdown processing failed: #{ex.message}")
        end

        # Renders Markdown to HTML and generates a Table of Contents
        # Returns {html_content, toc_headers}
        # @param highlight - whether to enable syntax highlighting for code blocks
        # @param safe - if true, raw HTML will not be passed through (replaced by comments)
        # @param lazy_loading - if true, adds loading="lazy" to img tags
        # @param emoji - if true, converts emoji shortcodes to emoji characters
        # @param hooks - render-hook context; nil (the default) renders exactly
        #   as before this parameter existed.
        def render(content : String, highlight : Bool = true, safe : Bool = false, lazy_loading : Bool = false, emoji : Bool = false, markdown_config : Models::MarkdownConfig? = nil,
                   hooks : Content::Processors::RenderHooks::HookRenderContext? = nil) : Tuple(String, Array(Models::TocHeader))
          # Tables are converted FIRST: cell bodies render through
          # InlineMarkdown, which HTML-escapes — so the HTML-injecting
          # extension passes (strikethrough/footnote refs/math) must not have
          # touched cell text yet, or their tags get escaped into visible
          # literal markup. The footnote-ref and math passes still reach the
          # generated <td> text afterwards, so refs and `$…$` inside cells
          # keep working. The math flag keeps `$~~x~~$` formula internals in
          # cells out of InlineMarkdown's strikethrough/emphasis passes.
          # `flags` also threads the F10 opt-in inline markup (ins/mark/sub/
          # sup) into cell rendering, alongside the existing math flag.
          processed = TableParser.process(
            content,
            flags: markdown_config ? MarkdownExtensions.inline_flags(markdown_config) : InlineMarkdown::Flags.new,
            hooks: hooks)

          # Pre-process markdown extensions (task lists, footnotes, etc.)
          if md_cfg = markdown_config
            processed = MarkdownExtensions.preprocess(processed, md_cfg)
          end

          # Use SyntaxHighlighter for rendering with highlighting support.
          # Tables were already converted above — skip the redundant re-scan.
          smart = markdown_config.try(&.smart_punctuation) || false
          html = SyntaxHighlighter.render(processed, highlight, safe, smart: smart, tables_preprocessed: true, hooks: hooks)

          # Post-process markdown extensions (footnotes section, mermaid)
          if md_cfg = markdown_config
            html = MarkdownExtensions.postprocess(html, md_cfg)
          end

          has_headers = html.includes?("<h")
          has_images = lazy_loading && html.includes?("<img")

          # Optimization: If no headers and no images (or lazy loading disabled), don't parse XML
          unless has_headers || has_images
            result_html = emoji ? apply_emoji(html) : html
            return {result_html, [] of Models::TocHeader}
          end

          result_html, toc = post_process_html(html, has_headers, has_images)
          result_html = apply_emoji(result_html) if emoji
          {result_html, toc}
        rescue ex : XML::Error
          Logger.debug "Markdown post-process: XML error, returning raw html: #{ex.message}"
          {(html || ""), [] of Models::TocHeader}
        end
      end

      # Register the markdown processor by default
      Registry.register(Markdown.new)
    end
  end
end

# Backward compatibility module alias
module Hwaro
  module Processor
    module Markdown
      extend self

      # Create shared instance for module-level access
      @@instance = Content::Processors::Markdown.new

      # The site's [markdown] config, published for template filters
      # (currently `markdownify`) that have no per-call config access.
      # Set once per build in Phases::Initialize — mirroring
      # `SyntaxHighlighter.server_mode` — so `serve` config reloads
      # propagate; nil in library/spec contexts keeps the bare defaults.
      class_property filter_markdown_config : Models::MarkdownConfig? = nil

      # Renders Markdown to HTML and generates a Table of Contents
      # @param highlight - whether to enable syntax highlighting for code blocks
      # @param safe - if true, raw HTML will not be passed through (replaced by comments)
      # @param lazy_loading - if true, adds loading="lazy" to img tags
      # @param emoji - if true, converts emoji shortcodes to emoji characters
      # @param hooks - render-hook context; nil (the default) renders exactly
      #   as before this parameter existed.
      def render(content : String, highlight : Bool = true, safe : Bool = false, lazy_loading : Bool = false, emoji : Bool = false, markdown_config : Models::MarkdownConfig? = nil,
                 hooks : Content::Processors::RenderHooks::HookRenderContext? = nil) : Tuple(String, Array(Models::TocHeader))
        @@instance.render(content, highlight, safe, lazy_loading, emoji, markdown_config, hooks: hooks)
      end

      # Memoized body render for the Generate-phase fallbacks: on warm
      # --cache builds (and in streaming mode) feeds and search hit pages
      # whose `page.content` is empty because the Render phase skipped
      # them, and the same page can be re-rendered up to four times in one
      # build (feed summary + full body + section feed + search index).
      # Output is a pure function of the raw content and the passed
      # options, so it is shared by content digest + options fingerprint.
      #
      # Callers should pass the site's markdown options so fallback bodies
      # match what the render phase produces (safe-mode HTML stripping,
      # emoji, extensions) instead of a default-options approximation.
      #
      # Mutex-guarded — feeds and search run as parallel fibers. The byte
      # cap keeps streaming mode's memory bound: once full, renders still
      # happen, they just stop being remembered.
      @@body_cache = {} of String => String
      @@body_cache_bytes = 0_i64
      @@body_cache_mutex = Mutex.new
      BODY_CACHE_MAX_BYTES = 32_i64 * 1024 * 1024

      # @param hooks - render-hook context for feed/search fallback rendering
      #   (see `RenderHooks.fallback_context`); nil when no registry is
      #   configured, in which case the memo key and render call are
      #   unaffected by this parameter.
      # @param hooks_key - identifies the page for the hook page/config
      #   vars (`"#{page.url}:#{page.language}"`); only consulted when
      #   `hooks` is present, since the vars aren't otherwise part of the
      #   cache key.
      def render_body_cached(content : String, safe : Bool = false, emoji : Bool = false, lazy_loading : Bool = false, markdown_config : Models::MarkdownConfig? = nil,
                             hooks : Content::Processors::RenderHooks::HookRenderContext? = nil, hooks_key : String? = nil) : String
        key = String.build do |io|
          io << (safe ? '1' : '0') << (emoji ? '1' : '0') << (lazy_loading ? '1' : '0') << ':'
          io << Content::Processors::SyntaxHighlighter.body_fingerprint << ':'
          io << (markdown_config.try(&.cache_fingerprint) || "-") << ':'
          io << Digest::MD5.hexdigest(content)
          if hooks
            io << "|hooks:" << hooks.registry_fingerprint << "|" << hooks_key
          end
        end
        @@body_cache_mutex.synchronize do
          if cached = @@body_cache[key]?
            return cached
          end
        end

        html, _ = render(content, safe: safe, lazy_loading: lazy_loading, emoji: emoji, markdown_config: markdown_config, hooks: hooks)

        @@body_cache_mutex.synchronize do
          unless @@body_cache.has_key?(key) || @@body_cache_bytes + html.bytesize > BODY_CACHE_MAX_BYTES
            @@body_cache[key] = html
            @@body_cache_bytes += html.bytesize
          end
        end
        html
      end

      # Returns parsed metadata and content
      def parse(raw_content : String, file_path : String = "")
        @@instance.parse(raw_content, file_path)
      end

      # Renders with anchor links injected into headings (delegates to shared instance)
      def render_with_anchors(content : String, highlight : Bool = true, safe : Bool = false, anchor_style : String = "heading", lazy_loading : Bool = false, emoji : Bool = false, markdown_config : Models::MarkdownConfig? = nil,
                              hooks : Content::Processors::RenderHooks::HookRenderContext? = nil) : Tuple(String, Array(Models::TocHeader))
        @@instance.render_with_anchors(content, highlight, safe, anchor_style, lazy_loading, emoji, markdown_config, hooks: hooks)
      end
    end
  end
end
