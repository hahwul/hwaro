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

        private def generate_seo_files(ctx : Core::Lifecycle::BuildContext)
          site = ctx.site
          return unless site

          all_pages = ctx.all_pages

          # Generate sitemap
          Content::Seo::Sitemap.generate(all_pages, site, ctx.output_dir, ctx.options.verbose)

          # Generate feeds (RSS/Atom)
          Content::Seo::Feeds.generate(all_pages, site.config, ctx.output_dir, ctx.options.verbose)

          # Generate robots.txt
          Content::Seo::Robots.generate(site.config, ctx.output_dir, ctx.options.verbose)

          # Generate llms.txt
          Content::Seo::Llms.generate(site.config, ctx.output_dir, ctx.options.verbose)
        end

        private def generate_search_index(ctx : Core::Lifecycle::BuildContext)
          site = ctx.site
          return unless site

          Content::Search.generate(ctx.all_pages, site.config, ctx.output_dir, ctx.options.verbose)
        end
      end
    end
  end
end
