# Phase: Finalize — cache save
#
# Handles the final phase of the build lifecycle:
# persisting the build cache to disk for future incremental builds.

module Hwaro::Core::Build::Phases::Finalize
  private def execute_finalize_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    profiler.start_phase("Finalize")
    result = @lifecycle.run_phase(Lifecycle::Phase::Finalize, ctx) do
      build_cache = @cache || raise "Cache not initialized"
      build_cache.save if ctx.options.cache
    end
    profiler.end_phase
    result
  end
end
