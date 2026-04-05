# Unified cache layer management
#
# Provides a single entry point for all runtime caches used during builds.
# Each cache registers with the manager, enabling:
# - Bulk invalidation (clear all / clear runtime only)
# - Selective invalidation for incremental builds
# - Cache hit/miss tracking and stats reporting (lock-free via Atomic)
# - Debug-friendly status inspection

require "../../utils/logger"

module Hwaro
  module Core
    module Build
      class CacheManager
        # Lock-free hit/miss counters using Atomic operations.
        # Safe for concurrent access from parallel render fibers
        # without requiring mutex synchronization.
        class CacheStats
          @hits : Atomic(Int64) = Atomic(Int64).new(0_i64)
          @misses : Atomic(Int64) = Atomic(Int64).new(0_i64)

          def initialize
          end

          def hits : Int64
            @hits.get(:relaxed)
          end

          def misses : Int64
            @misses.get(:relaxed)
          end

          def increment_hit
            @hits.add(1, :relaxed)
          end

          def increment_miss
            @misses.add(1, :relaxed)
          end

          def total : Int64
            hits + misses
          end

          def hit_rate : Float64
            t = total
            return 0.0 if t == 0
            (hits.to_f64 / t.to_f64) * 100.0
          end

          def reset
            @hits.set(0_i64, :relaxed)
            @misses.set(0_i64, :relaxed)
          end
        end

        # A registered cache layer with its clear callback and stats.
        private class Layer
          property name : String
          property description : String
          property runtime : Bool # true = per-build runtime cache; false = persistent
          property clear_proc : Proc(Nil)
          property stats : CacheStats

          def initialize(@name, @description, @runtime, @clear_proc)
            @stats = CacheStats.new
          end
        end

        @layers : Hash(String, Layer) = {} of String => Layer
        @mutex : Mutex = Mutex.new(:reentrant)

        def initialize
        end

        # Register a cache layer with the manager.
        # `runtime`: true for per-build in-memory caches, false for persistent (file-based) caches.
        def register(name : String, description : String, runtime : Bool = true, &clear : -> Nil)
          @mutex.synchronize do
            @layers[name] = Layer.new(
              name: name,
              description: description,
              runtime: runtime,
              clear_proc: clear,
            )
          end
        end

        # Record a cache hit for the named layer.
        def record_hit(name : String)
          @mutex.synchronize do
            if layer = @layers[name]?
              layer.stats.increment_hit
            end
          end
        end

        # Record a cache miss for the named layer.
        def record_miss(name : String)
          @mutex.synchronize do
            if layer = @layers[name]?
              layer.stats.increment_miss
            end
          end
        end

        # Clear all registered caches (both runtime and persistent).
        # Pass `reset_stats: false` to preserve hit/miss counters (e.g. for
        # memory-management clears where you still want end-of-build reporting).
        def clear_all(reset_stats : Bool = true)
          @mutex.synchronize do
            @layers.each_value do |layer|
              layer.clear_proc.call
              layer.stats.reset if reset_stats
            end
          end
        end

        # Clear only runtime (in-memory) caches, preserving persistent caches.
        # Pass `reset_stats: false` to preserve hit/miss counters.
        def clear_runtime(reset_stats : Bool = true)
          @mutex.synchronize do
            @layers.each_value do |layer|
              if layer.runtime
                layer.clear_proc.call
                layer.stats.reset if reset_stats
              end
            end
          end
        end

        # Clear specific named caches.
        # Pass `reset_stats: false` to preserve hit/miss counters across clears
        # (useful for streaming batch clears where stats should span the whole build).
        def clear(*names : String, reset_stats : Bool = true)
          @mutex.synchronize do
            names.each do |name|
              if layer = @layers[name]?
                layer.clear_proc.call
                layer.stats.reset if reset_stats
              end
            end
          end
        end

        # Reset all hit/miss counters without clearing cache contents.
        def reset_stats
          @mutex.synchronize do
            @layers.each_value { |layer| layer.stats.reset }
          end
        end

        # Get an immutable stats snapshot for a specific cache layer.
        def stats_for(name : String) : {hits: Int64, misses: Int64, hit_rate: Float64}?
          if layer = @layers[name]?
            s = layer.stats
            {hits: s.hits, misses: s.misses, hit_rate: s.hit_rate}
          end
        end

        # Return a snapshot of all layer stats as an array of named tuples.
        def all_stats : Array({name: String, description: String, runtime: Bool, hits: Int64, misses: Int64, hit_rate: Float64})
          @layers.values.map do |layer|
            {
              name:        layer.name,
              description: layer.description,
              runtime:     layer.runtime,
              hits:        layer.stats.hits,
              misses:      layer.stats.misses,
              hit_rate:    layer.stats.hit_rate,
            }
          end
        end

        # Log cache stats summary. Only logs layers that had activity.
        def report
          active_layers = all_stats.select { |s| s[:hits] > 0 || s[:misses] > 0 }
          return if active_layers.empty?

          Logger.debug "Cache stats:"
          active_layers.each do |s|
            total = s[:hits] + s[:misses]
            Logger.debug "  #{s[:name]}: #{s[:hits]}/#{total} hits (#{s[:hit_rate].round(1)}%)"
          end
        end

        # Verbose report with all layers (including inactive ones).
        def report_verbose
          stats = all_stats
          return if stats.empty?

          Logger.info "Cache layers (#{stats.size} registered):"
          stats.each do |s|
            type_label = s[:runtime] ? "runtime" : "persistent"
            total = s[:hits] + s[:misses]
            if total > 0
              Logger.info "  [#{type_label}] #{s[:name]}: #{s[:hits]}/#{total} hits (#{s[:hit_rate].round(1)}%) — #{s[:description]}"
            else
              Logger.info "  [#{type_label}] #{s[:name]}: no activity — #{s[:description]}"
            end
          end
        end

        # Number of registered layers.
        def size : Int32
          @layers.size
        end

        # Check if a layer is registered.
        def registered?(name : String) : Bool
          @layers.has_key?(name)
        end
      end
    end
  end
end
