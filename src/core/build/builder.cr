# Main builder module for site generation
#
# This is the core build orchestrator that coordinates phase-based modules:
# - Initialize: output dir setup, cache init, config/template loading
# - ReadContent: content path collection
# - ParseContent: frontmatter parsing (sequential/parallel)
# - Transform: site population, taxonomy, related posts
# - Render: template rendering (sequential/parallel/streaming)
# - Generate: SEO files (sitemap, feeds, robots, etc.)
# - Write: 404 page, raw files, assets
# - Finalize: cache save
#
# The Builder uses the Lifecycle system to allow extensibility
# through hooks at various phases of the build process.

require "digest/md5"
require "file_utils"
require "html"
require "set"
require "toml"
require "json"
require "crinja"
require "./cache"
require "./cache_manager"
require "./parallel"
require "./template_deps"
require "./shortcode_processor"
require "./phases/initialize"
require "./phases/read_content"
require "./phases/parse_content"
require "./phases/transform"
require "./phases/render"
require "./phases/generate"
require "./phases/write"
require "./phases/finalize"
require "../../content/seo/feeds"
require "../../content/seo/sitemap"
require "../../content/seo/robots"
require "../../content/seo/llms"
require "../../content/seo/tags"
require "../../content/seo/jsonld"
require "../../content/search"
require "../../content/pagination/paginator"
require "../../content/pagination/renderer"
require "../../utils/digest_utils"
require "../../utils/errors"
require "../../utils/file_safe"
require "../../utils/logger"
require "../../utils/profiler"
require "../../utils/text_utils"
require "../../config/options/build_options"
require "../../content/processors/markdown"
require "../../content/processors/content_files"
require "../../content/processors/template"
require "../../content/multilingual"
require "../../content/i18n"
require "../../models/config"
require "../../models/page"
require "../../models/section"
require "../../models/toc"
require "../../models/site"
require "../lifecycle"
require "../../utils/debug_printer"
require "../../utils/path_utils"
require "../../utils/crinja_utils"
require "../../utils/html_minifier"
require "../../utils/output_guard"
require "../../utils/redirect_html"

