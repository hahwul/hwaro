require "../../core/lifecycle"
require "../seo/amp"

module Hwaro
  module Content
    module Hooks
      class AmpHooks
        include Core::Lifecycle::Hookable

        def register_hooks(manager : Core::Lifecycle::Manager)
          # Run after rendering so we can read the generated HTML files
          manager.on(Core::Lifecycle::HookPoint::AfterRender, priority: 40, name: "amp:generate") do |ctx|
            generate_amp_pages(ctx)
            Core::Lifecycle::HookResult::Continue
          end
        end

        private def generate_amp_pages(ctx : Core::Lifecycle::BuildContext)
          site = ctx.site
          return unless site
          return unless site.config.amp.enabled

          Content::Seo::Amp.generate(
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
