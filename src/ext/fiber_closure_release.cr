# A finished fiber keeps its block alive, and with it everything the block
# captured. The execution context's run queues (`Runnables(N)`, a ring of
# Fiber slots) never clear a slot they hand out, so a dead fiber stays
# reachable from its scheduler until that slot is reused — up to 256 per
# scheduler thread. The fiber's `@proc` closure is what makes that expensive:
# a render worker captures the build's global template variables (every
# page's Crinja value), so each `hwaro serve` rebuild left that whole set
# reachable. Measured: ~350 bytes of live heap per page per rebuild (1.7 MB
# per edit on a 5,000-page site) climbing for hundreds of edits.
#
# `Fiber.inactive` runs once, from `Fiber#run`'s ensure after the block has
# returned (and when a thread exits); dropping the block there leaves a dead
# fiber pinning only its own small object. A no-op on a Crystal whose Fiber
# has no `inactive` hook.
class Fiber
  {% if @type.class.has_method?(:inactive) %}
    # :nodoc:
    def hwaro_release_proc : Nil
      @proc = Proc(Void).new { }
    end

    # :nodoc:
    def self.inactive(fiber : Fiber)
      previous_def
      fiber.hwaro_release_proc
    end
  {% end %}
end
