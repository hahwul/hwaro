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
require "./data_disk"
require "./remote_data"
require "./content_generate"
require "./template_deps"
require "./template_loader"
require "./shortcode_processor"
require "./phases/initialize"
require "./phases/read_content"
require "./phases/parse_content"
require "./phases/transform"
require "./phases/render"
require "./phases/output_formats"
require "./phases/generate"
require "./phases/write"
require "./phases/finalize"
require "../../assets/pipeline"
require "../../content/hooks/asset_hooks"
require "../../content/seo/feeds"
require "../../content/seo/sitemap"
require "../../content/seo/robots"
require "../../content/seo/llms"
require "../../content/seo/tags"
require "../../content/seo/jsonld"
require "../../content/seo/pwa"
require "../../content/seo/og_image"
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
require "../../content/versions"
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

require "./builder/incremental"
require "./builder/serve_sync"
require "./builder/seo_surfaces"

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
        include Phases::OutputFormats
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
        # Content hashes of extension-shadowed template files (foo.j2 while
        # foo.html holds the "foo" slot), keyed by source path. Renders can
        # reach these by explicit name through the loader's disk fallback,
        # so run_rerender must treat their edits as template changes even
        # though the snapshot hash itself is unchanged.
        @shadowed_template_hashes : Hash(String, String) = {} of String => String
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
        # Digest of the fetched [[data.remote]] payloads for this build,
        # folded into compute_data_hash so a changed payload invalidates
        # cached pages like an edited data/ file. "" when no remote sources
        # are configured (keeps cache keys byte-identical to pre-feature).
        @remote_data_digest : String = ""
        # `[git]` commit metadata keyed by content-relative path, collected
        # ONCE per full build in the Initialize phase (see GitInfo.collect)
        # and read by parse_single_page — including the serve incremental
        # re-parse, which deliberately reuses the last full build's map
        # rather than shelling out to git on every keystroke. Nil when the
        # feature is off or history is unavailable.
        @git_info : Hash(String, Models::GitInfo)? = nil
        # Per-SERVE-SESSION memo of fetched [[data.remote]] payloads. The
        # dev server holds one Builder for the whole session, so this lives
        # exactly as long as `hwaro serve` does; `hwaro build` is one process
        # per build and never populates it, which is why build semantics are
        # untouched.
        #
        # Without it every full rebuild refetched every source synchronously:
        # editing a paragraph offline failed the rebuild, and the default
        # (no `cache`) entry re-hit the network on every unrelated save.
        # Keyed by {entry key, url digest} — not the url itself, which can
        # carry a credential in its query string — so editing either in
        # config.toml misses the memo and refetches, exactly like the disk
        # cache.
        @remote_data_memo : Hash({String, String}, {RemoteData::Result, Time}) = {} of {String, String} => {RemoteData::Result, Time}
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
        # Crinja-owned regions (raw blocks, macro invocations) masked out of a
        # template source, keyed by that source's hash. Masking is a pure
        # function of the string but used to run once per rendered PAGE; like
        # the scan above it is populated once in load_templates and read-only
        # during render. Also the only place a macro inherited through
        # `{% extends %}` can be seen, since that needs the whole template set.
        @template_literal_masks : Hash(UInt64, {String, Array(String)}) = {} of UInt64 => {String, Array(String)}
        # Which expensive per-page template variables a template's static
        # closure can actually reach. build_template_variables skips building
        # the ones it provably can't (SEO/OG strings, JSON-LD strings, the
        # per-page section-pages array copy — O(section size) per page).
        # Detection is substring-based over the closure's source union, so it
        # only ever over-approximates: any occurrence of the identifier keeps
        # the variable. A template is only gated when its whole closure is
        # statically resolvable AND it cannot contain shortcodes (template
        # shortcodes render with the same vars hash and could read anything).
        #
        # `listing_fanout_*` are the exception: they gate no output at all,
        # only the render phase's auto worker count (see
        # Phases::Render#auto_render_workers). They therefore use TARGETED
        # substrings (`site.pages` / `section.pages`) rather than the
        # deliberately over-broad ones above — over-approximating here costs
        # render parallelism on every site that merely mentions "section".
        record TemplateVarFeatures,
          needs_seo : Bool,
          needs_jsonld : Bool,
          needs_section_pages : Bool,
          listing_fanout_site : Bool,
          listing_fanout_section : Bool
        # Which page fields the site's LISTING templates can actually read.
        # A field folded into the page/section-set fingerprint re-renders every
        # listing whenever that field moves on any page, so `extra` and the
        # content-derived trio (`summary`, `word_count`, `reading_time`) are
        # only fingerprinted when some page-set-dependent template names them.
        # Detection is substring-based over those templates' closure sources,
        # so it only ever over-approximates: naming the field always keeps it.
        record ListingPageFields,
          extra : Bool,
          content_derived : Bool
        # Keyed by entry template NAME (closure semantics are per-name).
        # Populated once in load_templates, read-only during render. Missing
        # key means "unknown": build everything, exactly as before.
        @template_var_features : Hash(String, TemplateVarFeatures) = {} of String => TemplateVarFeatures
        # Tracks shortcode template keys we've already warned about, so a
        # single typo used across many pages emits just one warning line.
        @shortcode_warnings_seen : Set(String)? = nil
        @pages_by_path : Hash(String, Models::Page)?
        @i18n_translations : Content::I18n::TranslationData = Content::I18n::TranslationData.new
        # Per-section cache of Crinja::Value arrays, keyed by
        # {section_name, language} (a tuple, not an interpolated string —
        # these lookups run per page in the render hot path).
        @section_pages_crinja_cache : Hash({String, String?}, Array(Crinja::Value)) = {} of {String, String?} => Array(Crinja::Value)
        # Companion url→index map per section list, populated together with
        # (and invalidated exactly like) @section_pages_crinja_cache. Used
        # for O(1) current-page exclusion in build_template_variables —
        # the previous per-page linear Array#index scan made rendering a
        # flat N-page section O(N²).
        @section_pages_url_index_cache : Hash({String, String?}, Hash(String, Int32)) = {} of {String, String?} => Hash(String, Int32)
        # Per-section cache of Crinja::Value arrays for section assets, keyed by section name
        @section_assets_crinja_cache : Hash(String, Array(Crinja::Value)) = {} of String => Array(Crinja::Value)
        # Track created directories to avoid redundant mkdir_p syscalls
        @created_dirs : Set(String) = Set(String).new
        # Per-page Crinja::Value cache — avoids repeated Page→Crinja::Value conversion
        # across build_global_vars, section page lists, and page_to_crinja_list_value
        @page_crinja_value_cache : Hash(String, Crinja::Value) = {} of String => Crinja::Value
        @series_crinja_cache : Hash(String, Crinja::Value) = {} of String => Crinja::Value
        # Per-section ancestors Crinja::Value cache, keyed by
        # {section_name, language} (pages in the same section+language share ancestors)
        @ancestors_crinja_cache : Hash({String, String?}, Array(Crinja::Value)) = {} of {String, String?} => Array(Crinja::Value)
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
        # Pages the render loop counted but NO sink could publish (a URL with a
        # traversing segment). Subtracted from `pages_rendered` so the build
        # receipt cannot claim a page that never reached disk. Atomic because
        # the render fan-out increments it from worker fibers.
        # Memo for the listing-template source union (see Phases::Render).
        # Keyed by the templates Hash identity so a template reload recomputes.
        @listing_source_union_memo : String? = nil
        @listing_source_union_memo_key : UInt64 = 0_u64
        @unpublished_pages : Atomic(Int32) = Atomic(Int32).new(0)
        # Pages that actually wrote a file. `process_files_*` returns a delta of
        # this, so every caller (render phase, incremental rebuild, serve
        # re-render, streaming batches) reports the same published-not-processed
        # number instead of each keeping its own bookkeeping.
        @published_pages : Atomic(Int32) = Atomic(Int32).new(0)
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
        # Deterministic owner (page.path) of every claimed output URL — page
        # URLs and alias destinations. A page that is not the recorded winner
        # for a URL must not write it; under parallel render the colliding
        # file's bytes were whichever worker finished last. Recomputed per
        # full build and per incremental/rerender pass (see
        # compute_output_url_winners). Nil until the first render pass.
        @output_url_winners : Hash(String, String)? = nil
        # Unresolved `@/` internal links collected during the render fan-out
        # when `[links] broken_internal = "error"` (each entry is a formatted
        # "source.md → @/target (reason)" line). Guarded by
        # @broken_links_mutex — render workers append concurrently under
        # -Dpreview_mt. Cleared at every build entry point and aggregated
        # into one classified error by raise_on_broken_internal_links!.
        @broken_internal_links : Array(String) = [] of String
        @broken_links_mutex : Mutex = Mutex.new

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

        # The most recently loaded site config (nil before the first build).
        # The serve watcher reads it to diff restart-only [serve] settings
        # after a config-triggered rebuild.
        def config : Models::Config?
          @config
        end

        # The most recently built site (nil before the first build). The dev
        # server's lazy OG handler reads it to match a requested image path
        # back to the page that owns it.
        def site : Models::Site?
          @site
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

        # Keyword-argument convenience form of `run`: packs the arguments
        # into a BuildOptions and delegates to the struct overload, which is
        # the REAL implementation. Callers holding a BuildOptions (the build
        # command, the serve watcher) must call that overload directly so
        # fields this form doesn't expose — `full`, `serve_mode`, `workers`
        # — reach the build context verbatim instead of being silently
        # dropped in a re-pack.
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
        ) : Bool
          run(Config::Options::BuildOptions.new(
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
          ))
        end

        # Full build — the real implementation behind both `run` forms.
        # The incoming struct is stored on the BuildContext verbatim, so
        # fields the keyword form doesn't expose (`full`, `serve_mode`)
        # survive to the phases and hooks that branch on them (`--full`
        # cache clearing, `[og.image] lazy_generate` under serve).
        #
        # Returns false when the build failed without raising (pre-hook
        # failure or a phase abort) — the serve watcher branches on this to
        # surface the failure instead of live-reloading onto a broken site.
        def run(options : Config::Options::BuildOptions) : Bool
          @render_workers = options.workers
          # Load config once and reuse throughout the build.
          # `Models::Config.load` raises `HwaroError(HWARO_E_CONFIG)` directly
          # for missing files and TOML parse failures, so callers (and
          # `--json` consumers) can branch on HWARO_E_CONFIG without the
          # build pipeline rewrapping the exception.
          config = Models::Config.load(env: options.env)
          @config = config
          # `[build]` supplies output_dir/drafts/parallel/cache for anything the
          # command line left at its default. Applied before the BuildContext is
          # built so every phase (and the output guard) sees the same values.
          options.apply_build_config!(config.build)
          pre_hooks = config.build.hooks.pre
          post_hooks = config.build.hooks.post

          # Run pre-build hooks
          unless pre_hooks.empty?
            unless Utils::CommandRunner.run_pre_hooks(pre_hooks)
              Logger.error "Build aborted due to pre-build hook failure."
              return false
            end
          end

          # The build runs quietly; its story is told by the closing receipt
          # (and, under -Dpreview_mt TTY, the live status line in Phase 3).
          start_time = Time.instant

          # Initialize profiler
          profiler = Profiler.new(enabled: options.profile)
          @profiler = profiler
          profiler.start

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
          clear_broken_internal_links
          # The load_data() memo is keyed by ms-mtime, which a rewrite inside
          # one filesystem timestamp tick does not move; a build must read
          # the data files as they are now, not as a previous build saw them.
          Content::Processors::TemplateEngine.clear_load_data_cache
          # Same lifetime for the once-per-BUILD shortcode warnings (missing
          # template, unclosed block): a `serve` session that never cleared them
          # reported each name only for the first rebuild it appeared in.
          @shortcode_warnings_seen = nil

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
            # Phase bodies convert non-classified exceptions into Abort (see
            # Lifecycle::Manager); returning false lets callers that can't
            # rely on an exception — the serve watcher, `hwaro build`'s exit
            # code — still observe the failure.
            Logger.error "Build failed!"
            return false
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

          true
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
              # Keyed by {section, language} (see build_template_variables), so
              # drop every language's entry for the section, like section_pages.
              @ancestors_crinja_cache.reject! { |k, _| k[0] == section_name }
              @section_pages_crinja_cache.reject! { |k, _| k[0] == section_name }
              @section_pages_url_index_cache.reject! { |k, _| k[0] == section_name }
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
          if stats.pages_unpublished > 0
            receipt.row("skipped", "#{stats.pages_unpublished} not published", emphasis: "see warnings above")
          end
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
