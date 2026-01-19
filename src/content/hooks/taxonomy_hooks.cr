# Taxonomy hooks for build lifecycle
#
# Generates taxonomy index/term pages during the Generate phase.

require "../../core/lifecycle"
require "../taxonomies"

module Hwaro
  module Content
    module Hooks
      class TaxonomyHooks
        include Core::Lifecycle::Hookable

        def register_hooks(manager : Core::Lifecycle::Manager)
          manager.on(Core::Lifecycle::HookPoint::BeforeGenerate, priority: 40, name: "taxonomy:generate") do |ctx|
            generate_taxonomies(ctx)
            Core::Lifecycle::HookResult::Continue
          end
        end

        private def generate_taxonomies(ctx : Core::Lifecycle::BuildContext)
          site = ctx.site
          return unless site

          Content::Taxonomies.generate(site, ctx.output_dir, ctx.templates)
        end
      end
    end
  end
end
