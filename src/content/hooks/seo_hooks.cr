# SEO hooks for build lifecycle
#
# Generates SEO-related files: sitemap, feeds, robots.txt, llms.txt

require "../../core/lifecycle"
require "../seo/sitemap"
require "../seo/feeds"
require "../seo/robots"
require "../seo/llms"
require "../search"

module Hwaro
  module Content
    module Hooks
      class SeoHooks
        include Core::Lifecycle::Hookable

        def register_hooks(manager : Core::Lifecycle::Manager)
          # Generate phase: Create SEO files
          manager.on(Core::Lifecycle::HookPoint::BeforeGenerate, priority: 50, name: "seo:generate") do |ctx|
            generate_seo_files(ctx)
            Core::Lifecycle::HookResult::Continue
          end

          # Generate search index
          manager.on(Core::Lifecycle::HookPoint::AfterGenerate, priority: 50, name: "search:index") do |ctx|
            generate_search_index(ctx)
            Core::Lifecycle::HookResult::Continue
          end
        end

        # Route through the builder's skip-aware implementation whenever one is
        # attached (every CLI build and `serve`). This hook used to hold a
        # second copy of the generate phase's calls with no `skip_if_unchanged`,
        # which made the phase's own skip logic dead code in real builds and
        # regenerated feeds from un-hydrated cache-hit pages on every warm
        # `--cache` build. The direct calls below remain only for embedding
        # callers that trigger the hooks without a Builder.
        private def generate_seo_files(ctx : Core::Lifecycle::BuildContext)
          if builder = ctx.builder
            builder.generate_seo_outputs(ctx)
            return
          end

          site = ctx.site
          return unless site

          all_pages = ctx.all_pages

          Content::Seo::Sitemap.generate(all_pages, site, ctx.output_dir, ctx.options.verbose)
          Content::Seo::Feeds.generate(all_pages, site.config, ctx.output_dir, ctx.options.verbose,
            templates: ctx.templates.empty? ? nil : ctx.templates)
          Content::Seo::Robots.generate(site.config, ctx.output_dir, ctx.options.verbose)
          Content::Seo::Llms.generate(site.config, all_pages, ctx.output_dir, ctx.options.verbose)
        end

        private def generate_search_index(ctx : Core::Lifecycle::BuildContext)
          if builder = ctx.builder
            builder.generate_search_index(ctx)
            return
          end

          site = ctx.site
          return unless site

          Content::Search.generate(ctx.all_pages, site.config, ctx.output_dir, ctx.options.verbose)
        end
      end
    end
  end
end
