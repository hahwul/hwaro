# Parallel processing utilities for concurrent page rendering
#
# Uses Crystal Fibers and Channels for efficient parallel processing.
# Supports batch processing and worker pool patterns.

module Hwaro
  module Core
    module Build
      # Configuration for parallel processing
      struct ParallelConfig
        property enabled : Bool
        property max_workers : Int32
        property batch_size : Int32

        def initialize(
          @enabled : Bool = true,
          @max_workers : Int32 = 0,  # 0 = auto-detect based on CPU count
          @batch_size : Int32 = 10
        )
        end

        # Calculate actual worker count based on CPU and workload
        def calculate_workers(item_count : Int32) : Int32
          return 1 unless @enabled
          return 1 if item_count <= 1

          cpu_count = System.cpu_count.to_i
          default_workers = cpu_count * 2

          workers = @max_workers > 0 ? @max_workers : default_workers
          Math.min(workers, item_count).clamp(1, 64)
        end
      end

      # Result wrapper for parallel operations
      struct WorkResult(T)
        property value : T?
        property success : Bool
        property error : String?
        property index : Int32

        def initialize(@value : T?, @success : Bool, @error : String?, @index : Int32)
        end

        def self.success(value : T, index : Int32) : WorkResult(T)
          new(value: value, success: true, error: nil, index: index)
        end

        def self.failure(error : String, index : Int32) : WorkResult(T)
          new(value: nil, success: false, error: error, index: index)
        end
      end

      # Parallel processor for running work items concurrently
      class Parallel(T, R)
        @config : ParallelConfig

        def initialize(@config : ParallelConfig = ParallelConfig.new)
        end

        # Process items in parallel using a worker pool
        def process(items : Array(T), &block : T, Int32 -> R) : Array(WorkResult(R))
          return [] of WorkResult(R) if items.empty?

          worker_count = @config.calculate_workers(items.size)

          if worker_count == 1 || !@config.enabled
            return process_sequential(items, &block)
          end

          process_parallel(items, worker_count, &block)
        end

        # Map items in parallel, returning only successful results
        def map(items : Array(T), &block : T -> R) : Array(R)
          results = process(items) { |item, _idx| block.call(item) }
          results.select(&.success).compact_map(&.value)
        end

        # Process items in parallel, counting successes
        def count_success(items : Array(T), &block : T, Int32 -> R) : Int32
          results = process(items, &block)
          results.count(&.success)
        end

        private def process_sequential(items : Array(T), &block : T, Int32 -> R) : Array(WorkResult(R))
          results = [] of WorkResult(R)
          items.each_with_index do |item, idx|
            begin
              value = block.call(item, idx)
              results << WorkResult(R).success(value, idx)
            rescue ex
              results << WorkResult(R).failure(ex.message || "Unknown error", idx)
            end
          end
          results
        end

        private def process_parallel(items : Array(T), worker_count : Int32, &block : T, Int32 -> R) : Array(WorkResult(R))
          results = Channel(WorkResult(R)).new(items.size)
          work_queue = Channel({T, Int32}).new(items.size)

          # Enqueue all work items
          items.each_with_index { |item, idx| work_queue.send({item, idx}) }
          work_queue.close

          # Spawn workers
          worker_count.times do
            spawn do
              while work_item = work_queue.receive?
                item, idx = work_item
                begin
                  value = block.call(item, idx)
                  results.send(WorkResult(R).success(value, idx))
                rescue ex
                  results.send(WorkResult(R).failure(ex.message || "Unknown error", idx))
                end
              end
            end
          end

          # Collect results
          collected = [] of WorkResult(R)
          items.size.times do
            collected << results.receive
          end
          collected.sort_by(&.index)
        end
      end

      # Convenience methods for common parallel operations
      module ParallelHelper
        extend self

        # Process pages in parallel with automatic worker configuration
        def process_pages(T)(pages : Array(T), parallel : Bool = true, &block : T, Int32 -> Bool) : Int32
          config = ParallelConfig.new(enabled: parallel)
          processor = Parallel(T, Bool).new(config)
          processor.count_success(pages, &block)
        end

        # Parallel map with default configuration
        def map(T, R)(items : Array(T), parallel : Bool = true, &block : T -> R) : Array(R)
          config = ParallelConfig.new(enabled: parallel)
          processor = Parallel(T, R).new(config)
          processor.map(items, &block)
        end

        # Execute multiple independent tasks in parallel
        def execute(tasks : Array(Proc(Nil)), parallel : Bool = true)
          return if tasks.empty?
          return tasks.each(&.call) unless parallel

          done = Channel(Nil).new(tasks.size)
          tasks.each do |task|
            spawn do
              task.call
              done.send(nil)
            end
          end
          tasks.size.times { done.receive }
        end
      end
    end
  end
end
