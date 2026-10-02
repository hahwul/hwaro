require "../../../spec_helper"

private def stats_for(mgr, name)
  mgr.all_stats.find { |s| s[:name] == name }
end

describe Hwaro::Core::Build::CacheManager do
  # ===========================================================================
  # Registration
  # ===========================================================================
  describe "#register" do
    it "registers a cache layer" do
      mgr = Hwaro::Core::Build::CacheManager.new
      cleared = false
      mgr.register("test", "Test cache", runtime: true) { cleared = true; nil }
      mgr.all_stats.map(&.[:name]).should eq(["test"])
    end

    it "registers multiple layers" do
      mgr = Hwaro::Core::Build::CacheManager.new
      mgr.register("a", "Cache A", runtime: true) { nil }
      mgr.register("b", "Cache B", runtime: false) { nil }
      mgr.all_stats.size.should eq(2)
    end
  end

  # ===========================================================================
  # Hit/Miss Tracking
  # ===========================================================================
  describe "#record_hit / #record_miss" do
    it "tracks hits and misses" do
      mgr = Hwaro::Core::Build::CacheManager.new
      mgr.register("test", "Test cache", runtime: true) { nil }

      mgr.record_hit("test")
      mgr.record_hit("test")
      mgr.record_miss("test")

      stats = stats_for(mgr, "test")
      stats.should_not be_nil
      stats = stats.not_nil!
      stats[:hits].should eq(2)
      stats[:misses].should eq(1)
      (stats[:hits] + stats[:misses]).should eq(3)
      stats[:hit_rate].should be_close(66.67, 0.1)
    end

    it "ignores unregistered layer names" do
      mgr = Hwaro::Core::Build::CacheManager.new
      mgr.record_hit("nonexistent")
      mgr.record_miss("nonexistent")
      stats_for(mgr, "nonexistent").should be_nil
    end
  end

  # ===========================================================================
  # CacheStats (internal)
  # ===========================================================================
  describe "CacheStats" do
    it "returns 0 hit rate when no activity" do
      stats = Hwaro::Core::Build::CacheManager::CacheStats.new
      stats.hit_rate.should eq(0.0)
      stats.total.should eq(0)
    end

    it "calculates hit rate correctly" do
      stats = Hwaro::Core::Build::CacheManager::CacheStats.new
      3.times { stats.increment_hit }
      1.times { stats.increment_miss }
      stats.hit_rate.should eq(75.0)
    end

    it "resets counters" do
      stats = Hwaro::Core::Build::CacheManager::CacheStats.new
      5.times { stats.increment_hit }
      3.times { stats.increment_miss }
      stats.reset
      stats.hits.should eq(0)
      stats.misses.should eq(0)
    end
  end

  # ===========================================================================
  # Clear Operations
  # ===========================================================================
  describe "#clear stats" do
    it "resets stats on clear by default" do
      mgr = Hwaro::Core::Build::CacheManager.new
      mgr.register("test", "Test", runtime: true) { nil }
      mgr.record_hit("test")
      mgr.record_miss("test")

      mgr.clear("test")

      stats = stats_for(mgr, "test").not_nil!
      stats[:hits].should eq(0)
      stats[:misses].should eq(0)
    end
  end

  describe "#clear_runtime" do
    it "clears only runtime layers" do
      mgr = Hwaro::Core::Build::CacheManager.new
      runtime_cleared = false
      persistent_cleared = false
      mgr.register("runtime", "Runtime cache", runtime: true) { runtime_cleared = true; nil }
      mgr.register("persistent", "Persistent cache", runtime: false) { persistent_cleared = true; nil }

      mgr.clear_runtime
      runtime_cleared.should be_true
      persistent_cleared.should be_false
    end

    it "preserves stats when reset_stats: false" do
      mgr = Hwaro::Core::Build::CacheManager.new
      mgr.register("runtime", "Runtime", runtime: true) { nil }
      mgr.record_hit("runtime")

      mgr.clear_runtime(reset_stats: false)

      stats_for(mgr, "runtime").not_nil![:hits].should eq(1)
    end
  end

  describe "#clear(*names)" do
    it "clears specific named layers" do
      mgr = Hwaro::Core::Build::CacheManager.new
      a_cleared = false
      b_cleared = false
      c_cleared = false
      mgr.register("a", "A", runtime: true) { a_cleared = true; nil }
      mgr.register("b", "B", runtime: true) { b_cleared = true; nil }
      mgr.register("c", "C", runtime: true) { c_cleared = true; nil }

      mgr.clear("a", "c")
      a_cleared.should be_true
      b_cleared.should be_false
      c_cleared.should be_true
    end

    it "ignores unregistered names" do
      mgr = Hwaro::Core::Build::CacheManager.new
      mgr.clear("nonexistent") # should not raise
    end

    it "preserves stats when reset_stats: false" do
      mgr = Hwaro::Core::Build::CacheManager.new
      mgr.register("a", "A", runtime: true) { nil }
      mgr.record_hit("a")
      mgr.record_hit("a")

      mgr.clear("a", reset_stats: false)

      stats_for(mgr, "a").not_nil![:hits].should eq(2)
    end
  end

  describe "#all_stats" do
    it "returns snapshot of all layers" do
      mgr = Hwaro::Core::Build::CacheManager.new
      mgr.register("a", "Cache A", runtime: true) { nil }
      mgr.register("b", "Cache B", runtime: false) { nil }
      mgr.record_hit("a")
      mgr.record_miss("b")

      stats = mgr.all_stats
      stats.size.should eq(2)

      a_stats = stats.find! { |s| s[:name] == "a" }
      a_stats[:hits].should eq(1)
      a_stats[:misses].should eq(0)
      a_stats[:runtime].should be_true

      b_stats = stats.find! { |s| s[:name] == "b" }
      b_stats[:hits].should eq(0)
      b_stats[:misses].should eq(1)
      b_stats[:runtime].should be_false
    end
  end

  # ===========================================================================
  # Integration with real Hash caches
  # ===========================================================================
  describe "integration with Hash caches" do
    it "clears underlying hash when layer is cleared" do
      mgr = Hwaro::Core::Build::CacheManager.new
      cache = {"key" => "value"}

      mgr.register("hash_cache", "Test hash cache", runtime: true) { cache.clear; nil }

      cache.size.should eq(1)
      mgr.clear_runtime
      cache.size.should eq(0)
    end
  end
end
