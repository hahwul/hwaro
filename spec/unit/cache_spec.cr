require "../spec_helper"

describe Hwaro::Core::Build::Cache do
  describe "#initialize" do
    it "creates a disabled cache by default when disabled" do
      cache = Hwaro::Core::Build::Cache.new(enabled: false)
      cache.enabled?.should be_false
    end

    it "creates an enabled cache when specified" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.enabled?.should be_true
      end
    end
  end

  describe "#changed?" do
    it "returns true when cache is disabled" do
      cache = Hwaro::Core::Build::Cache.new(enabled: false)
      cache.changed?("any/path.md").should be_true
    end

    it "returns true for non-existent file" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.changed?("non_existent_file.md").should be_true
      end
    end

    it "returns true for file not in cache" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.changed?(test_file).should be_true
      end
    end

    it "returns false for unchanged file in cache" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)
        cache.changed?(test_file).should be_false
      end
    end

    it "returns true when file content changes" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "original content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)

        # Modify file content and update mtime
        sleep 10.milliseconds # Ensure different mtime
        File.write(test_file, "modified content")

        cache.changed?(test_file).should be_true
      end
    end

    it "returns true when output file does not exist" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        output_file = File.join(dir, "output.html")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file, output_file)

        # Check with non-existent output
        cache.changed?(test_file, output_file).should be_true
      end
    end
  end

  describe "#update" do
    it "does nothing when cache is disabled" do
      cache = Hwaro::Core::Build::Cache.new(enabled: false)
      # Should not raise
      cache.update("any/path.md")
    end

    it "stores file entry in cache" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)

        # File should now be considered unchanged
        cache.changed?(test_file).should be_false
      end
    end

    it "stores output path with entry" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        output_file = File.join(dir, "output.html")
        File.write(test_file, "content")
        File.write(output_file, "<p>content</p>")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file, output_file)

        cache.changed?(test_file, output_file).should be_false
      end
    end
  end

  describe "#invalidate" do
    it "removes file from cache" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)
        cache.changed?(test_file).should be_false

        cache.invalidate(test_file)
        cache.changed?(test_file).should be_true
      end
    end
  end

  describe "#clear" do
    it "removes all entries from cache" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file1 = File.join(dir, "test1.md")
        test_file2 = File.join(dir, "test2.md")
        File.write(test_file1, "content1")
        File.write(test_file2, "content2")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file1)
        cache.update(test_file2)
        cache.save

        cache.clear

        cache.stats[:total].should eq(0)
        File.exists?(cache_path).should be_false
      end
    end
  end

  describe "#save and #load" do
    it "persists cache to disk" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        # Create and save cache
        cache1 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache1.update(test_file)
        cache1.save

        File.exists?(cache_path).should be_true

        # Load cache in new instance
        cache2 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache2.changed?(test_file).should be_false
      end
    end

    it "handles corrupted cache file gracefully" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        File.write(cache_path, "invalid json content{{{")

        # Should not raise, just start with empty cache
        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.stats[:total].should eq(0)
      end
    end

    it "does not save when disabled" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")

        cache = Hwaro::Core::Build::Cache.new(enabled: false, cache_path: cache_path)
        cache.save

        File.exists?(cache_path).should be_false
      end
    end
  end

  describe "#filter_changed" do
    it "returns all files when cache is disabled" do
      cache = Hwaro::Core::Build::Cache.new(enabled: false)
      files = ["a.md", "b.md", "c.md"]
      cache.filter_changed(files).should eq(files)
    end

    it "returns only changed files" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        file1 = File.join(dir, "unchanged.md")
        file2 = File.join(dir, "changed.md")
        file3 = File.join(dir, "new.md")

        File.write(file1, "content1")
        File.write(file2, "content2")
        File.write(file3, "content3")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(file1)
        cache.update(file2)

        # Modify file2
        sleep 10.milliseconds
        File.write(file2, "modified content2")

        changed = cache.filter_changed([file1, file2, file3])
        changed.should contain(file2)
        changed.should contain(file3)
        changed.should_not contain(file1)
      end
    end
  end

  describe "#stats" do
    it "returns correct statistics" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        file1 = File.join(dir, "exists.md")
        file2 = File.join(dir, "deleted.md")

        File.write(file1, "content1")
        File.write(file2, "content2")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(file1)
        cache.update(file2)

        # Delete one file
        File.delete(file2)

        stats = cache.stats
        stats[:total].should eq(2)
        stats[:valid].should eq(1)
      end
    end
  end

  describe "#enabled?" do
    it "returns true when enabled" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.enabled?.should be_true
      end
    end

    it "returns false when disabled" do
      cache = Hwaro::Core::Build::Cache.new(enabled: false)
      cache.enabled?.should be_false
    end
  end
end

describe Hwaro::Core::Build::CacheEntry do
  it "serializes and deserializes to JSON" do
    entry = Hwaro::Core::Build::CacheEntry.new(
      path: "test.md",
      mtime: 1234567890_i64,
      hash: "abc123",
      output_path: "test.html"
    )

    json = entry.to_json
    restored = Hwaro::Core::Build::CacheEntry.from_json(json)

    restored.path.should eq("test.md")
    restored.mtime.should eq(1234567890_i64)
    restored.hash.should eq("abc123")
    restored.output_path.should eq("test.html")
  end
end
