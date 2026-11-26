# Phase: Generate — SEO files (sitemap, feeds, robots, etc.)
#
# Handles generating SEO and search-related output files:
# sitemap.xml, RSS/Atom feeds, robots.txt, llms.txt, and search index.
#
# ONE implementation, two entry points. `SeoHooks` (registered by every real
# CLI build and by `serve`) calls `generate_seo_outputs` / `generate_search_index`
# from its BeforeGenerate / AfterGenerate hooks; the phase body below calls the
# same two methods only when no hook is registered (embedding callers, specs).
# They used to be two copies: the hook copy passed no `skip_if_unchanged`, so
# the whole skip computation here was dead code in real builds, and a warm
# `--cache` build (render: 0 pages, N cached) regenerated search.json / rss.xml
# from pages the render phase never populated — shipping raw `{% shortcode %}`
# markup, unresolved `@/` links and un-prefixed subpath URLs into the index and
# the feeds until an unrelated edit happened to re-render every page.

module Hwaro::Core::Build::Phases::Generate
  private def execute_generate_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    profiler.start_phase("Generate")
    result = @lifecycle.run_phase(Lifecycle::Phase::Generate, ctx) do
      Logger.status_phase("generate")
      # Default generation if no SEO hooks registered
      unless @lifecycle.has_hooks?(Lifecycle::HookPoint::BeforeGenerate)
        generate_seo_outputs(ctx)
        generate_search_index(ctx)
      end
    end
    profiler.end_phase
    result
  end

  # True when a warm `--cache` build can leave the previous build's SEO and
  # search outputs in place: no page re-rendered AND the page/section set is
  # unchanged. A changed set (e.g. a deleted page) forces regeneration even
  # when no surviving page re-rendered — otherwise the sitemap/search index
  # would keep the removed URL until an unrelated edit.
  #
  # Nor when the static copy wrote over one of the skippable outputs:
  # Initialize copies `static/` before Generate runs, so a changed
  # `static/sitemap.xml` (or search.json, llms.txt, a feed) replaced the
  # generated file, and skipping the generator left the user's bytes
  # published where a cold build lets the generated file win. Any other
  # static edit keeps the skip.
  #
  # The render phase uses the same predicate to decide whether cache-hit pages
  # need their `content` hydrated for the generators (see
  # `hydrate_cached_page_content`), so the two decisions cannot drift.
  #
  # Nor after a config (or other global) change: it re-renders every page, so
  # "no page re-rendered" only means "unchanged" when the site has pages. A
  # site with none kept the previous title and base_url in rss.xml/llms.txt.
  def generate_outputs_unchanged?(ctx : Lifecycle::BuildContext) : Bool
    ctx.options.cache && ctx.stats.pages_rendered == 0 && !ctx.page_or_section_set_changed &&
      !@cache.try(&.globals_invalidated?) && !static_copy_over_skippable_output?(ctx)
  end

  # True when a warm `--cache` build may keep the taxonomy index, term, pager
  # and term-feed files the previous build wrote instead of rendering them
  # again (each still on disk and not just replaced by the static copy, see
  # `Taxonomies.reusable_output?`). Every input they render from is unchanged:
  #
  #   * every page was a cache hit, the page/section set did not move and no
  #     global input changed (`generate_outputs_unchanged?`) — so the term
  #     lists, the pages they print and the site-wide template variables are
  #     what they were;
  #   * no template changed and no feed template exists
  #     (`feeds_need_regeneration?`) — no page's dependency closure covers
  #     the taxonomy templates, so a cache hit says nothing about them;
  #   * what those templates read outside the tracked files is part of the
  #     recorded render inputs (`record_taxonomy_render_reads`), so a change
  #     there already invalidated the build;
  #   * no term `_index.md` — its body and aliases reach the term page
  #     outside the page fingerprints;
  #   * no `[build] write_stats` — its file lists every page written.
  #
  # Never in serve, which keeps its own record of taxonomy outputs.
  def taxonomy_outputs_unchanged?(ctx : Lifecycle::BuildContext) : Bool
    site = @site
    return false unless site && taxonomy_render_reads_recorded? && @html_stats.nil?
    hits = ctx.stats.cache_hits
    return false unless hits > 0 && hits == ctx.all_pages.size
    generate_outputs_unchanged?(ctx) && !feeds_need_regeneration? && site.sections.none?(&.term_metadata)
  end

  # Did this build's static copy land on a file one of the skippable
  # generators (sitemap, feeds, llms, search) publishes?
  private def static_copy_over_skippable_output?(ctx : Lifecycle::BuildContext) : Bool
    return false unless static_copies_recorded?
    site = @site
    return true unless site
    config = site.config
    output_dir = ctx.options.output_dir
    cwd = Dir.current
    outputs = Content::Seo::Sitemap.published_outputs(config, output_dir) +
              Content::Seo::Llms.published_outputs(config, output_dir) +
              Content::Search.published_outputs(config, output_dir) +
              Content::Seo::Feeds.published_outputs(ctx.all_pages, config, output_dir)
    outputs.any? { |path| static_copied_output?(path, cwd) }
  end

  # Sitemap, feeds, robots.txt and llms.txt. Public so `SeoHooks` can route
  # its BeforeGenerate hook through the skip-aware path.
  def generate_seo_outputs(ctx : Lifecycle::BuildContext) : Nil
    site = @site || raise "Site not initialized"
    output_dir = ctx.options.output_dir
    all_pages = ctx.all_pages
    verbose = ctx.options.verbose
    skip_unchanged = generate_outputs_unchanged?(ctx)

    # Feeds never join the skip when a user feed template exists: the
    # skip's cache-hit signal only reflects content changes, so a
    # template-only edit followed by a warm --cache build would keep
    # serving the stale feed output forever (see feeds_need_regeneration?).
    skip_feeds = skip_unchanged && !feeds_need_regeneration?
    # Run independent SEO generators in parallel.
    tasks = [
      # Each generator's published files are claimed whether written or
      # skipped as unchanged: the claim list is "what this build publishes"
      # (see Phases::Finalize), so disabling or renaming an output removes
      # the file an earlier build wrote.
      -> {
        Content::Seo::Sitemap.generate(all_pages, site, output_dir, verbose, skip_if_unchanged: skip_unchanged, builder: self)
        Content::Seo::Sitemap.published_outputs(site.config, output_dir).each { |path| claim_generated_output(path) }
        nil
      },
      -> {
        feeds = Content::Seo::Feeds.generate(all_pages, site.config, output_dir, verbose, skip_if_unchanged: skip_feeds, templates: @templates, renderer: feed_template_renderer)
        feeds.each { |path| claim_generated_output(path) }
        track_feed_outputs(feeds, output_dir)
        nil
      },
      -> {
        Content::Seo::Robots.generate(site.config, output_dir, verbose)
        if site.config.robots.enabled
          # Robots is always rewritten, even on an all-hit cache build.
          # Claim it explicitly so pruning a static file at this path does
          # not depend on the filesystem's mtime precision.
          filename = File.basename(site.config.robots.filename)
          claim_generated_output(File.join(output_dir, filename))
        end
        nil
      },
      -> {
        Content::Seo::Llms.generate(site.config, all_pages, output_dir, verbose, skip_if_unchanged: skip_unchanged)
        Content::Seo::Llms.published_outputs(site.config, output_dir).each { |path| claim_generated_output(path) }
        nil
      },
    ] of Proc(Nil)
    ParallelHelper.execute(tasks, ctx.options.parallel)

    config = site.config
    replaced = Content::Seo::Sitemap.published_outputs(config, output_dir).map { |path| {path, "set [sitemap] enabled = false"} }
    replaced.concat(Content::Seo::Feeds.published_outputs(all_pages, config, output_dir, warn_on_collision: false).map { |path| {path, "rename or turn off that feed ([feeds])"} })
    replaced << {File.join(output_dir, File.basename(config.robots.filename)), "set [robots] enabled = false"} if config.robots.enabled
    replaced.concat(Content::Seo::Llms.published_outputs(config, output_dir).map { |path| {path, "set [llms] enabled = false"} })
    warn_replaced_outputs(replaced, all_pages, output_dir)
  end

  # The search index. Kept separate from `generate_seo_outputs` because the
  # hook contract runs it on AfterGenerate.
  def generate_search_index(ctx : Lifecycle::BuildContext) : Nil
    site = @site || raise "Site not initialized"
    Content::Search.generate(ctx.all_pages, site.config, ctx.options.output_dir, ctx.options.verbose,
      skip_if_unchanged: generate_outputs_unchanged?(ctx), builder: self)
    # Claimed whether written or skipped: the claim list is "what this build
    # publishes" (see Phases::Finalize).
    published = Content::Search.published_outputs(site.config, ctx.options.output_dir)
    published.each { |path| claim_generated_output(path) }
    warn_replaced_outputs(published.map { |path| {path, "set another [search] filename"} }, ctx.all_pages, ctx.options.output_dir)
  end

  # A generated file wins over anything else published at its path: a
  # `static/` file (cold and `--cache` builds alike, see
  # `static_copy_over_skippable_output?`) or a page's `[outputs]` format file
  # (the home page's `index.xml` under `[feeds] filename = "index.xml"`).
  # Both were replaced silently: a hand-written `static/robots.txt` lost its
  # `Disallow` rules to the default allow-all file, and `alternate_output_tags`
  # kept advertising a format file that now held the feed. Say so, with the
  # setting that hands the path back. `outputs` pairs each generated file
  # with that setting.
  private def warn_replaced_outputs(outputs : Array({String, String}), pages : Array(Models::Page), output_dir : String) : Nil
    return if outputs.empty?
    config = @site.try(&.config)
    format_files = {} of String => {String, String}
    if config
      pages.each do |page|
        next unless page.render
        formats = effective_output_formats(page, config)
        next if formats.empty?
        format_output_paths(page, output_dir, formats).each do |path|
          format_files[File.expand_path(path)] ||= {page.path, File.extname(path).lchop('.')}
        end
      end
    end

    static = static_publish_config
    prefix = output_dir.ends_with?('/') ? output_dir : "#{output_dir}/"
    outputs.each do |(path, setting)|
      next unless path.starts_with?(prefix)
      relative = path[prefix.size..]
      if owner = format_files[File.expand_path(path)]?
        Logger.warn "#{relative}: the #{owner[1]} output of '#{owner[0]}' is replaced by a generated file at the same path; #{setting}, or drop that output format, to keep it"
      end
      source = File.join("static", relative)
      if File.file?(source) && !static.excluded?(relative)
        Logger.warn "#{source} is replaced by the generated #{relative}; #{setting} to publish your own file"
      end
    end
  end
end
