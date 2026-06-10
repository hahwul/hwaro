# Phase: Render — template rendering (sequential/parallel/streaming)
#
# Handles the render phase: building template variables, applying Crinja
# templates to pages, shortcode processing, markdown rendering, pagination,
# and writing rendered HTML to disk. Includes caching for Crinja values
# and compiled templates to minimize allocations during parallel rendering.

module Hwaro::Core::Build::Phases::Render
  # In streaming mode, we release per-page rendered content every batch,
  # but do the more expensive Crinja cache invalidation + GC.collect
  # only every N batches. This is the main D5 tuning knob for
  # memory vs. speed on very large sites.
  private STREAMING_CLEAR_INTERVAL = 4

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

    # Filter pages for caching
    pages_to_build = if cache_enabled
                       filter_changed_pages(all_pages, output_dir, build_cache)
                     else
                       all_pages
                     end

    if cache_enabled && pages_to_build.size < all_pages.size
      ctx.stats.cache_hits = all_pages.size - pages_to_build.size
      Logger.info "  Skipping #{ctx.stats.cache_hits} unchanged pages."
    end

    # Determine if syntax highlighting should be used
    # Config setting takes precedence, but can be overridden by CLI flag
    use_highlight = highlight && (site.config.highlight.enabled)

    error_overlay = ctx.options.error_overlay

    # Detect duplicate output paths (slug collisions)
    seen_urls = Hash(String, String).new
    all_pages.each do |page|
      url = page.url
      if prev_path = seen_urls[url]?
        Logger.warn "Duplicate output path '#{url}' — '#{page.path}' overwrites '#{prev_path}'"
      else
        seen_urls[url] = page.path
      end
    end

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
      global_vars = build_global_vars(site, ctx.options.cache_busting)
      @pages_by_path = build_pages_by_path(site)
      count = if ctx.options.streaming?
                render_streaming(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay, parallel, ctx.options.batch_size)
              elsif parallel && pages_to_build.size > 1
                process_files_parallel(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: @profiler)
              else
                process_files_sequential(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: @profiler)
              end
      ctx.stats.pages_rendered = count
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

    pages.each_slice(batch_size) do |batch|
      batch_num += 1
      Logger.debug "  Streaming batch #{batch_num} (#{batch.size} pages)"

      count = if parallel && batch.size > 1
                process_files_parallel(batch, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: @profiler)
              else
                process_files_sequential(batch, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: @profiler)
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
        GC.collect
      end
    end

    total_count
  end

  private def filter_changed_pages(pages : Array(Models::Page), output_dir : String, cache : Cache) : Array(Models::Page)
    pages.select do |page|
      source_path = File.join("content", page.path)
      output_path = get_output_path(page, output_dir)
      cache.changed?(source_path, output_path)
    end
  end

  private def get_output_path(page : Models::Page, output_dir : String) : String
    url_path = Utils::PathUtils.sanitize_path(page.url.lchop("/"))
    output_path = File.join(output_dir, url_path, "index.html")
    Utils::OutputGuard.safe_output_path(output_path, output_dir) || File.join(output_dir, "index.html")
  end

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
  ) : Int32
    return 0 if pages.empty?

    config = ParallelConfig.new(enabled: true)
    worker_count = config.calculate_workers(pages.size)
    safe = site.config.markdown.safe

    # Pre-create per-worker Crinja environments and template caches
    # to avoid shared mutable state between concurrent fibers.
    worker_envs = Array.new(worker_count) { create_fresh_crinja_env }
    worker_caches = Array.new(worker_count) { {} of UInt64 => Crinja::Template }

    # Warm the built-in shortcode template memo on THIS fiber before any worker
    # spawns. BuiltinShortcodes.templates is `@@templates ||= build_templates`,
    # an unsynchronized check-then-build; first-touched concurrently by two
    # workers under -Dpreview_mt it races. Building it once here makes it
    # read-only for the workers (identical content, negligible cost).
    BuiltinShortcodes.templates

    results = Channel(Bool).new(pages.size)
    work_queue = Channel({Models::Page, Int32}).new(pages.size)

    # Enqueue all work items
    pages.each_with_index { |page, idx| work_queue.send({page, idx}) }
    work_queue.close

    # Track the first classified error seen by any worker so the build
    # can abort deterministically after draining the result channel.
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
          begin
            page_start = profiler ? Time.instant : nil
            render_page(page, site, templates, output_dir, minify, highlight, safe, verbose, global_vars,
              crinja_env_override: env, template_cache_override: tmpl_cache, error_overlay: error_overlay, profiler: profiler)
            if profiler && page_start
              elapsed_ms = (Time.instant - page_start).total_milliseconds
              template_name = determine_template(page, templates, site)
              profiler.record_template(template_name, page.content.bytesize.to_i64, elapsed_ms)
            end
            source_path = File.join("content", page.path)
            output_path = get_output_path(page, output_dir)
            cache.update(source_path, output_path)
            results.send(true)
          rescue ex : Hwaro::HwaroError
            error_mutex.synchronize do
              classified_error ||= ex
              failures << {page_path: page.path, message: ex.message.to_s}
            end
            results.send(false)
          rescue ex
            error_mutex.synchronize do
              failures << {page_path: page.path, message: ex.message.to_s}
            end
            Logger.debug "  Template: #{determine_template(page, templates, site)}, Section: #{page.section}"
            Logger.debug "  Backtrace: #{ex.backtrace?.try(&.first(3).join("\n    ")) || "unavailable"}"
            results.send(false)
          end
        end
      end
    end

    # Collect results
    count = 0
    pages.size.times do
      count += 1 if results.receive
    end

    # Emit the (deduped) failure summary before surfacing the classified
    # error, so users see both the list of affected pages and the final
    # `Error [HWARO_E_TEMPLATE]: …` line.
    report_render_failures(failures, verbose) unless failures.empty?

    # Surface the first classified error now that all workers have drained
    # so the CLI sees the documented exit code / JSON payload instead of
    # a silent `status=ok, pages_generated=0`.
    if err = classified_error
      raise err
    end

    # Generic exceptions (Crystal-level bugs, non-Crinja crashes) used to
    # slip through here — workers logged them to `failures`, but with no
    # classified error to raise the build returned its success count and
    # the CLI happily printed `Build complete! Generated 2 pages` even
    # when 9 pages crashed. Promote the first such failure to a
    # `HWARO_E_TEMPLATE` so the build fails loud (#490).
    unless failures.empty?
      first = failures.first
      raise Hwaro::HwaroError.new(
        code: Hwaro::Errors::HWARO_E_TEMPLATE,
        message: "Render failed for #{failures.size} page(s); first failure on #{first[:page_path]}: #{first[:message]}",
      )
    end

    count
  end

  # Collapse identical errors raised across many pages (typical of a
  # broken shared template) into a single summary line, preserving the
  # full page list. `--verbose` opts back into per-page detail.
  private def report_render_failures(
    failures : Array(NamedTuple(page_path: String, message: String)),
    verbose : Bool,
  )
    if verbose
      failures.each do |f|
        Logger.error "Parallel render failed for #{f[:page_path]}: #{f[:message]}"
      end
      return
    end

    grouped = failures.group_by { |f| render_error_signature(f[:message]) }
    grouped.each do |signature, group|
      if group.size == 1
        Logger.error "Render failed for #{group.first[:page_path]}: #{group.first[:message]}"
      else
        Logger.error "Render failed for #{group.size} pages: #{signature}"
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
    count = 0
    safe = site.config.markdown.safe
    pages.each do |page|
      page_start = profiler ? Time.instant : nil
      render_page(page, site, templates, output_dir, minify, highlight, safe, verbose, global_vars, error_overlay: error_overlay, profiler: profiler)
      if profiler && page_start
        elapsed_ms = (Time.instant - page_start).total_milliseconds
        template_name = determine_template(page, templates, site)
        profiler.record_template(template_name, page.content.bytesize.to_i64, elapsed_ms)
      end
      source_path = File.join("content", page.path)
      output_path = get_output_path(page, output_dir)
      cache.update(source_path, output_path)
      count += 1
    end
    count
  end

  private def render_page(
    page : Models::Page,
    site : Models::Site,
    templates : Hash(String, String),
    output_dir : String,
    minify : Bool,
    highlight : Bool = true,
    safe : Bool = false,
    verbose : Bool = false,
    global_vars : Hash(String, Crinja::Value)? = nil,
    crinja_env_override : Crinja? = nil,
    template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
    error_overlay : Bool = false,
    profiler : Profiler? = nil,
  )
    return unless page.render

    # Clear warnings from previous renders (important for incremental rebuilds)
    page.build_warnings.clear

    # Handle redirect_to for pages AND sections
    if page.has_redirect?
      generate_redirect_page(page, output_dir, verbose)
      generate_aliases(page, site, output_dir, verbose)
      return
    end

    # Only build shortcode context and process shortcodes if content actually
    # contains shortcode syntax ({{ or {%).  This avoids the expensive
    # build_template_variables call for the majority of pages that have no
    # shortcodes.
    shortcode_results = {} of String => String
    raw = page.raw_content
    # Use accurate fence + inline-code aware pre-filter instead of naive includes?.
    # This is the main D2 optimization for the shortcode hot path (#562):
    # documentation pages full of example syntax no longer pay the cost of
    # build_template_variables + full shortcode processing.
    has_shortcodes = content_may_contain_shortcodes?(raw)
    warn_hugo_shortcode_syntax(raw, page.path) if raw.includes?("{{<")
    shortcode_context : Hash(String, Crinja::Value)? = nil

    processed_content = if has_shortcodes
                          shortcode_context = build_template_variables(page, site, "", "", "", global_vars: global_vars)
                          process_shortcodes_jinja(raw, templates, shortcode_context, shortcode_results,
                            crinja_env_override: crinja_env_override, template_cache_override: template_cache_override)
                        else
                          raw
                        end

    lazy_loading = site.config.markdown.lazy_loading
    emoji = site.config.markdown.emoji

    # Use anchor links if enabled
    md_config = site.config.markdown
    md_start = profiler ? Time.instant : nil
    md_input_bytes = processed_content.bytesize.to_i64
    html_content, toc_headers = if page.insert_anchor_links
                                  Processor::Markdown.render_with_anchors(processed_content, highlight, safe, "after", lazy_loading, emoji, markdown_config: md_config)
                                else
                                  Processor::Markdown.render(processed_content, highlight, safe, lazy_loading, emoji, markdown_config: md_config)
                                end
    if profiler && md_start
      md_elapsed = (Time.instant - md_start).total_milliseconds
      profiler.record_markdown(page.path, md_input_bytes, md_elapsed)
    end

    # Replace shortcode placeholders with their rendered HTML content
    html_content = replace_shortcode_placeholders(html_content, shortcode_results)

    # Resolve internal @/ links to actual page URLs
    if pages_by_path = @pages_by_path
      html_content = Content::Processors::InternalLinkResolver.resolve(html_content, pages_by_path, page.path, site.config.base_url)
    end

    # Prefix plain root-relative content links (e.g. `[Posts](/posts/)`) with the
    # base_url path so they resolve under a subpath deploy. No-op on root deploys;
    # also keeps RSS `<content:encoded>` and the search index subpath-correct
    # because both reuse `page.content` set below.
    html_content = Content::Processors::InternalLinkResolver.prefix_root_relative_links(html_content, site.config.base_url)

    # Make content images responsive: when image_processing generated width
    # variants for an <img>, add srcset/sizes so browsers pick an appropriate
    # size instead of always loading the full-resolution source.
    html_content = apply_responsive_images(html_content, page, site.config)

    # Store rendered HTML in page.content for reuse by Feed/Search generators
    # (avoids expensive re-rendering of Markdown in Generate phase)
    page.content = html_content

    # Only expose TOC data when page.toc is enabled
    if page.toc && !toc_headers.empty?
      toc_html = generate_toc_html(toc_headers)
    else
      toc_html = ""
      toc_headers = [] of Models::TocHeader
    end

    template_name = determine_template(page, templates, site)
    template_content = templates[template_name]? || templates["page"]?
    Logger.debug "Rendering #{page.path} (section=#{page.section.empty? ? "<root>" : page.section}, index=#{page.is_index}) using template '#{template_name}'" if verbose

    # Handle section pages with pagination
    if (template_name == "section" || page.template == "section") && page.is_a?(Models::Section)
      render_section_with_pagination(page.as(Models::Section), site, templates, template_content, output_dir, minify, html_content, toc_html, toc_headers, verbose, global_vars,
        crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, error_overlay: error_overlay)
    else
      section_list_html = ""

      final_html = if template_content
                     apply_template(template_content, html_content, page, site, section_list_html, toc_html, templates, toc_headers, global_vars: global_vars,
                       crinja_env_override: crinja_env_override, template_cache_override: template_cache_override,
                       prebuilt_vars: shortcode_context)
                   else
                     msg = "No template found for #{page.path}. Using raw content."
                     Logger.warn "#{msg}"
                     page.build_warnings << msg unless page.build_warnings.includes?(msg)
                     html_content
                   end

      if error_overlay && !page.build_warnings.empty?
        final_html = inject_error_overlay(final_html, page.build_warnings)
      end

      final_html = minify_html(final_html) if minify

      write_output(page, output_dir, final_html, verbose)
    end

    generate_aliases(page, site, output_dir, verbose)
  end

  private def generate_redirect_page(
    page : Models::Page,
    output_dir : String,
    verbose : Bool = false,
  )
    redirect_url = page.redirect_to
    return unless redirect_url

    url_path = Utils::PathUtils.sanitize_path(page.url.lchop("/"))
    candidate = File.join(output_dir, url_path, "index.html")
    output_path = Utils::OutputGuard.safe_output_path(candidate, output_dir)
    unless output_path
      Logger.warn "Skipping redirect outside output directory: #{candidate}"
      return
    end

    ensure_dir(Path[output_path].dirname.to_s)
    File.write(output_path, Utils::RedirectHtml.full_redirect(redirect_url))
    Logger.action :create, output_path if verbose
  end

  private def render_section_with_pagination(
    section : Models::Section,
    site : Models::Site,
    templates : Hash(String, String),
    template_content : String?,
    output_dir : String,
    minify : Bool,
    html_content : String,
    toc_html : String,
    toc_headers : Array(Models::TocHeader) = [] of Models::TocHeader,
    verbose : Bool = false,
    global_vars : Hash(String, Crinja::Value)? = nil,
    crinja_env_override : Crinja? = nil,
    template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
    error_overlay : Bool = false,
  )
    # Get pages in this section using the site utility method
    # Note: sorting is handled by Paginator.paginate (uses section.sort_by setting)
    section_name = Path[section.path].dirname
    section_name = "" if section_name == "."
    section_pages = site.pages_for_section(section_name, section.language)

    # Create paginator and render
    paginator = Content::Pagination::Paginator.new(site.config)
    pagination_result = paginator.paginate(section, section_pages)
    renderer = Content::Pagination::Renderer.new(site.config)

    pagination_result.paginated_pages.each do |paginated_page|
      section_list_html = renderer.render_section_list(paginated_page)
      pagination_nav_html = renderer.render_pagination_nav(paginated_page)
      pagination_seo_links = renderer.render_seo_links(paginated_page)

      # Use the correct URL for each paginated page during rendering (important for SEO tags, nav, etc.)
      base = section.url.rstrip("/")
      current_url = if paginated_page.page_number == 1
                      "#{base}/"
                    else
                      "#{base}/#{section.paginate_path}/#{paginated_page.page_number}/"
                    end

      final_html = if template_content
                     apply_template(template_content, html_content, section, site, section_list_html, toc_html, templates, toc_headers, pagination_nav_html, current_url, paginated_page, global_vars,
                       crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, pagination_seo_links: pagination_seo_links)
                   else
                     msg = "No template found for #{section.path}. Using raw content."
                     Logger.warn "#{msg}"
                     section.build_warnings << msg unless section.build_warnings.includes?(msg)
                     html_content
                   end

      if error_overlay && !section.build_warnings.empty?
        final_html = inject_error_overlay(final_html, section.build_warnings)
      end

      final_html = minify_html(final_html) if minify

      # Write output - first page uses section URL, subsequent pages use /page/N/
      if paginated_page.page_number == 1
        write_output(section, output_dir, final_html, verbose)
      else
        write_paginated_output(section, paginated_page.page_number, output_dir, final_html, verbose, section.paginate_path)
      end
    end
  end

  private def write_paginated_output(page : Models::Page, page_number : Int32, output_dir : String, content : String, verbose : Bool, paginate_path : String = "page")
    url_path = Utils::PathUtils.sanitize_path(page.url.lchop("/").rstrip("/"))
    output_path = File.join(output_dir, url_path, paginate_path, page_number.to_s, "index.html")
    return unless Utils::OutputGuard.within_output_dir?(output_path, output_dir)

    ensure_dir(Path[output_path].dirname.to_s)
    File.write(output_path, content)
    Logger.action :create, output_path if verbose
  end

  private def determine_template(page : Models::Page, templates : Hash(String, String), site : Models::Site) : String
    if custom = page.template
      return custom if templates.has_key?(custom)
      msg = "Custom template '#{custom}' not found for #{page.path}. Falling back to default."
      # determine_template runs again after render for profiler bookkeeping;
      # only log/record the first time so the warning isn't printed twice.
      unless page.build_warnings.includes?(msg)
        Logger.warn "#{msg}"
        page.build_warnings << msg
      end
    end

    if page.is_a?(Models::Section)
      return "section" if templates.has_key?("section")
    end

    if page.is_index && page.section.empty? && templates.has_key?("index")
      return "index"
    end

    # Inherit the parent section's default template (`page_template`) for regular
    # child pages that did not set an explicit `template`. Sections render with
    # their own "section" template (handled above), so they are excluded here.
    unless page.is_a?(Models::Section)
      if section = site.section_for(page.section, page.language)
        if pt = section.effective_page_template
          return pt if templates.has_key?(pt)
        end
      end
    end

    "page"
  end

  private def generate_aliases(page : Models::Page, site : Models::Site, output_dir : String, verbose : Bool)
    page.aliases.each do |alias_path|
      alias_clean = Utils::PathUtils.sanitize_path(alias_path.lchop("/"))
      # An alias that already names an HTML file (`/legacy.html`,
      # `/old/index.html`) is written to that exact path; only "pretty"
      # aliases (`/old/`) get an `index.html` appended. Previously every
      # alias got `/index.html` tacked on, so `/legacy/index.html` became
      # the directory `legacy/index.html/` with an `index.html` inside.
      dest_path = if alias_clean.ends_with?(".html") || alias_clean.ends_with?(".htm")
                    File.join(output_dir, alias_clean)
                  else
                    File.join(output_dir, alias_clean, "index.html")
                  end
      next unless Utils::OutputGuard.within_output_dir?(dest_path, output_dir)

      ensure_dir(File.dirname(dest_path))

      # Prefix the page's root-relative URL with `base_url`'s path component so
      # the redirect still resolves when the site is deployed under a subpath
      # (e.g. GitHub Pages project sites at `/repo/`). `page.url` may arrive
      # without a leading slash (see sitemap), so normalize before prefixing;
      # `with_base_path` is a no-op for a domain-root deployment.
      target = page.url.starts_with?('/') ? page.url : "/#{page.url}"
      redirect_url = site.config.with_base_path(target)
      File.write(dest_path, Utils::RedirectHtml.simple_redirect(redirect_url))
      Logger.action :create, dest_path, :yellow if verbose
    end
  end

  # Rewrite content <img> tags to add `srcset`/`sizes` when the image has
  # generated width variants (see ImageHooks). Only runs when image_processing
  # is enabled and at least one variant exists. A relative `src` is resolved
  # against the page URL to match the resize map keys (which are site-absolute,
  # e.g. `/posts/foo/photo.png`); absolute `src` is used as-is. External
  # (http/protocol-relative/data:) sources and tags that already carry a
  # `srcset` (e.g. emitted by the `resize_image()` helper) are left untouched.
  IMG_TAG_RE = /<img\b[^>]*>/
  IMG_SRC_RE = /\ssrc\s*=\s*("([^"]*)"|'([^']*)')/

  private def apply_responsive_images(html : String, page : Models::Page, config : Models::Config) : String
    return html unless config.image_processing.enabled
    return html unless html.includes?("<img")

    # Read-only view: apply_responsive_images only looks up keys, never
    # mutates. Using the live map avoids a per-page full-map copy plus a
    # contended global mutex on the parallel render hot path.
    resize_map = Content::Hooks::ImageHooks.resize_map_readonly
    return html if resize_map.empty?

    html.gsub(IMG_TAG_RE) do |tag|
      next tag if tag.includes?("srcset")
      m = tag.match(IMG_SRC_RE)
      next tag unless m
      src = m[2]? || m[3]? || ""
      next tag if src.empty?
      next tag if src.starts_with?("http://") || src.starts_with?("https://") ||
                  src.starts_with?("//") || src.starts_with?("data:")

      key = if src.starts_with?("/")
              src
            else
              base = page.url.ends_with?("/") ? page.url : "#{page.url}/"
              "#{base}#{src}".gsub("//", "/")
            end

      widths = resize_map[key]?
      next tag unless widths
      next tag if widths.empty?

      srcset = widths.to_a.sort_by { |(w, _)| w }.map { |(w, url)| "#{url} #{w}w" }.join(", ")
      additions = %( srcset="#{srcset}")
      additions += %( sizes="100vw") unless tag =~ /\ssizes\s*=/
      tag.sub("<img", "<img#{additions}")
    end
  end

  private def generate_toc_html(headers : Array(Models::TocHeader)) : String
    return "" if headers.empty?

    String.build do |str|
      str << "<ul>"
      headers.each do |header|
        str << "<li><a href=\"#{header.permalink}\">#{header.title}</a>"
        unless header.children.empty?
          str << generate_toc_html(header.children)
        end
        str << "</li>"
      end
      str << "</ul>"
    end
  end

  # Convert TocHeader tree to Crinja-compatible array for toc_obj.headers.
  private def toc_headers_to_crinja(headers : Array(Models::TocHeader)) : Array(Crinja::Value)
    headers.map do |h|
      Crinja::Value.new({
        "level"     => Crinja::Value.new(h.level),
        "id"        => Crinja::Value.new(h.id),
        "title"     => Crinja::Value.new(h.title),
        "permalink" => Crinja::Value.new(h.permalink),
        "children"  => Crinja::Value.new(toc_headers_to_crinja(h.children)),
      })
    end
  end

  # Inject a dismissible error overlay into the HTML page for development feedback.
  # The overlay shows build warnings collected during rendering so developers
  # can spot template issues directly in the browser.
  private def inject_error_overlay(html : String, warnings : Array(String)) : String
    return html if warnings.empty?

    escaped_warnings = warnings.map { |w| HTML.escape(w) }
    list_items = escaped_warnings.map { |w|
      "<li style=\"margin-bottom:8px;line-height:1.5;\">#{w}</li>"
    }.join("\n")

    overlay = <<-OVERLAY
      <div id="hwaro-error-overlay" style="position:fixed;inset:0;z-index:99999;background:rgba(0,0,0,0.65);display:flex;align-items:center;justify-content:center;font-family:-apple-system,BlinkMacSystemFont,sans-serif;">
        <div style="background:#1e1e2e;color:#cdd6f4;border-radius:8px;padding:24px;max-width:720px;width:90%;max-height:80vh;overflow-y:auto;box-shadow:0 8px 32px rgba(0,0,0,0.4);">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
            <h2 style="margin:0;color:#f38ba8;font-size:18px;">Build Warning</h2>
            <button onclick="document.getElementById('hwaro-error-overlay').remove()" style="background:none;border:none;color:#cdd6f4;font-size:24px;cursor:pointer;padding:0 4px;">&times;</button>
          </div>
          <ul style="margin:0;padding:0 0 0 20px;">
            #{list_items}
          </ul>
        </div>
      </div>
      OVERLAY

    # Inject before </body> if present, otherwise append
    if idx = html.rindex("</body>")
      html.insert(idx, overlay)
    else
      html + overlay
    end
  end

  def apply_template(
    template : String,
    content : String,
    page : Models::Page,
    site : Models::Site,
    section_list : String,
    toc : String,
    templates : Hash(String, String),
    toc_headers : Array(Models::TocHeader) = [] of Models::TocHeader,
    pagination : String = "",
    page_url_override : String? = nil,
    paginator : Content::Pagination::PaginatedPage? = nil,
    global_vars : Hash(String, Crinja::Value)? = nil,
    crinja_env_override : Crinja? = nil,
    template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
    pagination_seo_links : String = "",
    prebuilt_vars : Hash(String, Crinja::Value)? = nil,
  ) : String
    # Use per-worker env when provided (parallel path), otherwise shared env
    env = crinja_env_override || crinja_env
    cache = template_cache_override || @compiled_templates_cache

    # Build template variables — reuse prebuilt_vars if available (shortcode path)
    vars = if pv = prebuilt_vars
             update_content_vars(pv, content, section_list, toc, toc_headers, pagination, pagination_seo_links)
             pv
           else
             build_template_variables(page, site, content, section_list, toc, toc_headers, pagination, page_url_override, paginator, global_vars, pagination_seo_links: pagination_seo_links)
           end

    begin
      # Process shortcodes in template directly (skip per-line fence detection
      # since templates don't contain markdown fenced code blocks)
      processed_template = process_shortcodes_in_text(template, templates, vars,
        crinja_env_override: crinja_env_override, template_cache_override: template_cache_override)

      # Cache compiled Crinja templates by content hash.
      # Most pages share the same base template string, so this avoids
      # re-parsing the template AST on every page render.
      cache_key = processed_template.hash
      crinja_template = if cached = cache[cache_key]?
                          @cache_manager.record_hit("compiled_templates")
                          cached
                        else
                          @cache_manager.record_miss("compiled_templates")
                          compiled = env.from_string(processed_template)
                          cache[cache_key] = compiled
                          compiled
                        end
      crinja_template.render(vars)
    rescue ex : Crinja::Error
      # Classify as a template error so `hwaro build --json` surfaces a
      # stable HWARO_E_TEMPLATE code (exit 4). Previously these errors
      # were downgraded to build warnings, which hid misconfigured
      # templates from scripts and CI.
      raise Hwaro::HwaroError.new(
        code: Hwaro::Errors::HWARO_E_TEMPLATE,
        message: "Template error for #{page.path}: #{ex.message}",
        cause: ex,
      )
    end
  end

  # Update only content-dependent vars in a pre-built template variables hash.
  # Used to avoid rebuilding the entire variables hash when only content/toc/pagination change
  # (e.g., reusing shortcode context for final template rendering).
  private def update_content_vars(
    vars : Hash(String, Crinja::Value),
    content : String,
    section_list : String,
    toc : String,
    toc_headers : Array(Models::TocHeader),
    pagination : String,
    pagination_seo_links : String,
  )
    vars["content"] = Crinja::Value.new(content)
    vars["section_list"] = Crinja::Value.new(section_list)
    vars["toc"] = Crinja::Value.new(toc)
    vars["toc_obj"] = Crinja::Value.new({
      "html"    => Crinja::Value.new(toc),
      "headers" => Crinja::Value.new(toc_headers_to_crinja(toc_headers)),
    })
    vars["pagination"] = Crinja::Value.new(pagination)
    vars["pagination_seo_links"] = Crinja::Value.new(pagination_seo_links)

    # NOTE: pagination_obj is not updated here because its fields (URLs, page
    # numbers, booleans) are stable across the shortcode pre-render and final
    # render passes. The html field is set from the same pagination string
    # that was used when build_template_variables originally created it.
  end

  # Unified Page→Crinja::Value conversion with per-page caching.
  # Avoids repeated conversion of the same Page across build_global_vars,
  # section page lists, and paginator rendering.  The cached value contains
  # a superset of fields needed by all consumers.
  private def cached_page_crinja_value(p : Models::Page, default_language : String) : Crinja::Value
    @crinja_cache_mutex.synchronize do
      if cached = @page_crinja_value_cache[p.path]?
        @cache_manager.record_hit("page_crinja_value")
        next cached.as(Crinja::Value)
      end
      @cache_manager.record_miss("page_crinja_value")
      begin
        translations = p.translations.map do |t|
          Crinja::Value.new({
            "code"       => Crinja::Value.new(t.code),
            "url"        => Crinja::Value.new(t.url),
            "title"      => Crinja::Value.new(t.title),
            "is_current" => Crinja::Value.new(t.is_current),
            "is_default" => Crinja::Value.new(t.is_default),
          })
        end
        val = Crinja::Value.new({
          "path"         => Crinja::Value.new(p.path),
          "title"        => Crinja::Value.new(p.title),
          "description"  => Crinja::Value.new(p.description || ""),
          "url"          => Crinja::Value.new(p.url),
          "date"         => Crinja::Value.new(p.date.try(&.to_s("%Y-%m-%d")) || ""),
          "image"        => Crinja::Value.new(p.image || ""),
          "section"      => Crinja::Value.new(p.section),
          "draft"        => Crinja::Value.new(p.draft),
          "toc"          => Crinja::Value.new(p.toc),
          "render"       => Crinja::Value.new(p.render),
          "is_index"     => Crinja::Value.new(p.is_index),
          "generated"    => Crinja::Value.new(p.generated),
          "in_sitemap"   => Crinja::Value.new(p.in_sitemap),
          "language"     => Crinja::Value.new(p.language || default_language),
          "translations" => Crinja::Value.new(translations),
          "weight"       => Crinja::Value.new(p.weight),
          "summary"      => Crinja::Value.new(p.summary_html || p.effective_summary || ""),
          "word_count"   => Crinja::Value.new(p.word_count),
          "reading_time" => Crinja::Value.new(p.reading_time),
          # Leaf fields a full page_obj also exposes, so iterated lists
          # (section.pages / site.pages / term.pages) match the documented Page
          # shape. Only PAGE-LOCAL fields are cached here. `permalink` is omitted
          # (computed lazily per-page during render), and `series_index` is
          # omitted because it is recomputed from OTHER pages in the series — a
          # cross-page value @page_crinja_value_cache cannot keep fresh on the
          # incremental `serve` path, where only the changed page is invalidated.
          "updated"         => Crinja::Value.new(p.updated.try(&.to_s("%Y-%m-%d")) || ""),
          "in_search_index" => Crinja::Value.new(p.in_search_index),
          "series"          => Crinja::Value.new(p.series || ""),
          "tags"            => Crinja::Value.new(p.tags.map { |t| Crinja::Value.new(t) }),
          "authors"         => Crinja::Value.new(p.authors.map { |a| Crinja::Value.new(a) }),
          "taxonomies"      => taxonomies_crinja_for(p),
          "assets"          => Crinja::Value.new(p.assets.map { |a| Crinja::Value.new(a) }),
          "extra"           => Crinja::Value.new(
            p.extra.each_with_object({} of String => Crinja::Value) { |(k, v), h|
              h[k] = Utils::CrinjaUtils.from_extra(v)
            }),
        })
        @page_crinja_value_cache[p.path] = val
        val
      end
    end
  end

  # Per-page taxonomy terms as `{ name => [terms] }` so templates can read
  # `page.taxonomies.tech` (or iterate `w.taxonomies.<name>` in section
  # lists). `tags`/`authors` live on dedicated model fields rather than in
  # `Page#taxonomies`, so mirror `taxonomy_values`' special-casing — an
  # explicit `[taxonomies] tags = […]` entry still wins.
  private def taxonomies_crinja_for(p : Models::Page) : Crinja::Value
    h = p.taxonomies.each_with_object({} of String => Crinja::Value) do |(k, v), acc|
      acc[k] = Crinja::Value.new(v.map { |t| Crinja::Value.new(t) })
    end
    h["tags"] = Crinja::Value.new(p.tags.map { |t| Crinja::Value.new(t) }) unless h.has_key?("tags")
    h["authors"] = Crinja::Value.new(p.authors.map { |a| Crinja::Value.new(a) }) unless h.has_key?("authors")
    Crinja::Value.new(h)
  end

  # Convert a Page to a Crinja::Value hash for use in section page lists and paginator.
  # Delegates to the cached unified conversion to avoid redundant allocations.
  private def page_to_crinja_list_value(p : Models::Page, default_language : String) : Crinja::Value
    cached_page_crinja_value(p, default_language)
  end

  # Get (or build and cache) the sorted Crinja::Value array for a section's pages.
  # The cache stores the full sorted list; callers should filter current_page themselves if needed.
  private def cached_section_pages_crinja(
    section_name : String,
    language : String?,
    site : Models::Site,
  ) : Array(Crinja::Value)
    cache_key = "#{section_name}:#{language}"
    @crinja_cache_mutex.synchronize do
      if cached = @section_pages_crinja_cache[cache_key]?
        @cache_manager.record_hit("section_pages_crinja")
        next cached.as(Array(Crinja::Value))
      end
      @cache_manager.record_miss("section_pages_crinja")
      begin
        pages = site.pages_for_section(section_name, language)

        # Use section's sort_by setting if available, otherwise sort by title
        section = site.section_for(section_name, language)
        sort_by = section.try(&.sort_by) || "title"
        reverse = section.try(&.reverse) || false
        pages = Utils::SortUtils.sort_pages(pages, sort_by, reverse)

        default_lang = site.config.default_language
        arr = pages.map { |p| page_to_crinja_list_value(p, default_lang) }
        @section_pages_crinja_cache[cache_key] = arr
        arr
      end
    end
  end

  # Build a lookup map from content path → Page for internal link resolution.
  private def build_pages_by_path(site : Models::Site) : Hash(String, Models::Page)
    map = {} of String => Models::Page
    site.pages.each { |p| map[p.path] ||= p }
    site.sections.each { |s| map[s.path] ||= s }
    map
  end

  # Public accessor so callers that render many pages through one Builder
  # (e.g. taxonomy generation) can compute the shared, site-wide template vars
  # ONCE and thread them into apply_template, instead of rebuilding the whole
  # set — iterating every page/section and re-hashing static assets — per page.
  def global_template_vars(site : Models::Site, cache_busting : Bool = true) : Hash(String, Crinja::Value)
    build_global_vars(site, cache_busting)
  end

  private def build_global_vars(site : Models::Site, cache_busting : Bool = true) : Hash(String, Crinja::Value)
    config = site.config
    vars = {} of String => Crinja::Value

    # Hidden variables for get_page/get_section/get_taxonomy functions
    # These are prefixed with __ to indicate they're internal
    default_lang = config.default_language
    all_pages_array = Array(Crinja::Value).new(site.pages.size)
    pages_by_path = Hash(String, Crinja::Value).new

    site.pages.each do |p|
      # Reuse cached per-page Crinja::Value to avoid redundant allocations
      # (same cache is used by section page lists and paginator)
      page_val = cached_page_crinja_value(p, default_lang)
      all_pages_array << page_val

      # Build O(1) lookup map
      # Use ||= to preserve first-match behavior (consistent with linear search)
      pages_by_path[p.path] ||= page_val
      pages_by_path[p.url] ||= page_val

      # Handle URL without trailing slash for flexible matching
      if p.url.ends_with?("/") && p.url.size > 1
        pages_by_path[p.url.rstrip("/")] ||= page_val
      end
    end

    vars["__all_pages__"] = Crinja::Value.new(all_pages_array)
    vars["__pages_by_path__"] = Crinja::Value.new(pages_by_path)

    all_sections_array = [] of Crinja::Value
    sections_by_key = {} of String => Crinja::Value

    # `Section#pages` is the model property and is *not* populated by the
    # build pipeline — it stays `[]`. The live page list lives in
    # `site.pages_for_section(name, language)`. Compute the page array
    # once per section so `get_section(...).pages` and `.pages_count`
    # match what `section.html` would render. Also stash the live result
    # so the second pass can copy `pages_count` into each parent's
    # subsection entry.
    section_data_by_path = {} of String => {pages: Array(Crinja::Value), hash: Hash(String, Crinja::Value)}

    site.sections.each do |s|
      # Reuse the sorted-per-sort_by cached list so `get_section(...).pages`
      # returns the same order as `section.pages` inside section templates —
      # the raw `pages_for_section` list is discovery-ordered, which made a
      # homepage "featured" loop disagree with the section listing.
      section_pages = cached_section_pages_crinja(s.section, s.language, site)
      hash = {
        "path"               => Crinja::Value.new(s.path),
        "name"               => Crinja::Value.new(s.section),
        "title"              => Crinja::Value.new(s.title),
        "description"        => Crinja::Value.new(s.description || ""),
        "url"                => Crinja::Value.new(s.url),
        "date"               => Crinja::Value.new(s.date.try(&.to_s("%Y-%m-%d")) || ""),
        "draft"              => Crinja::Value.new(s.draft),
        "is_index"           => Crinja::Value.new(s.is_index),
        "language"           => Crinja::Value.new(s.language || default_lang),
        "weight"             => Crinja::Value.new(s.weight),
        "transparent"        => Crinja::Value.new(s.transparent),
        "sort_by"            => Crinja::Value.new(s.sort_by || ""),
        "reverse"            => Crinja::Value.new(s.reverse || false),
        "paginate"           => Crinja::Value.new(s.paginate || 0),
        "pagination_enabled" => Crinja::Value.new(s.pagination_enabled),
        "pages"              => Crinja::Value.new(section_pages),
        "pages_count"        => Crinja::Value.new(section_pages.size),
        "assets"             => Crinja::Value.new(s.assets.map { |a| Crinja::Value.new(a) }),
        "subsections"        => Crinja::Value.new([] of Crinja::Value),
      } of String => Crinja::Value
      section_val = Crinja::Value.new(hash)
      section_data_by_path[s.path] = {pages: section_pages, hash: hash}
      all_sections_array << section_val

      # Build O(1) lookup map for get_section() — match by path, name, and URL
      sections_by_key[s.path] ||= section_val
      sections_by_key[s.section] ||= section_val unless s.section.empty?
      sections_by_key[s.url] ||= section_val
    end

    # Second pass: link each section's `subsections` to its children so
    # `get_section("posts").subsections` returns the same data shape as
    # the parent. Iterates `site.sections` (not `site.pages`) because
    # only Section objects carry the `subsections` chain.
    site.sections.each do |s|
      next if s.subsections.empty?
      data = section_data_by_path[s.path]?
      next unless data
      subs_array = data[:hash]["subsections"].raw.as(Array)
      s.subsections.each do |child|
        if child_data = section_data_by_path[child.path]?
          subs_array << Crinja::Value.new(child_data[:hash])
        end
      end
    end

    vars["__all_sections__"] = Crinja::Value.new(all_sections_array)
    vars["__sections_by_key__"] = Crinja::Value.new(sections_by_key)

    # Build taxonomies hash for get_taxonomy function. Term slugs are
    # disambiguated with the SAME helper the taxonomy generator uses, so a
    # collision (e.g. "C++"/"C#" → "c") yields unique slugs that match the
    # written term-page paths. __taxonomy_slugs__ exposes the term→slug map so
    # get_taxonomy_url() can resolve a single term without recomputing the map.
    multilingual = config.multilingual?
    taxonomies_hash = {} of String => Crinja::Value
    taxonomy_slugs = {} of String => Crinja::Value
    site.taxonomies.each do |name, terms|
      # Disambiguate over the SAME term set the taxonomy generator uses to write
      # pages — build_taxonomy_index counts only non-draft, non-generated pages.
      # Under `--drafts`, the render-phase site.taxonomies (rebuild_taxonomies)
      # also carries draft-only terms; including them here would let a draft term
      # steal a base slug and shift a published term to a `-N` slug the generator
      # never wrote, breaking its get_taxonomy link. Normal builds are already
      # draft-free, so this filter is a no-op there.
      written_terms = terms.compact_map do |term, term_pages|
        term if term_pages.any? { |p| !p.draft && !p.generated }
      end
      slug_map = Utils::TextUtils.disambiguated_slugs(written_terms)
      term_slug_values = {} of String => Crinja::Value
      terms_array = terms.map do |term, term_pages|
        term_pages_array = term_pages.map do |tp|
          cached_page_crinja_value(tp, default_lang)
        end
        # A ROOT term page (what get_taxonomy_url targets) is written only when
        # the term has a non-draft page in the default language; on a
        # multilingual site a term that exists only in a non-default language
        # gets no root page, so exposing its disambiguated `-N` slug would point
        # at a 404. Only publish disambiguated slugs for terms with a root page;
        # others fall back to safe_slugify (the pre-centralization behavior).
        has_root = term_pages.any? do |p|
          next false if p.draft || p.generated
          !multilingual || (p.language || default_lang) == default_lang
        end
        slug = (has_root ? slug_map[term]? : nil) || Utils::TextUtils.safe_slugify(term)
        term_slug_values[term] = Crinja::Value.new(slug) if has_root
        Crinja::Value.new({
          "name"  => Crinja::Value.new(term),
          "slug"  => Crinja::Value.new(slug),
          "pages" => Crinja::Value.new(term_pages_array),
          "count" => Crinja::Value.new(term_pages.size),
        })
      end
      taxonomies_hash[name] = Crinja::Value.new({
        "name"  => Crinja::Value.new(name),
        "items" => Crinja::Value.new(terms_array),
      })
      taxonomy_slugs[name] = Crinja::Value.new(term_slug_values)
    end
    vars["__taxonomies__"] = Crinja::Value.new(taxonomies_hash)
    vars["__taxonomy_slugs__"] = Crinja::Value.new(taxonomy_slugs)

    # Site object with full data
    site_obj = {
      "title"       => Crinja::Value.new(config.title),
      "description" => Crinja::Value.new(config.description || ""),
      "base_url"    => Crinja::Value.new(config.base_url),
      "pages"       => Crinja::Value.new(all_pages_array),
      "sections"    => Crinja::Value.new(all_sections_array),
      "taxonomies"  => Crinja::Value.new(taxonomies_hash),
      "data"        => Crinja::Value.new(site.data),
      "authors"     => Crinja::Value.new(site.authors),
    }
    vars["site"] = Crinja::Value.new(site_obj)

    # Site-wide constant variables — computed once, shared across all pages
    # (These were previously recomputed in build_template_variables for every page)
    vars["site_title"] = Crinja::Value.new(config.title)
    vars["site_description"] = Crinja::Value.new(config.description || "")
    vars["base_url"] = Crinja::Value.new(config.base_url)

    # Cache busting (content hash of local CSS/JS files)
    cache_bust = cache_busting ? compute_cache_bust(config) : ""

    # Highlight tags
    vars["highlight_css"] = Crinja::Value.new(config.highlight.css_tag(cache_bust))
    vars["highlight_js"] = Crinja::Value.new(config.highlight.js_tag(cache_bust))
    vars["highlight_tags"] = Crinja::Value.new(config.highlight.tags(cache_bust))

    # `use_cdn = false` emits <script src="/assets/js/highlight.min.js"> (+ css),
    # but Hwaro doesn't ship those files — if the user hasn't placed them under
    # static/assets/ the references 404 and highlighting silently breaks. Warn
    # once per build (build_global_vars runs once) so it isn't a silent footgun.
    warn_missing_local_highlight_assets(config)

    # Math (KaTeX/MathJax) and Mermaid renderer scripts. When `math = true`
    # or `mermaid = true` is set in config, the markdown processor emits the
    # right wrapper markup but without these script tags the browser sees
    # only literal TeX / DOT source. Templates can pull them in via
    # `{{ math_tags }}` and `{{ mermaid_tags }}`; the default header partials
    # include them so the feature flags work out of the box.
    vars["math_tags"] = Crinja::Value.new(config.markdown.math_tags)
    vars["mermaid_tags"] = Crinja::Value.new(config.markdown.mermaid_tags)

    # Auto includes
    vars["auto_includes_css"] = Crinja::Value.new(config.auto_includes.css_tags(config.base_url, cache_bust))
    vars["auto_includes_js"] = Crinja::Value.new(config.auto_includes.js_tags(config.base_url, cache_bust))
    vars["auto_includes"] = Crinja::Value.new(config.auto_includes.all_tags(config.base_url, cache_bust))

    # JSON-LD: site-wide WebSite and Organization schemas
    vars["jsonld_website"] = Crinja::Value.new(Content::Seo::JsonLd.website(config))
    vars["jsonld_organization"] = Crinja::Value.new(Content::Seo::JsonLd.organization(config, config.og.default_image))

    # Time-related variables (fixed per build, not per page)
    now = Time.local
    vars["current_year"] = Crinja::Value.new(now.year)
    vars["current_date"] = Crinja::Value.new(now.to_s("%Y-%m-%d"))
    vars["current_datetime"] = Crinja::Value.new(now.to_s("%Y-%m-%d %H:%M:%S"))

    # i18n translations (available to {{ "key" | t }} filter)
    unless @i18n_translations.empty?
      i18n_hash = {} of Crinja::Value => Crinja::Value
      @i18n_translations.each do |lang, entries|
        entries_hash = {} of Crinja::Value => Crinja::Value
        entries.each do |key, value|
          entries_hash[Crinja::Value.new(key)] = Crinja::Value.new(value)
        end
        i18n_hash[Crinja::Value.new(lang)] = Crinja::Value.new(entries_hash)
      end
      vars["_i18n_translations"] = Crinja::Value.new(i18n_hash)
    end
    vars["_i18n_default_language"] = Crinja::Value.new(config.default_language)

    vars
  end

  # Public URLs of self-hosted highlight.js assets that are referenced
  # (`[highlight] use_cdn = false`) but missing from `static/`. Empty when the
  # CDN is used, highlighting is disabled, or every asset is present. Hwaro
  # never copies these files itself, so the user is expected to drop them under
  # `static/assets/`; this surfaces the gap instead of shipping 404s.
  def missing_local_highlight_assets(config : Models::Config) : Array(String)
    return [] of String unless config.highlight.enabled
    return [] of String if config.highlight.use_cdn

    missing = [] of String
    css_rel = File.join("static", "assets", "css", "highlight", "#{config.highlight.theme}.min.css")
    js_rel = File.join("static", "assets", "js", "highlight.min.js")
    missing << "/assets/css/highlight/#{config.highlight.theme}.min.css" unless File.exists?(css_rel)
    missing << "/assets/js/highlight.min.js" unless File.exists?(js_rel)
    missing
  end

  private def warn_missing_local_highlight_assets(config : Models::Config)
    missing = missing_local_highlight_assets(config)
    return if missing.empty?

    Logger.warn "[highlight] use_cdn = false but self-hosted asset(s) are missing: " \
                "#{missing.join(", ")}. Syntax highlighting will not load (the references 404). " \
                "Add the highlight.js build under static/ (static/assets/js/highlight.min.js and " \
                "static/assets/css/highlight/#{config.highlight.theme}.min.css), or set [highlight] use_cdn = true."
  end

  # Compute a content-based cache bust hash from local CSS/JS files.
  # Returns an 8-character hex digest, or "" if no local files exist.
  private def compute_cache_bust(config : Models::Config) : String
    has_local_highlight = config.highlight.enabled && !config.highlight.use_cdn
    has_auto_includes = config.auto_includes.enabled && config.auto_includes.dirs.present?

    return "" unless has_local_highlight || has_auto_includes

    digest = Digest::MD5.new

    if has_local_highlight
      css_path = File.join("static", "assets", "css", "highlight", "#{config.highlight.theme}.min.css")
      digest_file(digest, css_path) if File.exists?(css_path)
      js_path = File.join("static", "assets", "js", "highlight.min.js")
      digest_file(digest, js_path) if File.exists?(js_path)
    end

    if has_auto_includes
      config.auto_includes.dirs.each do |dir|
        static_dir = File.join("static", dir)
        next unless Dir.exists?(static_dir)
        Dir.glob(File.join(static_dir, "**", "*.{css,js}")).sort.each do |file|
          digest_file(digest, file)
        end
      end
    end

    digest.hexfinal[0, 8]
  end

  # Stream file contents into digest to avoid loading entire file into memory
  private def digest_file(digest : Digest::MD5, path : String)
    File.open(path, "r") do |io|
      buffer = Bytes.new(8192)
      while (n = io.read(buffer)) > 0
        digest.update(buffer[0, n])
      end
    end
  end

  # Build template variables hash for Crinja
  private def build_template_variables(
    page : Models::Page,
    site : Models::Site,
    content : String,
    section_list : String,
    toc : String,
    toc_headers : Array(Models::TocHeader) = [] of Models::TocHeader,
    pagination : String = "",
    page_url_override : String? = nil,
    paginator : Content::Pagination::PaginatedPage? = nil,
    global_vars : Hash(String, Crinja::Value)? = nil,
    pagination_seo_links : String = "",
  ) : Hash(String, Crinja::Value)
    config = site.config

    # Build page-specific vars into a fresh hash, then merge global_vars
    # at the end.  This is cheaper than global_vars.dup (which copies ~25
    # entries including heavy __all_pages__) because page vars are the
    # smaller set (~50 entries) and we only iterate global_vars once via
    # merge! rather than duplicating it per page.
    vars = {} of String => Crinja::Value

    effective_url = page_url_override || page.url

    # Precompute date strings once to avoid repeated .to_s formatting
    date_str = page.date.try(&.to_s("%Y-%m-%d")) || ""
    updated_str = page.updated.try(&.to_s("%Y-%m-%d")) || ""
    date_crinja = Crinja::Value.new(date_str)

    # Page variables (flat for convenience)
    vars["page_title"] = Crinja::Value.new(page.title)
    vars["page_description"] = Crinja::Value.new(page.description || config.description || "")
    vars["page_url"] = Crinja::Value.new(effective_url)
    vars["page_section"] = Crinja::Value.new(page.section)
    vars["page_date"] = date_crinja
    vars["page_image"] = Crinja::Value.new(page.image || config.og.default_image || "")
    vars["taxonomy_name"] = Crinja::Value.new(page.taxonomy_name || "")
    vars["taxonomy_term"] = Crinja::Value.new(page.taxonomy_term || "")
    default_lang = config.default_language
    page_language = page.language || default_lang
    vars["page_language"] = Crinja::Value.new(page_language)

    # `lang_prefix` is `""` for the default language and `"/<code>"`
    # for every other configured language, so multilingual scaffold
    # templates can write links as `{{ base_url }}{{ lang_prefix }}/posts/`
    # and have them resolve correctly per locale (gh#524).
    lang_prefix = page_language != default_lang && config.multilingual? ? "/#{page_language}" : ""
    vars["lang_prefix"] = Crinja::Value.new(lang_prefix)

    # Generate permalink only if not already set
    page.generate_permalink(config.base_url) unless page.permalink

    # Reuse cached Crinja arrays for tags/authors/assets/extra/translations
    # (avoids per-page .map allocation)
    cached_page_val = cached_page_crinja_value(page, default_lang)
    cached_raw = cached_page_val.raw.as(Hash)
    tags_crinja = cached_raw["tags"].as(Crinja::Value)
    authors_crinja = cached_raw["authors"].as(Crinja::Value)
    assets_crinja = cached_raw["assets"].as(Crinja::Value)
    extra_crinja = cached_raw["extra"].as(Crinja::Value)
    translations_crinja = cached_raw["translations"].as(Crinja::Value)
    vars["page_translations"] = translations_crinja

    # Reuse cached Crinja::Value for lower/higher pages
    lower_obj = page.lower.try { |l| cached_page_crinja_value(l, default_lang) }
    higher_obj = page.higher.try { |h| cached_page_crinja_value(h, default_lang) }

    # Build ancestors array (cached per section+language — pages in the same
    # section AND language share ancestors). The language is part of the key
    # because a multilingual section has per-language ancestors; omitting it
    # served whichever language rendered first to every language (mirrors the
    # section_pages cache key).
    ancestors_cache_key = "#{page.section}:#{page.language}"
    ancestors_array = @crinja_cache_mutex.synchronize do
      if cached = @ancestors_crinja_cache[ancestors_cache_key]?
        @cache_manager.record_hit("ancestors_crinja")
        next cached.as(Array(Crinja::Value))
      end
      @cache_manager.record_miss("ancestors_crinja")
      arr = page.ancestors.map do |ancestor|
        Crinja::Value.new({
          "title" => Crinja::Value.new(ancestor.title),
          "url"   => Crinja::Value.new(ancestor.url),
        })
      end
      @ancestors_crinja_cache[ancestors_cache_key] = arr
      arr
    end

    # Page object with all properties
    page_obj = {
      "title"        => Crinja::Value.new(page.title),
      "description"  => Crinja::Value.new(page.description || ""),
      "url"          => Crinja::Value.new(effective_url),
      "section"      => Crinja::Value.new(page.section),
      "date"         => date_crinja,
      "updated"      => Crinja::Value.new(updated_str),
      "image"        => Crinja::Value.new(page.image || ""),
      "draft"        => Crinja::Value.new(page.draft),
      "toc"          => Crinja::Value.new(page.toc),
      "render"       => Crinja::Value.new(page.render),
      "is_index"     => Crinja::Value.new(page.is_index),
      "generated"    => Crinja::Value.new(page.generated),
      "in_sitemap"   => Crinja::Value.new(page.in_sitemap),
      "language"     => Crinja::Value.new(page_language),
      "translations" => translations_crinja,
      # New properties
      "authors"         => authors_crinja,
      "tags"            => tags_crinja,
      "taxonomies"      => cached_raw["taxonomies"].as(Crinja::Value),
      "assets"          => assets_crinja,
      "extra"           => extra_crinja,
      "summary"         => Crinja::Value.new(page.summary_html || page.effective_summary || ""),
      "word_count"      => Crinja::Value.new(page.word_count),
      "reading_time"    => Crinja::Value.new(page.reading_time),
      "permalink"       => Crinja::Value.new(page.permalink || ""),
      "weight"          => Crinja::Value.new(page.weight),
      "in_search_index" => Crinja::Value.new(page.in_search_index),
      "lower"           => lower_obj || Crinja::Value.new(nil),
      "higher"          => higher_obj || Crinja::Value.new(nil),
      "ancestors"       => Crinja::Value.new(ancestors_array),
      "series"          => Crinja::Value.new(page.series || ""),
      "series_index"    => Crinja::Value.new(page.series_index),
      "series_pages"    => @crinja_cache_mutex.synchronize {
        # Skip tracking for pages without series to avoid inflating miss counts
        unless page.series
          next Crinja::Value.new([] of Crinja::Value)
        end
        cached_series = page.series.try { |s| @series_crinja_cache[s]? }
        if cached_series
          @cache_manager.record_hit("series_crinja")
          next cached_series
        end
        @cache_manager.record_miss("series_crinja")
        val = Crinja::Value.new(page.series_pages.map { |sp|
          cached_page_crinja_value(sp, default_lang)
        })
        page.series.try { |s| @series_crinja_cache[s] = val }
        val
      },
      "related_posts" => if page.related_posts.empty?
        # Mirror the early-return that `series_pages` does for series-less
        # pages. Sites without `[related]` enabled (the default) get an
        # empty list on every page, and acquiring the cache mutex 1000+
        # times to hand back the same empty array measurably hurts on big
        # builds.
        Crinja::Value.new([] of Crinja::Value)
      else
        @crinja_cache_mutex.synchronize do
          if cached = @related_posts_crinja_cache[page.path]?
            @cache_manager.record_hit("related_posts_crinja")
            next cached
          end
          @cache_manager.record_miss("related_posts_crinja")
          val = Crinja::Value.new(page.related_posts.map { |rp|
            cached_page_crinja_value(rp, default_lang)
          })
          @related_posts_crinja_cache[page.path] = val
          val
        end
      end,
    }
    vars["page"] = Crinja::Value.new(page_obj)

    # Flat variables for new properties
    vars["page_summary"] = Crinja::Value.new(page.summary_html || page.effective_summary || "")
    vars["page_word_count"] = Crinja::Value.new(page.word_count)
    vars["page_reading_time"] = Crinja::Value.new(page.reading_time)
    vars["page_permalink"] = Crinja::Value.new(page.permalink || "")
    vars["page_authors"] = authors_crinja
    vars["page_tags"] = tags_crinja
    vars["page_weight"] = Crinja::Value.new(page.weight)

    # Site variables (flat for convenience)
    # NOTE: site_title, site_description, base_url are now in global_vars
    # (computed once in build_global_vars). We skip them here to avoid
    # redundant Crinja::Value allocations per page.

    # Section variables
    section_title = ""
    section_description = ""
    section_pages_array = [] of Crinja::Value
    current_section = ""

    # Section-specific variables
    subsections_array = [] of Crinja::Value
    section_assets_val = Crinja::Value.new([] of Crinja::Value)
    page_template_var = ""
    paginate_path_var = "page"
    redirect_to_var = ""

    if page.is_a?(Models::Section)
      # For section pages, use the page itself as the section data
      section_title = page.title
      section_description = page.description || ""
      current_section = page.section

      # Section-specific properties
      page_template_var = page.page_template || ""
      paginate_path_var = page.paginate_path
      redirect_to_var = page.redirect_to || ""

      # Build subsections array
      subsections_array = page.subsections.map do |sub|
        Crinja::Value.new({
          "title"       => Crinja::Value.new(sub.title),
          "description" => Crinja::Value.new(sub.description || ""),
          "url"         => Crinja::Value.new(sub.url),
          "pages_count" => Crinja::Value.new(sub.pages.size),
        })
      end

      # Use the page's assets as section assets
      section_assets_val = assets_crinja
    elsif !page.section.empty?
      # For regular pages, find the parent section via O(1) lookup
      section_page = site.section_for(page.section, page.language)
      if section_page
        section_title = section_page.title
        section_description = section_page.description || ""
        current_section = page.section
        # Use cached section assets to avoid re-allocating per page
        section_assets_val = @crinja_cache_mutex.synchronize do
          if cached_arr = @section_assets_crinja_cache[page.section]?
            @cache_manager.record_hit("section_assets_crinja")
            next Crinja::Value.new(cached_arr).as(Crinja::Value)
          end
          @cache_manager.record_miss("section_assets_crinja")
          arr = section_page.assets.map { |a| Crinja::Value.new(a) }
          @section_assets_crinja_cache[page.section] = arr
          Crinja::Value.new(arr)
        end
      end
    end

    if !current_section.empty?
      if paginator
        # Paginated: convert paginator's page subset
        default_lang = config.default_language
        section_pages_array = paginator.pages.map { |p| page_to_crinja_list_value(p, default_lang) }
      else
        # Non-paginated: use per-section cache, then exclude current page.
        # Find index once, then build result skipping that slot (pre-sized array avoids realloc).
        all_section = cached_section_pages_crinja(current_section, page.language, site)
        page_url_str = page.url
        skip_idx = all_section.index do |v|
          raw = v.raw
          raw.is_a?(Hash) && raw["url"]?.try(&.to_s) == page_url_str
        end
        section_pages_array = if skip_idx
                                arr = Array(Crinja::Value).new(all_section.size - 1)
                                all_section.each_with_index { |v, i| arr << v unless i == skip_idx }
                                arr
                              else
                                # NOTE: This is the cached array from @section_pages_crinja_cache.
                                # Safe because downstream only wraps it in Crinja::Value (read-only).
                                # Do NOT mutate (sort!, push, delete, etc.) — it would corrupt the cache.
                                all_section
                              end
      end
    end
    vars["section_title"] = Crinja::Value.new(section_title)
    vars["section_description"] = Crinja::Value.new(section_description)

    # Section object with structured access
    # - section.title, section.description, section.pages (for iteration)
    # - section.list (HTML string, same as section_list for convenience)
    section_obj = {
      "title"       => Crinja::Value.new(section_title),
      "description" => Crinja::Value.new(section_description),
      "pages"       => Crinja::Value.new(section_pages_array),
      "pages_count" => Crinja::Value.new(section_pages_array.size),
      "list"        => Crinja::Value.new(section_list),
      # New section properties
      "subsections"   => Crinja::Value.new(subsections_array),
      "assets"        => section_assets_val,
      "page_template" => Crinja::Value.new(page_template_var),
      "paginate_path" => Crinja::Value.new(paginate_path_var),
      "redirect_to"   => Crinja::Value.new(redirect_to_var),
    }
    vars["section"] = Crinja::Value.new(section_obj)

    # Content and layout variables
    vars["content"] = Crinja::Value.new(content)
    vars["section_list"] = Crinja::Value.new(section_list)

    # TOC variables - both flat and structured access
    # - toc (HTML string for backward compatibility)
    # - toc_obj.html (same HTML in structured form)
    # - toc_obj.headers (array of structured header objects for custom rendering)
    vars["toc"] = Crinja::Value.new(toc)
    toc_obj = {
      "html"    => Crinja::Value.new(toc),
      "headers" => Crinja::Value.new(toc_headers_to_crinja(toc_headers)),
    }
    vars["toc_obj"] = Crinja::Value.new(toc_obj)

    vars["pagination"] = Crinja::Value.new(pagination)
    vars["pagination_seo_links"] = Crinja::Value.new(pagination_seo_links)

    if paginator
      # Reuse section_pages_array already built above for paginator.pages
      paginator_obj = {
        "paginate_by"   => Crinja::Value.new(paginator.per_page),
        "base_url"      => Crinja::Value.new(paginator.base_url),
        "number_pagers" => Crinja::Value.new(paginator.total_pages),
        "first"         => Crinja::Value.new(paginator.first_url),
        "last"          => Crinja::Value.new(paginator.last_url),
        "previous"      => Crinja::Value.new(paginator.prev_url),
        "next"          => Crinja::Value.new(paginator.next_url),
        "pages"         => Crinja::Value.new(section_pages_array),
        "current_index" => Crinja::Value.new(paginator.page_number),
        "total_pages"   => Crinja::Value.new(paginator.total_pages),
      }
      vars["paginator"] = Crinja::Value.new(paginator_obj)

      # Structured pagination object for custom markup in themes
      # Allows: {{ pagination_obj.previous_url }}, {{ pagination_obj.current_page }}, etc.
      pagination_obj_hash = {
        "html"         => Crinja::Value.new(pagination),
        "previous_url" => Crinja::Value.new(paginator.has_prev ? (paginator.prev_url || "") : ""),
        "next_url"     => Crinja::Value.new(paginator.has_next ? (paginator.next_url || "") : ""),
        "first_url"    => Crinja::Value.new(paginator.first_url),
        "last_url"     => Crinja::Value.new(paginator.last_url),
        "current_page" => Crinja::Value.new(paginator.page_number),
        "total_pages"  => Crinja::Value.new(paginator.total_pages),
        "total_items"  => Crinja::Value.new(paginator.total_items),
        "per_page"     => Crinja::Value.new(paginator.per_page),
        "has_previous" => Crinja::Value.new(paginator.has_prev),
        "has_next"     => Crinja::Value.new(paginator.has_next),
      }
      vars["pagination_obj"] = Crinja::Value.new(pagination_obj_hash)
    end

    # NOTE: highlight_css/js/tags and auto_includes_css/js are now in
    # global_vars (computed once in build_global_vars).

    # OG/Twitter tags (page-specific — depend on page title/description/url/image)
    og_type_override = og_type_for(page, effective_url)
    # Fall back to the site title when the page itself has no title — most
    # often the homepage, where authors deliberately leave `title = ""` so
    # the section/page heading doesn't duplicate the site name. Without
    # this fallback, og:title and twitter:title render as `content=""`,
    # which breaks link previews (gh issue list, fix #1).
    effective_og_title = page.title.empty? ? config.title : page.title

    # Use page.description if present, otherwise a plain-text rendering of
    # the `<!-- more -->` summary, finally fall back to site description.
    # `plain_summary` strips markup so raw markdown (headings, code fences,
    # literal newlines) never breaks the single-line meta attribute — using
    # `page.summary` directly here dumped the raw chunk into og/twitter
    # tags (gh#491). This gives social cards good per-post text without
    # requiring every author to write a description in frontmatter.
    effective_og_desc = page.description.presence || page.plain_summary || config.description

    og_tags = config.og.og_tags(effective_og_title, effective_og_desc, effective_url, page.image, config.base_url, og_type_override)
    twitter_tags = config.og.twitter_tags(effective_og_title, effective_og_desc, page.image, config.base_url)
    # Mirror the 2-space indent used inside og_tags/twitter_tags so the
    # joined block stays vertically aligned in the rendered HTML.
    og_all_tags = if og_tags.empty?
                    twitter_tags
                  elsif twitter_tags.empty?
                    og_tags
                  else
                    "#{og_tags}\n  #{twitter_tags}"
                  end
    vars["og_tags"] = Crinja::Value.new(og_tags)
    vars["twitter_tags"] = Crinja::Value.new(twitter_tags)
    vars["og_all_tags"] = Crinja::Value.new(og_all_tags)

    # Canonical and Hreflang tags
    canonical_tag = Content::Seo::Tags.canonical_tag(page, config)
    hreflang_tags = Content::Seo::Tags.hreflang_tags(page, config)
    vars["canonical_tag"] = Crinja::Value.new(canonical_tag)
    vars["hreflang_tags"] = Crinja::Value.new(hreflang_tags)

    # Structured SEO object for custom meta tag markup
    canonical_url = Content::Seo::Tags.canonical_url(page, config)
    seo_image = config.og.resolve_image_url(page.image, config.base_url) || ""
    seo_obj = {
      "canonical_url"   => Crinja::Value.new(canonical_url),
      "og_type"         => Crinja::Value.new(og_type_override || config.og.og_type),
      "og_image"        => Crinja::Value.new(seo_image),
      "twitter_card"    => Crinja::Value.new(config.og.twitter_card),
      "twitter_site"    => Crinja::Value.new(config.og.twitter_site || ""),
      "twitter_creator" => Crinja::Value.new(config.og.twitter_creator || ""),
      "fb_app_id"       => Crinja::Value.new(config.og.fb_app_id || ""),
      "hreflang"        => translations_crinja,
    }
    vars["seo"] = Crinja::Value.new(seo_obj)

    # JSON-LD structured data.
    #
    # The homepage is a WebSite, not an Article — and because the scaffold
    # homepage ships an empty title, emitting an Article there produced an
    # invalid empty `headline`. Use the WebSite schema for the homepage, and
    # for any other untitled page skip the Article entirely rather than emit
    # one with an empty headline.
    is_homepage = home?(page)
    jsonld_article = if is_homepage || page.title.empty?
                       ""
                     else
                       Content::Seo::JsonLd.article(page, config, site)
                     end
    needs_breadcrumb = !page.ancestors.empty? || !page.is_index
    jsonld_breadcrumb = needs_breadcrumb ? Content::Seo::JsonLd.breadcrumb(page, config) : ""

    # Extended schema types (FAQ, HowTo) auto-detected from extra.schema_type
    jsonld_extra = Content::Seo::JsonLd.for_page(page, config)

    jsonld_parts = [] of String
    if is_homepage
      jsonld_home_website = Content::Seo::JsonLd.website(config)
      jsonld_parts << jsonld_home_website unless jsonld_home_website.empty?
    end
    jsonld_parts << jsonld_article unless jsonld_article.empty?
    jsonld_parts << jsonld_breadcrumb unless jsonld_breadcrumb.empty?
    jsonld_parts << jsonld_extra unless jsonld_extra.empty?
    jsonld_all = jsonld_parts.join("\n")

    vars["jsonld_article"] = Crinja::Value.new(jsonld_article)
    vars["jsonld_breadcrumb"] = Crinja::Value.new(jsonld_breadcrumb)
    # Only compute FAQ/HowTo JSON-LD when schema_type indicates it (avoids
    # per-page hash lookups + array allocations for the common case)
    schema_type_raw = page.extra["schema_type"]?.try(&.as?(String)) || ""
    schema_lower = schema_type_raw.downcase
    vars["jsonld_faq"] = Crinja::Value.new(
      schema_lower == "faqpage" || schema_lower == "faq" ? Content::Seo::JsonLd.faq_page(page, config) : ""
    )
    vars["jsonld_howto"] = Crinja::Value.new(
      schema_lower == "howto" || schema_lower == "how-to" ? Content::Seo::JsonLd.how_to(page, config) : ""
    )
    vars["jsonld"] = Crinja::Value.new(jsonld_all)

    # Merge global vars at the end.  Page-specific keys (written above)
    # take precedence because they were set first; merge! only adds keys
    # that don't already exist when we reverse the direction below.
    gv = global_vars || build_global_vars(site)
    gv.each { |k, v| vars[k] = v unless vars.has_key?(k) }

    vars
  end

  private def minify_html(html : String) : String
    Utils::HtmlMinifier.minify(html)
  end

  # Hugo-style `{{< name >}}` shortcodes aren't a Hwaro syntax — they'd
  # otherwise reach Markdown unchanged and ship as HTML-escaped literals
  # (`{{&lt; alert &gt;}}`) in the rendered page. The conversion depends on
  # whether the shortcode wraps a body: self-closing Hugo shortcodes
  # (`{{< youtube id="v" >}}`) map to the direct-call form `{{ youtube(id="v") }}`,
  # while paired ones (`{{< alert >}}…{{< /alert >}}`) map to the block form
  # `{% alert(…) %}…{% end %}`. Emitting `{% youtube(…) %}` for a self-closing
  # shortcode produces an unclosed block tag that still ships as literal text,
  # so the warning must show both forms. Warn once per page and list the
  # distinct shortcode names so the message is actionable in a `hwaro build`
  # log even with hundreds of pages.
  HUGO_SHORTCODE_RE = /\{\{<\s*\/?\s*([a-zA-Z_][\w\-]*)/

  private def warn_hugo_shortcode_syntax(raw : String, path : String) : Nil
    names = Set(String).new
    raw.scan(HUGO_SHORTCODE_RE) { |m| names << m[1] }
    return if names.empty?
    sorted = names.to_a.sort
    Logger.warn "Hugo-style shortcode syntax `{{< … >}}` is not supported and will render as literal text in #{path}. " \
                "Found: #{sorted.join(", ")}. Convert to Hwaro's Crinja syntax — self-closing: " \
                "`{{< name arg=\"v\" >}}` → `{{ name(arg=\"v\") }}`; with a body: " \
                "`{{< name arg=\"v\" >}}body{{< /name >}}` → `{% name(arg=\"v\") %}body{% end %}` (named closer `{% endname %}` recommended)."
  end

  # Resolve the page kind into an `og:type` override. Returns "website"
  # for non-article pages (homepage, section indexes, taxonomy listings,
  # the synthetic 404), or `nil` to fall back to the configured
  # `[og].type` (article, by default) for content pages (gh#522).
  private def og_type_for(page : Models::Page, effective_url : String) : String?
    # 404 page is synthesized in write phase with `path = "404.html"`.
    return "website" if page.path == "404.html"
    # Taxonomy listings (`/tags/`, `/tags/<term>/`, …).
    return "website" if page.taxonomy_name
    # Section landings come from `_index.md`, which read_content parses into
    # a `Models::Section`. Key off the *type*, not `page.is_index`: a
    # page-bundle leaf (`some/post/index.md`) is a `Models::Page` with
    # `is_index = true` as well, yet it is ordinary article content. Keying
    # off `is_index` rendered og:type="website" for every page-bundle post
    # (gh#601).
    return "website" if page.is_a?(Models::Section)
    # Site / per-language homepage (`/`, `/<lang>/`). See `home?`.
    return "website" if home?(page)
    # Defensive fallback for a custom-permalink homepage remapped to root.
    return "website" if effective_url == "/" || effective_url.empty?
    nil
  end

  # Is this the site (or per-language) homepage — the root `index.md` /
  # `_index.md`? Such a page is an index whose source file sits directly
  # under `content/` with no parent directory, so `page.path` has no `/`
  # (`index.md`, `index.ko.md`, `_index.md`, …). This deliberately does NOT
  # use `page.is_index && page.section.empty?`: one-level page bundles like
  # `content/about/index.md` also resolve to an empty section, so that test
  # mislabels them as the homepage (gh#601).
  private def home?(page : Models::Page) : Bool
    page.is_index && !page.path.includes?('/')
  end
end
