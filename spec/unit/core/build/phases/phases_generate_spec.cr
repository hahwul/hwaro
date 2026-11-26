require "../../../../spec_helper"
require "../../../../support/build_helper"
require "../../../../../src/core/build/builder"

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
          builder.test_lifecycle.on(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate, name: "test-skip") do |_ctx|
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

# A generated SEO file wins over whatever else lands on its path, and that
# used to happen silently: a hand-written `static/robots.txt` lost its rules
# to the default allow-all file, and the home page's `index.xml` output
# format was overwritten by a feed named `index.xml`.
describe "generated files replacing other outputs" do
  it "warns when a generated file replaces a static file" do
    log = with_captured_log do
      build_site(
        %(title = "T"\nbase_url = "https://example.com"\n),
        content_files: {"post.md" => "+++\ntitle = \"P\"\n+++\nbody"},
        template_files: {"page.html" => "{{ content }}", "section.html" => "{{ content }}"},
        static_files: {"robots.txt" => "User-agent: *\nDisallow: /secret/\n", "notes.txt" => "n"},
      ) do |dir|
        File.read(File.join(dir, "public", "robots.txt")).should_not contain("/secret/")
        File.read(File.join(dir, "public", "notes.txt")).should eq("n")
      end
    end
    log.should contain("static/robots.txt is replaced by the generated robots.txt; set [robots] enabled = false to publish your own file")
    log.should_not contain("notes.txt")
  end

  it "keeps quiet when the generator is off" do
    log = with_captured_log do
      build_site(
        %(title = "T"\nbase_url = "https://example.com"\n[robots]\nenabled = false\n),
        content_files: {"post.md" => "+++\ntitle = \"P\"\n+++\nbody"},
        template_files: {"page.html" => "{{ content }}", "section.html" => "{{ content }}"},
        static_files: {"robots.txt" => "User-agent: *\nDisallow: /secret/\n"},
      ) do |dir|
        File.read(File.join(dir, "public", "robots.txt")).should contain("/secret/")
      end
    end
    log.should_not contain("is replaced by the generated")
  end

  it "warns when a feed replaces the home page's output format file" do
    log = with_captured_log do
      build_site(
        %(title = "T"\nbase_url = "https://example.com"\n[feeds]\nenabled = true\nfilename = "index.xml"\n[outputs]\nsection = ["xml"]\n),
        content_files: {"_index.md" => "+++\ntitle = \"Home\"\n+++\n", "post.md" => "+++\ntitle = \"P\"\ndate = \"2024-01-01\"\n+++\nbody"},
        template_files: {"page.html" => "{{ content }}", "section.html" => "{{ content }}",
                         "section.xml.jinja" => "<home>{{ page.title }}</home>"},
      ) { }
    end
    log.should contain("index.xml: the xml output of '_index.md' is replaced by a generated file at the same path")
  end
end
