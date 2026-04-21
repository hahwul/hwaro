require "../spec_helper"
require "../../src/core/build/parallel"

describe Hwaro::Core::Build::ParallelConfig do
  describe "#initialize" do
    it "has sensible defaults" do
      config = Hwaro::Core::Build::ParallelConfig.new
      config.enabled.should be_true
      config.max_workers.should eq(0)
      config.batch_size.should eq(10)
    end

    it "accepts custom values" do
      config = Hwaro::Core::Build::ParallelConfig.new(
        enabled: false,
        max_workers: 4,
        batch_size: 20
      )
      config.enabled.should be_false
      config.max_workers.should eq(4)
      config.batch_size.should eq(20)
    end
  end

  describe "#calculate_workers" do
    it "returns 1 when disabled" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: false)
      config.calculate_workers(100).should eq(1)
    end

    it "returns 1 when item_count is 0" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true)
      config.calculate_workers(0).should eq(1)
    end

    it "returns 1 when item_count is 1" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true)
      config.calculate_workers(1).should eq(1)
    end

    it "does not exceed item_count" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true, max_workers: 100)
      config.calculate_workers(3).should be <= 3
    end

    it "does not exceed MAX_PARALLEL_WORKERS" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true, max_workers: 0)
      config.calculate_workers(10000).should be <= Hwaro::Core::Build::MAX_PARALLEL_WORKERS
    end

    it "respects explicit max_workers" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true, max_workers: 2)
      config.calculate_workers(100).should eq(2)
    end

    it "uses auto-detect when max_workers is 0" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true, max_workers: 0)
      workers = config.calculate_workers(1000)
      workers.should be >= 1
      workers.should be <= Hwaro::Core::Build::MAX_PARALLEL_WORKERS
    end

    it "clamps workers to at least 1" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true, max_workers: 1)
      config.calculate_workers(5).should be >= 1
    end
  end
end

describe Hwaro::Core::Build::WorkResult do
  describe ".success" do
    it "creates a successful result" do
      result = Hwaro::Core::Build::WorkResult(String).success("hello", 0)
      result.success.should be_true
      result.value.should eq("hello")
      result.error.should be_nil
      result.index.should eq(0)
    end

    it "stores the index" do
      result = Hwaro::Core::Build::WorkResult(Int32).success(42, 7)
      result.index.should eq(7)
      result.value.should eq(42)
    end
  end

  describe ".failure" do
    it "creates a failed result" do
      result = Hwaro::Core::Build::WorkResult(String).failure("something broke", 3)
      result.success.should be_false
      result.value.should be_nil
      result.error.should eq("something broke")
      result.index.should eq(3)
    end
  end
end

describe Hwaro::Core::Build::Parallel do
  describe "#process" do
    it "returns empty array for empty input" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true)
      processor = Hwaro::Core::Build::Parallel(String, String).new(config)
      results = processor.process([] of String) { |item, _| item.upcase }
      results.should be_empty
    end

    it "processes items sequentially when disabled" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: false)
      processor = Hwaro::Core::Build::Parallel(Int32, Int32).new(config)

      items = [1, 2, 3, 4, 5]
      results = processor.process(items) { |item, _| item * 2 }

      results.size.should eq(5)
      results.all?(&.success).should be_true
      results.map(&.value.not_nil!).should eq([2, 4, 6, 8, 10])
    end

    it "processes items sequentially for single item" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true)
      processor = Hwaro::Core::Build::Parallel(String, String).new(config)

      results = processor.process(["hello"]) { |item, _| item.upcase }
      results.size.should eq(1)
      results.first.success.should be_true
      results.first.value.should eq("HELLO")
      results.first.index.should eq(0)
    end

    it "processes items in parallel when enabled with multiple items" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true, max_workers: 2)
      processor = Hwaro::Core::Build::Parallel(Int32, Int32).new(config)

      items = [1, 2, 3, 4, 5, 6, 7, 8]
      results = processor.process(items) { |item, _| item * 10 }

      results.size.should eq(8)
      results.all?(&.success).should be_true

      # Results should be sorted by index
      results.map(&.index).should eq([0, 1, 2, 3, 4, 5, 6, 7])

      # Values should be correct regardless of processing order
      values = results.sort_by(&.index).map(&.value.not_nil!)
      values.should eq([10, 20, 30, 40, 50, 60, 70, 80])
    end

    it "captures exceptions as failures in sequential mode" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: false)
      processor = Hwaro::Core::Build::Parallel(Int32, Int32).new(config)

      items = [1, 0, 3]
      results = processor.process(items) do |item, _|
        raise "division error" if item == 0
        10 // item
      end

      results.size.should eq(3)
      results[0].success.should be_true
      results[0].value.should eq(10)
      results[1].success.should be_false
      results[1].error.should eq("division error")
      results[2].success.should be_true
      results[2].value.should eq(3)
    end

    it "captures exceptions as failures in parallel mode" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true, max_workers: 2)
      processor = Hwaro::Core::Build::Parallel(Int32, String).new(config)

      items = [1, 2, 3, 4, 5]
      results = processor.process(items) do |item, _|
        raise "bad item" if item == 3
        "ok-#{item}"
      end

      results.size.should eq(5)

      sorted = results.sort_by(&.index)
      sorted[0].success.should be_true
      sorted[0].value.should eq("ok-1")
      sorted[1].success.should be_true
      sorted[1].value.should eq("ok-2")
      sorted[2].success.should be_false
      sorted[2].error.should eq("bad item")
      sorted[3].success.should be_true
      sorted[3].value.should eq("ok-4")
      sorted[4].success.should be_true
      sorted[4].value.should eq("ok-5")
    end

    it "preserves index ordering in results" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true, max_workers: 4)
      processor = Hwaro::Core::Build::Parallel(Int32, Int32).new(config)

      items = (0...20).to_a
      results = processor.process(items) { |item, _| item }

      results.map(&.index).should eq((0...20).to_a)
    end
  end

  describe "#map" do
    it "returns only successful values" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: false)
      processor = Hwaro::Core::Build::Parallel(Int32, String).new(config)

      items = [1, 2, 3]
      results = processor.map(items) { |item| "item-#{item}" }
      results.should eq(["item-1", "item-2", "item-3"])
    end

    it "skips failed items" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: false)
      processor = Hwaro::Core::Build::Parallel(Int32, String).new(config)

      items = [1, 2, 3]
      results = processor.map(items) do |item|
        raise "skip" if item == 2
        "item-#{item}"
      end
      results.should eq(["item-1", "item-3"])
    end

    it "returns empty array for empty input" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true)
      processor = Hwaro::Core::Build::Parallel(String, String).new(config)
      results = processor.map([] of String) { |item| item }
      results.should be_empty
    end
  end

  describe "#count_success" do
    it "counts successful items" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: false)
      processor = Hwaro::Core::Build::Parallel(Int32, Bool).new(config)

      items = [1, 2, 3, 4, 5]
      count = processor.count_success(items) { |_, _| true }
      count.should eq(5)
    end

    it "excludes failed items from count" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: false)
      processor = Hwaro::Core::Build::Parallel(Int32, Bool).new(config)

      items = [1, 2, 3, 4, 5]
      count = processor.count_success(items) do |item, _|
        raise "fail" if item % 2 == 0
        true
      end
      count.should eq(3) # 1, 3, 5 succeed
    end

    it "returns 0 for empty input" do
      config = Hwaro::Core::Build::ParallelConfig.new(enabled: true)
      processor = Hwaro::Core::Build::Parallel(String, Bool).new(config)
      count = processor.count_success([] of String) { |_, _| true }
      count.should eq(0)
    end
  end
