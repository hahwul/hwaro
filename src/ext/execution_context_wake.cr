# Crystal 1.21's `Fiber::ExecutionContext::Parallel` pushes a fiber spawned
# from inside the context onto the spawning thread's local queue and wakes
# nobody: only a cross-context enqueue calls `wake_scheduler`, which is also
# what starts the context's threads (lazily). A fan-out spawned by one fiber
# therefore runs on whichever threads happen to be spinning at that moment.
# Measured on 14 cores with 158 CPU-bound items on 28 fibers: 8 threads ever
# ran, one of them 55 items, 3.2x slower than with the idle threads woken.
class Fiber::ExecutionContext::Parallel
  # Unpark (or start) up to *count* idle scheduler threads so they steal the
  # fibers just spawned. A no-op on a Crystal without `wake_scheduler`.
  def wake_idle_schedulers(count : Int32) : Nil
    {% if @type.has_method?(:wake_scheduler) %}
      wake_scheduler(count)
    {% end %}
  end
end
