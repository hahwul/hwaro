require "../spec_helper"
require "../../src/core/build/builder"

# Tests that exercise the full build pipeline on Builder — phase sequencing,
# abort handling, and the incremental/rerender fallback paths. These rely on
# the render path being instantiable, which currently requires Crystal 1.19.0
# (the local CI version). Crystal 1.20.0 hits a pre-existing type-inference
# issue in `src/core/build/phases/render.cr:1089`.

# Reopen Builder to expose private execute_phases for testing.
module Hwaro::Core::Build
  class Builder
    def test_execute_phases(ctx : Lifecycle::BuildContext, profiler : Profiler)
      execute_phases(ctx, profiler)
    end

    def test_set_orch_run_config(config : Models::Config?)
      @config = config
    end
  end
end

private def with_minimal_site(&)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
      FileUtils.mkdir_p("content")
      File.write("content/about.md", "---\ntitle: About\n---\nbody")
      FileUtils.mkdir_p("templates")
      File.write("templates/page.html", "<p>{{ content }}</p>")
      yield dir
    end
  end
end

describe Hwaro::Core::Build::Builder do
  describe "#execute_phases" do
    it "runs all phases in order and returns Continue on success" do
      with_minimal_site do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_orch_run_config(Hwaro::Models::Config.new)

        options = Hwaro::Config::Options::BuildOptions.new(
          output_dir: "public",
          parallel: false,
          cache: false,
          highlight: false,
        )
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        profiler = Hwaro::Profiler.new(enabled: false)

        result = builder.test_execute_phases(ctx, profiler)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
        File.exists?("public/about/index.html").should be_true
      end
    end

    it "stops at the first phase that returns Abort" do
      with_minimal_site do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_orch_run_config(Hwaro::Models::Config.new)

        # Force ParseContent to abort by registering a hook that returns Abort
        builder.lifecycle.before(
          Hwaro::Core::Lifecycle::Phase::ParseContent, name: "force-abort"
        ) do |_ctx|
          Hwaro::Core::Lifecycle::HookResult::Abort
        end

        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        profiler = Hwaro::Profiler.new(enabled: false)

        result = builder.test_execute_phases(ctx, profiler)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
        # Render did not run, so no output was generated
        File.exists?("public/about/index.html").should be_false
      end
    end
  end

  describe "#run_incremental" do
    it "falls back to a full build when no prior state exists" do
      with_minimal_site do
        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)

        # No prior @config / @site / @templates → must fall back to full run
        builder.run_incremental(["content/about.md"], options)
        File.exists?("public/about/index.html").should be_true
      end
    end
  end

  describe "#run_rerender" do
    it "falls back to a full build when no prior state exists" do
      with_minimal_site do
        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        builder.run_rerender(options)
        File.exists?("public/about/index.html").should be_true
      end
    end
  end

  describe "#run_incremental_then_rerender" do
    it "falls back to a full build when no prior state exists" do
      with_minimal_site do
        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        builder.run_incremental_then_rerender(["content/about.md"], options)
        File.exists?("public/about/index.html").should be_true
      end
    end
  end
end
