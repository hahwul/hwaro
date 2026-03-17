# Phase: Generate — SEO files (sitemap, feeds, robots, etc.)
#
# Handles generating SEO and search-related output files:
# sitemap.xml, RSS/Atom feeds, robots.txt, llms.txt, and search index.

module Hwaro::Core::Build::Phases::Generate
  private def execute_generate_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    profiler.start_phase("Generate")
    result = @lifecycle.run_phase(Lifecycle::Phase::Generate, ctx) do
      # Default generation if no SEO hooks registered
      unless @lifecycle.has_hooks?(Lifecycle::HookPoint::BeforeGenerate)
        site = @site || raise "Site not initialized"
        output_dir = ctx.options.output_dir
        all_pages = ctx.all_pages

        # Run independent SEO/search generators in parallel
        tasks = [
          -> { Content::Seo::Sitemap.generate(all_pages, site, output_dir); nil },
          -> { Content::Seo::Feeds.generate(all_pages, site.config, output_dir); nil },
          -> { Content::Seo::Robots.generate(site.config, output_dir); nil },
          -> { Content::Seo::Llms.generate(site.config, all_pages, output_dir); nil },
          -> { Content::Search.generate(all_pages, site.config, output_dir); nil },
        ] of Proc(Nil)
        ParallelHelper.execute(tasks, ctx.options.parallel)
      end
    end
    profiler.end_phase
    result
  end
end
