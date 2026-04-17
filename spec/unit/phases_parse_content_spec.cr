require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose private ParseContent helpers for testing.
module Hwaro::Core::Build
  class Builder
    def test_parse_single_page(page : Models::Page)
      parse_single_page(page)
    end

    def test_parse_content_sequential(pages : Array(Models::Page))
      parse_content_sequential(pages)
    end

    def test_parse_content_parallel(pages : Array(Models::Page))
      parse_content_parallel(pages)
    end

    def test_parse_content_default(ctx : Lifecycle::BuildContext)
      parse_content_default(ctx)
    end

    def test_set_parse_config(config : Models::Config)
      @config = config
    end

    def test_run_parse_content(ctx : Lifecycle::BuildContext, profiler : Profiler)
      execute_parse_content_phase(ctx, profiler)
    end
  end
end

private def with_content_dir(files : Hash(String, String), &)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      FileUtils.mkdir_p("content")
      files.each do |path, body|
        full = File.join("content", path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, body)
      end
      yield dir
    end
  end
end

describe Hwaro::Core::Build::Phases::ParseContent do
  describe "#parse_single_page" do
    it "populates frontmatter fields on the page" do
      with_content_dir({
        "post.md" => "---\ntitle: Hello\ndescription: A post\ndraft: false\ntags: [a, b]\n---\nBody content",
      }) do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_parse_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("post.md")
        builder.test_parse_single_page(page)

        page.title.should eq("Hello")
        page.description.should eq("A post")
        page.draft.should be_false
        page.tags.sort.should eq(["a", "b"])
        page.raw_content.should contain("Body content")
      end
    end

    it "computes word count and reading time" do
      with_content_dir({
        "p.md" => "---\ntitle: P\n---\n#{"word " * 50}",
      }) do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_parse_config(Hwaro::Models::Config.new)
        page = Hwaro::Models::Page.new("p.md")
        builder.test_parse_single_page(page)

        page.word_count.should be > 0
        page.reading_time.should be >= 1
      end
    end

    it "calculates the URL using calculate_page_url" do
      with_content_dir({
        "blog/intro.md" => "---\ntitle: Intro\n---\nx",
      }) do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_parse_config(Hwaro::Models::Config.new)
        page = Hwaro::Models::Page.new("blog/intro.md")
        builder.test_parse_single_page(page)
        page.url.should eq("/blog/intro/")
      end
    end

    it "handles section-specific frontmatter on Section instances" do
      with_content_dir({
        "blog/_index.md" => "---\ntitle: Blog\nsort_by: weight\nreverse: true\ntransparent: true\n---\nBlog index",
      }) do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_parse_config(Hwaro::Models::Config.new)
        section = Hwaro::Models::Section.new("blog/_index.md")
        builder.test_parse_single_page(section)

        section.sort_by.should eq("weight")
        section.reverse.should eq(true)
        section.transparent.should be_true
      end
    end

    it "is a no-op when the source file is missing" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          builder.test_set_parse_config(Hwaro::Models::Config.new)
          page = Hwaro::Models::Page.new("missing.md")
          # Should not raise
          builder.test_parse_single_page(page)
          page.title.should eq("Untitled")
        end
      end
    end
  end

  describe "#parse_content_sequential" do
    it "marks pages with parse failures rather than raising" do
      with_content_dir({
        "good.md" => "---\ntitle: Good\n---\nfine",
      }) do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_parse_config(Hwaro::Models::Config.new)

        good = Hwaro::Models::Page.new("good.md")
        # Missing file simulates a transient I/O failure
        missing = Hwaro::Models::Page.new("missing.md")

        builder.test_parse_content_sequential([good, missing])
        good.title.should eq("Good")
        good.parse_failed.should be_false
        # Missing file is silently skipped (parse_single_page returns early)
        missing.parse_failed.should be_false
      end
    end
  end

  describe "#parse_content_parallel" do
    it "parses multiple pages concurrently with the same results as sequential" do
      with_content_dir({
        "a.md" => "---\ntitle: A\n---\na",
        "b.md" => "---\ntitle: B\n---\nb",
        "c.md" => "---\ntitle: C\n---\nc",
      }) do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_parse_config(Hwaro::Models::Config.new)

        pages = ["a.md", "b.md", "c.md"].map { |p| Hwaro::Models::Page.new(p) }
        builder.test_parse_content_parallel(pages)

        pages.map(&.title).sort.should eq(["A", "B", "C"])
      end
    end
  end

  describe "#parse_content_default" do
    it "filters out drafts unless include_drafts is true" do
      with_content_dir({
        "draft.md"     => "---\ntitle: Draft\ndraft: true\n---\nbody",
        "published.md" => "---\ntitle: Published\n---\nbody",
      }) do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_parse_config(Hwaro::Models::Config.new)

        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        ctx.config = Hwaro::Models::Config.new
        ctx.pages = [
          Hwaro::Models::Page.new("draft.md"),
          Hwaro::Models::Page.new("published.md"),
        ]

        builder.test_parse_content_default(ctx)
        ctx.pages.map(&.title).sort.should eq(["Published"])
      end
    end

    it "keeps drafts when include_drafts is true" do
      with_content_dir({
        "draft.md" => "---\ntitle: Draft\ndraft: true\n---\nbody",
      }) do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_parse_config(Hwaro::Models::Config.new)

        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, drafts: true)
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        ctx.config = Hwaro::Models::Config.new
        ctx.pages = [Hwaro::Models::Page.new("draft.md")]

        builder.test_parse_content_default(ctx)
        ctx.pages.size.should eq(1)
      end
    end

    it "filters out future-dated pages by default" do
      future_date = (Time.utc + 30.days).to_s("%Y-%m-%dT%H:%M:%SZ")
      with_content_dir({
        "future.md" => %(---\ntitle: Future\ndate: "#{future_date}"\n---\nbody),
        "now.md"    => "---\ntitle: Now\n---\nbody",
      }) do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_parse_config(Hwaro::Models::Config.new)

        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        ctx.config = Hwaro::Models::Config.new
        ctx.pages = [Hwaro::Models::Page.new("future.md"), Hwaro::Models::Page.new("now.md")]

        builder.test_parse_content_default(ctx)
        ctx.pages.map(&.title).sort.should eq(["Now"])
      end
    end

    it "filters out expired pages by default" do
      past_date = (Time.utc - 30.days).to_s("%Y-%m-%dT%H:%M:%SZ")
      with_content_dir({
        "old.md"  => %(---\ntitle: Old\nexpires: "#{past_date}"\n---\nbody),
        "live.md" => "---\ntitle: Live\n---\nbody",
      }) do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_parse_config(Hwaro::Models::Config.new)

        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        ctx.config = Hwaro::Models::Config.new
        ctx.pages = [Hwaro::Models::Page.new("old.md"), Hwaro::Models::Page.new("live.md")]

        builder.test_parse_content_default(ctx)
        ctx.pages.map(&.title).sort.should eq(["Live"])
      end
    end
  end

  describe "#execute_parse_content_phase" do
    it "returns Continue and parses queued pages" do
      with_content_dir({
        "p.md" => "---\ntitle: P\n---\nbody",
      }) do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_parse_config(Hwaro::Models::Config.new)

        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        ctx.config = Hwaro::Models::Config.new
        ctx.pages = [Hwaro::Models::Page.new("p.md")]

        profiler = Hwaro::Profiler.new(enabled: false)
        result = builder.test_run_parse_content(ctx, profiler)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
        ctx.pages.first.title.should eq("P")
      end
    end
  end
end
