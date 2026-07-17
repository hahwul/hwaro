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

        # Initialize ran (config loaded onto ctx)
        ctx.config.should_not be_nil
        ctx.templates.should_not be_empty
        # ReadContent + ParseContent ran (about.md surfaced as a page)
        ctx.all_pages.size.should eq(1)
        ctx.all_pages.first.title.should eq("About")
        # Render ran (page count tallied) and Write ran (file on disk)
        ctx.stats.pages_rendered.should eq(1)
        File.exists?("public/about/index.html").should be_true
      end
    end

    it "stops at the first phase whose Before hook returns Abort" do
      with_minimal_site do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_orch_run_config(Hwaro::Models::Config.new)

        # The Before hook returning Abort short-circuits the ParseContent
        # phase (via Manager#trigger), which run_phase propagates back to
        # execute_phases, which then skips Render/Generate/Write/Finalize.
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
        ctx.stats.pages_rendered.should eq(0)
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

    it "re-renders a nested subsection index's breadcrumb after a parent section title edit" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
          FileUtils.mkdir_p("content/blog/news")
          File.write("content/blog/_index.md", "---\ntitle: BlogOld\n---\n")
          File.write("content/blog/news/_index.md", "---\ntitle: News\n---\n")
          File.write("content/blog/news/post.md", "---\ntitle: Post\n---\nbody")
          FileUtils.mkdir_p("templates")
          # Breadcrumb from page.ancestors in every template the build may pick.
          bc = "BC:{% for a in page.ancestors %}{{ a.title }};{% endfor %}|{{ content }}"
          ["page.html", "section.html", "index.html"].each { |t| File.write("templates/#{t}", bc) }

          builder = Hwaro::Core::Build::Builder.new
          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)

          # First call falls back to a full build (no prior state).
          builder.run_incremental(["content/blog/news/_index.md"], options)
          File.read("public/blog/news/index.html").should contain("BC:BlogOld;")

          # Edit ONLY the parent section's title, then incrementally rebuild.
          File.write("content/blog/_index.md", "---\ntitle: BlogNew\n---\n")
          builder.run_incremental(["content/blog/_index.md"], options)

          # The nested SUBSECTION index (a site.sections page, not a site.pages
          # page) must pick up the parent's new title in its breadcrumb.
          File.read("public/blog/news/index.html").should contain("BC:BlogNew;")
        end
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

    it "refreshes the search index after a combined content+template change" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", <<-TOML)
            title = "T"
            base_url = "http://localhost"

            [search]
            enabled = true
            TOML
          FileUtils.mkdir_p("content")
          File.write("content/about.md", "---\ntitle: About\n---\nbody")
          FileUtils.mkdir_p("templates")
          File.write("templates/page.html", "<p>{{ content }}</p>")

          builder = Hwaro::Core::Build::Builder.new
          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
          builder.run(options)
          File.read("public/search.json").should contain("About")

          # Save content and template together — the watcher's
          # :content_and_template strategy. The SEO surfaces read page
          # content/metadata, so they must refresh here just like the
          # pure content-incremental path does.
          File.write("content/about.md", "---\ntitle: Refreshed\n---\nbody")
          File.write("templates/page.html", "<div>{{ content }}</div>")
          builder.run_incremental_then_rerender(["content/about.md"], options)

          File.read("public/search.json").should contain("Refreshed")
        end
      end
    end
  end

  describe "#run_rerender output formats" do
    it "re-renders sibling format outputs when only the format template changed" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", <<-TOML)
            title = "T"
            base_url = "http://localhost"

            [outputs]
            page = ["json"]
            TOML
          FileUtils.mkdir_p("content")
          File.write("content/about.md", "---\ntitle: About\n---\nbody")
          FileUtils.mkdir_p("templates")
          File.write("templates/page.html", "<p>{{ content }}</p>")
          File.write("templates/page.json.jinja", %({"v": 1}))

          builder = Hwaro::Core::Build::Builder.new
          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
          builder.run(options)
          File.read("public/about/index.json").should contain(%("v": 1))

          # Edit ONLY the format template. Its pages' HTML entry template is
          # untouched, so the selective re-render must pick them up through
          # the format-template check or index.json stays stale.
          File.write("templates/page.json.jinja", %({"v": 2}))
          builder.run_rerender(options)

          File.read("public/about/index.json").should contain(%("v": 2))
        end
      end
    end
  end

  describe "#run_rerender feed templates" do
    it "regenerates the feed when only the feed template changed (zero pages re-render)" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", <<-TOML)
            title = "T"
            base_url = "http://localhost"

            [feeds]
            enabled = true
            TOML
          FileUtils.mkdir_p("content")
          File.write("content/about.md", "---\ntitle: About\ndate: 2026-03-05\n---\nbody")
          FileUtils.mkdir_p("templates")
          File.write("templates/page.html", "<p>{{ content }}</p>")
          File.write("templates/rss.xml.jinja", "FEED-V1 items={{ pages | length }}")

          builder = Hwaro::Core::Build::Builder.new
          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
          builder.run(options)
          File.read("public/rss.xml").should contain("FEED-V1 items=1")

          # Edit ONLY the feed template. No page uses it as an entry
          # template, so the selective re-render picks zero pages — but the
          # feed output on disk must still refresh, or serve keeps shipping
          # the stale bytes until an unrelated content edit.
          File.write("templates/rss.xml.jinja", "FEED-V2 items={{ pages | length }}")
          builder.run_rerender(options)

          File.read("public/rss.xml").should contain("FEED-V2 items=1")
        end
      end
    end
  end

  describe "template snapshot consistency" do
    it "renders with the loaded template snapshot even when a partial changed on disk" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
          FileUtils.mkdir_p("content")
          File.write("content/about.md", "---\ntitle: About\n---\nbody")
          FileUtils.mkdir_p("templates/partials")
          File.write("templates/partials/nav.html", "NAV-OLD")
          File.write("templates/page.html", %({% include "partials/nav.html" %}|{{ content }}))

          builder = Hwaro::Core::Build::Builder.new
          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
          builder.run(options)
          File.read("public/about/index.html").should contain("NAV-OLD")

          # An editor rewrites the partial while no template reload has
          # happened (mid-rebuild in serve terms). A content-only
          # incremental pass must keep rendering the snapshot the build
          # loaded — half-written disk state must not leak into output.
          File.write("templates/partials/nav.html", "NAV-DISK")
          File.write("content/about.md", "---\ntitle: About\n---\nbody v2")
          builder.run_incremental(["content/about.md"], options)
          File.read("public/about/index.html").should contain("NAV-OLD")

          # The template edit's own rebuild (run_rerender reloads the
          # snapshot from disk) then converges on the new partial.
          builder.run_rerender(options)
          File.read("public/about/index.html").should contain("NAV-DISK")
        end
      end
    end
  end
end
