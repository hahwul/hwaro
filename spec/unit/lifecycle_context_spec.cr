require "../spec_helper"
require "../../src/core/lifecycle/context"
require "../../src/core/build/cache"

describe Hwaro::Core::Lifecycle::RawFile do
  describe "#initialize" do
    it "sets source_path and relative_path" do
      raw = Hwaro::Core::Lifecycle::RawFile.new("content/data.json", "data.json")
      raw.source_path.should eq("content/data.json")
      raw.relative_path.should eq("data.json")
    end

    it "extracts extension from source_path" do
      raw = Hwaro::Core::Lifecycle::RawFile.new("content/data.json", "data.json")
      raw.extension.should eq(".json")
    end

    it "normalizes extension to lowercase" do
      raw = Hwaro::Core::Lifecycle::RawFile.new("content/data.JSON", "data.JSON")
      raw.extension.should eq(".json")
    end

    it "handles xml extension" do
      raw = Hwaro::Core::Lifecycle::RawFile.new("content/feed.xml", "feed.xml")
      raw.extension.should eq(".xml")
    end

    it "handles files with no extension" do
      raw = Hwaro::Core::Lifecycle::RawFile.new("content/Makefile", "Makefile")
      raw.extension.should eq("")
    end

    it "handles nested paths" do
      raw = Hwaro::Core::Lifecycle::RawFile.new("content/api/v1/data.json", "api/v1/data.json")
      raw.source_path.should eq("content/api/v1/data.json")
      raw.relative_path.should eq("api/v1/data.json")
      raw.extension.should eq(".json")
    end

    it "handles files with multiple dots" do
      raw = Hwaro::Core::Lifecycle::RawFile.new("content/file.test.json", "file.test.json")
      raw.extension.should eq(".json")
    end
  end
end

describe Hwaro::Core::Lifecycle::BuildStats do
  describe "#initialize" do
    it "starts with all counters at zero" do
      stats = Hwaro::Core::Lifecycle::BuildStats.new
      stats.pages_read.should eq(0)
      stats.pages_rendered.should eq(0)
      stats.pages_skipped.should eq(0)
      stats.files_written.should eq(0)
      stats.cache_hits.should eq(0)
      stats.raw_files_processed.should eq(0)
    end

    it "starts with nil times" do
      stats = Hwaro::Core::Lifecycle::BuildStats.new
      stats.start_time.should be_nil
      stats.end_time.should be_nil
    end
  end

  describe "#elapsed" do
    it "returns 0.0 when no start_time is set" do
      stats = Hwaro::Core::Lifecycle::BuildStats.new
      stats.elapsed.should eq(0.0)
    end

    it "returns elapsed time when start and end are set" do
      stats = Hwaro::Core::Lifecycle::BuildStats.new
      stats.start_time = Time.instant
      sleep(5.milliseconds)
      stats.end_time = Time.instant
      stats.elapsed.should be > 0.0
    end

    it "returns elapsed time from start to now when end is not set" do
      stats = Hwaro::Core::Lifecycle::BuildStats.new
      stats.start_time = Time.instant
      sleep(1.milliseconds)
      stats.elapsed.should be > 0.0
    end
  end

  describe "counter mutation" do
    it "can increment pages_read" do
      stats = Hwaro::Core::Lifecycle::BuildStats.new
      stats.pages_read = 5
      stats.pages_read.should eq(5)
    end

    it "can increment pages_rendered" do
      stats = Hwaro::Core::Lifecycle::BuildStats.new
      stats.pages_rendered = 10
      stats.pages_rendered.should eq(10)
    end

    it "can increment pages_skipped" do
      stats = Hwaro::Core::Lifecycle::BuildStats.new
      stats.pages_skipped = 3
      stats.pages_skipped.should eq(3)
    end

    it "can increment files_written" do
      stats = Hwaro::Core::Lifecycle::BuildStats.new
      stats.files_written = 42
      stats.files_written.should eq(42)
    end

    it "can increment cache_hits" do
      stats = Hwaro::Core::Lifecycle::BuildStats.new
      stats.cache_hits = 7
      stats.cache_hits.should eq(7)
    end

    it "can increment raw_files_processed" do
      stats = Hwaro::Core::Lifecycle::BuildStats.new
      stats.raw_files_processed = 2
      stats.raw_files_processed.should eq(2)
    end
  end
