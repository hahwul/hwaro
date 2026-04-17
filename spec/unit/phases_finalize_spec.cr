require "../spec_helper"
require "../../src/core/build/builder"

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
          cache.update("dummy-source.md", "dummy-output.html")
          builder.test_set_cache(cache)

          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: true)
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
          ctx.cache = cache

          profiler = Hwaro::Profiler.new(enabled: false)
          result = builder.test_run_finalize(ctx, profiler)

          result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
          File.exists?(".hwaro_cache.json").should be_true
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
