# Unified cache layer management
#
# Provides a single entry point for all runtime caches used during builds.
# Each cache registers with the manager, enabling:
# - Bulk invalidation (clear all / clear runtime only)
# - Selective invalidation for incremental builds
# - Cache hit/miss tracking and stats reporting
# - Debug-friendly status inspection

require "../../utils/logger"

module Hwaro
  module Core
    module Build
      class CacheManager
        # Tracks hit/miss counts for a named cache layer.
        class CacheStats
          property hits : Int64 = 0_i64
          property misses : Int64 = 0_i64

          def initialize
          end

          def total : Int64
            hits + misses
          end

          def hit_rate : Float64
            return 0.0 if total == 0
            (hits.to_f64 / total.to_f64) * 100.0
          end

          def reset
            @hits = 0_i64
            @misses = 0_i64
          end
        end

        # A registered cache layer with its clear callback and stats.
        private class Layer
          property name : String
          property description : String
          property runtime : Bool  # true = per-build runtime cache; false = persistent
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
              layer.stats.hits += 1
            end
          end
        end

        # Record a cache miss for the named layer.
        def record_miss(name : String)
          @mutex.synchronize do
            if layer = @layers[name]?
              layer.stats.misses += 1
            end
          end
        end

        # Clear all registered caches (both runtime and persistent).
        def clear_all
          @mutex.synchronize do
            @layers.each_value do |layer|
              layer.clear_proc.call
              layer.stats.reset
            end
          end
        end

        # Clear only runtime (in-memory) caches, preserving persistent caches.
        def clear_runtime
          @mutex.synchronize do
            @layers.each_value do |layer|
              if layer.runtime
                layer.clear_proc.call
                layer.stats.reset
              end
            end
          end
        end

        # Clear specific named caches.
        def clear(*names : String)
          @mutex.synchronize do
            names.each do |name|
              if layer = @layers[name]?
                layer.clear_proc.call
                layer.stats.reset
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

        # Get stats for a specific cache layer.
        def stats_for(name : String) : CacheStats?
          @mutex.synchronize do
            @layers[name]?.try(&.stats)
          end
        end

        # Return a snapshot of all layer stats as an array of tuples.
        def all_stats : Array({name: String, description: String, runtime: Bool, hits: Int64, misses: Int64, hit_rate: Float64})
          @mutex.synchronize do
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
