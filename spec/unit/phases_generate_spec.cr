require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose private Generate phase entry point.
module Hwaro::Core::Build
  class Builder
    def test_run_generate(ctx : Lifecycle::BuildContext, profiler : Profiler)
      execute_generate_phase(ctx, profiler)
    end

    def test_set_generate_site(site : Models::Site)
      @site = site
    end
  end
end

describe Hwaro::Core::Build::Phases::Generate do
  describe "#execute_generate_phase" do
    it "returns Continue and writes baseline SEO outputs" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")

          config = Hwaro::Models::Config.new
          config.title = "Test Site"
          config.base_url = "https://example.com"
          site = Hwaro::Models::Site.new(config)

          page = Hwaro::Models::Page.new("about.md")
          page.title = "About"
          page.url = "/about/"
          page.date = Time.utc
          site.pages = [page]

          builder = Hwaro::Core::Build::Builder.new
          builder.test_set_generate_site(site)

          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
          ctx.config = config
          ctx.site = site
          ctx.pages = [page]

          profiler = Hwaro::Profiler.new(enabled: false)
          result = builder.test_run_generate(ctx, profiler)

          result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
          # Robots.txt is generated unconditionally based on default config.
          File.exists?("public/robots.txt").should be_true
        end
      end
    end

    it "aborts when the site is not initialized" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")

          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

          builder = Hwaro::Core::Build::Builder.new
          # Site is intentionally not set on the builder
          profiler = Hwaro::Profiler.new(enabled: false)
          result = builder.test_run_generate(ctx, profiler)
          result.should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
        end
      end
    end

    it "skips default generation when a BeforeGenerate hook is registered" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")

          config = Hwaro::Models::Config.new
          config.title = "Test Site"
          config.base_url = "https://example.com"
          site = Hwaro::Models::Site.new(config)

          builder = Hwaro::Core::Build::Builder.new
          builder.test_set_generate_site(site)

          # Register a hook so the default SEO generation is skipped
          builder.lifecycle.before(Hwaro::Core::Lifecycle::Phase::Generate, name: "test-skip") do |_ctx|
            Hwaro::Core::Lifecycle::HookResult::Continue
          end

          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
          ctx.config = config
          ctx.site = site

          profiler = Hwaro::Profiler.new(enabled: false)
          result = builder.test_run_generate(ctx, profiler)
          result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
          # robots.txt should NOT be generated when a BeforeGenerate hook is registered
          File.exists?("public/robots.txt").should be_false
        end
      end
    end
  end
end
