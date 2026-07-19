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

        # Replace the class-level manifest (serve-mode SCSS/asset recompile).
        # Full builds go through process_assets; this keeps fingerprint paths
        # in sync when only static files changed.
        def self.replace_manifest(manifest : Hash(String, String))
          @@manifest_mutex.synchronize { @@manifest = manifest }
        end

        private def process_assets(ctx : Core::Lifecycle::BuildContext)
          config = ctx.config
          return unless config && config.assets.enabled

          pipeline = Assets::Pipeline.new(config.assets, config.base_url, config.sass.enabled)
          pipeline.process(ctx.output_dir)

          AssetHooks.replace_manifest(pipeline.manifest)

          if pipeline.manifest.size > 0
            Logger.info "  Assets: #{pipeline.manifest.size} bundle(s) processed."
          end
        end
      end
    end
  end
end
