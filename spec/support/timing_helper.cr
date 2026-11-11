# The CPU time (user + system, whole process) one call of the block takes,
# best of `runs`; each run repeats the block until it has used `min` of CPU
# time, so a fast block is still measured well above clock and GC noise.
# Scaling specs compare these, not wall time: on a loaded machine a run that
# gets preempted grows in wall time but not in CPU time.
def best_cpu_time(runs : Int32 = 3, min : Time::Span = 50.milliseconds, &) : Time::Span
  Array.new(runs) do
    before = Process.times
    calls = 0
    spent = Time::Span.zero
    until spent >= min
      yield
      calls += 1
      now = Process.times
      spent = (now.utime + now.stime - before.utime - before.stime).seconds
    end
    spent / calls
  end.min
end
