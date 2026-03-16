# Asset pipeline hooks for build lifecycle
#
# Processes CSS/JS bundles during the build, producing minified and
# fingerprinted output files. The resulting manifest is exposed to
# templates via the `asset()` function.

require "../../core/lifecycle"
require "../../assets/pipeline"

module Hwaro
  module Content
    module Hooks
      class AssetHooks
        include Core::Lifecycle::Hookable

        # Class-level manifest shared with template functions
        @@manifest = {} of String => String
        @@manifest_mutex = Mutex.new

        def register_hooks(manager : Core::Lifecycle::Manager)
          manager.on(Core::Lifecycle::HookPoint::AfterInitialize, priority: 40, name: "assets:process") do |ctx|
            process_assets(ctx)
            Core::Lifecycle::HookResult::Continue
          end
        end

        def self.manifest : Hash(String, String)
          @@manifest_mutex.synchronize { @@manifest }
        end

        private def process_assets(ctx : Core::Lifecycle::BuildContext)
          config = ctx.config
          return unless config && config.assets.enabled

          pipeline = Assets::Pipeline.new(config.assets, config.base_url)
          pipeline.process(ctx.output_dir)

          @@manifest_mutex.synchronize { @@manifest = pipeline.manifest }

          if pipeline.manifest.size > 0
            Logger.info "  Assets: #{pipeline.manifest.size} bundle(s) processed."
          end
        end
      end
    end
  end
end
