# Hook system for Hwaro build lifecycle
#
# Hooks allow extending the build process at defined points.
# Handlers are Procs that receive BuildContext and return HookResult.

require "./phases"
require "./context"

module Hwaro
  module Core
    module Lifecycle
      # Result of hook execution
      enum HookResult
        Continue # Proceed to next hook/phase
        Skip     # Skip remaining hooks in current phase
        Abort    # Stop the entire build
      end

      # Hook handler type - receives context, returns result
      alias HookHandler = Proc(BuildContext, HookResult)

      # Registered hook with metadata
      struct RegisteredHook
        property handler : HookHandler
        property priority : Int32 # Higher = runs first
        property name : String    # For debugging/logging

        def initialize(@handler : HookHandler, @priority : Int32 = 0, @name : String = "anonymous")
        end
      end

      # Interface for modules that register hooks
      module Hookable
        abstract def register_hooks(manager : Manager)
      end

      # Simple hook registration via block
      module HookDSL
        macro included
          @@_pending_hooks = [] of Tuple(HookPoint, Int32, String, HookHandler)

          def self.on(point : HookPoint, priority : Int32 = 0, name : String = "hook", &block : BuildContext -> HookResult)
            @@_pending_hooks << {point, priority, name, block}
          end

          def self.before(phase : Phase, priority : Int32 = 0, name : String = "hook", &block : BuildContext -> HookResult)
            before_point, _ = Lifecycle.hook_points_for(phase)
            on(before_point, priority, name, &block)
          end

          def self.after(phase : Phase, priority : Int32 = 0, name : String = "hook", &block : BuildContext -> HookResult)
            _, after_point = Lifecycle.hook_points_for(phase)
            on(after_point, priority, name, &block)
          end

          def self.pending_hooks
            @@_pending_hooks
          end
        end
      end
    end
  end
end
