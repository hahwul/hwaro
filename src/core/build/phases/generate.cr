# Phase: Generate — SEO files (sitemap, feeds, robots, etc.)
#
# Handles generating SEO and search-related output files:
# sitemap.xml, RSS/Atom feeds, robots.txt, llms.txt, and search index.

module Hwaro::Core::Build::Phases::Generate
  private def execute_generate_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    profiler.start_phase("Generate")
    result = @lifecycle.run_phase(Lifecycle::Phase::Generate, ctx) do
      Logger.status_phase("generate")
      # Default generation if no SEO hooks registered
      unless @lifecycle.has_hooks?(Lifecycle::HookPoint::BeforeGenerate)
        site = @site || raise "Site not initialized"
        output_dir = ctx.options.output_dir
        all_pages = ctx.all_pages

        # When cache is enabled and no pages were rendered (all cache hits),
        # skip regenerating SEO/search files if they already exist. A changed
        # page/section set (e.g. a deleted page) forces regeneration even
        # when no surviving page re-rendered — otherwise the sitemap/search
        # index would keep the removed URL until an unrelated edit.
        skip_unchanged = ctx.options.cache && ctx.stats.pages_rendered == 0 &&
                         !ctx.page_or_section_set_changed

        # Run independent SEO/search generators in parallel
        tasks = [
          -> { Content::Seo::Sitemap.generate(all_pages, site, output_dir, skip_if_unchanged: skip_unchanged); nil },
          -> { Content::Seo::Feeds.generate(all_pages, site.config, output_dir, skip_if_unchanged: skip_unchanged); nil },
          -> { Content::Seo::Robots.generate(site.config, output_dir); nil },
          -> { Content::Seo::Llms.generate(site.config, all_pages, output_dir, skip_if_unchanged: skip_unchanged); nil },
          -> { Content::Search.generate(all_pages, site.config, output_dir, skip_if_unchanged: skip_unchanged); nil },
        ] of Proc(Nil)
        ParallelHelper.execute(tasks, ctx.options.parallel)
      end
    end
    profiler.end_phase
    result
  end
end
