require "../spec_helper"

describe Hwaro::Core::Build::Cache do
  # ===========================================================================
  # Initialization
  # ===========================================================================
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

    it "starts with zero entries when no cache file exists" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.stats[:total].should eq(0)
      end
    end

    it "loads existing cache on init" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        c1 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        c1.update(test_file)
        c1.save

        c2 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        c2.stats[:total].should eq(1)
      end
    end

    it "does not load cache when disabled" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        # Write a valid cache file
        File.write(cache_path, %({"metadata":{"template_hash":"","config_hash":""},"entries":[{"path":"x","mtime":0,"hash":"","output_path":""}]}))

        cache = Hwaro::Core::Build::Cache.new(enabled: false, cache_path: cache_path)
        cache.stats[:total].should eq(0)
      end
    end
  end

  # ===========================================================================
  # changed? — core change detection
  # ===========================================================================
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

        sleep 10.milliseconds
        File.write(test_file, "modified content")

        cache.changed?(test_file).should be_true
      end
    end

    it "returns false when file is touched but content is identical" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "same content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)

        sleep 10.milliseconds
        File.write(test_file, "same content")

        cache.changed?(test_file).should be_false
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

        cache.changed?(test_file, output_file).should be_true
      end
    end

    it "returns false when both source and output exist and source unchanged" do
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

    it "returns true when output is deleted after caching" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        output_file = File.join(dir, "output.html")
        File.write(test_file, "content")
        File.write(output_file, "<p>content</p>")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file, output_file)

        File.delete(output_file)
        cache.changed?(test_file, output_file).should be_true
      end
    end

    it "returns true when source is deleted after caching" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)

        File.delete(test_file)
        cache.changed?(test_file).should be_true
      end
    end

    it "returns false when checking without output_path but originally cached with one" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file, "/some/output.html")

        # Check without output_path — output check is skipped (empty string)
        cache.changed?(test_file).should be_false
      end
    end

    it "handles empty file correctly" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "empty.md")
        File.write(test_file, "")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)
        cache.changed?(test_file).should be_false
      end
    end

    it "detects change from empty to non-empty" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)

        sleep 10.milliseconds
        File.write(test_file, "now has content")
        cache.changed?(test_file).should be_true
      end
    end

    it "detects change from non-empty to empty" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "has content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)

        sleep 10.milliseconds
        File.write(test_file, "")
        cache.changed?(test_file).should be_true
      end
    end

    it "handles large files" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "large.md")
        File.write(test_file, "x" * 1_000_000)

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)
        cache.changed?(test_file).should be_false
      end
    end

    it "detects single-byte change in large file" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "large.md")
        content = "a" * 100_000
        File.write(test_file, content)

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)

        sleep 10.milliseconds
        modified = content.sub(/a\z/, "b")
        File.write(test_file, modified)
        cache.changed?(test_file).should be_true
      end
    end

    it "handles files with special characters in path" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "file with spaces.md")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)
        cache.changed?(test_file).should be_false
      end
    end

    it "handles unicode filenames" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "한글파일.md")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)
        cache.changed?(test_file).should be_false
      end
    end

    it "handles binary content" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "binary.bin")
        File.write(test_file, "\x00\x01\x02\xFF\xFE")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)
        cache.changed?(test_file).should be_false
      end
    end

    it "handles file with only newlines" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "newlines.md")
        File.write(test_file, "\n\n\n")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)
        cache.changed?(test_file).should be_false
      end
    end

    it "handles deeply nested file paths" do
      Dir.mktmpdir do |dir|
        nested_dir = File.join(dir, "a", "b", "c", "d", "e")
        FileUtils.mkdir_p(nested_dir)
        test_file = File.join(nested_dir, "deep.md")
        cache_path = File.join(dir, ".hwaro_cache.json")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)
        cache.changed?(test_file).should be_false
      end
    end
  end

  # ===========================================================================
  # update
  # ===========================================================================
  describe "#update" do
    it "does nothing when cache is disabled" do
      cache = Hwaro::Core::Build::Cache.new(enabled: false)
      cache.update("any/path.md")
      cache.stats[:total].should eq(0)
    end

    it "stores file entry in cache" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)

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

    it "does nothing for non-existent files" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update("/nonexistent/file.md")
        cache.stats[:total].should eq(0)
      end
    end

    it "updates existing entry when content changes" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")

        File.write(test_file, "version 1")
        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)

        sleep 10.milliseconds
        File.write(test_file, "version 2")
        cache.update(test_file)

        cache.changed?(test_file).should be_false
        cache.stats[:total].should eq(1) # Still just one entry
      end
    end

    it "skips update when mtime and output_path unchanged (optimization)" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file, "out.html")
        cache.update(test_file, "out.html")
        cache.stats[:total].should eq(1)
      end
    end

    it "re-updates when output_path changes" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        out1 = File.join(dir, "out1.html")
        out2 = File.join(dir, "out2.html")
        File.write(test_file, "content")
        File.write(out1, "html1")
        File.write(out2, "html2")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file, out1)
        cache.changed?(test_file, out1).should be_false

        # Same source, different output path
        cache.update(test_file, out2)
        cache.changed?(test_file, out2).should be_false
      end
    end

    it "handles many files" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        files = (1..50).map do |i|
          path = File.join(dir, "file#{i}.md")
          File.write(path, "content #{i}")
          path
        end

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        files.each { |f| cache.update(f) }

        cache.stats[:total].should eq(50)
        files.each { |f| cache.changed?(f).should be_false }
      end
    end

    it "update then invalidate then update again" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)
        cache.changed?(test_file).should be_false

        cache.invalidate(test_file)
        cache.changed?(test_file).should be_true

        cache.update(test_file)
        cache.changed?(test_file).should be_false
      end
    end
  end

  # ===========================================================================
  # invalidate
  # ===========================================================================
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

    it "is a no-op for files not in cache" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.invalidate("not_in_cache.md")
        cache.stats[:total].should eq(0)
      end
    end

    it "only removes the specified file" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        file1 = File.join(dir, "a.md")
        file2 = File.join(dir, "b.md")
        file3 = File.join(dir, "c.md")
        File.write(file1, "a")
        File.write(file2, "b")
        File.write(file3, "c")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(file1)
        cache.update(file2)
        cache.update(file3)

        cache.invalidate(file2)
        cache.changed?(file1).should be_false
        cache.changed?(file2).should be_true
        cache.changed?(file3).should be_false
        cache.stats[:total].should eq(2)
      end
    end

    it "can invalidate all files one by one" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        files = (1..5).map do |i|
          path = File.join(dir, "f#{i}.md")
          File.write(path, "c#{i}")
          path
        end

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        files.each { |f| cache.update(f) }
        cache.stats[:total].should eq(5)

        files.each { |f| cache.invalidate(f) }
        cache.stats[:total].should eq(0)
      end
    end
  end

  # ===========================================================================
  # clear
  # ===========================================================================
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

    it "handles clear when cache file doesn't exist" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.clear
        cache.stats[:total].should eq(0)
      end
    end

    it "makes all previously cached files report as changed" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)
        cache.changed?(test_file).should be_false

        cache.clear
        cache.changed?(test_file).should be_true
      end
    end

    it "allows re-populating after clear" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(test_file)
        cache.clear
        cache.update(test_file)
        cache.changed?(test_file).should be_false
        cache.stats[:total].should eq(1)
      end
    end
  end

  # ===========================================================================
  # save and load — persistence
  # ===========================================================================
  describe "#save and #load" do
    it "persists cache to disk" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")

        cache1 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache1.update(test_file)
        cache1.save

        File.exists?(cache_path).should be_true

        cache2 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache2.changed?(test_file).should be_false
      end
    end

    it "loads legacy cache format (plain array without metadata)" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")
        mtime = File.info(test_file).modification_time.to_unix_ms

        legacy_json = %([{"path":"#{test_file}","mtime":#{mtime},"hash":"","output_path":""}])
        File.write(cache_path, legacy_json)

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.stats[:total].should eq(1)
        cache.changed?(test_file).should be_false
      end
    end

    it "loads new format entries that are missing optional fields" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")
        mtime = File.info(test_file).modification_time.to_unix_ms

        new_json = <<-JSON
          {
            "metadata":{"template_hash":"abc","config_hash":"def"},
            "entries":[{"path":"#{test_file}","mtime":#{mtime},"hash":"","output_path":""}]
          }
          JSON
        File.write(cache_path, new_json)

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.stats[:total].should eq(1)
        cache.changed?(test_file).should be_false
      end
    end

    it "handles corrupted cache file gracefully" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        File.write(cache_path, "invalid json content{{{")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.stats[:total].should eq(0)
      end
    end

    it "handles empty cache file" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        File.write(cache_path, "")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.stats[:total].should eq(0)
      end
    end

    it "handles cache file with empty entries array" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        File.write(cache_path, %({"metadata":{"template_hash":"","config_hash":""},"entries":[]}))

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.stats[:total].should eq(0)
      end
    end

    it "handles cache file with unknown extra fields in entries" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        File.write(test_file, "content")
        mtime = File.info(test_file).modification_time.to_unix_ms

        json_with_extra = <<-JSON
          {
            "metadata":{"template_hash":"","config_hash":""},
            "entries":[{"path":"#{test_file}","mtime":#{mtime},"hash":"","output_path":"","unknown_field":"value"}]
          }
          JSON
        File.write(cache_path, json_with_extra)

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.stats[:total].should eq(1)
      end
    end

    it "handles cache file that is valid JSON but wrong structure" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        File.write(cache_path, %({"random": "data"}))

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.stats[:total].should eq(0)
      end
    end

    it "handles cache file that is JSON null" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        File.write(cache_path, "null")

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

    it "preserves multiple entries across save/load cycles" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        files = (1..5).map do |i|
          path = File.join(dir, "file#{i}.md")
          File.write(path, "content #{i}")
          path
        end

        cache1 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        files.each { |f| cache1.update(f) }
        cache1.save

        cache2 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache2.stats[:total].should eq(5)
        files.each { |f| cache2.changed?(f).should be_false }
      end
    end

    it "round-trips output_path through save/load" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        test_file = File.join(dir, "test.md")
        output_file = File.join(dir, "output.html")
        File.write(test_file, "content")
        File.write(output_file, "<p>content</p>")

        cache1 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache1.update(test_file, output_file)
        cache1.save

        cache2 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache2.changed?(test_file, output_file).should be_false
      end
    end

    it "multiple save/load cycles preserve correct state" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        f1 = File.join(dir, "f1.md")
        f2 = File.join(dir, "f2.md")
        File.write(f1, "v1")
        File.write(f2, "v1")

        # Cycle 1: cache both
        c1 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        c1.update(f1)
        c1.update(f2)
        c1.save

        # Cycle 2: modify f1, rebuild
        sleep 10.milliseconds
        File.write(f1, "v2")

        c2 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        c2.changed?(f1).should be_true
        c2.changed?(f2).should be_false
        c2.update(f1)
        c2.save

        # Cycle 3: both should be cached
        c3 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        c3.changed?(f1).should be_false
        c3.changed?(f2).should be_false
      end
    end

    it "handles overwriting old cache file" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        f1 = File.join(dir, "old.md")
        f2 = File.join(dir, "new.md")
        File.write(f1, "old")
        File.write(f2, "new")

        c1 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        c1.update(f1)
        c1.save

        # New cache overwrites
        c2 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        c2.update(f2)
        c2.save

        # Load: should have both (f1 from loaded, f2 from update)
        c3 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        c3.stats[:total].should eq(2)
      end
    end
  end

  # ===========================================================================
  # filter_changed
  # ===========================================================================
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

        sleep 10.milliseconds
        File.write(file2, "modified content2")

        changed = cache.filter_changed([file1, file2, file3])
        changed.should contain(file2)
        changed.should contain(file3)
        changed.should_not contain(file1)
      end
    end

    it "returns empty array when nothing changed" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        file1 = File.join(dir, "a.md")
        file2 = File.join(dir, "b.md")
        File.write(file1, "a")
        File.write(file2, "b")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.update(file1)
        cache.update(file2)

        cache.filter_changed([file1, file2]).should be_empty
      end
    end

    it "handles empty input array" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        cache.filter_changed([] of String).should be_empty
      end
    end

    it "includes non-existent files as changed" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        changed = cache.filter_changed(["ghost1.md", "ghost2.md"])
        changed.size.should eq(2)
      end
    end

    it "preserves order of changed files" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        files = (1..5).map do |i|
          path = File.join(dir, "f#{i}.md")
          File.write(path, "c#{i}")
          path
        end

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        # Only cache f1 and f3
        cache.update(files[0])
        cache.update(files[2])

        changed = cache.filter_changed(files)
        changed.should eq([files[1], files[3], files[4]])
      end
    end
  end

  # ===========================================================================
  # stats
  # ===========================================================================
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

        File.delete(file2)

        stats = cache.stats
        stats[:total].should eq(2)
        stats[:valid].should eq(1)
      end
    end

    it "returns zero for empty cache" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        stats = cache.stats
        stats[:total].should eq(0)
        stats[:valid].should eq(0)
      end
    end

    it "counts all valid when none deleted" do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, ".hwaro_cache.json")
        files = (1..3).map do |i|
          path = File.join(dir, "f#{i}.md")
          File.write(path, "c#{i}")
          path
        end

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
        files.each { |f| cache.update(f) }

        stats = cache.stats
        stats[:total].should eq(3)
        stats[:valid].should eq(3)
      end
    end
  end

  # ===========================================================================
  # enabled?
  # ===========================================================================
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

# ===========================================================================
# CacheEntry serialization
# ===========================================================================
describe Hwaro::Core::Build::CacheEntry do
  it "serializes and deserializes to JSON" do
    entry = Hwaro::Core::Build::CacheEntry.new(
      path: "test.md",
      mtime: 1234567890_i64,
      hash: "abc123",
      output_path: "test.html",
      template_hash: "tmpl_hash",
      config_hash: "cfg_hash",
    )

    json = entry.to_json
    restored = Hwaro::Core::Build::CacheEntry.from_json(json)

    restored.path.should eq("test.md")
    restored.mtime.should eq(1234567890_i64)
    restored.hash.should eq("abc123")
    restored.output_path.should eq("test.html")
    restored.template_hash.should eq("tmpl_hash")
    restored.config_hash.should eq("cfg_hash")
  end

  it "handles missing optional fields on deserialize" do
    json = %({"path":"test.md","mtime":123,"hash":"abc","output_path":"out.html"})
    entry = Hwaro::Core::Build::CacheEntry.from_json(json)
    entry.template_hash.should eq("")
    entry.config_hash.should eq("")
  end

  it "handles entry with empty strings" do
    entry = Hwaro::Core::Build::CacheEntry.new(
      path: "",
      mtime: 0_i64,
      hash: "",
      output_path: "",
    )
    json = entry.to_json
    restored = Hwaro::Core::Build::CacheEntry.from_json(json)
    restored.path.should eq("")
    restored.mtime.should eq(0_i64)
  end

  it "handles entry with large mtime" do
    entry = Hwaro::Core::Build::CacheEntry.new(
      path: "test.md",
      mtime: 9999999999999_i64,
      hash: "abc",
      output_path: "out.html",
    )
    json = entry.to_json
    restored = Hwaro::Core::Build::CacheEntry.from_json(json)
    restored.mtime.should eq(9999999999999_i64)
  end

  it "handles entry with unicode path" do
    entry = Hwaro::Core::Build::CacheEntry.new(
      path: "content/한글/포스트.md",
      mtime: 100_i64,
      hash: "abc",
      output_path: "public/한글/포스트/index.html",
    )
    json = entry.to_json
    restored = Hwaro::Core::Build::CacheEntry.from_json(json)
    restored.path.should eq("content/한글/포스트.md")
    restored.output_path.should eq("public/한글/포스트/index.html")
  end

  it "ignores unknown fields during deserialization" do
    json = %({"path":"test.md","mtime":100,"hash":"abc","output_path":"out.html","future_field":42,"another":"new"})
    entry = Hwaro::Core::Build::CacheEntry.from_json(json)
    entry.path.should eq("test.md")
    entry.hash.should eq("abc")
  end
end

# ===========================================================================
# Global checksums — template and config invalidation
# ===========================================================================
describe Hwaro::Core::Build::Cache, "global checksums" do
  it "invalidates all entries when template hash changes" do
    Dir.mktmpdir do |dir|
      cache_path = File.join(dir, ".hwaro_cache.json")
      test_file = File.join(dir, "test.md")
      File.write(test_file, "content")

      cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache.set_global_checksums("tmpl_v1", "cfg_v1")
      cache.update(test_file)
      cache.save

      cache2 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache2.set_global_checksums("tmpl_v2", "cfg_v1")

      cache2.changed?(test_file).should be_true
    end
  end

  it "invalidates all entries when config hash changes" do
    Dir.mktmpdir do |dir|
      cache_path = File.join(dir, ".hwaro_cache.json")
      test_file = File.join(dir, "test.md")
      File.write(test_file, "content")

      cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache.set_global_checksums("tmpl_v1", "cfg_v1")
      cache.update(test_file)
      cache.save

      cache2 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache2.set_global_checksums("tmpl_v1", "cfg_v2")

      cache2.changed?(test_file).should be_true
    end
  end

  it "invalidates when both template and config change" do
    Dir.mktmpdir do |dir|
      cache_path = File.join(dir, ".hwaro_cache.json")
      test_file = File.join(dir, "test.md")
      File.write(test_file, "content")

      cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache.set_global_checksums("tmpl_v1", "cfg_v1")
      cache.update(test_file)
      cache.save

      cache2 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache2.set_global_checksums("tmpl_v2", "cfg_v2")

      cache2.changed?(test_file).should be_true
    end
  end

  it "preserves entries when checksums are unchanged" do
    Dir.mktmpdir do |dir|
      cache_path = File.join(dir, ".hwaro_cache.json")
      test_file = File.join(dir, "test.md")
      File.write(test_file, "content")

      cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache.set_global_checksums("tmpl_v1", "cfg_v1")
      cache.update(test_file)
      cache.save

      cache2 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache2.set_global_checksums("tmpl_v1", "cfg_v1")

      cache2.changed?(test_file).should be_false
    end
  end

  it "does not invalidate on first build (empty metadata)" do
    Dir.mktmpdir do |dir|
      cache_path = File.join(dir, ".hwaro_cache.json")
      test_file = File.join(dir, "test.md")
      File.write(test_file, "content")

      cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache.set_global_checksums("tmpl_v1", "cfg_v1")
      cache.update(test_file)

      cache.changed?(test_file).should be_false
    end
  end

  it "handles calling set_global_checksums multiple times" do
    Dir.mktmpdir do |dir|
      cache_path = File.join(dir, ".hwaro_cache.json")
      test_file = File.join(dir, "test.md")
      File.write(test_file, "content")

      cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache.set_global_checksums("v1", "v1")
      cache.update(test_file)

      # Call again with same values — should not invalidate
      cache.set_global_checksums("v1", "v1")
      cache.changed?(test_file).should be_false
    end
  end

  it "invalidates all entries, not just some" do
    Dir.mktmpdir do |dir|
      cache_path = File.join(dir, ".hwaro_cache.json")
      files = (1..5).map do |i|
        path = File.join(dir, "f#{i}.md")
        File.write(path, "c#{i}")
        path
      end

      cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache.set_global_checksums("v1", "v1")
      files.each { |f| cache.update(f) }
      cache.save

      cache2 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache2.set_global_checksums("v2", "v1")

      files.each { |f| cache2.changed?(f).should be_true }
    end
  end

  it "allows rebuilding cache after invalidation" do
    Dir.mktmpdir do |dir|
      cache_path = File.join(dir, ".hwaro_cache.json")
      test_file = File.join(dir, "test.md")
      File.write(test_file, "content")

      cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache.set_global_checksums("v1", "v1")
      cache.update(test_file)
      cache.save

      # Load with new template → invalidates
      cache2 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache2.set_global_checksums("v2", "v1")
      cache2.changed?(test_file).should be_true

      # Re-cache and save
      cache2.update(test_file)
      cache2.save

      # Load again with same v2 → should be cached
      cache3 = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache3.set_global_checksums("v2", "v1")
      cache3.changed?(test_file).should be_false
    end
  end
end

# ===========================================================================
# Compute helpers
# ===========================================================================
describe Hwaro::Core::Build::Cache, "compute helpers" do
  it "computes consistent template hash" do
    templates = {"page" => "<p>{{ content }}</p>", "default" => "<html>{{ content }}</html>"}
    hash1 = Hwaro::Core::Build::Cache.compute_templates_hash(templates)
    hash2 = Hwaro::Core::Build::Cache.compute_templates_hash(templates)
    hash1.should eq(hash2)
  end

  it "produces different hash for different templates" do
    t1 = {"page" => "<p>v1</p>"}
    t2 = {"page" => "<p>v2</p>"}
    Hwaro::Core::Build::Cache.compute_templates_hash(t1).should_not eq(
      Hwaro::Core::Build::Cache.compute_templates_hash(t2)
    )
  end

  it "produces different hash for different template names" do
    t1 = {"page" => "<p>same</p>"}
    t2 = {"other" => "<p>same</p>"}
    Hwaro::Core::Build::Cache.compute_templates_hash(t1).should_not eq(
      Hwaro::Core::Build::Cache.compute_templates_hash(t2)
    )
  end

  it "produces consistent hash regardless of insertion order" do
    t1 = {"a" => "1", "b" => "2", "c" => "3"}
    t2 = {"c" => "3", "a" => "1", "b" => "2"}
    Hwaro::Core::Build::Cache.compute_templates_hash(t1).should eq(
      Hwaro::Core::Build::Cache.compute_templates_hash(t2)
    )
  end

  it "handles empty template set" do
    hash = Hwaro::Core::Build::Cache.compute_templates_hash({} of String => String)
    hash.should_not be_empty
  end

  it "handles single template" do
    hash = Hwaro::Core::Build::Cache.compute_templates_hash({"only" => "content"})
    hash.should_not be_empty
  end

  it "detects even tiny template changes" do
    t1 = {"page" => "a"}
    t2 = {"page" => "b"}
    Hwaro::Core::Build::Cache.compute_templates_hash(t1).should_not eq(
      Hwaro::Core::Build::Cache.compute_templates_hash(t2)
    )
  end

  it "computes config hash from file" do
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "config.toml")
      File.write(config_path, "title = \"test\"")
      hash = Hwaro::Core::Build::Cache.compute_config_hash(config_path)
      hash.should_not be_empty
    end
  end

  it "returns empty string for missing config" do
    Hwaro::Core::Build::Cache.compute_config_hash("/nonexistent/config.toml").should eq("")
  end

  it "produces different hash for different config content" do
    Dir.mktmpdir do |dir|
      path1 = File.join(dir, "config1.toml")
      path2 = File.join(dir, "config2.toml")
      File.write(path1, "title = \"v1\"")
      File.write(path2, "title = \"v2\"")

      h1 = Hwaro::Core::Build::Cache.compute_config_hash(path1)
      h2 = Hwaro::Core::Build::Cache.compute_config_hash(path2)
      h1.should_not eq(h2)
    end
  end

  it "computes consistent config hash" do
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "config.toml")
      File.write(config_path, "title = \"test\"")

      h1 = Hwaro::Core::Build::Cache.compute_config_hash(config_path)
      h2 = Hwaro::Core::Build::Cache.compute_config_hash(config_path)
      h1.should eq(h2)
    end
  end
end

# ===========================================================================
# compute_file_hash
# ===========================================================================
describe Hwaro::Core::Build::Cache, "#compute_file_hash" do
  it "produces consistent hash for same content" do
    Dir.mktmpdir do |dir|
      cache_path = File.join(dir, ".hwaro_cache.json")
      f = File.join(dir, "test.md")
      File.write(f, "hello world")

      cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      h1 = cache.compute_file_hash(f)
      h2 = cache.compute_file_hash(f)
      h1.should eq(h2)
    end
  end

  it "produces different hash for different content" do
    Dir.mktmpdir do |dir|
      cache_path = File.join(dir, ".hwaro_cache.json")
      f1 = File.join(dir, "a.md")
      f2 = File.join(dir, "b.md")
      File.write(f1, "content A")
      File.write(f2, "content B")

      cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      cache.compute_file_hash(f1).should_not eq(cache.compute_file_hash(f2))
    end
  end

  it "handles empty file" do
    Dir.mktmpdir do |dir|
      cache_path = File.join(dir, ".hwaro_cache.json")
      f = File.join(dir, "empty.md")
      File.write(f, "")

      cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      hash = cache.compute_file_hash(f)
      hash.should_not be_empty
    end
  end

  it "handles binary content" do
    Dir.mktmpdir do |dir|
      cache_path = File.join(dir, ".hwaro_cache.json")
      f = File.join(dir, "bin")
      File.write(f, "\x00\xFF\xFE\x01")

      cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: cache_path)
      hash = cache.compute_file_hash(f)
      hash.should_not be_empty
    end
  end
end
