require "html"
require "crinja"
require "../utils/text_utils"
require "../content/processors/fence_tracker"
require "./git_info"
require "./config"

module Hwaro
  module Models
    # Recursive value type for `page.extra`. Keeps `Array(String)` in the union
    # so existing call sites that assign a plain string literal array
    # (`page.extra["x"] = ["a", "b"]`) continue to compile — Crystal arrays are
    # invariant so `Array(String)` is not assignable to `Array(ExtraValue)`.
    alias ExtraValue = String | Bool | Int64 | Float64 | Array(String) | Array(ExtraValue) | Hash(String, ExtraValue)

    struct TranslationLink
      property code : String
      property url : String
      property title : String
      property is_current : Bool
      property is_default : Bool

      def initialize(
        @code : String,
        @url : String,
        @title : String,
        @is_current : Bool = false,
        @is_default : Bool = false,
      )
      end
    end

    # One entry of `page.version_links` — the version switcher row for a
    # versioned page. `url` is the SAME page in that version when it exists
    # (matched by path relative to the version root, same language), else
    # that version's root URL with `exists = false`.
    struct VersionLink
      property name : String
      property label : String
      property latest : Bool
      property url : String
      property exists : Bool
      property current : Bool

      def initialize(
        @name : String,
        @label : String,
        @latest : Bool,
        @url : String,
        @exists : Bool,
        @current : Bool = false,
      )
      end
    end

    # Front-matter registration of a page/section into a named menu (see
    # `[[menus.*]]` in config for the config-side counterpart). All fields
    # are optional: a bare `menus = ["main"]` entry yields a
    # `MenuRegistration` with everything `nil`, and the menu builder falls
    # back to the page's own title/weight/identifier/parent-less defaults.
    record MenuRegistration,
      name : String? = nil,
      weight : Int32? = nil,
      parent : String? = nil,
      identifier : String? = nil

    class Page
      # Front Matter Properties
      property title : String
      property description : String?
      property date : Time?
      property updated : Time?
      property expires : Time?
      property template : String?
      property draft : Bool
      property render : Bool
      property slug : String?
      property custom_path : String?
      property aliases : Array(String)
      property tags : Array(String)
      property taxonomies : Hash(String, Array(String))
      # Named-menu registrations from front matter (`menus`/`menu` keys),
      # keyed by menu name. See `Content::Menus.build`.
      property menus : Hash(String, MenuRegistration)
      property front_matter_keys : Array(String)
      property weight : Int32
      # Rendered HTML for the chunk before `<!-- more -->`. Populated by
      # the build pipeline after `extract_summary` runs and the markdown
      # processor is available; nil for pages without a `<!-- more -->`
      # marker (in which case `page.summary` falls back to `description`).
      # See https://github.com/hahwul/hwaro/issues/491.
      property summary_html : String?
      property taxonomy_name : String?
      property taxonomy_term : String?
      property in_sitemap : Bool
      property toc : Bool
      property generated : Bool
      property image : String?

      # Provenance of a page materialized from `[[content.generate]]` (see
      # Core::Build::ContentGenerate). Unlike `generated` — which marks the
      # SYNTHETIC taxonomy listing pages that every content surface (feeds,
      # search, related, OG, AMP, output formats) deliberately excludes —
      # a synthesized page is first-class content: it enters the build in
      # the ReadContent phase and flows through parse/transform/render like
      # an authored file. The parse phase reads `markdown` instead of a
      # disk file, and re-exposes `item` (the source record) under
      # `page.extra.item` after front matter parsing.
      class Synthesis
        # Full synthetic markdown document (TOML front matter + body).
        getter markdown : String
        # The source record, bound to `item` in body_template renders and
        # published to templates as `page.extra.item`.
        getter item : Crinja::Value
        # Human-readable origin for logs/tooling, e.g. "data.products".
        getter origin : String

        def initialize(@markdown : String, @item : Crinja::Value, @origin : String)
        end
      end

      property synthesis : Synthesis?

      # True for pages materialized from `[[content.generate]]`.
      def synthesized? : Bool
        !@synthesis.nil?
      end

      # New: Assets - static files in this page directory
      property assets : Array(String)

      # New: Authors field (array of author names)
      property authors : Array(String)

      # New: Extra field for arbitrary custom metadata from front matter.
      # Values are recursive (`ExtraValue`) so nested `[extra.*]` subtables
      # and arrays-of-tables round-trip into `{{ page.extra.a.b }}` in templates.
      property extra : Hash(String, ExtraValue)

      # New: Summary - content before <!-- more --> marker or auto-generated
      property summary : String?

      # Automatic summary: plain text cut from the rendered body when the
      # page has neither a `<!-- more -->` marker nor a `description`
      # (`[content] summary_length`). Populated by
      # ParseContent#render_page_summaries; nil when the fallback is
      # disabled, when a higher-precedence source exists, or when the body
      # has no prose. `summary_truncated` is true only when the text was cut.
      property auto_summary : String?
      property summary_truncated : Bool

      # New: In search index - whether to include in search index
      property in_search_index : Bool

      # New: Insert anchor links - whether to add anchor links to headings.
      # Tri-state: nil (front matter silent) falls back to the site-wide
      # `[markdown] insert_anchor_links` config; an explicit true/false wins.
      property insert_anchor_links : Bool?

      # Fingerprint of the merged section [cascade] values applied to this
      # page (empty when none apply). Stored in the build cache so editing a
      # parent _index.md's cascade invalidates descendant pages whose own
      # source files did not change.
      property cascade_fingerprint : String

      # Build warnings collected during rendering (used for error overlay in serve mode)
      property build_warnings : Array(String)

      # Whether parsing (front-matter / markdown) failed for this page
      property parse_failed : Bool

      # Deferred [permalinks] error from the parse fan-out (a date-token
      # pattern matched a dateless page). Whether it's fatal isn't knowable
      # until cascades and draft/expiry filtering ran: a page filtered out
      # of the build (or a headless `render: false` page) never publishes
      # the URL, so only surviving renderable pages raise — see
      # ParseContent#raise_on_permalink_errors!.
      property permalink_error : String?

      # True when the page is outside its publication window at build time
      # (future `date` or past `expires`). Such pages only survive the parse
      # filter under --include-future / --include-expired — preview flags —
      # and must then behave exactly like drafts under --drafts: the HTML
      # page renders, but the page stays out of every public discovery
      # surface (sitemap, feeds, search index, llms.txt) and out of
      # generated listings (taxonomies, series, related posts, authors).
      property unpublished : Bool

      # True when the render phase resolved an output-path collision AGAINST
      # this page, or found its URL unpublishable (a segment traverses out of
      # the output directory), so no file was written for its URL (see
      # compute_output_url_winners). Recomputed from scratch on every build and
      # rerender — a collision introduced or resolved during a serve session
      # must not leave a stale verdict behind.
      #
      # The discovery surfaces have to honour it: without this the build warned
      # about the collision, declined to write the page, and then advertised
      # its URL anyway in sitemap.xml, llms.txt, the feeds and the search
      # index — trading a silent overwrite for a guaranteed 404 that the site's
      # own sitemap points at.
      property output_suppressed : Bool = false

      # Runtime / Computed Properties
      property content : String
      property raw_content : String
      property path : String      # Relative path from content/ (e.g. "projects/a.md")
      property section : String   # Parent directory path (e.g. "blog/news"), not just the first component
      getter url : String         # Calculated relative URL (e.g. "/projects/a/"), written through #url=
      property is_index : Bool    # Is this an index file?
      property language : String? # Language code (e.g. "en", "ko", nil for default)
      property translations : Array(TranslationLink)
      # Documentation version this page belongs to (`[[versions.list]]`),
      # resolved from its content directory in ReadContent; nil for
      # unversioned content. See Content::Versions.
      property version : VersionConfig?
      # Switcher rows, one per configured version (see VersionLink); empty
      # for unversioned pages. Filled by Content::Versions.link!.
      property version_links : Array(VersionLink)

      # New: Word count and reading time (computed)
      property word_count : Int32
      property reading_time : Int32 # in minutes

      # New: Permalink (absolute URL with base_url)
      property permalink : String?

      # New: Lower/Higher page references (previous/next in section)
      property lower : Page?  # Previous page (by date or weight)
      property higher : Page? # Next page (by date or weight)

      # New: Ancestors - parent sections chain
      property ancestors : Array(Page)

      # New: Series support
      property series : String?
      property series_weight : Int32
      property series_index : Int32
      property series_pages : Array(Page)

      # New: Related posts (computed by taxonomy similarity)
      property related_posts : Array(Page)

      # New: Redirect to - URL to redirect this page to
      property redirect_to : String?

      # Commit metadata for this page's source file (`[git] enabled = true`).
      # Nil when the feature is off, the file is uncommitted, the site is not
      # a git checkout, or the page is synthesized/generated.
      property git : GitInfo?

      def initialize(@path : String)
        @title = "Untitled"
        @draft = false
        @render = true
        @tags = [] of String
        @aliases = [] of String
        @taxonomies = {} of String => Array(String)
        @menus = {} of String => MenuRegistration
        @front_matter_keys = [] of String
        @weight = 0
        @taxonomy_name = nil
        @taxonomy_term = nil
        @generated = false
        @image = nil
        @content = ""
        @raw_content = ""
        @section = ""
        @unpublished = false
        @url = ""
        @is_index = false
        @in_sitemap = true
        @toc = false
        @language = nil
        @translations = [] of TranslationLink
        @version = nil
        @version_links = [] of VersionLink
        @assets = [] of String

        # New field defaults
        @authors = [] of String
        @extra = {} of String => ExtraValue
        @summary = nil
        @summary_html = nil
        @auto_summary = nil
        @summary_truncated = false
        @in_search_index = true
        @insert_anchor_links = nil
        @word_count = 0
        @reading_time = 0
        @permalink = nil
        @lower = nil
        @higher = nil
        @ancestors = [] of Page
        @series = nil
        @series_weight = 0
        @series_index = 0
        @series_pages = [] of Page
        @related_posts = [] of Page
        @redirect_to = nil
        @git = nil
        @cascade_fingerprint = ""
        @build_warnings = [] of String
        @parse_failed = false
      end

      # Check if page has redirect
      def has_redirect? : Bool
        !@redirect_to.nil? && !@redirect_to.try(&.empty?)
      end

      # True when a page should be omitted from generated listings (taxonomy
      # indexes, related posts, …): drafts, preview-only unpublished pages,
      # and synthetic generated pages.
      def excluded_from_listings? : Bool
        draft || unpublished || generated
      end

      # True when a page is eligible for the search index / llms.txt: it emits
      # HTML, isn't a draft or preview-only unpublished page, opts into the
      # search index, and isn't a synthetic generated listing page.
      def search_index_eligible? : Bool
        render && !draft && !unpublished && in_search_index && !generated && !output_suppressed
      end

      # Recompute `unpublished` from the publication window (`date` in the
      # future or `expires` in the past) relative to the build's single `now`.
      # Called by the parse-phase filter and the incremental (--cache)
      # re-parse path so every downstream consumer sees a consistent value.
      def refresh_unpublished!(now : Time)
        @unpublished = (expires.try { |e| e <= now } || false) ||
                       (date.try { |d| d > now } || false)
      end

      # Resolve the term list for a configured taxonomy `name`. Most
      # taxonomies live in `@taxonomies`, but a few — `tags` and `authors`
      # — are stored on dedicated `Page` properties so other features
      # (the `tags` shortcut, the `site.authors` aggregation) can reach
      # them without a hash lookup. Centralizing the fallback here keeps
      # call sites (Taxonomies generator, related-posts scoring, …) from
      # forgetting any of the special cases.
      def taxonomy_values(name : String) : Array(String)
        return @taxonomies[name] if @taxonomies.has_key?(name)
        case name
        when "tags"    then @tags
        when "authors" then @authors
        else                [] of String
        end
      end

      # Collect assets from page directory
      #
      # When `content_files` is configured (`[content.files]` with
      # `allow_extensions`), co-located bundle assets are filtered through the
      # SAME allow/disallow rules as standalone content files. Without this, a
      # root `_index.md` turns the whole `content/` tree into one recursive
      # bundle and republishes arbitrary non-markdown files (e.g.
      # `content/public/robots.txt`) to the output regardless of
      # `allow_extensions`. When `[content.files]` is not configured, every
      # non-markdown file is collected (unchanged behavior).
      #
      # Two structural limits keep the recursion inside the bundle it belongs
      # to (both hold regardless of `[content.files]`, which many hand-written
      # configs omit entirely):
      #
      #   1. `content/` itself is never a bundle. `content/index.md` is the
      #      homepage, not a bundle spanning the site, and treating it as one
      #      republished every non-markdown file anywhere under `content/`
      #      (`content/private/internal.pdf`, `notes.txt`, `*.bak`, …) into the
      #      output root.
      #   2. Recursion stops at nested bundles/sections. A subdirectory holding
      #      its own `index.md`/`_index.md` is a different page and publishes
      #      its own assets; descending into it made every ancestor index
      #      re-copy the same files.
      # `bundle_dirs` (content-relative directories that host their own bundle
      # index, computed by Transform#collect_assets from the page set) extends
      # nested-bundle detection to language-suffixed indexes
      # (`photos/index.ko.md`) that the literal on-disk probe cannot see.
      def collect_assets(content_dir : String, content_files : ContentFilesConfig? = nil, bundle_dirs : Set(String)? = nil) : Array(String)
        # Assets are only collected for page bundles (directories)
        # This usually means the page is an index.md (either _index.md or index.md)
        return [] of String unless @is_index

        # So we construct the directory path.
        page_dir = File.dirname(File.join(content_dir, @path))

        return [] of String unless Dir.exists?(page_dir)
        return [] of String if Path[page_dir].normalize == Path[content_dir].normalize

        @assets = Dir.glob(File.join(page_dir, "**", "*")).compact_map do |file|
          next unless File.file?(file)
          next if file.ends_with?(".md") || file.ends_with?(".markdown")
          next if nested_bundle?(page_dir, file, content_dir, bundle_dirs)

          relative = Path[file].relative_to(content_dir).to_s
          # Honor [content.files] allow/disallow rules when configured so the
          # bundle path can't bypass the user's publishing allowlist.
          next if content_files && content_files.enabled? && !content_files.publish?(relative)

          relative
        end

        @assets
      end

      # True when `file` sits under a subdirectory of `page_dir` that carries
      # its own bundle index — i.e. it is another page's asset, not this
      # bundle's. Walks the intermediate directories from the bundle root
      # down to the file's own directory. Beyond the literal
      # `index.md`/`_index.md` probe, `bundle_dirs` membership catches
      # translated-only bundles (`index.ko.md`) whose assets would otherwise
      # be re-published by every ancestor bundle.
      private def nested_bundle?(page_dir : String, file : String, content_dir : String, bundle_dirs : Set(String)?) : Bool
        dir = File.dirname(file)
        while dir != page_dir && dir.size > page_dir.size
          return true if File.exists?(File.join(dir, "index.md")) ||
                         File.exists?(File.join(dir, "_index.md"))
          if bundle_dirs
            return true if bundle_dirs.includes?(Path[dir].relative_to(content_dir).to_s)
          end
          parent = File.dirname(dir)
          break if parent == dir
          dir = parent
        end
        false
      end

      # Calculate word count from raw content
      # Note: @raw_content already has front matter stripped during parsing,
      # so we only need to remove HTML tags and markdown syntax.
      def calculate_word_count : Int32
        # Shared with `hwaro tool stats` via TextUtils so the CLI report and
        # the published `page.word_count` can never drift apart.
        @word_count = Utils::TextUtils.count_words(@raw_content)
        @word_count
      end

      # Calculate reading time in minutes (assuming ~200 words per minute)
      def calculate_reading_time(words_per_minute : Int32 = 200) : Int32
        calculate_word_count if @word_count == 0
        wpm = words_per_minute < 1 ? 200 : words_per_minute
        @reading_time = (@word_count.to_f / wpm).ceil.to_i
        @reading_time = 1 if @reading_time < 1 && @word_count > 0
        @reading_time
      end

      # Extract summary from content using <!-- more --> marker
      # Returns content before the marker, or nil if no marker found
      # Note: @raw_content has front matter already stripped during parsing
      #
      # Fence-aware: a marker shown inside a fenced code block (a docs page
      # demonstrating the feature) is literal text, not a split point. The
      # per-line pattern no longer matches a marker whose parts sit on
      # different lines — degenerate input the old multi-line `\s*` accepted.
      MORE_MARKER_REGEX = /<!--\s*more\s*-->/i

      def extract_summary : String?
        return @summary unless @raw_content.includes?("<!--")

        offset = 0
        tracker = Content::Processors::FenceTracker.new
        @raw_content.each_line(chomp: false) do |line|
          if !tracker.fence_line?(line) && (match = line.match(MORE_MARKER_REGEX))
            summary_md = @raw_content.byte_slice(0, offset + match.byte_begin(0)).strip
            @summary = summary_md unless summary_md.empty?
            return @summary
          end
          offset += line.bytesize
        end
        @summary
      end

      # `#` and `?` are legal in a filename (and in an explicit `slug`/`path`)
      # but they END the path component of a URL: `/posts/a#b/` is the page
      # `/posts/a` with the fragment `b`. A page named `a#b.md` was written
      # correctly to `public/posts/a#b/index.html`, yet every link hwaro
      # emitted for it — `page.url` in listings, `page.permalink`, the sitemap
      # `<loc>` — pointed at `/posts/a`, a 404. Encode them here, at the one
      # place a page's URL is assigned, so templates that use `page.url`
      # directly are right too and not just the permalink.
      #
      # Nothing else is escaped. The output path is derived from this string
      # by decoding it again (`PathUtils.split_safe_segments`), so `%23` still
      # lands in the directory named `a#b` that the URL now addresses —
      # whereas encoding more (a non-ASCII slug, say) would rename the
      # directory every existing site already publishes to. Leaving `%` itself
      # alone also keeps this idempotent when a URL is assigned twice.
      def url=(value : String)
        @url = if value.includes?('#') || value.includes?('?')
                 value.gsub('#', "%23").gsub('?', "%3F")
               else
                 value
               end
      end

      # Generate permalink (absolute URL)
      def generate_permalink(base_url : String) : String
        base = base_url.rstrip("/")
        path = @url.starts_with?("/") ? @url : "/#{@url}"
        permalink = "#{base}#{path}"
        @permalink = permalink
        permalink
      end

      # Check if page has a summary: `<!-- more -->` marker, description, or
      # the automatic body excerpt (same precedence as `effective_summary`).
      def has_summary? : Bool
        !@summary.nil? || !@description.nil? || !@auto_summary.nil?
      end

      # Get effective summary: `<!-- more -->` chunk > description > automatic
      # excerpt. The excerpt is returned as a single escaped `<p>` so
      # `{{ page.summary | safe }}` keeps working for every source.
      def effective_summary : String?
        @summary || @description || auto_summary_html
      end

      # The automatic excerpt as HTML: text is escaped (it was decoded from
      # the rendered body, so `<`/`&` are literal characters) and wrapped in
      # one paragraph. Nil when there is no automatic summary.
      def auto_summary_html : String?
        @auto_summary.try { |text| "<p>#{HTML.escape(text)}</p>" }
      end

      # plain_summary memo — see the method below. `@plain_summary_for`
      # holds the exact String instance the text was derived from.
      @plain_summary_for : String? = nil
      @plain_summary_text : String? = nil

      # Plain-text rendering of the `<!-- more -->` summary, safe to embed
      # in single-line contexts like `og:description`,
      # `twitter:description`, or a feed `<description>`. Uses the
      # already-rendered `summary_html` and strips markup so raw markdown
      # (`##` headings, code fences, math, literal newlines) never leaks
      # into meta tags — see https://github.com/hahwul/hwaro/issues/491.
      # Returns nil when the page has no summary. Soft-truncates to `limit`
      # characters on a word boundary. Falls back to the automatic body
      # excerpt (already plain text) when no marker summary exists.
      def plain_summary(limit : Int32 = 200) : String?
        # Prefer the rendered summary HTML (populated during parsing); fall
        # back to the raw markdown chunk only if render hasn't run yet —
        # strip_html still removes any inline HTML there.
        source = @summary_html || @summary
        return soft_truncate_summary(@auto_summary, limit) unless source
        # Memoize the strip/unescape (it runs per page for og:description
        # AND again per feed item). Keyed on the source string's identity:
        # any reassignment of summary_html/summary swaps in a different
        # String instance and forces a recompute, so no setter hooks are
        # needed for invalidation.
        if @plain_summary_for.same?(source)
          text = @plain_summary_text
        else
          # Strip tags, then decode entities so escaped chars from rendered
          # HTML (e.g. `&gt;` inside code blocks) become real characters —
          # the meta-tag layer re-escapes them, avoiding `&amp;gt;` artifacts.
          stripped = Hwaro::Utils::TextUtils.html_to_plain_text(source)
          text = stripped.empty? ? nil : stripped
          @plain_summary_text = text
          @plain_summary_for = source
        end
        soft_truncate_summary(text, limit)
      end

      private def soft_truncate_summary(text : String?, limit : Int32) : String?
        return unless text
        return text if text.size <= limit

        truncated = text[0, limit]
        if (idx = truncated.rindex(' ')) && idx > limit // 2
          truncated = truncated[0, idx]
        end
        "#{truncated.rstrip}…"
      end
    end
  end
end
