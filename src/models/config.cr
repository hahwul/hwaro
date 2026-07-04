require "toml"
require "uri"
require "./deployment"
require "../utils/errors"
require "../utils/text_utils"
require "../utils/env_substitutor"
require "../utils/path_utils"

module Hwaro
  module Models
    # Cache-busting query suffix shared by the asset/highlight tag emitters.
    def self.cache_bust_suffix(value : String) : String
      value.empty? ? "" : "?v=#{HTML.escape(value)}"
    end

    # Join non-empty tag fragments with newlines.
    def self.join_tags(*parts : String) : String
      parts.reject(&.empty?).join("\n")
    end

    class SitemapConfig
      property enabled : Bool
      property filename : String
      property changefreq : String
      property priority : Float64
      property exclude : Array(String)

      def initialize
        @enabled = false
        @filename = "sitemap.xml"
        @changefreq = "weekly"
        @priority = 0.5
        @exclude = [] of String
      end
    end

    class RobotsRule
      property user_agent : String
      property allow : Array(String)
      property disallow : Array(String)

      def initialize(user_agent : String)
        @user_agent = user_agent
        @allow = [] of String
        @disallow = [] of String
      end
    end

    class RobotsConfig
      property enabled : Bool
      property filename : String
      property rules : Array(RobotsRule)

      def initialize
        @enabled = true
        @filename = "robots.txt"
        @rules = [] of RobotsRule
      end
    end

    class LlmsConfig
      property enabled : Bool
      property filename : String
      property instructions : String
      property full_enabled : Bool
      property full_filename : String

      def initialize
        @enabled = true
        @filename = "llms.txt"
        @instructions = ""
        @full_enabled = false
        @full_filename = "llms-full.txt"
      end
    end

    class SearchConfig
      property enabled : Bool
      property format : String
      property fields : Array(String)
      property filename : String
      property exclude : Array(String)
      property tokenize_cjk : Bool

      def initialize
        @enabled = false
        @format = "fuse_json"
        @fields = ["title", "content"]
        @filename = "search.json"
        @exclude = [] of String
        @tokenize_cjk = false
      end
    end

    class FeedConfig
      property enabled : Bool
      property filename : String
      property type : String
      property truncate : Int32
      property limit : Int32
      property sections : Array(String)
      property default_language_only : Bool
      property full_content : Bool

      def initialize
        @enabled = false
        @filename = ""
        @type = "rss"
        @truncate = 0
        @limit = 10
        @sections = [] of String
        @default_language_only = true
        @full_content = true
      end
    end

    # Series configuration
    class SeriesConfig
      property enabled : Bool

      def initialize
        @enabled = false
      end
    end

    # Related posts configuration
    class RelatedConfig
      property enabled : Bool
      property limit : Int32
      property taxonomies : Array(String)

      def initialize
        @enabled = false
        @limit = 5
        @taxonomies = ["tags"]
      end
    end

    # Plugin configuration for extensibility
    class PluginConfig
      property processors : Array(String)

      def initialize
        @processors = ["markdown"] # Default processor
      end
    end

    # Content file publishing configuration
    #
    # Allows copying non-Markdown files from `content/` to the output directory
    # (e.g. `content/about/profile.jpg` -> `/about/profile.jpg`).
    class ContentFilesConfig
      property allow_extensions : Array(String)
      property disallow_extensions : Array(String)
      property disallow_paths : Array(String)

      def initialize
        @allow_extensions = [] of String
        @disallow_extensions = [] of String
        @disallow_paths = [] of String
      end

      def enabled? : Bool
        @allow_extensions.present?
      end

      def publish?(relative_path : String) : Bool
        normalized_path = ContentFilesConfig.normalize_path(relative_path)
        ext = File.extname(normalized_path).downcase
        return false if ext.empty?
        return false if ext == ".md"
        return false unless @allow_extensions.includes?(ext)
        return false if @disallow_extensions.includes?(ext)
        @disallow_paths.each do |pattern|
          # A malformed glob is treated as non-matching by glob_match?, so a
          # config typo can't crash the build; other patterns still apply.
          return false if Utils::PathUtils.glob_match?(pattern, normalized_path)
        end
        true
      end

      def self.normalize_extensions(values : Array(String)) : Array(String)
        values.compact_map do |ext|
          normalize_extension(ext)
        end.uniq!
      end

      def self.normalize_paths(values : Array(String)) : Array(String)
        values.compact_map do |pattern|
          normalized = normalize_path(pattern)
          normalized.empty? ? nil : normalized
        end
      end

      def self.normalize_path(path : String) : String
        path = path.strip.gsub('\\', '/')
        path = path.lchop("/")
        path = path.lchop("content/")
        path
      end

      private def self.normalize_extension(ext : String) : String?
        ext = ext.strip.downcase
        return if ext.empty?
        ext.starts_with?(".") ? ext : ".#{ext}"
      end
    end

    # `hwaro new` content scaffolding configuration.
    #
    # Controls what `hwaro new` writes when there is no matching archetype:
    #   - `front_matter_format` — "toml" (default) or "yaml"
    #   - `default_fields`      — extra front matter keys (e.g. "description")
    #     emitted with empty values so users can fill them in without having
    #     to remember them.
    #   - `bundle`              — when true, new pages default to the
    #     leaf-bundle layout (`foo/index.md`) instead of a single file
    #     (`foo.md`), which is the shape needed for multilingual siblings
    #     and colocated page assets. Overridden by an archetype's own
    #     `<!-- hwaro: bundle -->` directive, and by `--bundle`/`--no-bundle`
    #     on the CLI (CLI > archetype > config).
    #
    # Fields listed in `default_fields` that overlap with built-ins
    # (`title`, `date`, `draft`, `tags`) are ignored because those have
    # dedicated handling and values.
    class ContentNewConfig
      FORMAT_TOML    = "toml"
      FORMAT_YAML    = "yaml"
      FORMAT_JSON    = "json"
      VALID_FORMATS  = {FORMAT_TOML, FORMAT_YAML, FORMAT_JSON}
      BUILTIN_FIELDS = {"title", "date", "draft", "tags"}

      property front_matter_format : String
      property default_fields : Array(String)
      property bundle : Bool

      def initialize
        @front_matter_format = FORMAT_TOML
        @default_fields = ["description"]
        @bundle = false
      end

      def toml? : Bool
        @front_matter_format == FORMAT_TOML
      end

      def yaml? : Bool
        @front_matter_format == FORMAT_YAML
      end

      def json? : Bool
        @front_matter_format == FORMAT_JSON
      end

      # Extra fields, with built-ins filtered out and duplicates removed,
      # preserving configured order.
      def extra_fields : Array(String)
        @default_fields.reject { |f| BUILTIN_FIELDS.includes?(f) }.uniq!
      end
    end

    # Auto-includes configuration for automatic CSS/JS loading
    class AutoIncludesConfig
      property enabled : Bool
      property dirs : Array(String)

      def initialize
        @enabled = false
        @dirs = [] of String
      end

      # Generate CSS link tags for files in configured directories
      def css_tags(base_url : String = "", cache_bust : String = "") : String
        collect_tags("css", base_url, cache_bust) do |url|
          %(<link rel="stylesheet" href="#{url}">)
        end
      end

      # Generate JS script tags for files in configured directories
      def js_tags(base_url : String = "", cache_bust : String = "") : String
        collect_tags("js", base_url, cache_bust) do |url|
          %(<script src="#{url}"></script>)
        end
      end

      private def collect_tags(extension : String, base_url : String, cache_bust : String, & : String -> String) : String
        return "" unless @enabled
        return "" if @dirs.empty?

        suffix = Models.cache_bust_suffix(cache_bust)
        tags = [] of String
        @dirs.each do |dir|
          static_dir = File.join("static", dir)
          next unless Dir.exists?(static_dir)

          Dir.glob(File.join(static_dir, "**", "*.#{extension}")).sort.each do |file|
            relative_path = file.sub(/^static\/?/, "/")
            tags << yield(HTML.escape("#{base_url}#{relative_path}#{suffix}"))
          end
        end
        tags.join("\n")
      end

      # Generate both CSS and JS tags
      def all_tags(base_url : String = "", cache_bust : String = "") : String
        css = css_tags(base_url, cache_bust)
        js = js_tags(base_url, cache_bust)
        Models.join_tags(css, js)
      end
    end

    # Pagination configuration
    class PaginationConfig
      property enabled : Bool
      property per_page : Int32

      def initialize
        @enabled = false
        @per_page = 10
      end
    end

    # Auto-generated OG image configuration
    class AutoImageConfig
      property enabled : Bool
      property background : String
      property text_color : String
      property accent_color : String

      # Optional second color for two-tone geometric styles (split / brutalist).
      # When nil, a complementary tone is auto-derived from accent_color.
      property secondary_color : String?

      property font_size : Int32
      property logo : String?
      property output_dir : String
      property show_title : Bool
      property style : String
      property pattern_opacity : Float64
      property pattern_scale : Float64
      property background_image : String?
      property overlay_opacity : Float64
      property format : String
      property font_path : String?
      property logo_position : String

      # Controls a semi-transparent panel behind the title/description area.
      # Higher values make text more readable on busy/artistic backgrounds
      # while still letting the background show through (0.0 = disabled).
      # Modern editorial/brand styles benefit from 0.25~0.45.
      property text_panel : Float64

      # Whether to draw the thin top/bottom accent bars using accent_color.
      # These are the classic "old school" OG accent lines, drawn for the
      # pattern styles (default / dots / grid / diagonal / gradient / waves).
      # Off by default for a cleaner, more modern look; set to true to opt in.
      property accent_bars : Bool

      # If true, skip automatic OG image generation during `hwaro serve`.
      # Images will be generated on-demand the first time they are requested
      # from the dev server. Greatly improves initial serve time on large sites.
      property lazy_generate : Bool

      def initialize
        @enabled = false
        @background = "#1a1a2e"
        @text_color = "#ffffff"
        @accent_color = "#e94560"
        @secondary_color = nil
        @font_size = 48
        @logo = nil
        @output_dir = "og-images"
        @show_title = true
        @style = "default"
        @pattern_opacity = 0.12
        @pattern_scale = 1.0
        @background_image = nil
        @overlay_opacity = 0.45
        # PNG is the default because social platforms (Facebook, X/Twitter,
        # LinkedIn, Slack, Discord, iMessage) do not render SVG og:image —
        # an SVG preview silently shows nothing. Generation falls back to SVG
        # automatically if PNG font initialization is unavailable.
        @format = "png"
        @font_path = nil
        @logo_position = "bottom-left"
        @text_panel = 0.0
        @accent_bars = false
        @lazy_generate = false
      end
    end

    # OpenGraph and Twitter Card configuration
    class OpenGraphConfig
      property default_image : String?
      property twitter_card : String
      property twitter_site : String?
      property twitter_creator : String?
      property fb_app_id : String?
      property og_type : String
      property auto_image : AutoImageConfig

      def initialize
        @default_image = nil
        @twitter_card = "summary_large_image"
        @twitter_site = nil
        @twitter_creator = nil
        @fb_app_id = nil
        @og_type = "article"
        @auto_image = AutoImageConfig.new
      end

      # Append a single conditional `<meta>` line (leading newline + 2-space
      # indent) for the OG/Twitter tag builders.
      private def append_meta(str, attr : String, name : String, value : String)
        str << %(\n  <meta #{attr}="#{name}" content="#{Utils::TextUtils.escape_xml(value)}">)
      end

      # Generate OG meta tags.
      #
      # `og_type_override` lets the renderer force `og:type="website"` for
      # the homepage, section indexes, taxonomy listings, and the 404
      # page — the configured `@og_type` ("article" by default) only fits
      # content pages. See render.cr's `og_type_for` helper (gh#522).
      def og_tags(
        title : String,
        description : String?,
        url : String,
        image : String?,
        base_url : String,
        og_type_override : String? = nil,
      ) : String
        og_type = og_type_override || @og_type
        # Subsequent lines are joined with `\n  ` so the rendered output
        # keeps the same 2-space indent the scaffold templates use for the
        # `{{ og_all_tags }}` line. Without this, only the first tag picks
        # up the template's indent and the rest start at column 0.
        String.build(256) do |str|
          str << %(<meta property="og:title" content="#{Utils::TextUtils.escape_xml(title)}">\n  )
          str << %(<meta property="og:type" content="#{Utils::TextUtils.escape_xml(og_type)}">\n  )
          str << %(<meta property="og:url" content="#{Utils::TextUtils.escape_xml(base_url)}#{Utils::TextUtils.escape_xml(url)}">)
          if desc = description
            append_meta(str, "property", "og:description", desc)
          end
          if img_url = resolve_image_url(image, base_url)
            append_meta(str, "property", "og:image", img_url)
          end
          if fb_id = @fb_app_id
            append_meta(str, "property", "fb:app_id", fb_id)
          end
        end
      end

      # Generate Twitter Card meta tags
      def twitter_tags(
        title : String,
        description : String?,
        image : String?,
        base_url : String,
      ) : String
        # A "summary_large_image" card with no image renders as a blank preview
        # on most platforms, so downgrade to the plain "summary" card when this
        # page resolves to no image (e.g. auto OG images disabled and no
        # per-page or default image set).
        img_url = resolve_image_url(image, base_url)
        card = (@twitter_card == "summary_large_image" && img_url.nil?) ? "summary" : @twitter_card

        # See `og_tags` above for why subsequent lines are pre-indented.
        String.build(256) do |str|
          str << %(<meta name="twitter:card" content="#{Utils::TextUtils.escape_xml(card)}">\n  )
          str << %(<meta name="twitter:title" content="#{Utils::TextUtils.escape_xml(title)}">)
          if desc = description
            append_meta(str, "name", "twitter:description", desc)
          end
          if img_url
            append_meta(str, "name", "twitter:image", img_url)
          end
          if site = @twitter_site
            append_meta(str, "name", "twitter:site", site)
          end
          if creator = @twitter_creator
            append_meta(str, "name", "twitter:creator", creator)
          end
        end
      end

      # Resolve an image path to an absolute URL, falling back to default_image
      def resolve_image_url(image : String?, base_url : String) : String?
        img = image || @default_image
        return unless img
        img.starts_with?("http") ? img : "#{base_url}#{img.starts_with?("/") ? img : "/#{img}"}"
      end

      # Generate both OG and Twitter tags
      def all_tags(
        title : String,
        description : String?,
        url : String,
        image : String?,
        base_url : String,
        og_type_override : String? = nil,
      ) : String
        og = og_tags(title, description, url, image, base_url, og_type_override)
        twitter = twitter_tags(title, description, image, base_url)
        Models.join_tags(og, twitter)
      end
    end

    # Syntax highlighting configuration
    class HighlightConfig
      property enabled : Bool
      property theme : String
      property use_cdn : Bool
      # "client" injects Highlight.js and highlights in the browser;
      # "server" highlights at build time (Tartrazine lexers, hljs-compatible
      # CSS classes) so no JavaScript ships — theme CSS keeps working either way.
      property mode : String
      # Global default for fence-level `linenos` (see FenceOptions): when
      # true, every fenced code block with a language gets line numbers
      # unless it opts out with a per-block `{linenos=false}`. Off by
      # default so existing output is unaffected.
      property line_numbers : Bool

      def initialize
        @enabled = true
        @theme = "github"
        @use_cdn = true
        @mode = "client"
        @line_numbers = false
      end

      # True when code is highlighted at build time (no client-side JS).
      def server? : Bool
        @mode == "server"
      end

      # Generate the CSS link tag for highlighting
      def css_tag(cache_bust : String = "") : String
        return "" unless @enabled
        safe_theme = HTML.escape(@theme)
        if @use_cdn
          %(<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/#{safe_theme}.min.css">)
        else
          suffix = Models.cache_bust_suffix(cache_bust)
          %(<link rel="stylesheet" href="/assets/css/highlight/#{safe_theme}.min.css#{suffix}">)
        end
      end

      # Generate the JS script tag for highlighting.
      # Server-side highlighting needs no JavaScript at all.
      def js_tag(cache_bust : String = "") : String
        return "" unless @enabled
        return "" if server?
        if @use_cdn
          %(<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>\n<script>hljs.highlightAll();</script>)
        else
          suffix = Models.cache_bust_suffix(cache_bust)
          %(<script src="/assets/js/highlight.min.js#{suffix}"></script>\n<script>hljs.highlightAll();</script>)
        end
      end

      # Generate both CSS and JS tags
      def tags(cache_bust : String = "") : String
        return "" unless @enabled
        js = js_tag(cache_bust)
        js.empty? ? css_tag(cache_bust) : "#{css_tag(cache_bust)}\n#{js}"
      end
    end

    class TaxonomyConfig
      property name : String
      property feed : Bool
      property sitemap : Bool
      property paginate_by : Int32?

      def initialize(@name : String)
        @feed = false
        @sitemap = true
        @paginate_by = nil
      end
    end

    # Build hooks configuration for pre/post build commands
    class BuildHooksConfig
      property pre : Array(String)
      property post : Array(String)

      def initialize
        @pre = [] of String
        @post = [] of String
      end
    end

    # Build configuration section
    class BuildConfig
      property hooks : BuildHooksConfig

      # Track template extends/include/import dependencies so a template
      # edit only invalidates the pages that actually render it (cached
      # builds and `hwaro serve`). Set to false to restore the previous
      # behavior: any template change rebuilds every page.
      property template_deps : Bool = true

      def initialize
        @hooks = BuildHooksConfig.new
      end
    end

    # Serve (development server) configuration
    #
    # Currently used to configure custom response headers that are injected
    # on every request while running `hwaro serve`. This makes it easy to
    # reproduce production reverse-proxy / CDN header behaviour locally.
    class ServeConfig
      # Custom HTTP response headers applied to *all* responses during
      # `hwaro serve` (including 404s, redirects, and static assets).
      property headers : Hash(String, String)

      # When true, `hwaro serve` will behave as if `--fast` was passed
      # (skips heavy OG image generation and image processing by default).
      # CLI flags can still override this.
      property fast : Bool = false

      def initialize
        @headers = {} of String => String
        @fast = false
      end
    end

    # Markdown parser configuration
    # Maps to Markd::Options for controlling markdown parsing behavior
    class MarkdownConfig
      property safe : Bool             # If true, raw HTML will not be passed through (replaced by comments)
      property lazy_loading : Bool     # If true, adds loading="lazy" to img tags
      property emoji : Bool            # If true, converts emoji shortcodes (e.g. :smile:) to emoji characters
      property footnotes : Bool        # If true, enables footnote syntax ([^1])
      property task_lists : Bool       # If true, enables task list syntax (- [ ] / - [x])
      property definition_lists : Bool # If true, enables definition list syntax (Term\n: Definition)
      property mermaid : Bool          # If true, renders ```mermaid blocks as diagrams
      property math : Bool             # If true, enables math syntax ($...$ and $$...$$)
      property math_engine : String    # "katex" or "mathjax"
      property admonitions : Bool      # If true, GitHub-style `> [!NOTE]` blockquotes become admonition <div>s
      property heading_ids : Bool      # If true, `## Heading {#custom-id}` sets an explicit id
      property ins : Bool              # If true, enables inserted-text syntax (++ins++)
      property mark : Bool             # If true, enables highlighted-text syntax (==mark==)
      property sub : Bool              # If true, enables subscript syntax (~sub~)
      property sup : Bool              # If true, enables superscript syntax (^sup^)
      property attributes : Bool       # If true, enables `{#id .class key=val}` attribute blocks on headings/images

      def initialize
        @safe = false
        @lazy_loading = false
        @emoji = false
        @footnotes = true
        @task_lists = true
        @definition_lists = true
        @mermaid = false
        @math = false
        @math_engine = "katex"
        @admonitions = true
        @heading_ids = true
        @ins = false
        @mark = false
        @sub = false
        @sup = false
        @attributes = false
      end

      # Compact fingerprint of every field that changes rendered body HTML.
      # Keys Processor::Markdown.render_body_cached's memo so entries from a
      # previous config (e.g. after a config reload in `serve`) can't be
      # served for a build running with different markdown options.
      def cache_fingerprint : String
        String.build(17 + @math_engine.bytesize) do |io|
          io << (@safe ? '1' : '0') << (@lazy_loading ? '1' : '0') << (@emoji ? '1' : '0')
          io << (@footnotes ? '1' : '0') << (@task_lists ? '1' : '0') << (@definition_lists ? '1' : '0')
          io << (@mermaid ? '1' : '0') << (@math ? '1' : '0') << (@admonitions ? '1' : '0')
          io << (@heading_ids ? '1' : '0')
          io << (@ins ? '1' : '0') << (@mark ? '1' : '0') << (@sub ? '1' : '0')
          io << (@sup ? '1' : '0') << (@attributes ? '1' : '0') << @math_engine
        end
      end

      # Generate CDN script tags for the math engine. The markdown processor
      # emits `\(…\)`/`\[…\]` wrappers with `class="math math-{inline,display}"`
      # but doesn't load the renderer — without these tags the math reaches
      # the browser as literal TeX. Templates can opt out by overriding the
      # `{{ math_tags }}` variable or by leaving `math = false` and inlining
      # their own includes via [auto_includes].
      def math_tags : String
        return "" unless @math
        case @math_engine
        when "katex"
          # auto-render finds class="math math-{inline,display}" automatically
          # and replaces the inner TeX with rendered KaTeX. Pinned KaTeX 0.16.x
          # to avoid surprise major-version churn in build outputs.
          <<-HTML.gsub('\n', "")
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/katex.min.css">
            <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/katex.min.js"></script>
            <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/contrib/auto-render.min.js" onload="renderMathInElement(document.body);"></script>
            HTML
        when "mathjax"
          # MathJax 3 reads `class="math math-*"` via the `[tex]` extension
          # configured to recognise `\(…\)` and `\[…\]` delimiters (which is
          # how the markdown processor emits them).
          <<-HTML.gsub('\n', "")
            <script>window.MathJax={tex:{inlineMath:[["\\\\(","\\\\)"]],displayMath:[["\\\\[","\\\\]"]]}};</script>
            <script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script>
            HTML
        else
          ""
        end
      end

      # Generate the Mermaid.js script tag. Mirrors `math_tags`: the markdown
      # processor emits `<div class="mermaid">…</div>`, but without a renderer
      # those blocks ship to the browser as DOT-like source text. Pinned to
      # 10.x to avoid major-version drift.
      def mermaid_tags : String
        return "" unless @mermaid
        <<-HTML.gsub('\n', "")
          <script type="module">
            import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs";
            mermaid.initialize({ startOnLoad: true });
          </script>
          HTML
      end
    end

    # Language configuration for multilingual sites
    class LanguageConfig
      property code : String
      property language_name : String
      property weight : Int32
      property generate_feed : Bool
      property build_search_index : Bool
      property taxonomies : Array(String)

      def initialize(@code : String)
        @language_name = code
        @weight = 1
        @generate_feed = true
        @build_search_index = true
        @taxonomies = ["tags", "categories"]
      end
    end

    # Asset bundle configuration
    class AssetBundleConfig
      property name : String
      property files : Array(String)

      def initialize(@name : String = "", @files : Array(String) = [] of String)
      end
    end

    # Asset pipeline configuration
    class AssetsConfig
      property enabled : Bool
      property minify : Bool
      property fingerprint : Bool
      property source_dir : String
      property output_dir : String
      property bundles : Array(AssetBundleConfig)

      def initialize
        @enabled = false
        @minify = true
        @fingerprint = true
        @source_dir = "static"
        @output_dir = "assets"
        @bundles = [] of AssetBundleConfig
      end
    end

    # Image processing configuration
    #
    # Enables automatic image resizing during build using stb (statically linked).
    # Supports JPG, PNG, BMP. No external tools required.
    #
    # Config example (config.toml):
    #   [image_processing]
    #   enabled = true
    #   widths = [320, 640, 1024, 1280]
    #   quality = 85
    class ImageProcessingConfig
      property enabled : Bool
      property widths : Array(Int32)
      property quality : Int32
      property lqip_enabled : Bool
      property lqip_width : Int32
      property lqip_quality : Int32

      def initialize
        @enabled = false
        @widths = [] of Int32
        @quality = 85
        @lqip_enabled = false
        @lqip_width = 32
        @lqip_quality = 20
      end
    end

    # AMP (Accelerated Mobile Pages) configuration
    class AmpConfig
      property enabled : Bool
      property path_prefix : String
      property sections : Array(String)

      def initialize
        @enabled = false
        @path_prefix = "amp"
        @sections = [] of String
      end

      # Check if a page section should get an AMP version
      def section_enabled?(section : String) : Bool
        @sections.empty? || @sections.includes?(section)
      end
    end

    # PWA (Progressive Web App) configuration
    class PwaConfig
      property enabled : Bool
      property name : String?
      property short_name : String?
      property theme_color : String
      property background_color : String
      property display : String
      property start_url : String
      property icons : Array(String)
      property offline_page : String?
      property precache_urls : Array(String)
      property cache_strategy : String

      VALID_STRATEGIES = %w[cache-first network-first stale-while-revalidate]

      def initialize
        @enabled = false
        @name = nil
        @short_name = nil
        @theme_color = "#ffffff"
        @background_color = "#ffffff"
        @display = "standalone"
        @start_url = "/"
        @icons = [] of String
        @offline_page = nil
        @precache_urls = [] of String
        @cache_strategy = "cache-first"
      end
    end

    class DoctorConfig
      property ignore : Array(String)

      def initialize
        @ignore = [] of String
      end
    end

    # `[static]` — controls which files under `static/` get published.
    #
    # `static/` is copied verbatim into the site root, so OS/editor/VCS cruft
    # placed there (`.DS_Store`, `Thumbs.db`, `.git/`, vim swap files, …) would
    # otherwise be deployed. A built-in denylist filters the common offenders;
    # `exclude` adds project-specific patterns — a glob like `*.bak` filters at
    # any depth, `drafts/**` scopes a subtree, and a literal name is anchored to
    # an exact file or directory (`drafts` drops `drafts/…`) — and
    # `use_default_excludes = false` opts out of the built-in list entirely.
    #
    # Note: this only filters *cruft*. Legitimate dot-paths such as
    # `.well-known/` are NOT in the denylist and are always published.
    class StaticConfig
      # Exact file/dir names that should essentially never be published.
      # Matched per path segment, so an entry like `.git` filters that
      # directory (and everything under it) at any depth.
      DEFAULT_EXCLUDE_NAMES = Set{
        ".DS_Store", ".AppleDouble", ".LSOverride", ".Spotlight-V100",
        ".Trashes", ".fseventsd", ".DocumentRevisions-V100", ".TemporaryItems",
        ".VolumeIcon.icns", "__MACOSX",
        "Thumbs.db", "ehthumbs.db", "ehthumbs_vista.db", "desktop.ini", ".directory",
        ".git", ".gitignore", ".gitattributes", ".gitmodules", ".gitkeep",
        ".svn", ".hg", ".bzr",
      }

      # Suffixes for vim swap files, matched against the leaf file name only.
      # Kept deliberately narrow: a name ending in `.swp`/`.swo` is never a
      # legitimate published asset, so the always-on default denylist can't
      # silently drop real content. Emacs-style `~` backups are intentionally
      # NOT here — a trailing tilde is a legal file name, so filtering it is
      # left to an explicit `exclude` pattern.
      DEFAULT_EXCLUDE_SUFFIXES = [".swp", ".swo"]

      # Glob metacharacters that distinguish an `exclude` glob from a literal
      # path/name.
      GLOB_METACHARS = /[*?\[{]/

      property exclude : Array(String)
      property use_default_excludes : Bool

      def initialize
        @exclude = [] of String
        @use_default_excludes = true
      end

      # Whether `relative_path` (relative to `static/`) should be filtered out
      # of the published output.
      #
      # `exclude` entries match two ways depending on their shape:
      # - a glob (contains `* ? [ {`) matches the relative path, and — when it
      #   has no `/` — the bare file name too, so `*.bak` filters at any depth
      #   while `drafts/**` scopes to a subtree;
      # - a literal is anchored: it matches that exact path or, when it names a
      #   directory, the whole subtree under it. So `drafts` drops `drafts/...`
      #   but `config` only drops a top-level `config`, never a same-named file
      #   nested elsewhere.
      def excluded?(relative_path : String) : Bool
        normalized = Path[relative_path].to_posix.to_s
        return false if normalized.empty? || normalized == "."

        if @use_default_excludes
          segments = normalized.split('/')
          # Exact-name cruft (`.git`, `.DS_Store`, …) filters at any depth; the
          # swap-file suffix check applies to the leaf name only, so a directory
          # whose name happens to end in `.swp` doesn't take its subtree with it.
          return true if segments.any? { |segment| DEFAULT_EXCLUDE_NAMES.includes?(segment) }
          return true if DEFAULT_EXCLUDE_SUFFIXES.any? { |suffix| segments.last.ends_with?(suffix) }
        end

        return false if @exclude.empty?
        basename = File.basename(normalized)
        @exclude.any? { |pattern| pattern_matches?(pattern, normalized, basename) }
      end

      private def pattern_matches?(pattern : String, normalized : String, basename : String) : Bool
        if GLOB_METACHARS.matches?(pattern)
          # Glob: match the full relative path, plus the bare name for a
          # path-less glob so it applies at any depth. A malformed glob (e.g.
          # an unclosed `[` class) makes File.match? raise File::BadPatternError;
          # treat it as non-matching rather than crashing the whole build on a
          # single config typo.
          Utils::PathUtils.glob_match?(pattern, normalized) ||
            (!pattern.includes?('/') && Utils::PathUtils.glob_match?(pattern, basename))
        else
          # Literal: an exact file, or a directory subtree rooted at it.
          normalized == pattern || normalized.starts_with?("#{pattern}/")
        end
      end
    end

    # `[outputs]` — declares extra per-page/per-section output formats
    # beyond HTML (sibling `index.<fmt>` files rendered from a user-supplied
    # `templates/<name>.<fmt>.jinja` template). See
    # docs/content/features/output-formats.md for the full selection chain
    # and front matter override (`page.extra["outputs"]`).
    class OutputsConfig
      VALID_FORMATS = %w[json txt xml csv]

      # Formats every regular page emits (unless overridden by front matter).
      property page : Array(String)
      # Formats every section index emits (unless overridden by front matter).
      property section : Array(String)
      # Optional allowlist of section names formats apply to; empty = all
      # sections. Matches a section name or any of its descendants, mirroring
      # `FeedConfig#sections`.
      property sections : Array(String)

      def initialize
        @page = [] of String
        @section = [] of String
        @sections = [] of String
      end

      # Whether any format is configured at all (page or section).
      def any? : Bool
        @page.present? || @section.present?
      end
    end

    class Config
      property title : String
      property description : String
      getter base_url : String
      property sitemap : SitemapConfig
      property robots : RobotsConfig
      property llms : LlmsConfig
      property feeds : FeedConfig
      property search : SearchConfig
      property plugins : PluginConfig
      property content_files : ContentFilesConfig
      property content_new : ContentNewConfig
      property pagination : PaginationConfig
      property highlight : HighlightConfig
      property auto_includes : AutoIncludesConfig
      property og : OpenGraphConfig
      property taxonomies : Array(TaxonomyConfig)
      property default_language : String
      property languages : Hash(String, LanguageConfig)
      property build : BuildConfig
      property serve : ServeConfig
      property markdown : MarkdownConfig
      property series : SeriesConfig
      property related : RelatedConfig
      property deployment : DeploymentConfig
      property assets : AssetsConfig
      property pwa : PwaConfig
      property amp : AmpConfig
      property image_processing : ImageProcessingConfig
      property doctor : DoctorConfig
      property static : StaticConfig
      property outputs : OutputsConfig
      property permalinks : Hash(String, String)
      property raw : Hash(String, TOML::Any)
      @base_url_stripped : String? = nil
      @base_path : String? = nil

      def initialize
        @title = "Hwaro Site"
        @description = ""
        @base_url = ""
        @sitemap = SitemapConfig.new
        @robots = RobotsConfig.new
        @llms = LlmsConfig.new
        @feeds = FeedConfig.new
        @search = SearchConfig.new
        @plugins = PluginConfig.new
        @content_files = ContentFilesConfig.new
        @content_new = ContentNewConfig.new
        @pagination = PaginationConfig.new
        @highlight = HighlightConfig.new
        @auto_includes = AutoIncludesConfig.new
        @og = OpenGraphConfig.new
        @taxonomies = [] of TaxonomyConfig
        @default_language = "en"
        @languages = {} of String => LanguageConfig
        @build = BuildConfig.new
        @serve = ServeConfig.new
        @markdown = MarkdownConfig.new
        @series = SeriesConfig.new
        @related = RelatedConfig.new
        @deployment = DeploymentConfig.new
        @assets = AssetsConfig.new
        @pwa = PwaConfig.new
        @amp = AmpConfig.new
        @image_processing = ImageProcessingConfig.new
        @doctor = DoctorConfig.new
        @static = StaticConfig.new
        @outputs = OutputsConfig.new
        @permalinks = {} of String => String
        @raw = Hash(String, TOML::Any).new
      end

      # Normalize on assignment: a trailing slash makes `{{ base_url }}/path`
      # templates (and canonical/og URLs) emit `//`. Strip it so the build is
      # correct whether the trailing slash came from config.toml or `--base-url`
      # (previously only `doctor --fix` normalized this).
      def base_url=(value : String)
        @base_url = value.rstrip("/")
        @base_url_stripped = nil
        @base_path = nil
      end

      # Cached base_url with trailing slash stripped (avoids repeated rstrip per page)
      def base_url_stripped : String
        @base_url_stripped ||= @base_url.rstrip("/")
      end

      # Path component of `base_url`, used to make root-relative links work when
      # the site is deployed under a subpath (e.g. GitHub/GitLab project pages
      # served at `https://user.github.io/repo/`). For `https://x.com/repo` this
      # returns `/repo`; for a domain-root deployment (`https://x.com`) or an
      # empty `base_url` it returns `""`. Trailing slashes are stripped so callers
      # can build `base_path + page.url` without producing `//`.
      def base_path : String
        @base_path ||= begin
          stripped = base_url_stripped
          if stripped.empty?
            ""
          else
            path = URI.parse(stripped).path.rstrip("/")
            path == "/" ? "" : path
          end
        rescue URI::Error
          ""
        end
      end

      # Prefix a site-internal root-relative path (e.g. `/posts/x/`) with
      # `base_path` so generated URLs resolve under a subpath deployment.
      # Absolute `http(s)://` URLs and paths that are not root-relative are
      # returned unchanged; a no-op when `base_path` is "" (domain-root deploy).
      # Callers that may hold a path without a leading slash (e.g. some
      # `page.url` values) should normalize it first — this helper only
      # prefixes values that already start with "/".
      def with_base_path(path : String) : String
        return path if base_path.empty?
        return path if path.starts_with?("http://") || path.starts_with?("https://")
        # Protocol-relative URLs (`//cdn.example.com/x`) are external — leave
        # them untouched, matching how render.cr / internal_link_resolver treat
        # `//host`. Without this they'd become `/base//cdn.example.com/x`.
        return path if path.starts_with?("//")
        return path unless path.starts_with?("/")
        "#{base_path}#{path}"
      end

      # Check if site is multilingual
      def multilingual? : Bool
        codes = @languages.keys
        codes << @default_language unless @default_language.empty?
        codes.uniq.size > 1
      end

      # Get language config by code, returns nil if not found
      def language(code : String) : LanguageConfig?
        @languages[code]?
      end

      # Get sorted languages by weight
      def sorted_languages : Array(LanguageConfig)
        @languages.values.sort_by!(&.weight)
      end

      # Resolve a content directory through the configured `permalinks` rules.
      #
      # Returns the remapped directory (relative to the site root) for the first
      # rule whose source matches `directory_path` exactly or as a parent prefix;
      # the matched prefix is replaced and any deeper path is preserved. An empty
      # target maps the matched tree to the site root (so `pages/contact` under
      # `"pages" => ""` becomes `contact`, not `/contact`). Returns
      # `directory_path` unchanged when no rule matches.
      def resolve_permalink_dir(directory_path : String) : String
        permalinks.each do |source, target|
          if directory_path == source
            return target
          elsif directory_path.starts_with?("#{source}/")
            rest = directory_path[(source.size + 1)..]
            return target.empty? ? rest : "#{target}/#{rest}"
          end
        end
        directory_path
      end

      # Load and parse a `config.toml` into a populated `Config`.
      #
      # Raises `Hwaro::HwaroError(HWARO_E_CONFIG)` directly at the source for
      # file-not-found and TOML parse errors so every caller (build, deploy,
      # doctor, tool, services) gets a classified error with exit code 3
      # without having to do substring matching on the exception message.
      # File-not-found is classified as HWARO_E_CONFIG rather than HWARO_E_IO
      # because a missing `config.toml` is a config-level user error, not an
      # arbitrary IO failure.
      # Accepts an absolute `http(s)://host[:port][/path]` URL or the empty
      # string (which means "no absolute URL is configured"). Raises
      # ArgumentError on anything else so callers can wrap the failure in
      # whichever classified `HwaroError` code suits their context
      # (`HWARO_E_CONFIG` for config.toml, `HWARO_E_USAGE` for CLI flags).
      def self.validate_base_url!(value : String) : Nil
        return if value.empty?

        uri = begin
          URI.parse(value)
        rescue URI::Error
          raise ArgumentError.new("Invalid base_url: '#{value}'. Expected http(s)://host[/path].")
        end

        scheme = uri.scheme
        host = uri.host
        if scheme.nil? || !%w[http https].includes?(scheme.downcase) || host.nil? || host.empty?
          raise ArgumentError.new("Invalid base_url: '#{value}'. Expected http(s)://host[/path].")
        end
        # A query/fragment is not part of the origin+path that page URLs append
        # to. base_path parses with URI#path (dropping query/fragment), so the
        # raw base_url and the derived base_path would silently disagree and
        # corrupt absolute (base_url + page.url) links. Reject it at the source.
        unless (uri.query.nil? || uri.query.try(&.empty?)) && (uri.fragment.nil? || uri.fragment.try(&.empty?))
          raise ArgumentError.new("Invalid base_url: '#{value}'. base_url must not contain a query string or fragment.")
        end
      end

      def self.load(config_path : String = "config.toml", env : String? = nil) : Config
        config = new

        unless File.exists?(config_path)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "config.toml not found at #{config_path}",
            hint: "Run 'hwaro init' to scaffold a project, or cd into a directory containing config.toml.",
          )
        end

        # Read file content and substitute environment variables before TOML parsing
        raw_content = File.read(config_path)
        substituted_content = Utils::EnvSubstitutor.substitute_with_warnings(raw_content, config_path)
        config.raw = parse_toml(substituted_content, config_path)

        # Merge environment-specific override (e.g. config.production.toml).
        # A missing override is recoverable (we just use the base config), but
        # it's the most common way to ship a localhost build to production by
        # accident (typo `--env prdo`, file not committed, etc.), so the warning
        # is intentionally explicit and names both the requested env and the
        # exact filename we looked for.
        if env_name = env
          env_path = config_path.sub(/\.toml$/, ".#{env_name}.toml")
          if File.exists?(env_path)
            env_content = File.read(env_path)
            env_substituted = Utils::EnvSubstitutor.substitute_with_warnings(env_content, env_path)
            env_raw = parse_toml(env_substituted, env_path)
            config.raw = deep_merge(config.raw, env_raw)
            Logger.info "Loaded environment config: #{env_path}"
          else
            Logger.warn "--env #{env_name}: override file '#{env_path}' not found; continuing with base #{config_path} only. If you intended to ship environment-specific settings (e.g. a production base_url), create #{env_path} or check for a typo in --env."
          end
        end

        config.title = config.raw["title"]?.try(&.as_s?) || config.title
        config.description = config.raw["description"]?.try(&.as_s?) || config.description
        if raw_base_url = config.raw["base_url"]?.try(&.as_s?)
          begin
            validate_base_url!(raw_base_url)
          rescue ex : ArgumentError
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONFIG,
              message: ex.message || "Invalid base_url in #{config_path}",
              hint: "Set base_url to an absolute URL such as \"https://example.com\" or \"http://localhost:3000\".",
            )
          end
          config.base_url = raw_base_url
        end
        config.default_language = config.raw["default_language"]?.try(&.as_s?) || config.default_language

        load_sitemap(config)
        load_robots(config)
        load_llms(config)
        load_feeds(config)
        load_search(config)
        load_plugins(config)
        load_content_files(config)
        load_content_new(config)
        load_pagination(config)
        load_highlight(config)
        load_auto_includes(config)
        load_og(config)
        load_taxonomies(config)
        load_languages(config)
        load_build(config)
        load_serve(config)
        load_markdown(config)
        load_series(config)
        load_related(config)
        load_permalinks(config)
        load_assets(config)
        load_pwa(config)
        load_amp(config)
        load_image_processing(config)
        load_doctor(config)
        load_static(config)
        load_deployment(config)
        load_outputs(config)

        config
      end

      # --- Private helpers -----------------------------------------------------------

      # Parse a TOML string, re-raising any parser failure as a classified
      # `HWARO_E_CONFIG` error so the CLI maps it to exit code 3 and the
      # `--json` handlers emit the structured error payload. The hint points
      # users at the offending file so they can fix the syntax.
      private def self.parse_toml(content : String, path : String) : Hash(String, TOML::Any)
        TOML.parse(content)
      rescue ex : Hwaro::HwaroError
        raise ex
      rescue ex
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "Invalid TOML in #{path}: #{ex.message}",
          hint: "Check TOML syntax in #{path}.",
        )
      end

      # Deep-merge two TOML hashes.  Values in `override` take precedence.
      # Sub-tables (hashes) are merged recursively; all other types are replaced.
      private def self.deep_merge(
        base : Hash(String, TOML::Any),
        override : Hash(String, TOML::Any),
      ) : Hash(String, TOML::Any)
        merged = base.dup
        override.each do |key, value|
          if base_val = merged[key]?
            base_hash = base_val.as_h?
            over_hash = value.as_h?
            if base_hash && over_hash
              merged[key] = TOML::Any.new(deep_merge(base_hash, over_hash))
            else
              merged[key] = value
            end
          else
            merged[key] = value
          end
        end
        merged
      end

      # Safe boolean loader: returns the parsed Bool if present, otherwise the default.
      # This avoids the `||` pitfall where `false || default` silently ignores `false`.
      private def self.bool_value(raw : TOML::Any?, default : Bool) : Bool
        val = raw.try(&.as_bool?)
        val.nil? ? default : val
      end

      # Safe integer loader: handles both integer and float TOML values.
      # Uses the 64-bit accessor and clamps to Int32 range so an oversized
      # config value (e.g. `per_page = 9999999999` or `1e30`) yields a clamped
      # Int32 instead of raising OverflowError out of `as_i?`/`to_i` — which
      # would abort the build with an unclassified crash instead of running.
      private def self.int_value(raw : TOML::Any?, default : Int32) : Int32
        return default unless raw
        # `finite?` guard: NaN.clamp is NaN and NaN.to_i64 raises OverflowError,
        # so a `nan`/`-nan` float in config would otherwise crash the build.
        val = raw.as_i64? || raw.as_f?.try { |f| f.finite? ? f.clamp(Int32::MIN.to_f64, Int32::MAX.to_f64).to_i64 : nil }
        unless val
          # Present but not a usable number (e.g. a quoted "20", a bool, NaN) —
          # warn instead of silently using the default with zero feedback.
          Logger.warn "Ignoring non-numeric config value #{raw.raw.inspect}; using default #{default}"
          return default
        end
        val.clamp(Int32::MIN.to_i64, Int32::MAX.to_i64).to_i32
      end

      # Safe float loader: handles both float and integer TOML values.
      # Uses as_i64? (Int64#to_f never overflows) to avoid the OverflowError
      # that as_i? raises for integers above Int32::MAX.
      private def self.float_value(raw : TOML::Any?, default : Float64) : Float64
        return default unless raw
        val = raw.as_f? || raw.as_i64?.try(&.to_f)
        unless val
          Logger.warn "Ignoring non-numeric config value #{raw.raw.inspect}; using default #{default}"
          return default
        end
        val
      end

      # Non-raising Int32 extraction from a single TOML value (nil if absent or
      # non-numeric). Clamps to Int32 range like int_value so an oversized value
      # never raises OverflowError out of as_i?/to_i at the inline call sites.
      private def self.int_or_nil(raw : TOML::Any) : Int32?
        val = raw.as_i64? || raw.as_f?.try { |f| f.finite? ? f.clamp(Int32::MIN.to_f64, Int32::MAX.to_f64).to_i64 : nil }
        val.try(&.clamp(Int32::MIN.to_i64, Int32::MAX.to_i64).to_i32)
      end

      # Extracts a string-or-array TOML value into an Array(String).
      private def self.string_or_array(raw : TOML::Any?) : Array(String)
        return [] of String unless raw
        raw.as_a?.try(&.compact_map(&.as_s?)) ||
          raw.as_s?.try { |v| [v] } ||
          [] of String
      end

      # --- Private section loaders ---------------------------------------------------

      private def self.load_sitemap(config : Config)
        # Handle backward compatibility where sitemap was just a boolean
        if sitemap_bool = config.raw["sitemap"]?.try(&.as_bool?)
          config.sitemap.enabled = sitemap_bool
        elsif s = config.raw["sitemap"]?.try(&.as_h?)
          config.sitemap.enabled = bool_value(s["enabled"]?, config.sitemap.enabled)
          config.sitemap.filename = s["filename"]?.try(&.as_s?) || config.sitemap.filename
          config.sitemap.changefreq = s["changefreq"]?.try(&.as_s?) || config.sitemap.changefreq
          # Keep the priority raw here (NOT clamped) so `hwaro doctor` can detect
          # an out-of-range value and warn/offer a fix. The sitemap EMITTER
          # (sitemap.cr) clamps to [0.0, 1.0] so the generated XML stays valid
          # even for users who never run doctor. NaN is the exception: it
          # sails through both doctor's range checks and the emitter's clamp
          # (NaN comparisons are all false) and lands in the XML as "NaN",
          # so non-finite values fall back to the default here.
          pr = float_value(s["priority"]?, config.sitemap.priority)
          config.sitemap.priority = pr.finite? ? pr : config.sitemap.priority
          if exclude_arr = s["exclude"]?.try(&.as_a?)
            config.sitemap.exclude = exclude_arr.compact_map(&.as_s?)
          end
        end
      end

      private def self.load_robots(config : Config)
        return unless s = config.raw["robots"]?.try(&.as_h?)

        config.robots.enabled = bool_value(s["enabled"]?, config.robots.enabled)
        config.robots.filename = s["filename"]?.try(&.as_s?) || config.robots.filename

        if rules = s["rules"]?.try(&.as_a?)
          config.robots.rules = rules.compact_map do |rule_any|
            if rule_h = rule_any.as_h?
              user_agent = rule_h["user_agent"]?.try(&.as_s?) || "*"
              rule = RobotsRule.new(user_agent)
              rule.allow = string_or_array(rule_h["allow"]?)
              rule.disallow = string_or_array(rule_h["disallow"]?)
              rule
            end
          end
        end
      end

      private def self.load_llms(config : Config)
        return unless s = config.raw["llms"]?.try(&.as_h?)

        config.llms.enabled = bool_value(s["enabled"]?, config.llms.enabled)
        config.llms.filename = s["filename"]?.try(&.as_s?) || config.llms.filename
        config.llms.instructions = s["instructions"]?.try(&.as_s?) || config.llms.instructions
        config.llms.full_enabled = bool_value(s["full_enabled"]?, config.llms.full_enabled)
        config.llms.full_filename = s["full_filename"]?.try(&.as_s?) || config.llms.full_filename
      end

      private def self.load_feeds(config : Config)
        return unless s = config.raw["feeds"]?.try(&.as_h?)

        # Backward compatibility for 'generate' property
        enabled = s["enabled"]?.try(&.as_bool?)
        generate = s["generate"]?.try(&.as_bool?)

        if !enabled.nil?
          config.feeds.enabled = enabled
        elsif !generate.nil?
          config.feeds.enabled = generate
        end

        config.feeds.filename = s["filename"]?.try(&.as_s?) || config.feeds.filename
        config.feeds.type = s["type"]?.try(&.as_s?) || config.feeds.type
        config.feeds.truncate = int_value(s["truncate"]?, config.feeds.truncate)
        config.feeds.limit = int_value(s["limit"]?, config.feeds.limit)
        if sections = s["sections"]?.try(&.as_a?)
          config.feeds.sections = sections.compact_map(&.as_s?)
        end
        config.feeds.default_language_only = bool_value(s["default_language_only"]?, config.feeds.default_language_only)
        config.feeds.full_content = bool_value(s["full_content"]?, config.feeds.full_content)
      end

      private def self.load_search(config : Config)
        return unless s = config.raw["search"]?.try(&.as_h?)

        config.search.enabled = bool_value(s["enabled"]?, config.search.enabled)
        config.search.format = s["format"]?.try(&.as_s?) || config.search.format
        config.search.filename = s["filename"]?.try(&.as_s?) || config.search.filename
        if fields = s["fields"]?.try(&.as_a?)
          config.search.fields = fields.compact_map(&.as_s?)
        end
        if exclude_arr = s["exclude"]?.try(&.as_a?)
          config.search.exclude = exclude_arr.compact_map(&.as_s?)
        end
        config.search.tokenize_cjk = bool_value(s["tokenize_cjk"]?, config.search.tokenize_cjk)
      end

      private def self.load_plugins(config : Config)
        return unless s = config.raw["plugins"]?.try(&.as_h?)

        if processors = s["processors"]?.try(&.as_a?)
          config.plugins.processors = processors.compact_map(&.as_s?)
        end
      end

      private def self.load_content_files(config : Config)
        return unless content_section = config.raw["content"]?.try(&.as_h?)
        return unless s = content_section["files"]?.try(&.as_h?)

        allow_any = s["allow_extensions"]? || s["extensions"]?
        disallow_any = s["disallow_extensions"]?
        disallow_paths_any = s["disallow_paths"]?

        if allow_any
          config.content_files.allow_extensions = ContentFilesConfig.normalize_extensions(string_or_array(allow_any))
        end

        if disallow_any
          config.content_files.disallow_extensions = ContentFilesConfig.normalize_extensions(string_or_array(disallow_any))
        end

        if disallow_paths_any
          config.content_files.disallow_paths = ContentFilesConfig.normalize_paths(string_or_array(disallow_paths_any))
        end
      end

      # Loads `hwaro new` scaffold settings from `[content.new]` (preferred)
      # or falls back to flat keys on `[content]` so short configs like
      # `[content]\nfront_matter_format = "yaml"` also work. The fallback is
      # scoped to the two recognised keys so unrelated `[content]` sub-tables
      # (e.g. `[content.files]`) can never be misread as `new`-scaffold input.
      private def self.load_content_new(config : Config)
        return unless content_section = config.raw["content"]?.try(&.as_h?)

        nested = content_section["new"]?.try(&.as_h?)
        format_any = nested.try(&.[]?("front_matter_format")) || content_section["front_matter_format"]?
        fields_any = nested.try(&.[]?("default_fields")) || content_section["default_fields"]?
        bundle_any = nested.try(&.[]?("bundle")) || content_section["bundle"]?

        if format = format_any.try(&.as_s?)
          normalized = format.downcase
          if ContentNewConfig::VALID_FORMATS.includes?(normalized)
            config.content_new.front_matter_format = normalized
          else
            Logger.warn "Unknown content.new.front_matter_format '#{format}', keeping '#{config.content_new.front_matter_format}'"
          end
        end

        if fields = fields_any.try(&.as_a?)
          config.content_new.default_fields = fields.compact_map(&.as_s?)
        end

        if bundle = bundle_any.try(&.as_bool?)
          config.content_new.bundle = bundle
        end
      end

      private def self.load_pagination(config : Config)
        return unless s = config.raw["pagination"]?.try(&.as_h?)

        config.pagination.enabled = bool_value(s["enabled"]?, config.pagination.enabled)
        config.pagination.per_page = int_value(s["per_page"]?, config.pagination.per_page)
      end

      private def self.load_highlight(config : Config)
        return unless s = config.raw["highlight"]?.try(&.as_h?)

        config.highlight.enabled = bool_value(s["enabled"]?, config.highlight.enabled)
        config.highlight.theme = s["theme"]?.try(&.as_s?) || config.highlight.theme
        config.highlight.use_cdn = bool_value(s["use_cdn"]?, config.highlight.use_cdn)
        config.highlight.line_numbers = bool_value(s["line_numbers"]?, config.highlight.line_numbers)
        if mode = s["mode"]?.try(&.as_s?)
          if mode == "client" || mode == "server"
            config.highlight.mode = mode
          else
            Logger.warn "Unknown highlight.mode '#{mode}' — expected \"client\" or \"server\". Using \"client\"."
          end
        end
      end

      private def self.load_auto_includes(config : Config)
        return unless s = config.raw["auto_includes"]?.try(&.as_h?)

        config.auto_includes.enabled = bool_value(s["enabled"]?, config.auto_includes.enabled)
        if dirs = s["dirs"]?.try(&.as_a?)
          config.auto_includes.dirs = dirs.compact_map(&.as_s?)
        end
      end

      private def self.load_og(config : Config)
        return unless s = config.raw["og"]?.try(&.as_h?)

        config.og.default_image = s["default_image"]?.try(&.as_s?)
        config.og.twitter_card = s["twitter_card"]?.try(&.as_s?) || config.og.twitter_card
        config.og.twitter_site = s["twitter_site"]?.try(&.as_s?)
        config.og.twitter_creator = s["twitter_creator"]?.try(&.as_s?)
        config.og.fb_app_id = s["fb_app_id"]?.try(&.as_s?)
        config.og.og_type = s["type"]?.try(&.as_s?) || config.og.og_type

        if ai = s["auto_image"]?.try(&.as_h?)
          config.og.auto_image.enabled = bool_value(ai["enabled"]?, config.og.auto_image.enabled)
          config.og.auto_image.background = ai["background"]?.try(&.as_s?) || config.og.auto_image.background
          config.og.auto_image.text_color = ai["text_color"]?.try(&.as_s?) || config.og.auto_image.text_color
          config.og.auto_image.accent_color = ai["accent_color"]?.try(&.as_s?) || config.og.auto_image.accent_color
          config.og.auto_image.secondary_color = ai["secondary_color"]?.try(&.as_s?)
          config.og.auto_image.font_size = int_value(ai["font_size"]?, config.og.auto_image.font_size)
          config.og.auto_image.logo = ai["logo"]?.try(&.as_s?)
          config.og.auto_image.output_dir = ai["output_dir"]?.try(&.as_s?) || config.og.auto_image.output_dir
          config.og.auto_image.show_title = bool_value(ai["show_title"]?, config.og.auto_image.show_title)
          config.og.auto_image.style = ai["style"]?.try(&.as_s?) || config.og.auto_image.style
          # Opacity-style floats share pattern_scale's hazard below: TOML
          # accepts `nan`/`inf` literals, NaN survives the renderer's
          # clamp(0.0, 1.0) (NaN comparisons are all false), and the pixel
          # blend's `.to_u8` then raises OverflowError, aborting the build.
          # A non-finite value falls back to the field's default.
          po = float_value(ai["pattern_opacity"]?, config.og.auto_image.pattern_opacity)
          config.og.auto_image.pattern_opacity = po.finite? ? po : config.og.auto_image.pattern_opacity
          # Clamp to a sane range: the pattern renderer multiplies scale into
          # Int32 expressions (e.g. (80 * scale).to_i), so a huge value overflows
          # Int32 and crashes OG generation. 0.1..10.0 covers every visible scale;
          # a non-finite (nan) value falls back to the default.
          ps = float_value(ai["pattern_scale"]?, config.og.auto_image.pattern_scale)
          config.og.auto_image.pattern_scale = ps.finite? ? ps.clamp(0.1, 10.0) : 1.0
          config.og.auto_image.background_image = ai["background_image"]?.try(&.as_s?)
          oo = float_value(ai["overlay_opacity"]?, config.og.auto_image.overlay_opacity)
          config.og.auto_image.overlay_opacity = oo.finite? ? oo : config.og.auto_image.overlay_opacity
          config.og.auto_image.format = ai["format"]?.try(&.as_s?) || config.og.auto_image.format
          config.og.auto_image.font_path = ai["font_path"]?.try(&.as_s?)
          if lp = ai["logo_position"]?.try(&.as_s?)
            if {"bottom-left", "bottom-right", "top-left", "top-right"}.includes?(lp)
              config.og.auto_image.logo_position = lp
            end
          end
          tp = float_value(ai["text_panel"]?, config.og.auto_image.text_panel)
          config.og.auto_image.text_panel = tp.finite? ? tp : config.og.auto_image.text_panel
          config.og.auto_image.accent_bars = bool_value(ai["accent_bars"]?, config.og.auto_image.accent_bars)
          config.og.auto_image.lazy_generate = bool_value(ai["lazy_generate"]?, config.og.auto_image.lazy_generate)
        end
      end

      private def self.load_taxonomies(config : Config)
        return unless taxonomies_section = config.raw["taxonomies"]?.try(&.as_a?)

        config.taxonomies = taxonomies_section.compact_map do |taxonomy_any|
          taxonomy_hash = taxonomy_any.as_h?
          next unless taxonomy_hash

          name = taxonomy_hash["name"]?.try(&.as_s?)
          next unless name

          taxonomy = TaxonomyConfig.new(name)
          taxonomy.feed = bool_value(taxonomy_hash["feed"]?, taxonomy.feed)
          taxonomy.sitemap = bool_value(taxonomy_hash["sitemap"]?, taxonomy.sitemap)
          taxonomy.paginate_by = taxonomy_hash["paginate_by"]?.try { |v| int_or_nil(v) }
          taxonomy
        end
      end

      private def self.load_languages(config : Config)
        return unless s = config.raw["languages"]?.try(&.as_h?)

        s.each do |lang_code, lang_data|
          next unless lang_hash = lang_data.as_h?

          lang_config = LanguageConfig.new(lang_code)
          lang_config.language_name = lang_hash["language_name"]?.try(&.as_s?) || lang_code
          lang_config.weight = int_value(lang_hash["weight"]?, lang_config.weight)
          lang_config.generate_feed = bool_value(lang_hash["generate_feed"]?, lang_config.generate_feed)
          lang_config.build_search_index = bool_value(lang_hash["build_search_index"]?, lang_config.build_search_index)

          if taxonomies = lang_hash["taxonomies"]?.try(&.as_a?)
            lang_config.taxonomies = taxonomies.compact_map(&.as_s?)
          else
            # No per-language `taxonomies` key → inherit the global
            # `[[taxonomies]]` set rather than the hardcoded `["tags",
            # "categories"]` default. Otherwise a `[languages.<code>]` block
            # that omits the key silently restricts that language to two
            # taxonomies, dropping any third (e.g. `authors`) from its output —
            # for the default language that means a taxonomy generated before
            # this block existed would disappear at the root. `load_taxonomies`
            # runs before `load_languages`, so `config.taxonomies` is populated.
            lang_config.taxonomies = config.taxonomies.map(&.name)
          end

          config.languages[lang_code] = lang_config
        end
      end

      private def self.load_build(config : Config)
        return unless s = config.raw["build"]?.try(&.as_h?)

        config.build.template_deps = bool_value(s["template_deps"]?, config.build.template_deps)

        if hooks_section = s["hooks"]?.try(&.as_h?)
          if pre_hooks = hooks_section["pre"]?.try(&.as_a?)
            config.build.hooks.pre = pre_hooks.compact_map(&.as_s?)
          end
          if post_hooks = hooks_section["post"]?.try(&.as_a?)
            config.build.hooks.post = post_hooks.compact_map(&.as_s?)
          end
        end
      end

      private def self.load_serve(config : Config)
        return unless s = config.raw["serve"]?.try(&.as_h?)

        if headers_table = s["headers"]?.try(&.as_h?)
          headers_table.each do |name, value|
            next unless str = value.as_s?
            next if name.each_char.any? { |c| c.ascii_control? || c == ':' } ||
                    str.each_char.any?(&.ascii_control?)

            config.serve.headers[name] = str
          end
        end

        # Fast dev mode default (can be overridden by CLI flags like --fast or explicit --skip-*)
        config.serve.fast = bool_value(s["fast"]?, config.serve.fast)
      end

      private def self.load_markdown(config : Config)
        return unless s = config.raw["markdown"]?.try(&.as_h?)

        config.markdown.safe = bool_value(s["safe"]?, config.markdown.safe)
        config.markdown.lazy_loading = bool_value(s["lazy_loading"]?, config.markdown.lazy_loading)
        config.markdown.emoji = bool_value(s["emoji"]?, config.markdown.emoji)
        config.markdown.footnotes = bool_value(s["footnotes"]?, config.markdown.footnotes)
        config.markdown.task_lists = bool_value(s["task_lists"]?, config.markdown.task_lists)
        config.markdown.definition_lists = bool_value(s["definition_lists"]?, config.markdown.definition_lists)
        config.markdown.mermaid = bool_value(s["mermaid"]?, config.markdown.mermaid)
        config.markdown.math = bool_value(s["math"]?, config.markdown.math)
        if engine = s["math_engine"]?.try(&.as_s?)
          config.markdown.math_engine = engine
        end
        config.markdown.admonitions = bool_value(s["admonitions"]?, config.markdown.admonitions)
        config.markdown.heading_ids = bool_value(s["heading_ids"]?, config.markdown.heading_ids)
        config.markdown.ins = bool_value(s["ins"]?, config.markdown.ins)
        config.markdown.mark = bool_value(s["mark"]?, config.markdown.mark)
        config.markdown.sub = bool_value(s["sub"]?, config.markdown.sub)
        config.markdown.sup = bool_value(s["sup"]?, config.markdown.sup)
        config.markdown.attributes = bool_value(s["attributes"]?, config.markdown.attributes)
      end

      private def self.load_series(config : Config)
        return unless s = config.raw["series"]?.try(&.as_h?)

        config.series.enabled = bool_value(s["enabled"]?, config.series.enabled)
      end

      private def self.load_related(config : Config)
        return unless s = config.raw["related"]?.try(&.as_h?)

        config.related.enabled = bool_value(s["enabled"]?, config.related.enabled)
        # Clamp at the source so every consumer sees a sane value. A negative
        # limit reaches `Array#first(limit)` in the incremental related-posts
        # rebuild (transform.cr) and raises `ArgumentError: Negative count`,
        # crashing `serve` watch rebuilds (the full build guards `limit <= 0`,
        # the incremental path did not — clamping fixes both uniformly).
        config.related.limit = int_value(s["limit"]?, config.related.limit).clamp(0, Int32::MAX)
        if taxonomies = s["taxonomies"]?.try(&.as_a?)
          config.related.taxonomies = taxonomies.compact_map(&.as_s?)
        end
      end

      private def self.load_permalinks(config : Config)
        return unless s = config.raw["permalinks"]?.try(&.as_h?)

        s.each do |k, v|
          if target = v.as_s?
            # Strip surrounding slashes from BOTH the source key and the target.
            # resolve_permalink_dir matches against slash-free directory paths
            # and interpolates the target as `/#{effective_dir}/`, so a key or
            # target written with leading/trailing slashes (e.g. `"/blog/"`)
            # would otherwise silently never match (source) or produce
            # double-slash URLs like `http://host//blog//p/` (target).
            config.permalinks[k.strip("/")] = target.strip("/")
          end
        end
      end

      private def self.load_assets(config : Config)
        return unless s = config.raw["assets"]?.try(&.as_h?)

        config.assets.enabled = bool_value(s["enabled"]?, config.assets.enabled)
        config.assets.minify = bool_value(s["minify"]?, config.assets.minify)
        config.assets.fingerprint = bool_value(s["fingerprint"]?, config.assets.fingerprint)
        config.assets.source_dir = s["source_dir"]?.try(&.as_s?) || config.assets.source_dir
        config.assets.output_dir = s["output_dir"]?.try(&.as_s?) || config.assets.output_dir

        if bundles = s["bundles"]?.try(&.as_a?)
          bundles.each do |bundle_any|
            next unless b = bundle_any.as_h?
            name = b["name"]?.try(&.as_s?) || ""
            next if name.empty?

            files = if f = b["files"]?.try(&.as_a?)
                      f.compact_map(&.as_s?)
                    else
                      [] of String
                    end

            config.assets.bundles << AssetBundleConfig.new(name: name, files: files)
          end
        end
      end

      private def self.load_amp(config : Config)
        return unless s = config.raw["amp"]?.try(&.as_h?)

        config.amp.enabled = bool_value(s["enabled"]?, config.amp.enabled)
        config.amp.path_prefix = s["path_prefix"]?.try(&.as_s?) || config.amp.path_prefix
        if sections = s["sections"]?.try(&.as_a?)
          config.amp.sections = sections.compact_map(&.as_s?)
        end
      end

      private def self.load_pwa(config : Config)
        return unless s = config.raw["pwa"]?.try(&.as_h?)

        config.pwa.enabled = bool_value(s["enabled"]?, config.pwa.enabled)
        config.pwa.name = s["name"]?.try(&.as_s?)
        config.pwa.short_name = s["short_name"]?.try(&.as_s?)
        config.pwa.theme_color = s["theme_color"]?.try(&.as_s?) || config.pwa.theme_color
        config.pwa.background_color = s["background_color"]?.try(&.as_s?) || config.pwa.background_color
        config.pwa.display = s["display"]?.try(&.as_s?) || config.pwa.display
        config.pwa.start_url = s["start_url"]?.try(&.as_s?) || config.pwa.start_url
        config.pwa.offline_page = s["offline_page"]?.try(&.as_s?)
        if icons = s["icons"]?.try(&.as_a?)
          config.pwa.icons = icons.compact_map(&.as_s?)
        end
        if precache = s["precache_urls"]?.try(&.as_a?)
          config.pwa.precache_urls = precache.compact_map(&.as_s?)
        end
        if strategy = s["cache_strategy"]?.try(&.as_s?)
          if PwaConfig::VALID_STRATEGIES.includes?(strategy)
            config.pwa.cache_strategy = strategy
          else
            Logger.warn "Unknown pwa.cache_strategy '#{strategy}', using 'cache-first'"
          end
        end
      end

      private def self.load_image_processing(config : Config)
        return unless s = config.raw["image_processing"]?.try(&.as_h?)

        config.image_processing.enabled = bool_value(s["enabled"]?, config.image_processing.enabled)
        config.image_processing.quality = int_value(s["quality"]?, config.image_processing.quality).clamp(1, 100)
        if widths = s["widths"]?.try(&.as_a?)
          config.image_processing.widths = widths.compact_map { |w|
            val = int_or_nil(w)
            val && val > 0 ? val : nil
          }
        end

        # LQIP sub-config: [image_processing.lqip]
        if lqip = s["lqip"]?.try(&.as_h?)
          config.image_processing.lqip_enabled = bool_value(lqip["enabled"]?, config.image_processing.lqip_enabled)
          config.image_processing.lqip_width = int_value(lqip["width"]?, config.image_processing.lqip_width).clamp(8, 128)
          config.image_processing.lqip_quality = int_value(lqip["quality"]?, config.image_processing.lqip_quality).clamp(1, 100)
        end
      end

      private def self.load_doctor(config : Config)
        return unless s = config.raw["doctor"]?.try(&.as_h?)

        if ignore = s["ignore"]?.try(&.as_a?)
          config.doctor.ignore = ignore.compact_map(&.as_s?)
        end
      end

      private def self.load_static(config : Config)
        return unless s = config.raw["static"]?.try(&.as_h?)

        config.static.use_default_excludes = bool_value(s["use_default_excludes"]?, config.static.use_default_excludes)
        if exclude_any = s["exclude"]?
          config.static.exclude = string_or_array(exclude_any)
        end
      end

      private def self.load_deployment(config : Config)
        return unless s = config.raw["deployment"]?.try(&.as_h?)

        config.deployment.target = s["target"]?.try(&.as_s?)
        config.deployment.confirm = bool_value(s["confirm"]?, config.deployment.confirm)

        dry_any = s["dryRun"]? || s["dry_run"]?
        if dry_val = dry_any.try(&.as_bool?)
          config.deployment.dry_run = dry_val
        end

        if force_val = s["force"]?.try(&.as_bool?)
          config.deployment.force = force_val
        end

        max_deletes_any = s["maxDeletes"]? || s["max_deletes"]?
        if max_deletes_val = max_deletes_any.try { |v| int_or_nil(v) }
          config.deployment.max_deletes = max_deletes_val
        end

        if workers_val = s["workers"]?.try { |v| int_or_nil(v) }
          config.deployment.workers = workers_val
        end

        source_any = s["source_dir"]? || s["source"]?
        if source_val = source_any.try(&.as_s?)
          config.deployment.source_dir = source_val
        end

        load_deployment_targets(config, s)
        load_deployment_matchers(config, s)
      end

      private def self.load_deployment_targets(config : Config, s : Hash(String, TOML::Any))
        return unless targets_any = s["targets"]?.try(&.as_a?)

        config.deployment.targets = targets_any.compact_map do |target_any|
          next unless target_h = target_any.as_h?

          name = target_h["name"]?.try(&.as_s?)
          next unless name

          target = DeploymentTarget.new
          target.name = name
          # `path = "/tmp/out"` is the obvious shape for the
          # local-filesystem case and matches what Hugo / Jekyll users
          # try first. Treat it as an alias for `url`; the deployer
          # already routes bare local paths to its native copy
          # implementation (gh#529).
          target.url = target_h["URL"]?.try(&.as_s?) || target_h["url"]?.try(&.as_s?) || target_h["path"]?.try(&.as_s?) || ""
          target.command = target_h["command"]?.try(&.as_s?)
          target.include = target_h["include"]?.try(&.as_s?)
          target.exclude = target_h["exclude"]?.try(&.as_s?)

          strip_any = target_h["stripIndexHTML"]? || target_h["strip_index_html"]?
          if strip_val = strip_any.try(&.as_bool?)
            target.strip_index_html = strip_val
          end

          target
        end
      end

      private def self.load_deployment_matchers(config : Config, s : Hash(String, TOML::Any))
        return unless matchers_any = s["matchers"]?.try(&.as_a?)

        config.deployment.matchers = matchers_any.compact_map do |matcher_any|
          next unless matcher_h = matcher_any.as_h?

          pattern = matcher_h["pattern"]?.try(&.as_s?)
          next unless pattern

          matcher = DeploymentMatcher.new
          matcher.pattern = pattern
          matcher.cache_control = matcher_h["cacheControl"]?.try(&.as_s?) || matcher_h["cache_control"]?.try(&.as_s?)
          matcher.content_type = matcher_h["contentType"]?.try(&.as_s?) || matcher_h["content_type"]?.try(&.as_s?)
          if gzip_val = matcher_h["gzip"]?.try(&.as_bool?)
            matcher.gzip = gzip_val
          end
          if force_val = matcher_h["force"]?.try(&.as_bool?)
            matcher.force = force_val
          end
          matcher
        end
      end

      private def self.load_outputs(config : Config)
        return unless s = config.raw["outputs"]?.try(&.as_h?)

        if page_any = s["page"]?
          config.outputs.page = validate_output_formats(string_or_array(page_any))
        end
        if section_any = s["section"]?
          config.outputs.section = validate_output_formats(string_or_array(section_any))
        end
        if sections = s["sections"]?.try(&.as_a?)
          config.outputs.sections = sections.compact_map(&.as_s?)
        end
      end

      # Validate `[outputs]` format names against `OutputsConfig::VALID_FORMATS`.
      # Raises a classified `HWARO_E_CONFIG` error (rather than warning and
      # falling back) because an unknown format silently produces no output —
      # a user who typos "jso" for "json" deserves a build failure, not a
      # quietly-missing file.
      private def self.validate_output_formats(formats : Array(String)) : Array(String)
        formats.each do |fmt|
          next if OutputsConfig::VALID_FORMATS.includes?(fmt)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Unknown output format '#{fmt}' in [outputs]. Valid formats: #{OutputsConfig::VALID_FORMATS.join(", ")}.",
            hint: "Use one of: #{OutputsConfig::VALID_FORMATS.join(", ")}.",
          )
        end
        formats
      end
    end
  end
end
