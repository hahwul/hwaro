require "../../../../spec_helper"
require "../../../../../src/core/build/builder"

# Reopen Builder to expose the private finalize phase entry point.
module Hwaro::Core::Build
  class Builder
    def test_run_finalize(ctx : Lifecycle::BuildContext, profiler : Profiler)
      execute_finalize_phase(ctx, profiler)
    end

    def test_set_cache(cache : Cache?)
      @cache = cache
    end
  end
end

describe Hwaro::Core::Build::Phases::Finalize do
  describe "#execute_finalize_phase" do
    it "saves the cache when ctx.options.cache is true" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: ".hwaro_cache.json")
          # The source file must exist: Cache#update silently skips missing
          # files, and #save only writes when an update made the cache dirty.
          Dir.mkdir_p("content")
          File.write("content/dummy.md", "# dummy")
          cache.update("content/dummy.md", "public/dummy/index.html")
          builder.test_set_cache(cache)

          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: true)
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
          ctx.cache = cache
          # The page still exists, so the entry must survive the stale-output
          # prune that now runs before the save.
          page = Hwaro::Models::Page.new("dummy.md")
          page.url = "/dummy/"
          ctx.pages = [page]

          profiler = Hwaro::Profiler.new(enabled: false)
          result = builder.test_run_finalize(ctx, profiler)

          result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
          File.exists?(".hwaro_cache.json").should be_true

          data = Hwaro::Core::Build::CacheData.from_json(File.read(".hwaro_cache.json"))
          data.entries.map(&.path).should contain("content/dummy.md")
        end
      end
    end

    # Regression: `--cache` keeps the output directory between builds, and the
    # render phase only walks pages that still exist — so a deleted, renamed,
    # newly-draft or newly-expired page kept serving its old HTML and shipped
    # with the next deploy.
    it "deletes the output of a page whose source is gone and drops its entry" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: ".hwaro_cache.json")
          Dir.mkdir_p("content")
          Dir.mkdir_p("public/gone")
          Dir.mkdir_p("public/kept")
          File.write("public/gone/index.html", "<p>removed</p>")
          File.write("public/kept/index.html", "<p>kept</p>")

          # Two entries from the previous build; only `kept.md` still exists.
          File.write("content/gone.md", "# gone")
          File.write("content/kept.md", "# kept")
          cache.update("content/gone.md", "public/gone/index.html")
          cache.update("content/kept.md", "public/kept/index.html")
          File.delete("content/gone.md")
          builder.test_set_cache(cache)

          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: true)
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
          ctx.cache = cache
          kept = Hwaro::Models::Page.new("kept.md")
          kept.url = "/kept/"
          ctx.pages = [kept]

          builder.test_run_finalize(ctx, Hwaro::Profiler.new(enabled: false))

          File.exists?("public/gone/index.html").should be_false
          Dir.exists?("public/gone").should be_false
          File.exists?("public/kept/index.html").should be_true

          data = Hwaro::Core::Build::CacheData.from_json(File.read(".hwaro_cache.json"))
          data.entries.map(&.path).should_not contain("content/gone.md")
          data.entries.map(&.path).should contain("content/kept.md")
        end
      end
    end

    # Regression: the source survives but the page moved (`slug`, `path`,
    # a permalink rule), so the entry is rewritten with the new output and
    # the file at the old URL used to stay published forever.
    it "deletes the file a page left behind when its URL moved" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: ".hwaro_cache.json")
          Dir.mkdir_p("content")
          Dir.mkdir_p("public/old-slug")
          File.write("public/old-slug/index.html", "<p>old</p>")
          File.write("content/post.md", "# post")
          cache.update("content/post.md", "public/old-slug/index.html")
          # Same source, new output path — as a re-render after a slug edit.
          File.touch("content/post.md", Time.utc + 2.seconds)
          cache.update("content/post.md", "public/new-slug/index.html")
          builder.test_set_cache(cache)

          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: true)
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
          ctx.cache = cache
          page = Hwaro::Models::Page.new("post.md")
          page.url = "/new-slug/"
          ctx.pages = [page]

          builder.test_run_finalize(ctx, Hwaro::Profiler.new(enabled: false))

          File.exists?("public/old-slug/index.html").should be_false
          data = Hwaro::Core::Build::CacheData.from_json(File.read(".hwaro_cache.json"))
          data.entries.map(&.path).should contain("content/post.md")
        end
      end
    end

    # A page that stops rendering writes nothing, so the file it wrote on the
    # previous build is stale even though its source is untouched.
    it "deletes the output of a page turned render = false" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: ".hwaro_cache.json")
          Dir.mkdir_p("content")
          Dir.mkdir_p("public/hidden")
          File.write("public/hidden/index.html", "<p>hidden</p>")
          File.write("content/hidden.md", "# hidden")
          cache.update("content/hidden.md", "public/hidden/index.html")
          builder.test_set_cache(cache)

          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: true)
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
          ctx.cache = cache
          page = Hwaro::Models::Page.new("hidden.md")
          page.url = "/hidden/"
          page.render = false
          ctx.pages = [page]

          builder.test_run_finalize(ctx, Hwaro::Profiler.new(enabled: false))

          File.exists?("public/hidden/index.html").should be_false
        end
      end
    end

    it "does not save the cache when ctx.options.cache is false" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          cache = Hwaro::Core::Build::Cache.new(enabled: false, cache_path: ".hwaro_cache.json")
          builder.test_set_cache(cache)

          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: false)
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

          profiler = Hwaro::Profiler.new(enabled: false)
          builder.test_run_finalize(ctx, profiler)

          File.exists?(".hwaro_cache.json").should be_false
        end
      end
    end

    it "aborts when @cache is nil" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          builder.test_set_cache(nil)

          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: true)
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

          profiler = Hwaro::Profiler.new(enabled: false)
          # The phase raises "Cache not initialized"; run_phase converts the
          # exception into HookResult::Abort.
          result = builder.test_run_finalize(ctx, profiler)
          result.should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
        end
      end
    end
  end
end
