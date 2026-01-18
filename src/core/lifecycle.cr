# Lifecycle module - Build event orchestration
#
# This module provides an event-driven architecture for the build process.
# External components (processors, SEO generators, etc.) can hook into
# specific phases of the build lifecycle.
#
# Example usage:
#   lifecycle = Hwaro::Core::Lifecycle::Manager.new
#   lifecycle.before(Phase::Transform, name: "markdown") do |ctx|
#     # Transform markdown content
#     HookResult::Continue
#   end

require "./lifecycle/phases"
require "./lifecycle/hooks"
require "./lifecycle/context"
require "./lifecycle/manager"

module Hwaro
  module Core
    module Lifecycle
      # Re-export for convenience
    end
  end
end
