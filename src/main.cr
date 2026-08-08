require "./hwaro"

# Tune the Boehm GC before the Crystal runtime initializes it.
#
# Boehm reads GC_MARKERS and GC_INITIAL_HEAP_SIZE from the environment only
# once, inside GC_init — which `Crystal.main` runs before any top-level code.
# Redefining `fun main` is the only place early enough to influence them, so
# the values are injected here via setenv (overwrite: 0 keeps any value the
# user exported, preserving both env vars as escape hatches).
#
# Why these defaults (measured on the harsh benchmark corpus, 3000 pages,
# scripts/benchmark_run.cr, release binary, Apple M-series 14-core):
#
#   - GC_MARKERS=1: Boehm spawns one marker thread per core (13 here) and
#     their per-collection coordination dominates alloc-heavy builds. Marker
#     count alone took the default build from 64s to 20s.
#   - GC_INITIAL_HEAP_SIZE=256M: the build is a short-lived, allocate-heavy
#     process where almost nothing survives a collection — the worst shape
#     for growing the heap from Boehm's tiny default via repeated collect +
#     expand cycles. Presizing (with markers=1) reached 13.6s.
#
# Only raw LibC calls are safe here: the GC is not initialized yet, so
# anything that allocates (ENV, String interpolation, exceptions) would
# crash. String literals live in static memory and allocate nothing.
fun main(argc : Int32, argv : UInt8**) : Int32
  LibC.setenv("GC_MARKERS", "1", 0)
  LibC.setenv("GC_INITIAL_HEAP_SIZE", "256M", 0)
  Crystal.main(argc, argv)
end

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
#
# The thread count deliberately stays at the CPU count (a static clamp was
# measured and rejected): highlight/OG-heavy sites like docs/ scale to the
# full core count on macOS and Linux, while template/Crinja-heavy sites
# anti-scale past ~4 threads under the Boehm allocation lock — no single
# static value wins both, so the default favors the common case and
# `--jobs` / `CRYSTAL_WORKERS` remain the per-site escape hatches.
Fiber::ExecutionContext.default.resize(Fiber::ExecutionContext.default_workers_count)

Hwaro::CLI::Runner.new.run
