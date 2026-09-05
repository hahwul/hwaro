# Render phase — parallel/sequential page fan-out, worker sizing and failure reporting.
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro::Core::Build::Phases::Render
  private def process_files_parallel(
    pages : Array(Models::Page),
    site : Models::Site,
    templates : Hash(String, String),
    output_dir : String,
    minify : Bool,
    cache : Cache,
    highlight : Bool,
    verbose : Bool,
    global_vars : Hash(String, Crinja::Value),
    error_overlay : Bool = false,
    profiler : Profiler? = nil,
    env_pool : Array(Crinja)? = nil,
    template_cache_pool : Array(Hash(UInt64, Crinja::Template))? = nil,
  ) : Int32
    return 0 if pages.empty?

    # @render_workers (from `--jobs`, 0 = auto) caps the concurrent render
    # fibers. Fewer fibers means fewer of the runtime's worker threads render
    # at once, which on allocation-heavy template sites reduces GC-allocator
    # lock contention. Output is identical regardless of the count.
    worker_count = render_worker_count(pages, site, templates, pages.size)
    safe = site.config.markdown.safe

    # Per-worker Crinja environments and template caches avoid shared mutable
    # state between concurrent fibers. Streaming mode calls this once per
    # batch and passes pools created up front — rebuilding the envs (full
    # filter/function registration) and re-parsing the shared template ASTs
    # from empty caches every batch multiplied that setup cost by the batch
    # count. Never index past a caller-provided pool.
    worker_count = Math.min(worker_count, env_pool.size) if env_pool
    worker_count = Math.min(worker_count, template_cache_pool.size) if template_cache_pool
    worker_envs = env_pool || Array.new(worker_count) { create_fresh_crinja_env }
    worker_caches = template_cache_pool || Array.new(worker_count) { {} of UInt64 => Crinja::Template }

    results = Channel(Bool).new(pages.size)
    work_queue = Channel({Models::Page, Int32}).new(pages.size)

    # Enqueue all work items
    pages.each_with_index { |page, idx| work_queue.send({page, idx}) }
    work_queue.close

    # Track the first classified error seen by any worker so the build
    # can abort deterministically after draining the result channel.
    published_before = @published_pages.get
    classified_error : Hwaro::HwaroError? = nil
    error_mutex = Mutex.new

    # Accumulate per-page failures rather than logging immediately.
    # A broken shared template used to print the same "Parallel render
    # failed" line once per page (7 identical 4-line blocks on a 7-page
    # blog); deduping by normalized error signature collapses that into
    # one summary with the list of affected pages.
    failures = [] of NamedTuple(page_path: String, message: String)

    # Spawn workers, each with its own Crinja env and template cache
    worker_count.times do |worker_id|
      env = worker_envs[worker_id]
      tmpl_cache = worker_caches[worker_id]
      spawn do
        while work_item = work_queue.receive?
          page, _idx = work_item
          # `ensure` guarantees exactly one result per dequeued page even if a
          # rescue handler itself raises. Without it, a dying worker fiber
          # under-delivers and the `pages.size.times { results.receive }`
          # collector below blocks forever — the build hangs instead of
          # failing.
          ok = false
          begin
            page_start = profiler ? Time.instant : nil
            render_page(page, site, templates, output_dir, minify, highlight, safe, verbose, global_vars,
              crinja_env_override: env, template_cache_override: tmpl_cache, error_overlay: error_overlay, profiler: profiler)
            if profiler && page_start
              elapsed_ms = (Time.instant - page_start).total_milliseconds
              template_name = determine_template(page, templates, site)
              profiler.record_template(template_name, page.content.bytesize.to_i64, elapsed_ms)
            end
            record_page_cache_entry(page, cache, templates, site, output_dir)
            ok = true
          rescue ex : Hwaro::HwaroError
            error_mutex.synchronize do
              classified_error ||= ex
              failures << {page_path: page.path, message: ex.message.to_s}
            end
          rescue ex
            error_mutex.synchronize do
              failures << {page_path: page.path, message: ex.message.to_s}
            end
            # determine_template re-runs template resolution on the same
            # inputs that just failed, so it may raise the same error; keep
            # the diagnostic line from killing the worker.
            template_name = begin
              determine_template(page, templates, site)
            rescue
              "unknown"
            end
            Logger.debug "  Template: #{template_name}, Section: #{page.section}"
            Logger.debug "  Backtrace: #{ex.backtrace?.try(&.first(3).join("\n    ")) || "unavailable"}"
          ensure
            results.send(ok)
          end
        end
      end
    end

    # Collect results
    pages.size.times { results.receive }

    finalize_render_failures(failures, classified_error, verbose)

    # Published, not processed: a page whose URL no writer could accept must
    # not be reported as built. Returned as a delta so streaming batches and
    # the incremental/serve callers each get their own number.
    @published_pages.get - published_before
  end

  # Shared failure epilogue for the parallel and sequential render loops —
  # one copy of the exit-code/message contract so the two paths can't drift.
  #
  # Emits the (deduped) failure summary first, then surfaces the first
  # classified error so the CLI sees the documented exit code / JSON payload
  # instead of a silent `status=ok, pages_generated=0`. Generic exceptions
  # (Crystal-level bugs, non-Crinja crashes) used to slip through — with no
  # classified error to raise the build returned its success count and the
  # CLI happily printed `Build complete!` even when pages crashed. Promote
  # the first such failure to `HWARO_E_TEMPLATE` so the build fails loud (#490).
  private def finalize_render_failures(
    failures : Array(NamedTuple(page_path: String, message: String)),
    classified_error : Hwaro::HwaroError?,
    verbose : Bool,
  )
    report_render_failures(failures, verbose) unless failures.empty?

    if err = classified_error
      raise err
    end

    unless failures.empty?
      first = failures.first
      raise Hwaro::HwaroError.new(
        code: Hwaro::Errors::HWARO_E_TEMPLATE,
        message: "Render failed for #{failures.size} page(s); first failure on #{first[:page_path]}: #{Utils::TextUtils.truncate_error(first[:message])}",
      )
    end
  end

  # Collapse identical errors raised across many pages (typical of a
  # broken shared template) into a single summary line, preserving the
  # full page list. `--verbose` opts back into per-page detail.
  private def report_render_failures(
    failures : Array(NamedTuple(page_path: String, message: String)),
    verbose : Bool,
  )
    # A template error carries Crinja's source excerpt, so ONE failure in a
    # minified (single-line) template printed a multi-megabyte console line —
    # a 3 MB `{% if %}` line produced a 6 MB log, repeated on every serve
    # rebuild. `hwaro serve` already clamped the watcher line and the overlay
    # payload; these are the emitters it did not cover, and they fire with zero
    # clients attached (plain `hwaro build` too).
    if verbose
      failures.each do |f|
        Logger.error "Parallel render failed for #{f[:page_path]}: #{Utils::TextUtils.truncate_error(f[:message])}"
      end
      return
    end

    grouped = failures.group_by { |f| render_error_signature(f[:message]) }
    grouped.each do |signature, group|
      if group.size == 1
        Logger.error "Render failed for #{group.first[:page_path]}: #{Utils::TextUtils.truncate_error(group.first[:message])}"
      else
        Logger.error "Render failed for #{group.size} pages: #{Utils::TextUtils.truncate_error(signature)}"
        # The signature is the first line only; Crinja puts the template
        # file and line on the next one. Sixteen pages failing on a shared
        # partial is far more useful with `template: templates/post.html:79`
        # than with the page list alone.
        if location = render_error_location(group.first[:message])
          Logger.error "  #{Utils::TextUtils.truncate_error(location)}"
        end
        group.first(5).each { |f| Logger.error "  - #{f[:page_path]}" }
        if group.size > 5
          Logger.error "  … and #{group.size - 5} more"
        end
        Logger.error "  Run with --verbose to see each failure individually."
      end
    end
  end

  # Strip the page-specific prefix that Crinja adds to template errors
  # ("Template error for posts/hello-world.md: Unterminated tag …") so
  # identical failures on different pages collapse to the same key.
  private def render_error_signature(message : String) : String
    normalized = message.sub(/^Template error for [^:]+:\s*/, "")
    first_line = normalized.lines.first?.try(&.strip) || normalized.strip
    first_line.empty? ? normalized.strip : first_line
  end

  # The `template: <file>:<line>:<col> ..` line Crinja appends below the
  # message (see ext/crinja_error_location_fix), or nil when the failure
  # carries no location (a non-template exception, a message with only one
  # line).
  private def render_error_location(message : String) : String?
    message.each_line do |line|
      stripped = line.strip
      return stripped if stripped.starts_with?("template:")
    end
    nil
  end

  private def process_files_sequential(
    pages : Array(Models::Page),
    site : Models::Site,
    templates : Hash(String, String),
    output_dir : String,
    minify : Bool,
    cache : Cache,
    highlight : Bool,
    verbose : Bool,
    global_vars : Hash(String, Crinja::Value),
    error_overlay : Bool = false,
    profiler : Profiler? = nil,
  ) : Int32
    published_before = @published_pages.get
    safe = site.config.markdown.safe

    # Mirror the parallel path's failure handling: render every page,
    # accumulate failures, then fail loud once with the full picture.
    # Aborting on the first bad page gave `--no-parallel` (the natural
    # debugging flag) and incremental serve rebuilds *worse* diagnostics
    # than the default build.
    classified_error : Hwaro::HwaroError? = nil
    failures = [] of NamedTuple(page_path: String, message: String)

    pages.each do |page|
      page_start = profiler ? Time.instant : nil
      render_page(page, site, templates, output_dir, minify, highlight, safe, verbose, global_vars, error_overlay: error_overlay, profiler: profiler)
      if profiler && page_start
        elapsed_ms = (Time.instant - page_start).total_milliseconds
        template_name = determine_template(page, templates, site)
        profiler.record_template(template_name, page.content.bytesize.to_i64, elapsed_ms)
      end
      record_page_cache_entry(page, cache, templates, site, output_dir)
    rescue ex : Hwaro::HwaroError
      classified_error ||= ex
      failures << {page_path: page.path, message: ex.message.to_s}
    rescue ex
      failures << {page_path: page.path, message: ex.message.to_s}
      Logger.debug "  Backtrace: #{ex.backtrace?.try(&.first(3).join("\n    ")) || "unavailable"}"
    end

    finalize_render_failures(failures, classified_error, verbose)

    @published_pages.get - published_before
  end

  # Concurrent render fibers for `pages`. `--jobs N` wins outright; otherwise
  # the count comes from the site's listing fan-out (see the RENDER_FANOUT_*
  # constants). Never affects output — only how many pages render at once.
  private def render_worker_count(
    pages : Array(Models::Page),
    site : Models::Site,
    templates : Hash(String, String),
    item_count : Int32,
  ) : Int32
    if @render_workers > 0
      return ParallelConfig.new(enabled: true, max_workers: @render_workers).calculate_workers(item_count)
    end
    return 1 if item_count <= 1
    Math.min(auto_render_workers(pages, site, templates), item_count).clamp(1, MAX_PARALLEL_WORKERS)
  end

  # Mean number of page objects one page render materializes from a site-wide
  # collection, mapped onto a worker count.
  #
  # The mean (not the max) is what the allocator sees: a homepage that lists
  # every page is one expensive render among thousands of cheap ones and must
  # not drag the whole site down to a single worker, whereas a `page` template
  # with the same loop makes every render expensive. Templates whose static
  # closure could not be resolved are excluded from the mean; if they are the
  # majority, the fan-out is unknowable and the hedge applies.
  private def auto_render_workers(
    pages : Array(Models::Page),
    site : Models::Site,
    templates : Hash(String, String),
  ) : Int32
    features = @template_var_features
    return RENDER_WORKERS_UNKNOWN if features.empty?

    site_pages = site.pages.size
    # Upper bound over sections rather than each page's own section: the
    # thresholds are coarse, and this avoids depending on the language-keyed
    # section lookup semantics for what is only a sizing hint.
    largest_section = site.pages_by_section.each_value.max_of?(&.size) || 0

    total = 0_i64
    known = 0
    pages.each do |page|
      feature = features[determine_template(page, templates, site)]?
      next unless feature
      known += 1
      total += site_pages if feature.listing_fanout_site
      total += largest_section if feature.listing_fanout_section
    end
    return RENDER_WORKERS_UNKNOWN if known < (pages.size * RENDER_FANOUT_MIN_KNOWN_RATIO).ceil

    mean_fanout = total // known
    return 1 if mean_fanout >= RENDER_FANOUT_SERIAL
    return RENDER_WORKERS_UNKNOWN if mean_fanout >= RENDER_FANOUT_LIMITED
    Math.min(System.cpu_count.to_i, RENDER_WORKERS_AUTO_CAP)
  end
end