end

describe Hwaro::Core::Lifecycle::BuildContext do
  describe "#initialize" do
    it "initializes with build options" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.options.should eq(options)
    end

    it "starts with empty pages array" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.pages.should be_empty
    end

    it "starts with empty sections array" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.sections.should be_empty
    end

    it "starts with empty raw_files array" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.raw_files.should be_empty
    end

    it "starts with empty templates hash" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.templates.should be_empty
    end

    it "starts with empty metadata hash" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.metadata.should be_empty
    end

    it "uses output_dir from options" do
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "dist")
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.output_dir.should eq("dist")
    end

    it "defaults output_dir to public" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.output_dir.should eq("public")
    end

    it "starts with nil site" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.site.should be_nil
    end

    it "starts with nil config" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.config.should be_nil
    end

    it "starts with nil cache" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.cache.should be_nil
    end

    it "initializes BuildStats" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.stats.pages_read.should eq(0)
      ctx.stats.files_written.should eq(0)
    end
  end

  describe "#all_pages" do
    it "returns combined pages and sections" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      page = Hwaro::Models::Page.new("post.md")
      section = Hwaro::Models::Section.new("blog/_index.md")

      ctx.pages << page
      ctx.sections << section

      all = ctx.all_pages
      all.size.should eq(2)
    end

    it "returns empty when both are empty" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.all_pages.should be_empty
    end

    it "returns only pages when no sections" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.pages << Hwaro::Models::Page.new("a.md")
      ctx.pages << Hwaro::Models::Page.new("b.md")

      ctx.all_pages.size.should eq(2)
    end

    it "returns only sections when no pages" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.sections << Hwaro::Models::Section.new("docs/_index.md")

      ctx.all_pages.size.should eq(1)
    end
  end

  describe "#set and #get_string" do
    it "stores and retrieves a string value" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.set("theme", "dark")
      ctx.get_string("theme").should eq("dark")
    end

    it "returns default for missing string key" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.get_string("missing").should eq("")
      ctx.get_string("missing", "fallback").should eq("fallback")
    end

    it "returns default when value is not a string" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.set("flag", true)
      ctx.get_string("flag", "default").should eq("default")
    end
  end

  describe "#set and #get_bool" do
    it "stores and retrieves a bool value" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.set("debug", true)
      ctx.get_bool("debug").should be_true
    end

    it "returns default for missing bool key" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.get_bool("missing").should be_false
      ctx.get_bool("missing", true).should be_true
    end

    it "returns default when value is not a bool" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.set("count", 5)
      ctx.get_bool("count", false).should be_false
    end
  end

  describe "#set and #get_int" do
    it "stores and retrieves an int value" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.set("count", 42)
      ctx.get_int("count").should eq(42)
    end

    it "returns default for missing int key" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.get_int("missing").should eq(0)
      ctx.get_int("missing", 99).should eq(99)
    end

    it "returns default when value is not an int" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.set("name", "hello")
      ctx.get_int("name", 0).should eq(0)
    end
  end

  describe "mutable collections" do
    it "can add pages" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.pages << Hwaro::Models::Page.new("a.md")
      ctx.pages << Hwaro::Models::Page.new("b.md")
      ctx.pages.size.should eq(2)
    end

    it "can add sections" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.sections << Hwaro::Models::Section.new("blog/_index.md")
      ctx.sections.size.should eq(1)
    end

    it "can add raw_files" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.raw_files << Hwaro::Core::Lifecycle::RawFile.new("content/data.json", "data.json")
      ctx.raw_files.size.should eq(1)
      ctx.raw_files.first.extension.should eq(".json")
    end

    it "can add templates" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.templates["page.html"] = "<html>{{ content }}</html>"
      ctx.templates.size.should eq(1)
      ctx.templates["page.html"].should eq("<html>{{ content }}</html>")
    end

    it "can assign site" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)
      ctx.site = site
      ctx.site.should_not be_nil
    end

    it "can assign config" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      config = Hwaro::Models::Config.new
      ctx.config = config
      ctx.config.should_not be_nil
    end

    it "can assign cache" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      cache = Hwaro::Core::Build::Cache.new(enabled: false)
      ctx.cache = cache
      ctx.cache.should_not be_nil
    end

    it "can update output_dir" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.output_dir = "dist"
      ctx.output_dir.should eq("dist")
    end
  end

  describe "stats tracking" do
    it "can update build stats through context" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.stats.pages_read = 10
      ctx.stats.pages_rendered = 8
      ctx.stats.pages_skipped = 2
      ctx.stats.files_written = 15
      ctx.stats.cache_hits = 3
      ctx.stats.raw_files_processed = 4

      ctx.stats.pages_read.should eq(10)
      ctx.stats.pages_rendered.should eq(8)
      ctx.stats.pages_skipped.should eq(2)
      ctx.stats.files_written.should eq(15)
      ctx.stats.cache_hits.should eq(3)
      ctx.stats.raw_files_processed.should eq(4)
    end
  end

  describe "metadata overwrites" do
    it "overwrites existing metadata key" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.set("key", "value1")
      ctx.get_string("key").should eq("value1")

      ctx.set("key", "value2")
      ctx.get_string("key").should eq("value2")
    end

    it "allows different types for different keys" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.set("name", "hwaro")
      ctx.set("debug", true)
      ctx.set("count", 42)
      ctx.set("ratio", 3.14)

      ctx.get_string("name").should eq("hwaro")
      ctx.get_bool("debug").should be_true
      ctx.get_int("count").should eq(42)
    end
  end

  describe "all_pages caching" do
    it "memoizes the combined array across repeated calls" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.pages << Hwaro::Models::Page.new("a.md")
      ctx.sections << Hwaro::Models::Section.new("b/_index.md")

      first = ctx.all_pages
      second = ctx.all_pages
      # Same object identity proves the cached array was reused
      first.should be(second)
    end

    it "returns a stale cached array when pages are mutated in-place" do
      # Documents the known caveat: mutating pages/sections via << does NOT
      # invalidate the cache. Callers must use the assignment setters
      # (#pages= / #sections=) or call invalidate_all_pages_cache.
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.pages << Hwaro::Models::Page.new("a.md")

      first = ctx.all_pages
      first.size.should eq(1)

      ctx.pages << Hwaro::Models::Page.new("b.md")
      # Cache returns the previously-built array (still 1 element)
      ctx.all_pages.size.should eq(1)

      ctx.invalidate_all_pages_cache
      ctx.all_pages.size.should eq(2)
    end
  end

  describe "#pages= setter" do
    it "auto-invalidates the all_pages cache" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.pages << Hwaro::Models::Page.new("a.md")
      ctx.all_pages.size.should eq(1) # warm the cache

      ctx.pages = [
        Hwaro::Models::Page.new("x.md"),
        Hwaro::Models::Page.new("y.md"),
      ]
      ctx.all_pages.size.should eq(2)
      ctx.all_pages.map(&.path).sort.should eq(["x.md", "y.md"])
    end

    it "replaces the pages array" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.pages << Hwaro::Models::Page.new("a.md")
      ctx.pages = [] of Hwaro::Models::Page
      ctx.pages.should be_empty
    end
  end

  describe "#sections= setter" do
    it "auto-invalidates the all_pages cache" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.sections << Hwaro::Models::Section.new("a/_index.md")
      ctx.all_pages.size.should eq(1) # warm the cache

      ctx.sections = [
        Hwaro::Models::Section.new("x/_index.md"),
        Hwaro::Models::Section.new("y/_index.md"),
      ]
      ctx.all_pages.size.should eq(2)
    end

    it "replaces the sections array" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.sections << Hwaro::Models::Section.new("a/_index.md")
      ctx.sections = [] of Hwaro::Models::Section
      ctx.sections.should be_empty
    end
  end

  describe "#invalidate_all_pages_cache" do
    it "rebuilds the array on the next call to all_pages" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.pages << Hwaro::Models::Page.new("a.md")
      first = ctx.all_pages

      ctx.invalidate_all_pages_cache
      second = ctx.all_pages
      # Different object identity proves the array was rebuilt
      first.should_not be(second)
      second.size.should eq(1)
    end

    it "is safe to call when the cache has not been warmed" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      # No prior all_pages call — should not raise
      ctx.invalidate_all_pages_cache
      ctx.all_pages.should be_empty
    end
  end
end
