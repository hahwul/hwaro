require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose private Render helpers for testing.
module Hwaro::Core::Build
  class Builder
    def test_get_output_path(page : Models::Page, output_dir : String)
      get_output_path(page, output_dir)
    end

    def test_determine_template(page : Models::Page, templates : Hash(String, String))
      determine_template(page, templates)
    end

    def test_filter_changed_pages(pages, output_dir, cache)
      filter_changed_pages(pages, output_dir, cache)
    end

    def test_build_pages_by_path(site : Models::Site)
      build_pages_by_path(site)
    end

    def test_render_error_signature(message : String)
      render_error_signature(message)
    end

    def test_report_render_failures(failures, verbose)
      report_render_failures(failures, verbose)
    end
  end
end

describe Hwaro::Core::Build::Phases::Render do
  describe "#get_output_path" do
    it "appends index.html to a section URL" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          page = Hwaro::Models::Page.new("blog/post.md")
          page.url = "/blog/post/"
          builder.test_get_output_path(page, "public").should end_with("public/blog/post/index.html")
        end
      end
    end

    it "produces public/index.html for the root URL" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          page = Hwaro::Models::Page.new("index.md")
          page.url = "/"
          builder.test_get_output_path(page, "public").should end_with("public/index.html")
        end
      end
    end

    it "produces a path inside the output directory for nested pages" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          page = Hwaro::Models::Page.new("nested/page.md")
          page.url = "/nested/page/"
          result = builder.test_get_output_path(page, "public")
          result.should contain("public/nested/page/index.html")
        end
      end
    end
  end

  describe "#determine_template" do
    it "returns 'page' as the default for regular pages" do
      builder = Hwaro::Core::Build::Builder.new
      page = Hwaro::Models::Page.new("about.md")
      templates = {"page" => "x"}
      builder.test_determine_template(page, templates).should eq("page")
    end

    it "returns 'section' for Section instances when available" do
      builder = Hwaro::Core::Build::Builder.new
      section = Hwaro::Models::Section.new("blog/_index.md")
      templates = {"page" => "p", "section" => "s"}
      builder.test_determine_template(section, templates).should eq("section")
    end

    it "returns 'index' for the root index page when an index template exists" do
      builder = Hwaro::Core::Build::Builder.new
      page = Hwaro::Models::Page.new("_index.md")
      page.is_index = true
      page.section = ""
      templates = {"page" => "p", "index" => "i"}
      builder.test_determine_template(page, templates).should eq("index")
    end

    it "honors a page-level custom template when present" do
      builder = Hwaro::Core::Build::Builder.new
      page = Hwaro::Models::Page.new("about.md")
      page.template = "landing"
      templates = {"page" => "p", "landing" => "l"}
      builder.test_determine_template(page, templates).should eq("landing")
    end

    it "warns and falls back when the custom template is missing" do
      builder = Hwaro::Core::Build::Builder.new
      page = Hwaro::Models::Page.new("about.md")
      page.template = "missing"
      templates = {"page" => "p"}
      builder.test_determine_template(page, templates).should eq("page")
      page.build_warnings.any?(&.includes?("missing")).should be_true
    end
  end

  describe "#filter_changed_pages" do
    it "returns all pages when none are cached" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          File.write("content/p.md", "x")

          builder = Hwaro::Core::Build::Builder.new
          page = Hwaro::Models::Page.new("p.md")
          page.url = "/p/"

          cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: ".cache.json")
          result = builder.test_filter_changed_pages([page], "public", cache)
          result.size.should eq(1)
        end
      end
    end

    it "skips pages that are unchanged in the cache" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          File.write("content/p.md", "x")
          FileUtils.mkdir_p("public/p")
          File.write("public/p/index.html", "<html/>")

          builder = Hwaro::Core::Build::Builder.new
          page = Hwaro::Models::Page.new("p.md")
          page.url = "/p/"

          cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: ".cache.json")
          # Mark page as cached
          cache.update("content/p.md", "public/p/index.html")

          result = builder.test_filter_changed_pages([page], "public", cache)
          result.size.should eq(0)
        end
      end
    end
  end

  describe "#build_pages_by_path" do
    it "indexes both pages and sections by path" do
      builder = Hwaro::Core::Build::Builder.new
      site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
      page = Hwaro::Models::Page.new("blog/post.md")
      section = Hwaro::Models::Section.new("blog/_index.md")
      site.pages = [page]
      site.sections = [section]

      result = builder.test_build_pages_by_path(site)
      result["blog/post.md"].should eq(page)
      result["blog/_index.md"].should eq(section)
    end
  end

  describe "#render_error_signature" do
    it "strips the page-specific 'Template error for <path>' prefix" do
      builder = Hwaro::Core::Build::Builder.new
      msg = "Template error for posts/hello-world.md: Unterminated tag\ntemplate: <string>:1:20 .. 1:20"
      builder.test_render_error_signature(msg).should eq("Unterminated tag")
    end

    it "normalizes the same underlying error across different pages" do
      builder = Hwaro::Core::Build::Builder.new
      a = "Template error for about.md: Unterminated tag\nmore context"
      b = "Template error for posts/hello-world.md: Unterminated tag\nother context"
      builder.test_render_error_signature(a).should eq(builder.test_render_error_signature(b))
    end

    it "falls back to the first line when there is no 'Template error for' prefix" do
      builder = Hwaro::Core::Build::Builder.new
      builder.test_render_error_signature("Missing filter 'foo'\n  at line 3").should eq("Missing filter 'foo'")
    end
  end

  describe "#report_render_failures" do
    it "groups identical failures into a single summary line" do
      buffer = IO::Memory.new
      previous_io = Hwaro::Logger.io
      Hwaro::Logger.io = buffer
      begin
        builder = Hwaro::Core::Build::Builder.new
        failures = [
          {page_path: "index.md", message: "Template error for index.md: Unterminated tag"},
          {page_path: "about.md", message: "Template error for about.md: Unterminated tag"},
          {page_path: "posts/hello.md", message: "Template error for posts/hello.md: Unterminated tag"},
        ]
        builder.test_report_render_failures(failures, verbose: false)
      ensure
        Hwaro::Logger.io = previous_io
      end
      output = buffer.to_s
      output.should contain("Render failed for 3 pages: Unterminated tag")
      output.should contain("  - index.md")
      output.should contain("  - about.md")
      output.should contain("  - posts/hello.md")
      output.should contain("--verbose")
      output.scan("Unterminated tag").size.should eq(1)
    end

    it "shows per-page detail under --verbose" do
      buffer = IO::Memory.new
      previous_io = Hwaro::Logger.io
      Hwaro::Logger.io = buffer
      begin
        builder = Hwaro::Core::Build::Builder.new
        failures = [
          {page_path: "index.md", message: "Template error for index.md: Unterminated tag"},
          {page_path: "about.md", message: "Template error for about.md: Unterminated tag"},
        ]
        builder.test_report_render_failures(failures, verbose: true)
      ensure
        Hwaro::Logger.io = previous_io
      end
      output = buffer.to_s
      output.scan("Parallel render failed for").size.should eq(2)
      output.should contain("index.md")
      output.should contain("about.md")
    end

    it "uses the single-page format when only one page fails with a given error" do
      buffer = IO::Memory.new
      previous_io = Hwaro::Logger.io
      Hwaro::Logger.io = buffer
      begin
        builder = Hwaro::Core::Build::Builder.new
        failures = [
          {page_path: "index.md", message: "Template error for index.md: something unique"},
        ]
        builder.test_report_render_failures(failures, verbose: false)
      ensure
        Hwaro::Logger.io = previous_io
      end
      output = buffer.to_s
      output.should contain("Render failed for index.md:")
      output.should_not contain("Run with --verbose")
    end

    it "truncates large affected-page lists with an '… and N more' tail" do
      buffer = IO::Memory.new
      previous_io = Hwaro::Logger.io
      Hwaro::Logger.io = buffer
      begin
        builder = Hwaro::Core::Build::Builder.new
        failures = (1..8).map do |i|
          {page_path: "posts/p#{i}.md", message: "Template error for posts/p#{i}.md: Unterminated tag"}
        end.to_a
        builder.test_report_render_failures(failures, verbose: false)
      ensure
        Hwaro::Logger.io = previous_io
      end
      output = buffer.to_s
      output.should contain("Render failed for 8 pages: Unterminated tag")
      output.should contain("… and 3 more")
    end
  end
end
