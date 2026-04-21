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
require "../../utils/errors"
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
        @cache : Cache?
        @config : Models::Config?
        @lifecycle : Lifecycle::Manager
        @context : Lifecycle::BuildContext?
        @profiler : Profiler?
        @crinja_env : Crinja?
        @compiled_templates_cache : Hash(UInt64, Crinja::Template) = {} of UInt64 => Crinja::Template
        @pages_by_path : Hash(String, Models::Page)?
        @i18n_translations : Content::I18n::TranslationData = Content::I18n::TranslationData.new
        # Per-section cache of Crinja::Value arrays, keyed by "section_name:language"
        @section_pages_crinja_cache : Hash(String, Array(Crinja::Value)) = {} of String => Array(Crinja::Value)
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
        # Mutex to protect shared Crinja value caches during parallel rendering.
        # Crystal fibers are single-threaded by default, but this guards against
        # future multi-threaded mode (-Dpreview_mt) and ensures correctness.
        @crinja_cache_mutex : Mutex = Mutex.new(:reentrant)
        # Mutex to protect created_dirs set during parallel rendering
        @created_dirs_mutex : Mutex = Mutex.new
        # Unified cache manager for all cache layers
        @cache_manager : CacheManager = CacheManager.new

        def initialize
          @lifecycle = Lifecycle::Manager.new
          setup_cache_manager
        end

        # Access cache manager for external inspection
        def cache_manager : CacheManager
          @cache_manager
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
          config = @config
          site = @site
          templates = @templates

          # First build hasn't happened yet – fall back to full build
          unless config && site && templates
            return run(options)
          end

          Logger.info "Incremental build for #{changed_content_files.size} changed file(s)..."
          start_time = Time.instant

          output_dir = options.output_dir
          minify = options.minify
          highlight = options.highlight && site.config.highlight.enabled
          verbose = options.verbose
          safe = site.config.markdown.safe
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

          changed_content_files.each do |file|
            relative_path = begin
              Path[file].relative_to("content").to_s
            rescue
              file.lchop("content/")
            end

            page = pages_map[relative_path]?
            next unless page

            # Snapshot before re-parse
            old_taxonomies_snapshot[page.path] = page.taxonomies.transform_values(&.dup)
            old_series_names[page.path] = page.series
            old_neighbors[page.path] = {page.lower, page.higher}

            # Re-read, re-parse front-matter and recalculate URL
            parse_single_page(page)
            page.generate_permalink(config.base_url)

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

          # Re-link navigation only for affected sections
          relink_navigation_for_sections(site, affected_sections)

          # Recompute series for affected series (if enabled), including old memberships
          affected_series = if site.config.series.enabled
                              recompute_series_for_pages(site, changed_pages, old_series_names)
                            else
                              Set(String).new
                            end

          # Recompute related posts selectively (if enabled)
          related_pages_updated = recompute_related_posts_for_pages(site, changed_pages)

          # Invalidate Crinja caches for affected pages/sections
          invalidate_caches_for_pages(changed_pages, affected_sections)
          @crinja_cache_mutex.synchronize do
            affected_series.each { |s| @series_crinja_cache.delete(s) }
            related_pages_updated.each { |path| @related_posts_crinja_cache.delete(path) }
          end

          # --- 3. Determine the full set of pages that need re-rendering ---
          pages_to_render = Set(Models::Page).new(changed_pages)

          # Section index pages whose content lists include the changed pages
          affected_sections.each do |section_name|
            section = site.sections_by_name[section_name]?
            pages_to_render << section if section
          end

          # Previous / next pages (both old and new neighbors after re-linking)
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

          render_list = pages_to_render.to_a

          # --- 4. Re-render the affected pages ---
          global_vars = build_global_vars(site, options.cache_busting)
          @pages_by_path = build_pages_by_path(site)
          cache = @cache || Cache.new(enabled: false)

          error_overlay = options.error_overlay
          render_list.each do |page|
            next unless page.render
            render_page(page, site, templates, output_dir, minify, highlight, safe, verbose, global_vars, error_overlay: error_overlay)
            source_path = File.join("content", page.path)
            output_path = get_output_path(page, output_dir)
            cache.update(source_path, output_path)
          end

          cache.save if options.cache

          # --- 5. Regenerate taxonomy index/term pages ---
          Content::Taxonomies.generate(site, output_dir, templates, verbose)

          # --- 6. Regenerate lightweight SEO / search files in parallel ---
          seo_tasks = [
            -> { Content::Seo::Sitemap.generate(all_pages, site, output_dir, verbose); nil },
            -> { Content::Seo::Feeds.generate(all_pages, site.config, output_dir, verbose); nil },
            -> { Content::Seo::Robots.generate(site.config, output_dir, verbose); nil },
            -> { Content::Seo::Llms.generate(site.config, all_pages, output_dir, verbose); nil },
            -> { Content::Search.generate(all_pages, site.config, output_dir, verbose); nil },
          ] of Proc(Nil)
          ParallelHelper.execute(seo_tasks, options.parallel)

          elapsed = Time.instant - start_time
          Logger.success "Incremental build complete! Rendered #{render_list.size}/#{all_pages.size} pages in #{elapsed.total_milliseconds.round(2)}ms."
          if options.verbose
            @cache_manager.report_verbose
          else
            @cache_manager.report
          end
        end

        # Incremental parse of changed content + full re-render with reloaded templates.
        # Used when both content and templates changed simultaneously.
        def run_incremental_then_rerender(changed_content_files : Array(String), options : Config::Options::BuildOptions)
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

          changed_content_files.each do |file|
            relative_path = begin
              Path[file].relative_to("content").to_s
            rescue
              file.lchop("content/")
            end

            page = pages_map[relative_path]?
            next unless page

            # Snapshot before re-parse
            old_taxonomies_snapshot[page.path] = page.taxonomies.transform_values(&.dup)
            old_series_names[page.path] = page.series

            parse_single_page(page)
            page.generate_permalink(config.base_url)
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

          # Now do a full re-render with reloaded templates (caches cleared there)
          run_rerender(options)
        end

        # Re-render all pages using reloaded templates without re-parsing
        # content.  Useful when only template files have been modified.
        def run_rerender(options : Config::Options::BuildOptions)
          config = @config
          site = @site

          unless config && site
            return run(options)
          end

          Logger.info "Template change detected. Re-rendering all pages..."
          start_time = Time.instant

          # Reload templates from disk & reset all runtime caches
          @templates = nil
          @cache_manager.clear_runtime
          templates = load_templates
          @templates = templates

          output_dir = options.output_dir
          minify = options.minify
          highlight = options.highlight && site.config.highlight.enabled
          verbose = options.verbose

          all_pages = (site.pages + site.sections).as(Array(Models::Page))
          renderable_pages = all_pages.select(&.render)

          global_vars = build_global_vars(site, options.cache_busting)
          @pages_by_path = build_pages_by_path(site)
          cache = @cache || Cache.new(enabled: false)

          error_overlay = options.error_overlay
          count = if options.parallel && renderable_pages.size > 1
                    process_files_parallel(renderable_pages, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: error_overlay)
                  else
                    process_files_sequential(renderable_pages, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: error_overlay)
                  end

          # Re-generate 404 page with new template
          generate_404_page(site, templates, output_dir, minify, verbose)

          # Re-generate taxonomy pages with new templates
          Content::Taxonomies.generate(site, output_dir, templates, verbose)

          cache.save if options.cache

          elapsed = Time.instant - start_time
          Logger.success "Re-render complete! Rendered #{count} pages in #{elapsed.total_milliseconds.round(2)}ms."
          if verbose
            @cache_manager.report_verbose
          else
            @cache_manager.report
          end
        end

        # Copy only the specified static files to the output directory.
        # Used by serve mode when only static files have changed.
        def copy_changed_static(changed_files : Array(String), output_dir : String, verbose : Bool = false)
          copied = 0
          changed_files.each do |src_path|
            next unless File.exists?(src_path)
            next if File.directory?(src_path)

            relative = begin
              Path[src_path].relative_to("static").to_s
            rescue
              src_path.lchop("static/")
            end
            dest_path = File.join(output_dir, relative)

            FileUtils.mkdir_p(File.dirname(dest_path))
            FileUtils.cp(src_path, dest_path)
            copied += 1
          end
          Logger.success "Copied #{copied} static file(s)." if copied > 0
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

          Logger.info "Building site..."
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
          )
          if options.streaming?
            Logger.info "  Streaming mode enabled (batch size: #{options.batch_size})"
          end

          ctx = Lifecycle::BuildContext.new(options)
          ctx.stats.start_time = Time.instant
          @context = ctx

          # Reset internal caches (preserve @config loaded above)
          @site = nil
          @templates = nil
          @cache_manager.clear_runtime
          @created_dirs.clear

          # Execute build phases through lifecycle
          result = execute_phases(ctx, profiler)

          ctx.stats.end_time = Time.instant

          if result == Lifecycle::HookResult::Abort
            Logger.error "Build failed!"
            return
          end

          elapsed = Time.instant - start_time
          raw_msg = ctx.stats.raw_files_processed > 0 ? " + #{ctx.stats.raw_files_processed} raw files" : ""
          Logger.success "Build complete! Generated #{ctx.stats.pages_rendered} pages#{raw_msg} in #{elapsed.total_milliseconds.round(2)}ms."

          # Print profiling report if enabled
          profiler.report
          profiler.template_report

          # Print cache stats
          if options.verbose
            @cache_manager.report_verbose
          else
            @cache_manager.report
          end

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
              @ancestors_crinja_cache.delete(section_name)
              @section_pages_crinja_cache.reject! { |k, _| k.starts_with?("#{section_name}:") }
              @section_assets_crinja_cache.delete(section_name)
            end
          end
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