end

describe Hwaro::Core::Build::ParallelHelper do
  describe ".process_pages" do
    it "processes items and counts successes" do
      items = ["a", "b", "c", "d"]
      count = Hwaro::Core::Build::ParallelHelper.process_pages(items, parallel: false) do |_, _|
        true
      end
      count.should eq(4)
    end

    it "counts only successful items" do
      items = [1, 2, 3, 4, 5]
      count = Hwaro::Core::Build::ParallelHelper.process_pages(items, parallel: false) do |item, _|
        raise "skip even" if item % 2 == 0
        true
      end
      count.should eq(3)
    end

    it "handles empty array" do
      items = [] of String
      count = Hwaro::Core::Build::ParallelHelper.process_pages(items, parallel: false) do |_, _|
        true
      end
      count.should eq(0)
    end
  end

  describe ".map" do
    it "maps items with transformation" do
      items = [1, 2, 3]
      result = Hwaro::Core::Build::ParallelHelper.map(items, parallel: false) do |item|
        item.to_s
      end
      result.should eq(["1", "2", "3"])
    end

    it "skips items that raise exceptions" do
      items = [1, 2, 3, 4]
      result = Hwaro::Core::Build::ParallelHelper.map(items, parallel: false) do |item|
        raise "skip" if item == 3
        item * 10
      end
      result.should eq([10, 20, 40])
    end

    it "handles empty array" do
      items = [] of Int32
      result = Hwaro::Core::Build::ParallelHelper.map(items, parallel: false) do |item|
        item * 2
      end
      result.should be_empty
    end
  end

  describe ".execute" do
    it "executes all tasks" do
      counter = Atomic(Int32).new(0)
      tasks = [
        -> { counter.add(1); nil },
        -> { counter.add(1); nil },
        -> { counter.add(1); nil },
      ]

      Hwaro::Core::Build::ParallelHelper.execute(tasks, parallel: false)
      counter.get.should eq(3)
    end

    it "handles empty task list" do
      tasks = [] of Proc(Nil)
      Hwaro::Core::Build::ParallelHelper.execute(tasks, parallel: false)
      # Should not raise
    end

    it "executes tasks in parallel" do
      counter = Atomic(Int32).new(0)
      tasks = [
        -> { counter.add(1); nil },
        -> { counter.add(1); nil },
        -> { counter.add(1); nil },
        -> { counter.add(1); nil },
      ]

      Hwaro::Core::Build::ParallelHelper.execute(tasks, parallel: true)
      counter.get.should eq(4)
    end
  end
end

describe "MAX_PARALLEL_WORKERS" do
  it "is a positive integer" do
    Hwaro::Core::Build::MAX_PARALLEL_WORKERS.should be > 0
  end

  it "is 64" do
    Hwaro::Core::Build::MAX_PARALLEL_WORKERS.should eq(64)
  end
end
