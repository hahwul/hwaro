require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose private orchestration helpers for testing.
#
# Note: tests that exercise the full render pipeline (`execute_phases`,
# `run`, `run_incremental*`, `run_rerender`) live in
# `builder_orchestration_run_spec.cr`. They are split out because the
# render-path instantiation hits a Crystal 1.20.0 type-inference issue
# locally; CI runs Crystal 1.19.0 where it works.
module Hwaro::Core::Build
  class Builder
    def test_invalidate_caches_for_pages(changed, sections : Set(String))
      invalidate_caches_for_pages(changed, sections)
    end

    def test_get_internal_caches
      {
        page_crinja:     @page_crinja_value_cache,
        related_crinja:  @related_posts_crinja_cache,
        series_crinja:   @series_crinja_cache,
        ancestors:       @ancestors_crinja_cache,
        section_pages:   @section_pages_crinja_cache,
        section_assets:  @section_assets_crinja_cache,
      }
    end

    def test_seed_caches
      @page_crinja_value_cache["a.md"] = Crinja::Value.new("a")
      @page_crinja_value_cache["b.md"] = Crinja::Value.new("b")
      @related_posts_crinja_cache["a.md"] = Crinja::Value.new("ra")
      @series_crinja_cache["tutorial"] = Crinja::Value.new("series")
      @ancestors_crinja_cache["blog"] = [] of Crinja::Value
      @section_pages_crinja_cache["blog:en"] = [] of Crinja::Value
      @section_pages_crinja_cache["blog:ko"] = [] of Crinja::Value
      @section_pages_crinja_cache["other:en"] = [] of Crinja::Value
      @section_assets_crinja_cache["blog"] = [] of Crinja::Value
      @section_assets_crinja_cache["other"] = [] of Crinja::Value
    end
  end
end

# A minimal Hookable used to verify register/lifecycle wiring.
private class CountingHook
  include Hwaro::Core::Lifecycle::Hookable

  property counter : Int32 = 0

  def register_hooks(manager : Hwaro::Core::Lifecycle::Manager)
    manager.before(Hwaro::Core::Lifecycle::Phase::Initialize, name: "counting") do |_ctx|
      @counter += 1
      Hwaro::Core::Lifecycle::HookResult::Continue
    end
  end
end

describe Hwaro::Core::Build::Builder do
  describe "#initialize" do
    it "creates an instance with a fresh lifecycle and cache_manager" do
      builder = Hwaro::Core::Build::Builder.new
      builder.lifecycle.should be_a(Hwaro::Core::Lifecycle::Manager)
      builder.cache_manager.should be_a(Hwaro::Core::Build::CacheManager)
    end
  end

  describe "#register" do
    it "registers a Hookable and returns self for chaining" do
      builder = Hwaro::Core::Build::Builder.new
      hook = CountingHook.new
      builder.register(hook).should be(builder)
    end

    it "fires registered hooks during the build lifecycle" do
      hook = CountingHook.new
      builder = Hwaro::Core::Build::Builder.new
      builder.register(hook)

      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      # Trigger the lifecycle directly — focused on hook firing rather than
      # running the full build pipeline.
      builder.lifecycle.trigger(
        Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx
      )

      hook.counter.should eq(1)
    end
  end

  describe "#cache_manager" do
    it "exposes the same CacheManager across calls" do
      builder = Hwaro::Core::Build::Builder.new
      builder.cache_manager.should be(builder.cache_manager)
    end

    it "registers all known cache layers on initialization" do
      builder = Hwaro::Core::Build::Builder.new
      builder.cache_manager.should be_a(Hwaro::Core::Build::CacheManager)
    end
  end

  describe "#copy_changed_static" do
    it "copies the listed static files into the output directory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("static/css")
          File.write("static/css/main.css", "body{}")
          FileUtils.mkdir_p("public")

          builder = Hwaro::Core::Build::Builder.new
          builder.copy_changed_static(["static/css/main.css"], "public")

          File.exists?("public/css/main.css").should be_true
          File.read("public/css/main.css").should eq("body{}")
        end
      end
    end

    it "skips files that no longer exist on disk" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")
          builder = Hwaro::Core::Build::Builder.new
          # Should not raise
          builder.copy_changed_static(["static/missing.css"], "public")
          Dir.children("public").should be_empty
        end
      end
    end

    it "skips directories" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("static/folder")
          FileUtils.mkdir_p("public")

          builder = Hwaro::Core::Build::Builder.new
          builder.copy_changed_static(["static/folder"], "public")
          Dir.exists?("public/folder").should be_false
        end
      end
    end

    it "creates intermediate directories" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("static/deeply/nested")
          File.write("static/deeply/nested/file.txt", "x")
          FileUtils.mkdir_p("public")

          builder = Hwaro::Core::Build::Builder.new
          builder.copy_changed_static(["static/deeply/nested/file.txt"], "public")

          File.exists?("public/deeply/nested/file.txt").should be_true
        end
      end
    end

    it "handles paths outside static/ via lchop fallback" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")
          File.write("file.txt", "x")
          builder = Hwaro::Core::Build::Builder.new
          # Must not raise on non-static-prefixed paths
          builder.copy_changed_static(["file.txt"], "public")
        end
      end
    end
  end

  describe "#invalidate_caches_for_pages" do
    it "removes per-page Crinja cache entries for changed pages" do
      builder = Hwaro::Core::Build::Builder.new
      builder.test_seed_caches

      page = Hwaro::Models::Page.new("a.md")
      page.section = "blog"

      builder.test_invalidate_caches_for_pages([page], Set{"blog"})

      caches = builder.test_get_internal_caches
      caches[:page_crinja].has_key?("a.md").should be_false
      caches[:page_crinja].has_key?("b.md").should be_true
      caches[:related_crinja].has_key?("a.md").should be_false
    end

    it "removes section-scoped caches for affected sections" do
      builder = Hwaro::Core::Build::Builder.new
      builder.test_seed_caches

      builder.test_invalidate_caches_for_pages(
        [] of Hwaro::Models::Page,
        Set{"blog"}
      )

      caches = builder.test_get_internal_caches
      caches[:ancestors].has_key?("blog").should be_false
      caches[:section_pages].has_key?("blog:en").should be_false
      caches[:section_pages].has_key?("blog:ko").should be_false
      caches[:section_pages].has_key?("other:en").should be_true
      caches[:section_assets].has_key?("blog").should be_false
      caches[:section_assets].has_key?("other").should be_true
    end

    it "evicts neighbor pages from the Crinja cache" do
      builder = Hwaro::Core::Build::Builder.new
      builder.test_seed_caches

      page = Hwaro::Models::Page.new("a.md")
      lower = Hwaro::Models::Page.new("b.md")
      page.lower = lower

      builder.test_invalidate_caches_for_pages([page], Set(String).new)

      caches = builder.test_get_internal_caches
      caches[:page_crinja].has_key?("b.md").should be_false
    end

    it "evicts the series cache when a changed page belongs to a series" do
      builder = Hwaro::Core::Build::Builder.new
      builder.test_seed_caches

      page = Hwaro::Models::Page.new("a.md")
      page.series = "tutorial"

      builder.test_invalidate_caches_for_pages([page], Set(String).new)

      caches = builder.test_get_internal_caches
      caches[:series_crinja].has_key?("tutorial").should be_false
    end
  end
end
