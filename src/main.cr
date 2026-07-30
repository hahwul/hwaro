require "./hwaro"

# Size the default execution context so the build's fiber fan-out actually
# runs in parallel.
#
# Hwaro used to get its parallelism from `-Dpreview_mt`. Crystal 1.21
# deprecated that flag ("Resize the default execution context, or start
# additional contexts instead") and its legacy MT scheduler is buggy on the
# way out: under CPU oversubscription the `CRYSTAL-MT-*` worker threads spin
# forever inside `Crystal::EventLoop::Polling#run` → `Crystal::SpinLock#lock`
# and the process never exits, burning a core per thread. Measured on this
# repo's spec harness: 4/120 short-lived `-Dpreview_mt` invocations hung under
# load, 0/120 without the flag — and a hung `hwaro build` in CI never returns.
#
# Without the flag Crystal 1.21 starts a `Fiber::ExecutionContext::Parallel`
# default context, but with parallelism pinned to 1 — which made the docs
# build 3.1x slower (1.46s → 4.58s). `CRYSTAL_WORKERS` alone does NOT fix
# that: it only feeds `default_workers_count`, which nothing consults until
# the context is resized. Resizing here is the migration the deprecation
# message prescribes; every `spawn` in the build pipeline lands in the default
# context, so no call site changes.
Fiber::ExecutionContext.default.resize(Fiber::ExecutionContext.default_workers_count)

Hwaro::CLI::Runner.new.run
