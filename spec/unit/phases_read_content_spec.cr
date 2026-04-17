require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose private ReadContent helpers for testing.
module Hwaro::Core::Build
  class Builder
    def test_collect_content_paths(ctx : Lifecycle::BuildContext, include_drafts : Bool = false)
      collect_content_paths(ctx, include_drafts)
    end

    def test_extract_language_from_filename(basename : String, config : Models::Config?)
      extract_language_from_filename(basename, config)
    end

    def test_run_read_content(ctx : Lifecycle::BuildContext, profiler : Profiler)
      execute_read_content_phase(ctx, profiler)
    end
  end
end

private def make_ctx(config : Hwaro::Models::Config? = nil) : Hwaro::Core::Lifecycle::BuildContext
  options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
  ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
  ctx.config = config
  ctx
end

describe Hwaro::Core::Build::Phases::ReadContent do
  describe "#extract_language_from_filename" do
    it "returns nil for non-multilingual config" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      builder.test_extract_language_from_filename("about.ko.md", config).should be_nil
    end

    it "returns nil for nil config" do
      builder = Hwaro::Core::Build::Builder.new
      builder.test_extract_language_from_filename("about.ko.md", nil).should be_nil
    end

    it "extracts a registered language code" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new(code: "ko")
      config.languages["en"] = Hwaro::Models::LanguageConfig.new(code: "en")
      builder.test_extract_language_from_filename("about.ko.md", config).should eq("ko")
    end

    it "ignores unknown language codes" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new(code: "ko")
      builder.test_extract_language_from_filename("about.zz.md", config).should be_nil
    end

    it "matches the default language too" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new(code: "ko")
      builder.test_extract_language_from_filename("about.en.md", config).should eq("en")
    end

    it "returns nil for plain filenames without a language token" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new(code: "ko")
      builder.test_extract_language_from_filename("about.md", config).should be_nil
    end
  end

  describe "#collect_content_paths" do
    it "collects markdown pages and sections" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/blog")
          File.write("content/about.md", "---\ntitle: About\n---\nbody")
          File.write("content/blog/_index.md", "---\ntitle: Blog\n---\n")
          File.write("content/blog/post.md", "---\ntitle: Post\n---\nbody")

          builder = Hwaro::Core::Build::Builder.new
          ctx = make_ctx(Hwaro::Models::Config.new)
          builder.test_collect_content_paths(ctx)

          ctx.pages.size.should eq(2)
          ctx.sections.size.should eq(1)
          ctx.sections.first.section.should eq("blog")
        end
      end
    end

    it "marks index pages with is_index" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/blog/post")
          File.write("content/blog/_index.md", "---\ntitle: Blog\n---\n")
          File.write("content/blog/post/index.md", "---\ntitle: Post\n---\nbody")

          builder = Hwaro::Core::Build::Builder.new
          ctx = make_ctx(Hwaro::Models::Config.new)
          builder.test_collect_content_paths(ctx)

          ctx.sections.any?(&.is_index).should be_true
          ctx.pages.any?(&.is_index).should be_true
        end
      end
    end

    it "computes the correct section path for nested pages" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/docs/guide")
          File.write("content/docs/guide/topic.md", "---\ntitle: T\n---\nbody")

          builder = Hwaro::Core::Build::Builder.new
          ctx = make_ctx(Hwaro::Models::Config.new)
          builder.test_collect_content_paths(ctx)

          ctx.pages.first.section.should eq("docs/guide")
        end
      end
    end

    it "collects raw JSON and XML files" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          File.write("content/data.json", "{}")
          File.write("content/feed.xml", "<rss/>")

          builder = Hwaro::Core::Build::Builder.new
          ctx = make_ctx(Hwaro::Models::Config.new)
          builder.test_collect_content_paths(ctx)

          ctx.raw_files.map(&.relative_path).sort.should eq(["data.json", "feed.xml"])
        end
      end
    end

    it "extracts language code for multilingual filenames" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          File.write("content/about.ko.md", "---\ntitle: 소개\n---\n")

          builder = Hwaro::Core::Build::Builder.new
          config = Hwaro::Models::Config.new
          config.default_language = "en"
          config.languages["ko"] = Hwaro::Models::LanguageConfig.new(code: "ko")
          ctx = make_ctx(config)

          builder.test_collect_content_paths(ctx)
          page = ctx.pages.first
          page.language.should eq("ko")
        end
      end
    end

    it "handles empty content directory gracefully" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          builder = Hwaro::Core::Build::Builder.new
          ctx = make_ctx(Hwaro::Models::Config.new)
          builder.test_collect_content_paths(ctx)

          ctx.pages.should be_empty
          ctx.sections.should be_empty
          ctx.raw_files.should be_empty
        end
      end
    end
  end

  describe "#execute_read_content_phase" do
    it "returns Continue and populates the context" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          File.write("content/index.md", "---\ntitle: Home\n---\nhome")

          builder = Hwaro::Core::Build::Builder.new
          ctx = make_ctx(Hwaro::Models::Config.new)
          profiler = Hwaro::Profiler.new(enabled: false)

          result = builder.test_run_read_content(ctx, profiler)
          result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
          ctx.all_pages.size.should eq(1)
        end
      end
    end
  end
end
