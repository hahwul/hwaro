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
        @debug : Bool

        def initialize(@debug : Bool = false)
          @hooks = {} of HookPoint => Array(RegisteredHook)
          # Initialize empty arrays for all hook points
          HookPoint.each { |point| @hooks[point] = [] of RegisteredHook }
        end

        # ========================================
        # Hook Registration API
        # ========================================

        # Register a hook at a specific point
        def on(point : HookPoint, priority : Int32 = 0, name : String = "anonymous", &block : BuildContext -> HookResult)
          handler = HookHandler.new { |ctx| block.call(ctx) }
          register_hook(point, handler, priority, name)
          self
        end

        # Register hook before a phase
        def before(phase : Phase, priority : Int32 = 0, name : String = "anonymous", &block : BuildContext -> HookResult)
          before_point, _ = Lifecycle.hook_points_for(phase)
          on(before_point, priority, name, &block)
        end

        # Register hook after a phase
        def after(phase : Phase, priority : Int32 = 0, name : String = "anonymous", &block : BuildContext -> HookResult)
          _, after_point = Lifecycle.hook_points_for(phase)
          on(after_point, priority, name, &block)
        end

        # Register a Hookable module
        def register(hookable : Hookable)
          hookable.register_hooks(self)
          self
        end

        # Register handler directly
        def register_hook(point : HookPoint, handler : HookHandler, priority : Int32 = 0, name : String = "anonymous")
          @hooks[point] << RegisteredHook.new(handler, priority, name)
          # Sort by priority descending (higher priority first) — single sort, no reverse
          @hooks[point].sort! { |a, b| b.priority <=> a.priority }
        end

        # ========================================
        # Hook Execution API
        # ========================================

        # Trigger all hooks at a specific point.
        #
        # `Skip` is scoped to the CURRENT hook point (see HookResult's doc:
        # "skip remaining hooks in current phase"): the remaining hooks at
        # this point don't run, but the result is Continue so the phase body
        # and subsequent phases proceed. Only `Abort` (or a raised
        # HwaroError) terminates the build.
        def trigger(point : HookPoint, context : BuildContext) : HookResult
          hooks = @hooks[point]
          return HookResult::Continue if hooks.empty?

          hooks.each do |hook|
            Logger.debug "  → Hook: #{hook.name} @ #{point}" if @debug

            begin
              # Lightweight per-hook timing when --profile is enabled (#561)
              start = if (p = context.profiler) && p.enabled?
                        Time.instant
                      end

              result = hook.handler.call(context)

              if start && (p = context.profiler)
                elapsed = (Time.instant - start).total_milliseconds
                p.record_hook(hook.name, elapsed)
              end

              case result
              when HookResult::Skip
                Logger.info "  ⏭ Remaining hooks at #{point} skipped by hook: #{hook.name}" if @debug
                return HookResult::Continue
              when HookResult::Abort
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
          end

          HookResult::Continue
        end

        # Execute a phase with before/after hooks
        def run_phase(phase : Phase, context : BuildContext, &) : HookResult
          before_point, after_point = Lifecycle.hook_points_for(phase)

          Logger.debug "Phase: #{phase}" if @debug

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

        # Run all phases in sequence
        def run_all_phases(context : BuildContext, &phase_action : Phase ->) : HookResult
          Phase.each do |phase|
            result = run_phase(phase, context) do
              phase_action.call(phase)
            end
            return result if result != HookResult::Continue
          end
          HookResult::Continue
        end

        # ========================================
        # Introspection API
        # ========================================

        def hooks_at(point : HookPoint) : Array(RegisteredHook)
          @hooks[point]
        end

        def has_hooks?(point : HookPoint) : Bool
          @hooks[point].present?
        end

        def hook_count : Int32
          @hooks.values.sum(&.size)
        end

        def clear
          @hooks.each_value(&.clear)
        end

        def clear_point(point : HookPoint)
          @hooks[point].clear
        end

        # List all registered hooks for debugging
        def dump_hooks
          @hooks.each do |point, hooks|
            next if hooks.empty?
            Logger.debug "#{point}:"
            hooks.each do |hook|
              Logger.debug "  - #{hook.name} (priority: #{hook.priority})"
            end
          end
        end
      end

      # Global lifecycle manager instance (optional singleton pattern)
      class_property default : Manager { Manager.new }
    end
  end
end
