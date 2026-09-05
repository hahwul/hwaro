# Render phase — phase entry, priority split and streaming mode.
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro::Core::Build::Phases::Render
  private def execute_render_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    site = @site || raise "Site not initialized"
    templates = @templates || raise "Templates not loaded"
    build_cache = @cache || raise "Cache not initialized"
    output_dir = ctx.options.output_dir
    cache_enabled = ctx.options.cache
    parallel = ctx.options.parallel
    minify = ctx.options.minify
    highlight = ctx.options.highlight
    verbose = ctx.options.verbose

    all_pages = ctx.all_pages

    # Filter pages for caching. Listing pages (homepage, section indexes,
    # archives, taxonomy widgets) render content derived from the global
    # page/section set even when their own source is unchanged, so fold a
    # fingerprint of those sets into the rebuild decision.
    @unpublished_pages.set(0)
    @published_pages.set(0)
    listing_fields = cache_enabled ? listing_page_fields(templates) : Builder::ListingPageFields.new(false, false)
    page_set_fp = cache_enabled ? compute_page_set_fingerprint(site.pages, listing_fields) : ""
    section_set_fp = cache_enabled ? compute_section_set_fingerprint(site.sections) : ""
    pages_to_build = if cache_enabled
                       filtered = filter_changed_pages(all_pages, output_dir, build_cache, templates, site, page_set_fp, section_set_fp)
                       # Publish the set-change signal for the Generate phase
                       # BEFORE recording overwrites the stored fingerprints.
                       ctx.page_or_section_set_changed =
                         build_cache.page_set_changed?(page_set_fp) || build_cache.section_set_changed?(section_set_fp)
                       # Don't record under fast-start: deferred listing pages
                       # render in a later pass, so persisting the new fingerprint
                       # now would let the next build skip them while stale.
                       build_cache.record_set_fingerprints(page_set_fp, section_set_fp) unless ctx.options.fast_start
                       filtered
                     else
                       all_pages
                     end

    if cache_enabled && pages_to_build.size < all_pages.size
      # Surfaced as the receipt's "render … · N cached" detail instead of an
      # inline line.
      ctx.stats.cache_hits = all_pages.size - pages_to_build.size
    end

    # Determine if syntax highlighting should be used
    # Config setting takes precedence, but can be overridden by CLI flag
    use_highlight = highlight && (site.config.highlight.enabled)

    error_overlay = ctx.options.error_overlay

    # Claim a deterministic owner for every output URL (slug collisions and
    # alias collisions) — under parallel render the colliding file's bytes
    # used to be whichever worker finished last, flapping run-to-run.
    @output_url_winners = compute_output_url_winners(all_pages)

    # Fast-start mode: render only homepage + most recent N pages on this
    # pass and stash the rest on the Builder so a background fiber in
    # `serve` can render them after the server is already accepting
    # connections. Has no effect outside of `hwaro serve --fast-start`.
    #
    # Critically, the priority set is published on `ctx.priority_pages`
    # BEFORE BeforeRender hooks run so OG image generation and image
    # resizing (the dominant cost on large sites) only run for the
    # priority subset on the cold pass. Without this they iterated
    # `ctx.all_pages` and ate the savings the render-phase filter was
    # supposed to deliver — fast-start was indistinguishable from a
    # normal serve cold start. The background pass re-runs those hooks
    # for the rest, then renders the deferred pages.
    if ctx.options.fast_start
      priority, deferred = split_priority_pages(pages_to_build, ctx.options.fast_start_count)
      @deferred_pages = deferred
      if !deferred.empty?
        Logger.info "  Fast-start: rendering #{priority.size} priority page(s) up front, deferring #{deferred.size} for background render."
        # NOTE — both `priority_pages` and `partial_render` are consumed
        # by BeforeRender hooks below (`og_image:generate`,
        # `image:resize`). Don't move these assignments after
        # `run_phase` or those hooks will fall back to the all-pages
        # path and `--fast-start` becomes a no-op again.
        ctx.priority_pages = priority
        ctx.partial_render = true
      else
        ctx.priority_pages = nil
        ctx.partial_render = false
      end
      pages_to_build = priority
    else
      @deferred_pages = nil
      ctx.priority_pages = nil
      ctx.partial_render = false
    end

    profiler.start_phase("Render")
    result = @lifecycle.run_phase(Lifecycle::Phase::Render, ctx) do
      Logger.status_phase(pages_to_build.size > 0 ? "render #{pages_to_build.size} pages" : "render")
      global_vars = build_global_vars(site, ctx.options.cache_busting)
      # Stash for the Write phase's 404 page (see @render_global_vars).
      @render_global_vars = global_vars
      @pages_by_path = build_pages_by_path(site)
      # Freeze the Crinja value caches for the fan-out so workers read them
      # lock-free (see @crinja_caches_frozen). Streaming mode is excluded:
      # it clears these caches every Nth batch and relies on lazy refill,
      # which needs the locked read-write path.
      unless ctx.options.streaming?
        prewarm_crinja_caches(site, pages_to_build)
        @crinja_caches_frozen = true
      end
      begin
        count = if ctx.options.streaming?
                  render_streaming(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay, parallel, ctx.options.batch_size)
                elsif parallel && pages_to_build.size > 1
                  process_files_parallel(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: active_profiler)
                else
                  process_files_sequential(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: active_profiler)
                end
        # A page whose URL no sink could write is not a built page, however
        # far it got through rendering.
        # `count` is already the number of pages that wrote a file (see
        # process_files_*); the refusals are surfaced separately.
        ctx.stats.pages_rendered = count
        ctx.stats.pages_unpublished = @unpublished_pages.get
        # Pages the cache skipped still feed the Generate phase (search index,
        # feeds read `page.content`), so give them the content a real render
        # would have produced — unless nothing downstream is going to read it
        # (see `cached_content_needed?`), in which case the work is wasted.
        # Fast-start's deferred pages are excluded: they render for real in
        # the background pass.
        if cache_enabled && !ctx.options.streaming? && pages_to_build.size < all_pages.size &&
           cached_content_needed?(ctx, site)
          skipped = all_pages - pages_to_build
          if deferred = @deferred_pages
            skipped -= deferred
          end
          hydrate_cached_page_content(skipped, site, templates, use_highlight, global_vars, parallel)
        end
        # Strict [links] broken_internal = "error": fail the phase with one
        # aggregated error after the whole fan-out so every offender is
        # listed. The lifecycle manager re-raises HwaroError unchanged
        # (exit code 5 for build/CI; serve's watcher surfaces the overlay).
        raise_on_broken_internal_links!
      ensure
        @crinja_caches_frozen = false
      end
    end
    profiler.end_phase
    result
  end

  # Pick a "priority" subset of pages for fast-start: the homepage and
  # shallow section indexes (depth ≤ 1) plus the N most recent regular
  # pages by `date` descending. Pages without a date sort last.
  #
  # Earlier iterations included every `is_index` page, but on real sites
  # that pulls in deeply-nested `_index.md` files (e.g.
  # `archive/dev/crystal/_index.md`) plus every `index.md` page-bundle
  # leaf — on a 1k-page site this ballooned the priority set to 200+
  # pages and wiped out the win, since OG image generation and image
  # resize were still running for the whole subset. Section listings
  # for deep archive folders are exactly the pages users don't hit
  # first; live-reload will refresh any tab parked on one once the
  # background pass finishes.
  PRIORITY_MAX_SECTION_DEPTH = 1

  protected def split_priority_pages(
    pages : Array(Models::Page),
    count : Int32,
  ) : {Array(Models::Page), Array(Models::Page)}
    return {pages, [] of Models::Page} if pages.size <= count

    priority = Set(Models::Page).new
    regulars = [] of Models::Page

    pages.each do |page|
      if priority_section_index?(page)
        priority << page
      else
        regulars << page
      end
    end

    # Sort by date descending, nil dates last
    regulars.sort! do |a, b|
      ad = a.date
      bd = b.date
      if ad && bd
        bd <=> ad
      elsif ad
        -1
      elsif bd
        1
      else
        0
      end
    end

    regulars.first(count).each { |p| priority << p }

    priority_list = pages.select { |p| priority.includes?(p) }
    deferred_list = pages.reject { |p| priority.includes?(p) }
    {priority_list, deferred_list}
  end

  # Treat only the root section index and depth-1 section indexes as
  # always-priority. `Page#is_index` is also true for `index.md`
  # page-bundle leaves (regular posts that live alongside their
  # assets) — those should compete with other regulars for the
  # `fast_start_count` slots, not bypass the limit.
  private def priority_section_index?(page : Models::Page) : Bool
    return false unless page.is_a?(Models::Section)
    section = page.section
    return true if section.empty?
    section.count('/') < PRIORITY_MAX_SECTION_DEPTH
  end

  private def render_streaming(
    pages : Array(Models::Page),
    site : Models::Site,
    templates : Hash(String, String),
    output_dir : String,
    minify : Bool,
    build_cache : Cache,
    use_highlight : Bool,
    verbose : Bool,
    global_vars : Hash(String, Crinja::Value),
    error_overlay : Bool,
    parallel : Bool,
    batch_size : Int32,
  ) : Int32
    total_count = 0
    batch_num = 0

    # Create the per-worker Crinja envs and compiled-template caches ONCE
    # for the whole streaming render — every batch used to rebuild
    # worker_count envs and re-parse the shared template ASTs from empty
    # caches (worker_count × batch_count setup cost). Sized for the first
    # batch, which each_slice guarantees is the largest.
    env_pool : Array(Crinja)? = nil
    template_cache_pool : Array(Hash(UInt64, Crinja::Template))? = nil
    if parallel && pages.size > 1
      pool_size = render_worker_count(pages, site, templates, Math.min(batch_size, pages.size))
      env_pool = Array.new(pool_size) { create_fresh_crinja_env }
      template_cache_pool = Array.new(pool_size) { {} of UInt64 => Crinja::Template }
    end

    pages.each_slice(batch_size) do |batch|
      batch_num += 1
      Logger.debug "  Streaming batch #{batch_num} (#{batch.size} pages)"

      count = if parallel && batch.size > 1
                process_files_parallel(batch, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: active_profiler, env_pool: env_pool, template_cache_pool: template_cache_pool)
              else
                process_files_sequential(batch, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: active_profiler)
              end
      total_count += count

      # Always release the rendered HTML strings for this batch immediately.
      # This is cheap and the primary mechanism for keeping peak memory low.
      batch.each(&.content=(""))

      # Only do the heavier cache invalidation + full GC on every Nth batch.
      # This significantly reduces overhead compared to doing it on every batch,
      # while still preventing unbounded growth of cached Crinja values on
      # extremely large sites.
      if batch_num % STREAMING_CLEAR_INTERVAL == 0
        @cache_manager.clear(
          "page_crinja_value",
          "section_pages_crinja",
          "section_assets_crinja",
          "series_crinja",
          "ancestors_crinja",
          "related_posts_crinja",
          reset_stats: false,
        )
        # Also drop the per-worker compiled-template caches: a layout whose
        # shortcodes expand per page compiles a distinct AST per page, and a
        # pool shared across ALL batches would grow O(total pages) — exactly
        # the unbounded footprint streaming exists to avoid. Clearing every
        # Nth batch keeps cross-batch reuse for the common shared templates
        # while re-bounding growth (base templates recompile once per
        # interval per worker — negligible).
        template_cache_pool.try(&.each(&.clear))
        GC.collect
      end
    end

    total_count
  end
end
