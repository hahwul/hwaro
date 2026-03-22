require "../../core/lifecycle"
require "../seo/og_image"

module Hwaro
  module Content
    module Hooks
      class OgImageHooks
        include Core::Lifecycle::Hookable

        def register_hooks(manager : Core::Lifecycle::Manager)
          # Run before rendering so page.image is set before OG tag generation.
          # Priority 30 (lower than SEO hooks at 50) to run after content is parsed
          # but before template rendering uses page.image.
          manager.on(Core::Lifecycle::HookPoint::BeforeRender, priority: 30, name: "og_image:generate") do |ctx|
            generate_og_images(ctx)
            Core::Lifecycle::HookResult::Continue
          end
        end

        private def generate_og_images(ctx : Core::Lifecycle::BuildContext)
          site = ctx.site
          return unless site
          if ctx.options.skip_og_image
            Logger.debug "  Skipping OG image generation (--skip-og-image)"
            return
          end
          return unless site.config.og.auto_image.enabled

          Content::Seo::OgImage.generate(
            ctx.all_pages,
            site.config,
            ctx.output_dir,
            ctx.options.verbose,
          )
        end
      end
    end
  end
end