module Hwaro
  module Core
    module Build
      class Builder
        include ShortcodeProcessor

        # Phase modules — each contributes its methods to this class
        include Phases::Initialize
        include Phases::ReadContent
        include Phases::ParseContent
        include Phases::Transform
        include Phases::Render
        include Phases::Generate
        include Phases::Write
        include Phases::Finalize

        TEMPLATE_EXTENSION_REGEX = /\.(html|j2|jinja2|jinja|ecr)$/

        @site : Models::Site?
        @templates : Hash(String, String)?
        # Template name → source file path (e.g. "page" => "templates/page.html").
        # Lets compiled templates carry their filename so Crinja errors report
        # file:line:col with a source excerpt instead of an anonymous string.
        @template_paths : Hash(String, String) = {} of String => String
        # Static extends/include/import graph over the loaded templates.
        # Rebuilt whenever templates reload; nil before the first load.
        @template_deps : TemplateDeps?
        # Combined checksum of all templates for the current build — the
        # fallback per-entry template hash when dependency tracking is off.
        @global_templates_hash : String = ""
        # True when per-page template closure hashes drive cache invalidation
        # (config build.template_deps on and the graph is fully static).
        @per_page_template_hash : Bool = false
        # Validated {dir, language} => cascade map captured during the cold
        # build's parse phase — BEFORE draft/expired/future filtering, so
        # incremental passes see the same cascades a cold build applies
        # (a draft section's cascade still reaches its descendants).
        @cascade_map : Hash(Tuple(String, String), Hash(String, Models::ExtraValue))?
        @cache : Cache?
        @config : Models::Config?
        @lifecycle : Lifecycle::Manager
        @context : Lifecycle::BuildContext?
        @profiler : Profiler?
        @crinja_env : Crinja?
        @compiled_templates_cache : Hash(UInt64, Crinja::Template) = {} of UInt64 => Crinja::Template
        # Per-template "can the shortcode processor rewrite this?" decision,
        # keyed by template-source hash. Populated once in load_templates
        # (single-threaded Initialize phase), read-only during render — lets
        # apply_template skip the per-page shortcode scan over template
        # strings that contain no shortcode tokens. A missing key means
        # "unknown": process as before.
        @template_shortcode_scan : Hash(UInt64, Bool) = {} of UInt64 => Bool
        # Which expensive per-page template variables a template's static
        # closure can actually reach. build_template_variables skips building
        # the ones it provably can't (SEO/OG strings, JSON-LD strings, the
        # per-page section-pages array copy — O(section size) per page).
        # Detection is substring-based over the closure's source union, so it
        # only ever over-approximates: any occurrence of the identifier keeps
        # the variable. A template is only gated when its whole closure is
        # statically resolvable AND it cannot contain shortcodes (template
        # shortcodes render with the same vars hash and could read anything).
        record TemplateVarFeatures,
          needs_seo : Bool,
          needs_jsonld : Bool,
          needs_section_pages : Bool
        # Keyed by entry template NAME (closure semantics are per-name).
        # Populated once in load_templates, read-only during render. Missing
        # key means "unknown": build everything, exactly as before.
        @template_var_features : Hash(String, TemplateVarFeatures) = {} of String => TemplateVarFeatures
        # Tracks shortcode template keys we've already warned about, so a
        # single typo used across many pages emits just one warning line.
        @shortcode_warnings_seen : Set(String)? = nil
        @pages_by_path : Hash(String, Models::Page)?
        @i18n_translations : Content::I18n::TranslationData = Content::I18n::TranslationData.new
        # Per-section cache of Crinja::Value arrays, keyed by "section_name:language"
        @section_pages_crinja_cache : Hash(String, Array(Crinja::Value)) = {} of String => Array(Crinja::Value)
        # Companion url→index map per section list, populated together with
        # (and invalidated exactly like) @section_pages_crinja_cache. Used
        # for O(1) current-page exclusion in build_template_variables —
        # the previous per-page linear Array#index scan made rendering a
        # flat N-page section O(N²).
        @section_pages_url_index_cache : Hash(String, Hash(String, Int32)) = {} of String => Hash(String, Int32)
        # Per-section cache of Crinja::Value arrays for section assets, keyed by section name
        @section_assets_crinja_cache : Hash(String, Array(Crinja::Value)) = {} of String => Array(Crinja::Value)
        # Track created directories to avoid redundant mkdir_p syscalls
        @created_dirs : Set(String) = Set(String).new
        # Per-page Crinja::Value cache — avoids repeated Page→Crinja::Value conversion
        # across build_global_vars, section page lists, and page_to_crinja_list_value
        @page_crinja_value_cache : Hash(String, Crinja::Value) = {} of String => Crinja::Value
        @series_crinja_cache : Hash(String, Crinja::Value) = {} of String => Crinja::Value
        # Per-section ancestors Crinja::Value cache (pages in the same section share ancestors)
        @ancestors_crinja_cache : Hash(String, Array(Crinja::Value)) = {} of String => Array(Crinja::Value)
        # Per-page related_posts Crinja::Value cache (avoids rebuilding the array on each build_template_variables call)
        @related_posts_crinja_cache : Hash(String, Crinja::Value) = {} of String => Crinja::Value
        # Per-page template closure hash memo (page.path → hash). On cached
        # builds the hash is needed twice per page (filter_changed_pages and
        # cache.update) and costs shortcode regex scans over the raw content.
        # Cleared with the runtime caches; incremental builds drop entries
        # for re-parsed pages (their content — hence shortcode usage — may
        # have changed).
        @page_template_hash_memo : Hash(String, String) = {} of String => String
        @page_template_hash_mutex : Mutex = Mutex.new
        # Mutex to protect shared Crinja value caches during parallel rendering.
        # Crystal fibers are single-threaded by default, but this guards against
        # future multi-threaded mode (-Dpreview_mt) and ensures correctness.
        @crinja_cache_mutex : Mutex = Mutex.new(:reentrant)
        # True only while the default (non-streaming) Render phase fan-out runs:
        # prewarm_crinja_caches has filled every Crinja value cache the workers
        # can read, no cache is written until the flag drops, and readers
        # therefore skip @crinja_cache_mutex entirely (concurrent reads of a
        # non-mutated Hash are safe). A frozen-path miss computes its value
        # WITHOUT caching — prewarming makes that a rare one-off, so this can't
        # reintroduce the per-page re-conversion regression that removing the
        # mutex outright caused. Serve/incremental rebuilds, streaming mode
        # (which clears caches mid-run), fast-start deferred renders, and
        # rerenders all run with the flag false, i.e. the locked path.
        @crinja_caches_frozen : Bool = false
        # Mutex to protect created_dirs set during parallel rendering
        @created_dirs_mutex : Mutex = Mutex.new
        # Explicit render-worker count from `--jobs` (0 = auto/CPU-based).
        # Set from BuildOptions at every build entry point and consumed by
        # process_files_parallel's ParallelConfig. Does not affect output.
        @render_workers : Int32 = 0
        # Unified cache manager for all cache layers
        @cache_manager : CacheManager = CacheManager.new
        # The render phase's site-wide template vars, stashed so the Write
        # phase's 404 page can reuse them. Rebuilding them there re-converted
        # every page/section/taxonomy term to Crinja values and re-hashed
        # every auto-include asset — O(site) work for one page — and silently
        # used cache_busting defaults instead of the build's options.
        @render_global_vars : Hash(String, Crinja::Value)? = nil
        # Pages stashed by `--fast-start` during the initial build so the
        # dev server can render them in a background fiber after the
        # "ready" signal has been emitted. Nil outside of fast-start mode.
        @deferred_pages : Array(Models::Page)? = nil

        def initialize
          @lifecycle = Lifecycle::Manager.new
          setup_cache_manager
        end

        # Access cache manager for external inspection
        def cache_manager : CacheManager
          @cache_manager
        end

        # Profiler to thread into per-page render loops, or nil when
        # profiling is off. The record_* methods already no-op when
        # disabled, but callers test the reference before taking
        # timestamps — passing nil skips two Time.instant calls and a
        # redundant determine_template per rendered page.
        private def active_profiler : Profiler?
          @profiler.try { |p| p.enabled? ? p : nil }
        end

        # Access build context for external inspection (e.g. emitting JSON
        # output after a build). Returns nil before `run` has been invoked.
        def context : Lifecycle::BuildContext?
          @context
        end

        # Register all cache layers with the unified manager
        private def setup_cache_manager
          @cache_manager.register("compiled_templates", "Compiled Crinja template ASTs", runtime: true) do
            @compiled_templates_cache.clear
          end
          @cache_manager.register("page_crinja_value", "Page→Crinja::Value conversions", runtime: true) do
            @page_crinja_value_cache.clear
          end
          @cache_manager.register("section_pages_crinja", "Section page lists as Crinja values", runtime: true) do
            @section_pages_crinja_cache.clear
            @section_pages_url_index_cache.clear
          end
          @cache_manager.register("section_assets_crinja", "Section asset lists as Crinja values", runtime: true) do
            @section_assets_crinja_cache.clear
          end
          @cache_manager.register("series_crinja", "Series page lists as Crinja values", runtime: true) do
            @series_crinja_cache.clear
          end
          @cache_manager.register("ancestors_crinja", "Ancestor pages as Crinja values", runtime: true) do
            @ancestors_crinja_cache.clear
          end
          @cache_manager.register("related_posts_crinja", "Related posts as Crinja values", runtime: true) do
            @related_posts_crinja_cache.clear
          end
          @cache_manager.register("page_template_hash", "Per-page template closure hashes", runtime: true) do
            @page_template_hash_mutex.synchronize { @page_template_hash_memo.clear }
          end
          @cache_manager.register("build_cache", "Persistent file-change tracking (.hwaro_cache.json)", runtime: false) do
            @cache.try(&.clear)
          end
        end

        # Access lifecycle for external hook registration
        def lifecycle : Lifecycle::Manager
          @lifecycle
        end

        # Register a Hookable module
        def register(hookable : Lifecycle::Hookable)
          @lifecycle.register(hookable)
          self
        end

        def run(options : Config::Options::BuildOptions)
          @render_workers = options.workers
          run(
            output_dir: options.output_dir,
            base_url: options.base_url,
            drafts: options.drafts,
            include_expired: options.include_expired,
            include_future: options.include_future,
            minify: options.minify,
            parallel: options.parallel,
            cache: options.cache,
            highlight: options.highlight,
            verbose: options.verbose,
            profile: options.profile,
            debug: options.debug,
            error_overlay: options.error_overlay,
            stream: options.stream,
            memory_limit: options.memory_limit,
            env: options.env,
            fast_start: options.fast_start,
            fast_start_count: options.fast_start_count,
            skip_og_image: options.skip_og_image,
            skip_image_processing: options.skip_image_processing,
            preserve_output: options.preserve_output,
            cache_busting: options.cache_busting,
          )
        end

        # Incremental build: only re-parse and re-render pages whose source
        # files have been modified.  Falls back to a full build when the
        # necessary state from a previous build is not available.
        #
        # Optimizations over a full build:
        # - Only re-parses changed files (not all pages)
        # - Diff-based taxonomy update (not full rebuild)
        # - Re-links navigation only for affected sections
        # - Recomputes series/related posts only for affected pages
        # - Selectively invalidates Crinja caches
        def run_incremental(changed_content_files : Array(String), options : Config::Options::BuildOptions)
          @render_workers = options.workers
          config = @config
          site = @site
          templates = @templates

          # First build hasn't happened yet – fall back to full build
          unless config && site && templates
            return run(options)
          end

          Logger.info "Incremental build for #{changed_content_files.size} changed file(s)..." if options.verbose
          start_time = Time.instant

          output_dir = options.output_dir
          minify = options.minify
          highlight = options.highlight && site.config.highlight.enabled
          verbose = options.verbose
          include_drafts = options.drafts

          # --- 1. Identify changed pages and snapshot their state before re-parse ---
          changed_pages = [] of Models::Page
          affected_sections = Set(String).new
          old_taxonomies_snapshot = {} of String => Hash(String, Array(String))
          old_series_names = {} of String => String?

          # Build O(1) lookup map for changed file matching
          pages_map = @pages_by_path || build_pages_by_path(site)

          # Snapshot old neighbors before re-linking (for render set)
          old_neighbors = {} of String => {Models::Page?, Models::Page?}

          # Cascade context for re-applying section defaults to re-parsed pages
          # (parse_single_page resets fields from front matter only). Prefer
          # the cold build's pre-filter map: it still contains cascades from
          # draft/expired _index sections that site.sections no longer holds.
          cascade_map = @cascade_map || build_cascade_map(site.sections)

          changed_content_files.each do |file|
            relative_path = path_relative_to(file, "content")

            page = pages_map[relative_path]?
            unless page
              # A section _index that isn't in the site model (e.g. its own
              # front matter says draft = true) can still cascade to its
              # descendants — an edit to it is untrackable incrementally.
              if File.basename(relative_path).starts_with?("_index.")
                Logger.info "  Changed #{relative_path} is not in the site model — running full rebuild."
                return run(options)
              end
              next
            end

            # Snapshot before re-parse (includes property-backed taxonomies
            # like authors — see snapshot_page_taxonomies)
            old_taxonomies_snapshot[page.path] = snapshot_page_taxonomies(page, site)
            old_series_names[page.path] = page.series
            old_neighbors[page.path] = {page.lower, page.higher}
            old_cascade = page.is_a?(Models::Section) ? page.cascade : nil

            # Re-read, re-parse front-matter and recalculate URL
            parse_single_page(page)
            page.generate_permalink(config.base_url)
            # Content (shortcode usage) or front-matter template may have changed
            @page_template_hash_mutex.synchronize { @page_template_hash_memo.delete(page.path) }

            # A changed [cascade] affects descendant pages that are NOT in the
            # changed set — incremental bookkeeping can't reach them, so
            # escalate to a full rebuild (rare event, correctness first).
            if (previous_cascade = old_cascade) && page.is_a?(Models::Section) && page.cascade != previous_cascade
              Logger.info "  Section cascade changed in #{page.path} — running full rebuild."
              return run(options)
            end

            apply_cascade_to(page, cascade_map)

            changed_pages << page
            affected_sections << page.section
            # Also include ancestor sections that may list this page
            page.ancestors.each { |ancestor| affected_sections << ancestor.section }
          end

          if changed_pages.empty?
            Logger.info "  No matching pages found – skipping."
            return
          end

          # --- 2. Incrementally update relationships ---
          # Run taxonomy update on ALL re-parsed pages first (including those about
          # to be excluded), so excluded pages' old entries are properly removed.
          update_taxonomies_incremental(site, changed_pages, old_taxonomies_snapshot)

          # Now identify pages that should be excluded (draft/expired/future)
          excluded_pages = [] of Models::Page
          now = Time.utc
          unless include_drafts
            excluded = changed_pages.select(&.draft)
            excluded_pages.concat(excluded)
            changed_pages.reject!(&.draft)
          end
          unless options.include_expired
            expired = changed_pages.select { |p| p.expires.try { |e| e <= now } || false }
            excluded_pages.concat(expired)
            changed_pages.reject! { |p| p.expires.try { |e| e <= now } || false }
          end
          unless options.include_future
            future = changed_pages.select { |p| p.date.try { |d| d > now } || false }
            excluded_pages.concat(future)
            changed_pages.reject! { |p| p.date.try { |d| d > now } || false }
          end

          # Remove excluded pages from site indices and delete stale output files
          unless excluded_pages.empty?
            excluded_paths = excluded_pages.map(&.path).to_set
            site.pages.reject! { |p| excluded_paths.includes?(p.path) }
            site.sections.reject! { |p| excluded_paths.includes?(p.path) }
            excluded_pages.each do |p|
              stale_output = get_output_path(p, output_dir)
              File.delete(stale_output) if File.exists?(stale_output)
            end
          end

          all_pages = (site.pages + site.sections).as(Array(Models::Page))

          # Rebuild lookup index (page data may have changed)
          site.build_lookup_index

          # Re-link the global reading order; `renav_pages` is every page whose
          # prev/next pointer actually changed (a section weight/sort/reverse edit
          # reorders a whole block, not just the edited page's neighbors).
          renav_pages = relink_navigation_for_sections(site, affected_sections)

          # Recompute series for affected series (if enabled), including old memberships
          affected_series = if site.config.series.enabled
                              recompute_series_for_pages(site, changed_pages, old_series_names)
                            else
                              Set(String).new
                            end

          # Recompute related posts selectively (if enabled). Pass the excluded
          # pages' paths so pages that listed a now-removed page as related drop it.
          excluded_related_paths = excluded_pages.map(&.path).to_set
          related_pages_updated = recompute_related_posts_for_pages(site, changed_pages, excluded_related_paths)

          # Invalidate Crinja caches for affected pages/sections
          invalidate_caches_for_pages(changed_pages, affected_sections)
          @crinja_cache_mutex.synchronize do
            affected_series.each { |s| @series_crinja_cache.delete(s) }
            related_pages_updated.each { |path| @related_posts_crinja_cache.delete(path) }

            # A changed SECTION's title/url is embedded in every descendant's
            # breadcrumb, which is served from @ancestors_crinja_cache keyed
            # "section:language". affected_sections only covers the section itself
            # and its UPWARD ancestors, so drop the whole DESCENDANT subtree
            # ("sec:..." and "sec/...") too, or re-rendered descendants would read
            # a cached ancestors array still carrying the old title/url.
            changed_pages.each do |page|
              next unless page.is_a?(Models::Section)
              sec = page.section
              @ancestors_crinja_cache.reject! { |k, _| k.starts_with?("#{sec}:") || k.starts_with?("#{sec}/") }
            end
          end

          # --- 3. Determine the full set of pages that need re-rendering ---
          pages_to_render = Set(Models::Page).new(changed_pages)

          # Section index pages whose content lists include the changed pages.
          # Include every language variant of the section (multilingual sites
          # have one `_index.<lang>.md` per language under the same path).
          affected_sections.each do |section_name|
            site.sections.each do |section|
              pages_to_render << section if section.section == section_name
            end
          end

          # When a SECTION `_index` itself changed, its own title/url can appear
          # in every descendant page's breadcrumb (page.ancestors) and its sort
          # settings reorder the section's listings — so re-render the whole
          # subtree. Cover BOTH descendant content pages (site.pages) AND nested
          # section index pages (site.sections — `_index.md` files never live in
          # site.pages), or a nested subsection's breadcrumb stays stale. Bounded
          # by the edited section's size, and only triggered by the rarer section
          # edits.
          changed_pages.each do |page|
            next unless page.is_a?(Models::Section)
            sec = page.section
            prefix = "#{sec}/"
            site.pages.each do |p|
              pages_to_render << p if p.section == sec || p.section.starts_with?(prefix)
            end
            site.sections.each do |s|
              pages_to_render << s if s.section == sec || s.section.starts_with?(prefix)
            end
          end

          # Previous / next pages. `renav_pages` is every page whose lower/higher
          # pointer changed in the global re-link (covers block reorders from a
          # section weight/sort/reverse edit); the explicit old/new neighbors of
          # each changed page are a subset but kept for clarity.
          renav_pages.each { |p| pages_to_render << p }
          changed_pages.each do |page|
            # New neighbors (after re-link)
            page.lower.try { |l| pages_to_render << l }
            page.higher.try { |h| pages_to_render << h }

            # Old neighbors (before re-link, may have shifted)
            if old = old_neighbors[page.path]?
              old[0].try { |l| pages_to_render << l }
              old[1].try { |h| pages_to_render << h }
            end
          end

          # Pages in affected series (their series_index may have changed)
          unless affected_series.empty?
            site.pages.each do |p|
              pages_to_render << p if p.series && affected_series.includes?(p.series)
            end
          end

          # Pages whose related_posts were recomputed
          related_pages_updated.each do |path|
            if p = pages_map[path]?
              pages_to_render << p
            end
          end

          # KNOWN LIMITATION (serve preview only): a page that renders ANOTHER
          # section's listing via `get_section(X).pages` or a global `site.pages`
          # widget (e.g. a sidebar "recent posts") is NOT re-rendered when a page
          # in X changes, so its on-disk HTML can show a stale list until that
          # page is itself touched. Bounding this would require tracking which
          # pages reference which section lists; a full `hwaro build` is always
          # correct, so this is left as a documented preview-mode gap.

          render_list = pages_to_render.to_a

          # --- 4. Re-render the affected pages ---
          global_vars = build_global_vars(site, options.cache_busting)
          @pages_by_path = build_pages_by_path(site)
          cache = @cache || Cache.new(enabled: false)

          # Render in parallel like run_rerender/the cold build — a section
          # `_index` edit re-renders its whole subtree, and doing that one
          # page at a time made large-section edits the slowest watch path.
          # process_files_sequential mirrors the old per-page loop exactly
          # (render_page + record_page_cache_entry).
          error_overlay = options.error_overlay
          renderable_list = render_list.select(&.render)
          if options.parallel && renderable_list.size > 1
            process_files_parallel(renderable_list, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: error_overlay, profiler: active_profiler)
          else
            process_files_sequential(renderable_list, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: error_overlay, profiler: active_profiler)
          end

          cache.save if options.cache

          # --- 5. Regenerate taxonomy index/term pages ---
          # Merge the generated taxonomy pages into the page set the SEO
          # generators read so taxonomy.sitemap/feed take effect on incremental
          # rebuilds too (mirrors the lifecycle taxonomy hook). `all_pages` is
          # left intact for the rebuild summary below.
          taxonomy_sections = Content::Taxonomies.generate(site, output_dir, templates, verbose, builder: self)
          seo_pages = taxonomy_sections.empty? ? all_pages : all_pages + taxonomy_sections

          # --- 6. Regenerate lightweight SEO / search files in parallel ---
          regenerate_seo_surfaces(seo_pages, site, output_dir, verbose, options.parallel, include_robots: true)

          elapsed = Time.instant - start_time
          Logger.outcome("rebuilt", "#{render_list.size} / #{all_pages.size} pages", :result, elapsed.total_milliseconds)
          report_cache_stats(options.verbose)
        end

        # Incremental parse of changed content + full re-render with reloaded templates.
        # Used when both content and templates changed simultaneously.
        def run_incremental_then_rerender(changed_content_files : Array(String), options : Config::Options::BuildOptions)
          @render_workers = options.workers
          config = @config
          site = @site

          unless config && site
            return run(options)
          end

          Logger.info "Re-parsing #{changed_content_files.size} changed file(s) before full re-render..."

          pages_map = @pages_by_path || build_pages_by_path(site)
          changed_pages = [] of Models::Page
          affected_sections = Set(String).new
          old_taxonomies_snapshot = {} of String => Hash(String, Array(String))
          old_series_names = {} of String => String?

          # Same cascade context as run_incremental — re-parsed pages must
          # get their inherited section defaults back before rendering.
          cascade_map = @cascade_map || build_cascade_map(site.sections)

          changed_content_files.each do |file|
            relative_path = path_relative_to(file, "content")

            page = pages_map[relative_path]?
            unless page
              # See run_incremental: an excluded section's _index can still
              # cascade to descendants — escalate rather than miss it.
              if File.basename(relative_path).starts_with?("_index.")
                Logger.info "  Changed #{relative_path} is not in the site model — running full rebuild."
                return run(options)
              end
              next
            end

            # Snapshot before re-parse (includes property-backed taxonomies
            # like authors — see snapshot_page_taxonomies)
            old_taxonomies_snapshot[page.path] = snapshot_page_taxonomies(page, site)
            old_series_names[page.path] = page.series
            old_cascade = page.is_a?(Models::Section) ? page.cascade : nil

            parse_single_page(page)
            page.generate_permalink(config.base_url)
            @page_template_hash_mutex.synchronize { @page_template_hash_memo.delete(page.path) }

            # A changed [cascade] affects descendants outside the changed set
            # — escalate to a full rebuild, mirroring run_incremental.
            if (previous_cascade = old_cascade) && page.is_a?(Models::Section) && page.cascade != previous_cascade
              Logger.info "  Section cascade changed in #{page.path} — running full rebuild."
              return run(options)
            end

            apply_cascade_to(page, cascade_map)

            changed_pages << page
            affected_sections << page.section
            page.ancestors.each { |ancestor| affected_sections << ancestor.section }
          end

          # Update all derived relationships before full re-render
          update_taxonomies_incremental(site, changed_pages, old_taxonomies_snapshot)
          site.build_lookup_index
          relink_navigation_for_sections(site, affected_sections)
          recompute_series_for_pages(site, changed_pages, old_series_names) if site.config.series.enabled
          recompute_related_posts_for_pages(site, changed_pages) if site.config.related.enabled

          # Re-render with reloaded templates. The selective path inside
          # run_rerender only covers template-affected pages, so the content
          # pages re-parsed above must be forced into the render set.
          run_rerender(options, force_pages: changed_pages)
        end

        # Re-render pages using reloaded templates without re-parsing content.
        # Useful when only template files have been modified. With template
        # dependency tracking active, only the pages whose template closure
        # includes an edited template are re-rendered; otherwise (tracking
        # off, a dynamic include in the graph, or templates added/removed)
        # every page re-renders as before.
        #
        # `force_pages` are rendered regardless of template impact — callers
        # that re-parsed content (run_incremental_then_rerender) pass them so
        # the selective path can't skip a content-changed page. Their taxonomy
        # membership may have changed too, so taxonomy pages regenerate
        # whenever force_pages are present.
        def run_rerender(options : Config::Options::BuildOptions, force_pages : Array(Models::Page)? = nil)
          @render_workers = options.workers
          config = @config
          site = @site

          unless config && site
            return run(options)
          end

          start_time = Time.instant

          # Reload templates from disk & reset all runtime caches.
          # Keep the old sources so the dependency graph can diff them.
          old_templates = @templates
          @templates = nil
          @cache_manager.clear_runtime
          templates = load_templates
          @templates = templates

          # Refresh invalidation mode for the reloaded template set
          deps = @template_deps
          @global_templates_hash = Cache.compute_templates_hash(templates)
          @per_page_template_hash = config.build.template_deps &&
                                    (deps.try { |d| !d.dynamic? } || false)

          output_dir = options.output_dir
          minify = options.minify
          highlight = options.highlight && site.config.highlight.enabled
          verbose = options.verbose

          all_pages = (site.pages + site.sections).as(Array(Models::Page))
          renderable_pages = all_pages.select(&.render)

          # Selective re-render: same template set, fully static graph
          affected_templates : Set(String)? = nil
          if @per_page_template_hash && deps && old_templates &&
             old_templates.keys.sort! == templates.keys.sort!
            changed = Set(String).new
            templates.each do |name, source|
              changed << name if old_templates[name]? != source
            end
            if changed.empty? && (force_pages.nil? || force_pages.empty?)
              Logger.info "Template change detected, but contents are identical — nothing to re-render."
              return
            end
            if changed.any?(&.starts_with?("hooks/"))
              # Hook templates aren't in the {% include %}/{% extends %}
              # dependency graph (they're invoked from Markdown rendering,
              # not template rendering) — dependents_closure has no way to
              # know which pages a hook change affects, so fall back to a
              # full re-render.
              affected_templates = nil
            else
              affected_templates = deps.dependents_closure(changed)
            end
            Logger.info "Template change detected (#{changed.join(", ")}). Re-rendering affected pages..." if options.verbose && !changed.empty?
          else
            Logger.info "Template change detected. Re-rendering all pages..." if options.verbose
          end

          pages_to_render = if affected_templates && deps
                              selected = renderable_pages.select do |page|
                                entry = determine_template(page, templates, site)
                                affected_templates.includes?(entry) ||
                                  deps.shortcodes_used_in(page.raw_content).any? { |sc| affected_templates.includes?(sc) }
                              end
                              if forced = force_pages
                                seen = selected.map(&.path).to_set
                                forced.each do |page|
                                  selected << page if page.render && !seen.includes?(page.path)
                                end
                              end
                              selected
                            else
                              renderable_pages
                            end

          if options.verbose && affected_templates && pages_to_render.size < renderable_pages.size
            Logger.info "  #{pages_to_render.size} of #{renderable_pages.size} pages affected."
          end

          global_vars = build_global_vars(site, options.cache_busting)
          @pages_by_path = build_pages_by_path(site)
          cache = @cache || Cache.new(enabled: false)

          error_overlay = options.error_overlay
          count = if pages_to_render.empty?
                    0
                  elsif options.parallel && pages_to_render.size > 1
                    process_files_parallel(pages_to_render, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: error_overlay, profiler: active_profiler)
                  else
                    process_files_sequential(pages_to_render, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: error_overlay, profiler: active_profiler)
                  end

          # Re-generate 404 page with new template
          if affected_templates.nil? || affected_templates.includes?("404")
            generate_404_page(site, templates, output_dir, minify, verbose, global_vars)
          end

          # Re-generate taxonomy pages with new templates. Their template
          # resolution falls back taxonomy_term -> taxonomy -> page, so any
          # of those being affected triggers the regeneration. Forced content
          # pages may have changed taxonomy membership — regenerate then too.
          if affected_templates.nil? ||
             (force_pages && !force_pages.empty?) ||
             ["taxonomy", "taxonomy_term", "page"].any? { |name| affected_templates.includes?(name) }
            Content::Taxonomies.generate(site, output_dir, templates, verbose, builder: self)
          end

          cache.save if options.cache

          elapsed = Time.instant - start_time
          Logger.outcome("rebuilt", "#{count} pages · re-render", :result, elapsed.total_milliseconds)
          report_cache_stats(verbose)
        end

        # Are there any pages stashed by `--fast-start` waiting to render?
        # Server checks this to decide whether to spawn the background fiber.
        def has_deferred_pages? : Bool
          if pages = @deferred_pages
            !pages.empty?
          else
            false
          end
        end

        # Render pages that were skipped on the initial `--fast-start` build.
        # Runs after the dev server is already serving the priority subset,
        # so user-visible "ready" time stays bounded on large sites.
        # Regenerates SEO/search files at the end since feeds and the search
        # index pull from `page.content`, which was empty for deferred pages
        # during the initial Generate phase.
        #
        # Also runs the BeforeRender hooks for the remaining work the
        # cold pass deferred — OG image generation for non-priority pages
        # and image resizing for static/content_file globs + non-priority
        # page assets. Without this step those images never get produced
        # in a fast-start serve session until the user saves a file.
        def render_deferred(options : Config::Options::BuildOptions) : Int32
          @render_workers = options.workers
          pages = @deferred_pages
          return 0 if pages.nil? || pages.empty?

          site = @site
          templates = @templates
          unless site && templates
            Logger.warn "render_deferred called before initial build completed; skipping."
            return 0
          end

          Logger.info "Fast-start: background-rendering #{pages.size} deferred page(s)..."
          start_time = Time.instant

          output_dir = options.output_dir
          minify = options.minify
          highlight = options.highlight && site.config.highlight.enabled
          verbose = options.verbose
          cache = @cache || Cache.new(enabled: false)

          # Re-run the BeforeRender hooks against the full page set. The
          # ctx carries no priority_pages this time, so OG image
          # generation and image resizing process whatever the cold pass
          # left undone. We construct a fresh context rather than reusing
          # the original — the original's priority_pages would short-
          # circuit the very hooks we want to fully execute here.
          deferred_ctx = Lifecycle::BuildContext.new(options)
          deferred_ctx.site = site
          deferred_ctx.config = site.config
          deferred_ctx.pages = site.pages
          deferred_ctx.sections = site.sections
          deferred_ctx.templates = templates
          deferred_ctx.output_dir = output_dir
          deferred_ctx.cache = @cache
          deferred_ctx.priority_pages = nil
          deferred_ctx.profiler = @profiler if @profiler.try(&.enabled?)
          # Still a partial pass — the priority pass just wrote OG
          # manifest entries we must not truncate. Without this flag the
          # deferred pass would overwrite `.og_manifest.json` with only
          # its own slugs and the next cold start would re-render every
          # priority page's OG image from scratch.
          deferred_ctx.partial_render = true

          # Trigger BeforeRender hooks directly — we're not re-running the
          # Render phase, just the prep work it would have done.
          @lifecycle.trigger(Lifecycle::HookPoint::BeforeRender, deferred_ctx)

          global_vars = build_global_vars(site, options.cache_busting)
          @pages_by_path = build_pages_by_path(site)
          renderable = pages.select(&.render)

          count = if options.parallel && renderable.size > 1
                    process_files_parallel(renderable, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: options.error_overlay, profiler: active_profiler)
                  else
                    process_files_sequential(renderable, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: options.error_overlay, profiler: active_profiler)
                  end

          # Refresh feeds / sitemap / search now that every page has rendered
          # content. Without this, feed descriptions and the search index
          # only cover the priority subset. Per-taxonomy RSS feeds and tag
          # listing pages pull from `page.content` too, so they have to be
          # regenerated for the same reason — matches `run_rerender`.
          # Regenerate taxonomy pages BEFORE the SEO surfaces and merge them
          # into the page set. Previously taxonomy generation ran after the
          # sitemap, so its pages never appeared in it (taxonomy.sitemap/feed
          # had no effect on this deferred pass).
          taxonomy_sections = Content::Taxonomies.generate(site, output_dir, templates, verbose, builder: self)
          all_pages = (site.pages + site.sections + taxonomy_sections).as(Array(Models::Page))
          regenerate_seo_surfaces(all_pages, site, output_dir, verbose, options.parallel)

          # Persist cache updates from the deferred pass. The initial build
          # already saved once; without this second save, killing the server
          # before any watch rebuild loses the deferred pages' cache entries
          # and the next `--cache` cold start has to re-render them.
          cache.save if options.cache

          # Clear the stash so a second call is a no-op and subsequent
          # watch-triggered full rebuilds start clean.
          @deferred_pages = nil

          elapsed = Time.instant - start_time
          Logger.outcome("rendered", "#{count} deferred pages", :result, elapsed.total_milliseconds)
          count
        end

        # Copy only the specified static files to the output directory.
        # Used by serve mode when only static files have changed.
        def copy_changed_static(changed_files : Array(String), output_dir : String, verbose : Bool = false)
          static_config = static_publish_config
          copied = 0
          changed_files.each do |src_path|
            next unless File.exists?(src_path)
            next if File.directory?(src_path)

            relative = path_relative_to(src_path, "static")
            next if static_config.excluded?(relative)
            dest_path = File.join(output_dir, relative)

            Hwaro::Utils::FileSafe.mkdir_p(File.dirname(dest_path))
            FileUtils.cp(src_path, dest_path)
            copied += 1
          end
          Logger.outcome("copied", "#{copied} static #{copied == 1 ? "file" : "files"}") if copied > 0
        end

        # Republish non-Markdown content assets (images, etc.) to the output
        # directory, preserving their path relative to `content/`. Mirrors what
        # the full build does via the raw-files path in the Write phase, but
        # only touches the files the watcher actually flagged as changed.
        #
        # Skips files whose extension isn't permitted by `[content.files]`, so
        # the watcher can't smuggle a `.md` or a disallowed type into output.
        # No-ops when `[content.files]` isn't enabled — nothing was published
        # in the first place, so there's nothing to refresh. (`@config` is nil
        # only before the initial build, which `Server#run_with_options`
        # already performs before spawning the watcher, so the watcher always
        # sees a loaded config.)
        def copy_changed_content_files(changed_files : Array(String), output_dir : String, verbose : Bool = false)
          config = @config
          unless config && config.content_files.enabled?
            Logger.debug "  Content-file republish skipped — content.files not enabled."
            return
          end

          copied = 0
          changed_files.each do |src_path|
            next unless File.exists?(src_path)
            next if File.directory?(src_path)

            relative = path_relative_to(src_path, "content")

            next unless config.content_files.publish?(relative)

            dest_path = File.join(output_dir, relative)
            unless Utils::OutputGuard.within_output_dir?(dest_path, output_dir)
              Logger.warn "Skipping content file outside output directory: #{relative}"
              next
            end

            Hwaro::Utils::FileSafe.mkdir_p(File.dirname(dest_path))
            FileUtils.cp(src_path, dest_path)
            Logger.action :copy, dest_path, Logger::Role::Dim if verbose
            copied += 1
          end
          Logger.outcome("copied", "#{copied} content #{copied == 1 ? "file" : "files"}") if copied > 0
        end

        # Map source paths that were removed from disk to the output files
        # they produced in the last build. A rebuild rewrites surviving pages
        # but never deletes what's gone, so the serve watcher captures this
        # BEFORE rebuilding (while @site still knows the page's URL/slug) and
        # removes the orphans after — otherwise a deleted page keeps serving
        # 200 and ships with the next deploy of `public/`.
        def stale_outputs_for_removed(removed_paths : Array(String), output_dir : String) : Array(String)
          outputs = [] of String
          site = @site
          removed_paths.each do |path|
            if path.starts_with?("static/")
              dest = File.join(output_dir, path.lchop("static/"))
              outputs << dest if Utils::OutputGuard.within_output_dir?(dest, output_dir)
            elsif path.starts_with?("content/")
              if path.downcase.ends_with?(".md")
                next unless site
                rel = path.lchop("content/")
                if page = site.pages.find { |p| p.path == rel }
                  outputs << get_output_path(page, output_dir)
                end
              else
                dest = File.join(output_dir, path.lchop("content/"))
                outputs << dest if Utils::OutputGuard.within_output_dir?(dest, output_dir)
              end
            end
          end
          outputs
        end

        def run(
          output_dir : String = "public",
          base_url : String? = nil,
          drafts : Bool = false,
          include_expired : Bool = false,
          include_future : Bool = false,
          minify : Bool = false,
          parallel : Bool = true,
          cache : Bool = false,
          full : Bool = false,
          highlight : Bool = true,
          verbose : Bool = false,
          profile : Bool = false,
          debug : Bool = false,
          error_overlay : Bool = false,
          stream : Bool = false,
          memory_limit : String? = nil,
          env : String? = nil,
          fast_start : Bool = false,
          fast_start_count : Int32 = 20,
          skip_og_image : Bool = false,
          skip_image_processing : Bool = false,
          preserve_output : Bool = false,
          cache_busting : Bool = true,
        )
          # Load config once and reuse throughout the build.
          # `Models::Config.load` raises `HwaroError(HWARO_E_CONFIG)` directly
          # for missing files and TOML parse failures, so callers (and
          # `--json` consumers) can branch on HWARO_E_CONFIG without the
          # build pipeline rewrapping the exception.
          config = Models::Config.load(env: env)
          @config = config
          pre_hooks = config.build.hooks.pre
          post_hooks = config.build.hooks.post

          # Run pre-build hooks
          unless pre_hooks.empty?
            unless Utils::CommandRunner.run_pre_hooks(pre_hooks)
              Logger.error "Build aborted due to pre-build hook failure."
              return
            end
          end

          # The build runs quietly; its story is told by the closing receipt
          # (and, under -Dpreview_mt TTY, the live status line in Phase 3).
          start_time = Time.instant

          # Initialize profiler
          profiler = Profiler.new(enabled: profile)
          @profiler = profiler
          profiler.start

          # Create build context for lifecycle
          options = Config::Options::BuildOptions.new(
            output_dir: output_dir,
            base_url: base_url,
            drafts: drafts,
            include_expired: include_expired,
            include_future: include_future,
            minify: minify,
            parallel: parallel,
            cache: cache,
            full: full,
            highlight: highlight,
            verbose: verbose,
            profile: profile,
            debug: debug,
            error_overlay: error_overlay,
            stream: stream,
            memory_limit: memory_limit,
            env: env,
            fast_start: fast_start,
            fast_start_count: fast_start_count,
            skip_og_image: skip_og_image,
            skip_image_processing: skip_image_processing,
            preserve_output: preserve_output,
            cache_busting: cache_busting,
          )
          if options.streaming?
            Logger.info "  Streaming mode enabled (batch size: #{options.batch_size})"
          end

          ctx = Lifecycle::BuildContext.new(options)
          ctx.stats.start_time = Time.instant
          ctx.profiler = profiler if profiler.enabled?
          ctx.builder = self
          @context = ctx

          # Reset internal caches (preserve @config loaded above)
          @site = nil
          @templates = nil
          @cache_manager.clear_runtime
          @created_dirs.clear

          # Execute build phases through lifecycle. The live status region
          # animates the current phase on a TTY; `ensure` guarantees the
          # spinner is torn down (and its line cleared) on every exit path
          # before the receipt prints.
          Logger.status_start(verbose: options.verbose)
          begin
            result = execute_phases(ctx, profiler)
          ensure
            Logger.status_finish
          end

          ctx.stats.end_time = Time.instant

          if result == Lifecycle::HookResult::Abort
            Logger.error "Build failed!"
            return
          end

          elapsed = Time.instant - start_time
          raw_msg = ctx.stats.raw_files_processed > 0 ? " + #{ctx.stats.raw_files_processed} raw files" : ""
          # "content pages" rather than just "pages" — taxonomy/archive/section
          # index files are also written to disk, so a bare "N pages" count
          # misleads users who diff this number against `find public -name '*.html'`.
          emit_build_receipt(ctx, raw_msg, elapsed.total_milliseconds, profiler)
          # Only warn about an empty site when nothing was built at all. Under
          # `--cache`, unchanged pages are skipped (counted as `cache_hits`)
          # rather than re-rendered, so `pages_rendered` is 0 on a no-op rebuild
          # even though the site is full — guarding on `cache_hits == 0` keeps
          # the hint from misfiring on every cached rebuild.
          if ctx.stats.pages_rendered == 0 && ctx.stats.cache_hits == 0 && ctx.stats.raw_files_processed == 0
            Logger.info "No content found. Add Markdown files under content/ before deploying, or run `hwaro new <path>.md` to scaffold one."
          end

          # Print profiling report if enabled
          profiler.report
          profiler.template_report
          profiler.markdown_report
          profiler.asset_report
          profiler.hook_report

          # Print cache stats
          report_cache_stats(options.verbose)

          # Run post-build hooks
          unless post_hooks.empty?
            unless Utils::CommandRunner.run_post_hooks(post_hooks)
              Logger.warn "Post-build hooks failed, but build was successful."
            end
          end

          if options.debug
            if debug_site = @site
              Utils::DebugPrinter.print(debug_site)
            end
          end
        end

        # Resolve `path` relative to `root`, falling back to a plain prefix
        # strip when it can't be made relative (e.g. an absolute path).
        private def path_relative_to(path : String, root : String) : String
          Path[path].relative_to(root).to_s
        rescue ArgumentError
          path.lchop("#{root}/")
        end

        # Regenerate the lightweight SEO/search surfaces (sitemap, feeds, llms,
        # search index, optionally robots) for the given page set. Each
        # generator writes a distinct output file with no shared in-process
        # state, so task order doesn't affect output.
        #
        # `raise_on_error: false`: these are the serve-time passes (watch
        # incremental, fast-start deferred). A transient generator failure
        # must warn-and-continue here — raising would skip cache.save, the
        # deferred-pages cleanup, and the live-reload signal even though
        # every page rendered fine. The cold-build Generate phase keeps the
        # fail-loud default via its own ParallelHelper.execute call.
        private def regenerate_seo_surfaces(pages : Array(Models::Page), site : Models::Site, output_dir : String, verbose : Bool, parallel : Bool, include_robots : Bool = false)
          seo_tasks = [
            -> { Content::Seo::Sitemap.generate(pages, site, output_dir, verbose); nil },
            -> { Content::Seo::Feeds.generate(pages, site.config, output_dir, verbose); nil },
          ] of Proc(Nil)
          # Robots slots in right after Feeds — its original position in the
          # incremental path — so sequential (--no-parallel) output ordering is
          # preserved, not just the generated files.
          seo_tasks << -> { Content::Seo::Robots.generate(site.config, output_dir, verbose); nil } if include_robots
          seo_tasks << -> { Content::Seo::Llms.generate(site.config, pages, output_dir, verbose); nil }
          seo_tasks << -> { Content::Search.generate(pages, site.config, output_dir, verbose); nil }
          ParallelHelper.execute(seo_tasks, parallel, raise_on_error: false)
        end

        # Emit the end-of-build cache statistics at the requested verbosity.
        private def report_cache_stats(verbose : Bool)
          verbose ? @cache_manager.report_verbose : @cache_manager.report
        end

        # Selectively invalidate Crinja caches for changed pages and affected sections.
        # Fixes stale cache entries during incremental builds.
        private def invalidate_caches_for_pages(
          changed_pages : Array(Models::Page),
          affected_sections : Set(String),
        )
          @crinja_cache_mutex.synchronize do
            changed_pages.each do |page|
              @page_crinja_value_cache.delete(page.path)
              @related_posts_crinja_cache.delete(page.path)

              if series_name = page.series
                @series_crinja_cache.delete(series_name)
              end

              # Neighbors' cached values reference this page
              page.lower.try { |l| @page_crinja_value_cache.delete(l.path) }
              page.higher.try { |h| @page_crinja_value_cache.delete(h.path) }
            end

            affected_sections.each do |section_name|
              # Keyed by "section:language" now (see build_template_variables), so
              # drop every language's entry for the section, like section_pages.
              @ancestors_crinja_cache.reject! { |k, _| k.starts_with?("#{section_name}:") }
              @section_pages_crinja_cache.reject! { |k, _| k.starts_with?("#{section_name}:") }
              @section_pages_url_index_cache.reject! { |k, _| k.starts_with?("#{section_name}:") }
              @section_assets_crinja_cache.delete(section_name)
            end
          end
        end

        # Emit the calm closing receipt: an aligned per-phase summary plus the
        # one ember "built" outcome line. Rows are skipped when their value is
        # empty, so cached/no-op rebuilds stay terse. Falls back to plain
        # "label: value" lines (no color, no rule) when color is off. Each row
        # carries its phase timing as a TTY-only dim detail so slow phases are
        # visible at a glance without `--profile`.
        private def emit_build_receipt(ctx : Lifecycle::BuildContext, raw_msg : String, elapsed_ms : Float64, profiler : Profiler)
          stats = ctx.stats
          receipt = Logger::Receipt.new("build")
          receipt.row("read", stats.pages_read > 0 ? "#{stats.pages_read} content files" : "",
            detail: phase_detail(profiler, "ReadContent"))
          parsed = stats.pages_read - stats.pages_skipped
          receipt.row("parse", parsed > 0 ? "#{parsed} pages" : "",
            emphasis: stats.pages_skipped > 0 ? "#{stats.pages_skipped} skipped" : nil,
            detail: phase_detail(profiler, "ParseContent"))
          render_val =
            if stats.cache_hits > 0
              "#{stats.pages_rendered} pages · #{stats.cache_hits} cached"
            else
              "#{stats.pages_rendered} pages"
            end
          receipt.row("render", render_val, detail: phase_detail(profiler, "Render"))
          receipt.row("write", stats.raw_files_processed > 0 ? "#{stats.raw_files_processed} raw files" : "",
            detail: phase_detail(profiler, "Write"))
          receipt.outcome("built", "#{stats.pages_rendered} content pages#{raw_msg}", :result, elapsed_ms)
          receipt.emit
        end

        # A receipt row's dim timing note. Sub-millisecond phases return `nil`
        # so trivial builds don't sprout four "0ms" notes.
        private def phase_detail(profiler : Profiler, phase : String) : String?
          ms = profiler.phase_ms(phase)
          ms && ms >= 1.0 ? Logger.dur(ms) : nil
        end

        # Execute all build phases with lifecycle hooks
        private def execute_phases(
          ctx : Lifecycle::BuildContext,
          profiler : Profiler,
        ) : Lifecycle::HookResult
          # Phase: Initialize
          result = execute_initialize_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: ReadContent
          result = execute_read_content_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: ParseContent
          result = execute_parse_content_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Transform
          result = execute_transform_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Render
          result = execute_render_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Generate
          result = execute_generate_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          if ctx.options.streaming?
            ctx.all_pages.each(&.raw_content=(""))
            GC.collect
          end

          # Phase: Write
          result = execute_write_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Finalize
          execute_finalize_phase(ctx, profiler)
        end
      end
    end
  end
end
