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
          # Sort by priority descending (higher priority first)
          @hooks[point].sort_by!(&.priority).reverse!
        end

        # ========================================
        # Hook Execution API
        # ========================================

        # Trigger all hooks at a specific point
        def trigger(point : HookPoint, context : BuildContext) : HookResult
          hooks = @hooks[point]
          return HookResult::Continue if hooks.empty?

          hooks.each do |hook|
            Logger.debug "  → Hook: #{hook.name} @ #{point}" if @debug

            begin
              result = hook.handler.call(context)

              case result
              when HookResult::Skip
                Logger.info "  ⏭ Phase skipped by hook: #{hook.name}" if @debug
                return result
              when HookResult::Abort
                Logger.error "  ✖ Build aborted by hook: #{hook.name}"
                return result
              end
            rescue ex
              Logger.error "  ✖ Hook '#{hook.name}' failed: #{ex.message}"
              return HookResult::Abort
            end
          end

          HookResult::Continue
        end

        # Execute a phase with before/after hooks
        def run_phase(phase : Phase, context : BuildContext, &action) : HookResult
          before_point, after_point = Lifecycle.hook_points_for(phase)

          Logger.debug "Phase: #{phase}" if @debug

          # Before hooks
          result = trigger(before_point, context)
          return result if result != HookResult::Continue

          # Phase action
          begin
            yield
          rescue ex
            Logger.error "Phase #{phase} failed: #{ex.message}"
            return HookResult::Abort
          end

          # After hooks
          trigger(after_point, context)
        end

        # Run all phases in sequence
        def run_all_phases(context : BuildContext, &phase_action : Phase -> ) : HookResult
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
          @hooks[point].any?
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
