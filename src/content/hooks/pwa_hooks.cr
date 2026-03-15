require "../../core/lifecycle"
require "../seo/pwa"

module Hwaro
  module Content
    module Hooks
      class PwaHooks
        include Core::Lifecycle::Hookable

        def register_hooks(manager : Core::Lifecycle::Manager)
          manager.on(Core::Lifecycle::HookPoint::BeforeGenerate, priority: 50, name: "pwa:generate") do |ctx|
            generate_pwa_files(ctx)
            Core::Lifecycle::HookResult::Continue
          end
        end

        private def generate_pwa_files(ctx : Core::Lifecycle::BuildContext)
          site = ctx.site
          return unless site

          Content::Seo::Pwa.generate(site, ctx.output_dir, ctx.options.verbose)
        end
      end
    end
  end
end
