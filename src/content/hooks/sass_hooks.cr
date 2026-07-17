# Sass compilation hook for the build lifecycle.
#
# Runs at AfterInitialize with priority 50 — after the Initialize phase's
# static copy (which excludes raw `.scss` sources) and before
# assets:process (priority 40; hook priority is descending), so bundles
# can reference compiled output on disk.

require "../../core/lifecycle"
require "../../assets/sass_compiler"

module Hwaro
  module Content
    module Hooks
      class SassHooks
        include Core::Lifecycle::Hookable

        def register_hooks(manager : Core::Lifecycle::Manager)
          manager.on(Core::Lifecycle::HookPoint::AfterInitialize, priority: 50, name: "sass:compile") do |ctx|
            compile_sass(ctx)
            Core::Lifecycle::HookResult::Continue
          end
        end

        private def compile_sass(ctx : Core::Lifecycle::BuildContext)
          config = ctx.config
          return unless config && config.sass.enabled

          compiler = Assets::SassCompiler.new(config.sass, config.static)
          count = compiler.compile_all(ctx.output_dir)
          Logger.info "  Sass: #{count} file(s) compiled." if count > 0
        end
      end
    end
  end
end
