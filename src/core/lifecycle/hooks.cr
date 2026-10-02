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
    end
  end
end
