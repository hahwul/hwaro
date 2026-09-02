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
  # The render phase uses the same predicate to decide whether cache-hit pages
  # need their `content` hydrated for the generators (see
  # `hydrate_cached_page_content`), so the two decisions cannot drift.
  def generate_outputs_unchanged?(ctx : Lifecycle::BuildContext) : Bool
    ctx.options.cache && ctx.stats.pages_rendered == 0 && !ctx.page_or_section_set_changed
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
    # serving the stale feed output forever.
    skip_feeds = skip_unchanged && !feed_template_present?
    # Run independent SEO generators in parallel.
    tasks = [
      -> { Content::Seo::Sitemap.generate(all_pages, site, output_dir, verbose, skip_if_unchanged: skip_unchanged); nil },
      -> { Content::Seo::Feeds.generate(all_pages, site.config, output_dir, verbose, skip_if_unchanged: skip_feeds, templates: @templates, renderer: feed_template_renderer); nil },
      -> { Content::Seo::Robots.generate(site.config, output_dir, verbose); nil },
      -> { Content::Seo::Llms.generate(site.config, all_pages, output_dir, verbose, skip_if_unchanged: skip_unchanged); nil },
    ] of Proc(Nil)
    ParallelHelper.execute(tasks, ctx.options.parallel)
  end

  # The search index. Kept separate from `generate_seo_outputs` because the
  # hook contract runs it on AfterGenerate.
  def generate_search_index(ctx : Lifecycle::BuildContext) : Nil
    site = @site || raise "Site not initialized"
    Content::Search.generate(ctx.all_pages, site.config, ctx.options.output_dir, ctx.options.verbose,
      skip_if_unchanged: generate_outputs_unchanged?(ctx))
  end
end
