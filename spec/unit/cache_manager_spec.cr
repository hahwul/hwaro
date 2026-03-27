require "../spec_helper"

describe Hwaro::Core::Build::CacheManager do
  # ===========================================================================
  # Registration
  # ===========================================================================
  describe "#register" do
    it "registers a cache layer" do
      mgr = Hwaro::Core::Build::CacheManager.new
      cleared = false
      mgr.register("test", "Test cache", runtime: true) { cleared = true; nil }
      mgr.size.should eq(1)
      mgr.registered?("test").should be_true
    end

    it "registers multiple layers" do
      mgr = Hwaro::Core::Build::CacheManager.new
      mgr.register("a", "Cache A", runtime: true) { nil }
      mgr.register("b", "Cache B", runtime: false) { nil }
      mgr.size.should eq(2)
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

      stats = mgr.stats_for("test")
      stats.should_not be_nil
      stats = stats.not_nil!
      stats.hits.should eq(2)
      stats.misses.should eq(1)
      stats.total.should eq(3)
      stats.hit_rate.should be_close(66.67, 0.1)
    end

    it "ignores unregistered layer names" do
      mgr = Hwaro::Core::Build::CacheManager.new
      mgr.record_hit("nonexistent")
      mgr.record_miss("nonexistent")
      mgr.stats_for("nonexistent").should be_nil
    end
  end

  # ===========================================================================
  # CacheStats
  # ===========================================================================
  describe "CacheStats" do
    it "returns 0 hit rate when no activity" do
      stats = Hwaro::Core::Build::CacheManager::CacheStats.new
      stats.hit_rate.should eq(0.0)
      stats.total.should eq(0)
    end

    it "calculates hit rate correctly" do
      stats = Hwaro::Core::Build::CacheManager::CacheStats.new
      stats.hits = 3
      stats.misses = 1
      stats.hit_rate.should eq(75.0)
    end

    it "resets counters" do
      stats = Hwaro::Core::Build::CacheManager::CacheStats.new
      stats.hits = 5
      stats.misses = 3
      stats.reset
      stats.hits.should eq(0)
      stats.misses.should eq(0)
    end
  end

  # ===========================================================================
  # Clear Operations
  # ===========================================================================
  describe "#clear_all" do
    it "clears all layers" do
      mgr = Hwaro::Core::Build::CacheManager.new
      a_cleared = false
      b_cleared = false
      mgr.register("a", "Cache A", runtime: true) { a_cleared = true; nil }
      mgr.register("b", "Cache B", runtime: false) { b_cleared = true; nil }

      mgr.clear_all
      a_cleared.should be_true
      b_cleared.should be_true
    end

    it "resets stats on clear" do
      mgr = Hwaro::Core::Build::CacheManager.new
      mgr.register("test", "Test", runtime: true) { nil }
      mgr.record_hit("test")
      mgr.record_miss("test")

      mgr.clear_all

      stats = mgr.stats_for("test").not_nil!
      stats.hits.should eq(0)
      stats.misses.should eq(0)
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
      mgr.clear("nonexistent")  # should not raise
    end
  end

  # ===========================================================================
  # Stats Reporting
  # ===========================================================================
  describe "#reset_stats" do
    it "resets all stats without clearing caches" do
      mgr = Hwaro::Core::Build::CacheManager.new
      cleared = false
      mgr.register("test", "Test", runtime: true) { cleared = true; nil }
      mgr.record_hit("test")

      mgr.reset_stats
      cleared.should be_false  # cache not cleared
      mgr.stats_for("test").not_nil!.hits.should eq(0)
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

      a_stats = stats.find { |s| s[:name] == "a" }.not_nil!
      a_stats[:hits].should eq(1)
      a_stats[:misses].should eq(0)
      a_stats[:runtime].should be_true

      b_stats = stats.find { |s| s[:name] == "b" }.not_nil!
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
