# Lifecycle Manager - Central orchestrator for build hooks
#
# The Manager handles hook registration and execution across all phases.
# It provides a clean API for registering hooks and triggering them
# at the appropriate points in the build lifecycle.

require "./phases"
require "./hooks"
require "./context"
require "../../utils/logger"

module Hwaro
  module Core
    module Lifecycle
      class Manager
        # Storage: HookPoint → Array of registered hooks
        @hooks : Hash(HookPoint, Array(RegisteredHook))

        def initialize
          @hooks = {} of HookPoint => Array(RegisteredHook)
          # Initialize empty arrays for all hook points
          HookPoint.each { |point| @hooks[point] = [] of RegisteredHook }
        end

        # ========================================
        # Hook Registration API
        # ========================================

        # Register a hook at a specific point
        def on(point : HookPoint, priority : Int32 = 0, name : String = "anonymous", &block : BuildContext -> HookResult)
          @hooks[point] << RegisteredHook.new(HookHandler.new { |ctx| block.call(ctx) }, priority, name)
          # Sort by priority descending (higher priority first) — single sort, no reverse
          @hooks[point].sort! { |a, b| b.priority <=> a.priority }
          self
        end

        # Register a Hookable module
        def register(hookable : Hookable)
          hookable.register_hooks(self)
          self
        end

        # ========================================
        # Hook Execution API
        # ========================================

        # Trigger all hooks at a specific point. Only `Abort` (or a raised
        # HwaroError) terminates the build.
        def trigger(point : HookPoint, context : BuildContext) : HookResult
          hooks = @hooks[point]
          return HookResult::Continue if hooks.empty?

          hooks.each do |hook|
            # Lightweight per-hook timing when --profile is enabled (#561)
            start = if (p = context.profiler) && p.enabled?
                      Time.instant
                    end

            result = hook.handler.call(context)

            if start && (p = context.profiler)
              elapsed = (Time.instant - start).total_milliseconds
              p.record_hook(hook.name, elapsed)
            end

            if result.abort?
              Logger.error "  ✖ Build aborted by hook: #{hook.name}"
              return result
            end
          rescue ex : Hwaro::HwaroError
            # Classified errors propagate unchanged so the CLI can surface
            # them with their documented exit code / JSON payload.
            raise ex
          rescue ex
            Logger.error "  Hook '#{hook.name}' failed at #{point}: #{ex.message}"
            Logger.debug "  Backtrace: #{ex.backtrace?.try(&.first(5).join("\n    ")) || "unavailable"}"
            return HookResult::Abort
          end

          HookResult::Continue
        end

        # Execute a phase with before/after hooks
        def run_phase(phase : Phase, context : BuildContext, &) : HookResult
          before_point, after_point = Lifecycle.hook_points_for(phase)

          # Before hooks
          result = trigger(before_point, context)
          return result if result != HookResult::Continue

          # Phase action
          begin
            yield
          rescue ex : Hwaro::HwaroError
            # Classified phase-action errors propagate to the CLI so exit
            # code + JSON payload stay stable; don't downgrade to Abort.
            raise ex
          rescue ex : IO::Error
            # Ordinary filesystem trouble — a plain file squatting on the
            # output directory name, a permission denial, a name the
            # filesystem rejects, a full disk — is an environment problem,
            # not a hwaro bug. Swallowing the exception TYPE here (returning
            # Abort) made the CLI report every one of them as
            # HWARO_E_INTERNAL / exit 70, the code documented as
            # "unrecoverable bug or unexpected state", and dropped the only
            # useful detail (which path, which errno) from the --json
            # payload. Re-raise classified so it exits 6 with the real
            # message; genuine internal faults still fall through to Abort.
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_IO,
              message: "Phase #{phase} failed: #{ex.message}",
              cause: ex,
            )
          rescue ex
            Logger.error "Phase #{phase} failed: #{ex.message}"
            Logger.debug "  Backtrace: #{ex.backtrace?.try(&.first(5).join("\n    ")) || "unavailable"}"
            return HookResult::Abort
          end

          # After hooks
          trigger(after_point, context)
        end

        def has_hooks?(point : HookPoint) : Bool
          @hooks[point].present?
        end

        def hooks_at(point : HookPoint) : Array(RegisteredHook)
          @hooks[point]
        end

        def hook_count : Int32
          @hooks.values.sum(&.size)
        end
      end
    end
  end
end
