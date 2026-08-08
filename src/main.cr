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
# Scope: `hwaro build` only, and the heap presize additionally steps aside
# for --memory-limit / HWARO_MEMORYLIMIT (the presized floor never shrinks,
# which would defeat the documented memory-cap contract). Every other
# command keeps Boehm's stock behavior on purpose:
#
#   - `serve` is a long-lived process holding page/template caches; the
#     presize would become an all-day RSS floor, and single-threaded
#     marking over its large live set is an unbenchmarked latency risk.
#     Its watch rebuilds simply keep the pre-tuning performance.
#   - If the 256M reservation cannot be satisfied (tight RLIMIT_AS),
#     bdwgc's GC_init aborts the process — that must not be able to take
#     down `--version` or the shell-rc `completion` path.
#
# Only raw LibC calls are safe here: the GC is not initialized yet, so
# anything that allocates (ENV, String interpolation, exceptions) would
# crash. String literals live in static memory and allocate nothing.
# HWARO_GC_TUNED records which variables were injected so top-level code
# can scrub them from the child-process environment after GC_init consumed
# them (setenv would otherwise leak build-shaped GC tuning into user hook
# and deploy commands).
lib LibCExt
  fun strcmp(s1 : UInt8*, s2 : UInt8*) : LibC::Int
  fun strncmp(s1 : UInt8*, s2 : UInt8*, n : LibC::SizeT) : LibC::Int
end

fun main(argc : Int32, argv : UInt8**) : Int32
  command = Pointer(UInt8).null
  memory_limited = !LibC.getenv("HWARO_MEMORYLIMIT").null?
  i = 1
  while i < argc
    arg = argv[i]
    if LibCExt.strncmp(arg, "--memory-limit", 14) == 0
      memory_limited = true
    elsif command.null? && LibCExt.strcmp(arg, "-q") != 0 && LibCExt.strcmp(arg, "--quiet") != 0
      # First non-quiet argument is the command name (mirrors Runner#run,
      # which strips -q/--quiet globally and then shifts the command).
      command = arg
    end
    i += 1
  end

  if !command.null? && LibCExt.strcmp(command, "build") == 0
    set_markers = LibC.getenv("GC_MARKERS").null?
    set_heap = !memory_limited && LibC.getenv("GC_INITIAL_HEAP_SIZE").null?
    LibC.setenv("GC_MARKERS", "1", 0) if set_markers
    LibC.setenv("GC_INITIAL_HEAP_SIZE", "256M", 0) if set_heap
    if set_markers && set_heap
      LibC.setenv("HWARO_GC_TUNED", "mh", 1)
    elsif set_markers
      LibC.setenv("HWARO_GC_TUNED", "m", 1)
    elsif set_heap
      LibC.setenv("HWARO_GC_TUNED", "h", 1)
    end
  end

  # Crystal's Unix main shim ends with LibC.exit so the main fiber may
  # resume on any thread of the parallel execution context; a plain return
  # here would re-enter the C startup frame from whichever thread ran the
  # final continuation. Mirror the shim, never return.
  LibC.exit(Crystal.main(argc, argv))
end

# GC_init has consumed the injected variables above; scrub exactly the ones
# this process injected (HWARO_GC_TUNED says which) so spawned children —
# user build hooks, deploy commands — inherit a clean environment instead
# of build-shaped GC tuning they never asked for. User-exported values were
# never overwritten and are left untouched.
if tuned = ENV["HWARO_GC_TUNED"]?
  ENV.delete("GC_MARKERS") if tuned.includes?('m')
  ENV.delete("GC_INITIAL_HEAP_SIZE") if tuned.includes?('h')
  ENV.delete("HWARO_GC_TUNED")
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
