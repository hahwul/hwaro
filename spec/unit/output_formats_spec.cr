require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose private OutputFormats helpers for testing.
module Hwaro::Core::Build
  class Builder
    def test_effective_output_formats(page : Models::Page, config : Models::Config)
      effective_output_formats(page, config)
    end

    def test_determine_format_template(page : Models::Page, fmt : String, templates : Hash(String, String),
                                       site : Models::Site = Models::Site.new(Models::Config.new))
      determine_format_template(page, fmt, templates, site)
    end

    def test_format_output_paths(page : Models::Page, output_dir : String, formats : Array(String))
      format_output_paths(page, output_dir, formats)
    end

    def test_write_format_output(page : Models::Page, output_dir : String, fmt : String, content : String, verbose : Bool = false)
      write_format_output(page, output_dir, fmt, content, verbose)
    end

    def test_alternate_output_tags(page : Models::Page, config : Models::Config)
      alternate_output_tags(page, config)
    end
  end
end

describe Hwaro::Core::Build::Phases::OutputFormats do
  describe "#effective_output_formats" do
    it "returns [] when the config has no outputs configured" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      page = Hwaro::Models::Page.new("about.md")
      builder.test_effective_output_formats(page, config).should eq([] of String)
    end

    it "returns config.outputs.page for a regular page" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.outputs.page = ["json"]
      page = Hwaro::Models::Page.new("about.md")
      builder.test_effective_output_formats(page, config).should eq(["json"])
    end

    it "returns config.outputs.section for a Section" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.outputs.page = ["json"]
      config.outputs.section = ["xml"]
      section = Hwaro::Models::Section.new("blog/_index.md")
      builder.test_effective_output_formats(section, config).should eq(["xml"])
    end

    it "excludes generated pages" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.outputs.page = ["json"]
      page = Hwaro::Models::Page.new("about.md")
      page.generated = true
      builder.test_effective_output_formats(page, config).should eq([] of String)
    end

    it "excludes redirect pages" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.outputs.page = ["json"]
      page = Hwaro::Models::Page.new("about.md")
      page.redirect_to = "/elsewhere/"
      builder.test_effective_output_formats(page, config).should eq([] of String)
    end

    it "excludes the synthesized 404 page" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.outputs.page = ["json"]
      page = Hwaro::Models::Page.new("404.html")
      builder.test_effective_output_formats(page, config).should eq([] of String)
    end

    it "front matter outputs overrides the config default" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.outputs.page = ["json"]
      page = Hwaro::Models::Page.new("about.md")
      page.extra["outputs"] = ["xml", "csv"]
      builder.test_effective_output_formats(page, config).should eq(["xml", "csv"])
    end

    it "an explicit empty front matter outputs suppresses the config default" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.outputs.page = ["json"]
      page = Hwaro::Models::Page.new("about.md")
      page.extra["outputs"] = [] of String
      builder.test_effective_output_formats(page, config).should eq([] of String)
    end

    it "ignores an invalid front matter outputs value and warns once" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.outputs.page = ["json"]
      page = Hwaro::Models::Page.new("about.md")
      page.extra["outputs"] = ["not-a-format"]
      builder.test_effective_output_formats(page, config).should eq([] of String)
      page.build_warnings.size.should eq(1)

      # A second call must not add a duplicate warning.
      builder.test_effective_output_formats(page, config)
      page.build_warnings.size.should eq(1)
    end

    it "ignores a non-array front matter outputs value" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.outputs.page = ["json"]
      page = Hwaro::Models::Page.new("about.md")
      page.extra["outputs"] = "json"
      builder.test_effective_output_formats(page, config).should eq([] of String)
    end

    it "applies the sections allowlist" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.outputs.page = ["json"]
      config.outputs.sections = ["posts"]

      in_scope = Hwaro::Models::Page.new("posts/hello.md")
      in_scope.section = "posts"
      builder.test_effective_output_formats(in_scope, config).should eq(["json"])

      nested = Hwaro::Models::Page.new("posts/sub/hello.md")
      nested.section = "posts/sub"
      builder.test_effective_output_formats(nested, config).should eq(["json"])

      out_of_scope = Hwaro::Models::Page.new("about.md")
      out_of_scope.section = ""
      builder.test_effective_output_formats(out_of_scope, config).should eq([] of String)
    end

    it "front matter override bypasses the sections allowlist" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.outputs.sections = ["posts"]
      page = Hwaro::Models::Page.new("about.md")
      page.section = ""
      page.extra["outputs"] = ["json"]
      builder.test_effective_output_formats(page, config).should eq(["json"])
    end
  end

  describe "#determine_format_template" do
    it "prefers the entry-template-specific format template" do
      builder = Hwaro::Core::Build::Builder.new
      page = Hwaro::Models::Page.new("about.md")
      page.template = "custom"
      templates = {"custom" => "x", "custom.json" => "{}", "page.json" => "{}"}
      builder.test_determine_format_template(page, "json", templates).should eq("custom.json")
    end

    it "falls back to section.<fmt> for sections" do
      builder = Hwaro::Core::Build::Builder.new
      section = Hwaro::Models::Section.new("blog/_index.md")
      templates = {"section" => "x", "section.json" => "{}", "page.json" => "{}"}
      builder.test_determine_format_template(section, "json", templates).should eq("section.json")
    end

    it "falls back to page.<fmt> for a regular page" do
      builder = Hwaro::Core::Build::Builder.new
      page = Hwaro::Models::Page.new("about.md")
      templates = {"page" => "x", "page.json" => "{}"}
      builder.test_determine_format_template(page, "json", templates).should eq("page.json")
    end

    it "raises HWARO_E_TEMPLATE listing every name tried when none exist" do
      builder = Hwaro::Core::Build::Builder.new
      page = Hwaro::Models::Page.new("about.md")
      templates = {"page" => "x"}
      err = expect_raises(Hwaro::HwaroError) do
        builder.test_determine_format_template(page, "json", templates)
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_TEMPLATE)
      (err.message || "").should contain("page.json")
    end
  end

  describe "#format_output_paths" do
    it "returns one path per format under the page's URL" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          page = Hwaro::Models::Page.new("blog/post.md")
          page.url = "/blog/post/"
          paths = builder.test_format_output_paths(page, "public", ["json", "xml"])
          paths.size.should eq(2)
          paths[0].should end_with("public/blog/post/index.json")
          paths[1].should end_with("public/blog/post/index.xml")
        end
      end
    end

    it "returns an empty array for an empty formats list" do
      builder = Hwaro::Core::Build::Builder.new
      page = Hwaro::Models::Page.new("about.md")
      page.url = "/about/"
      builder.test_format_output_paths(page, "public", [] of String).should eq([] of String)
    end
  end

  describe "#write_format_output" do
    it "writes the rendered content to index.<fmt>" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")
          builder = Hwaro::Core::Build::Builder.new
          page = Hwaro::Models::Page.new("blog/post.md")
          page.url = "/blog/post/"
          builder.test_write_format_output(page, "public", "json", %({"a":1}))
          File.read("public/blog/post/index.json").should eq(%({"a":1}))
        end
      end
    end
  end

  describe "#alternate_output_tags" do
    it "returns an empty string when the page has no formats" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      page = Hwaro::Models::Page.new("about.md")
      page.url = "/about/"
      builder.test_alternate_output_tags(page, config).should eq("")
    end

    it "emits a rel=alternate link per enabled format" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.outputs.page = ["json"]
      page = Hwaro::Models::Page.new("about.md")
      page.url = "/about/"
      tags = builder.test_alternate_output_tags(page, config)
      tags.should contain(%(rel="alternate"))
      tags.should contain(%(type="application/json"))
      tags.should contain(%(href="https://example.com/about/index.json"))
    end

    it "emits one line per format, joined with a newline" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.outputs.page = ["json", "xml"]
      page = Hwaro::Models::Page.new("about.md")
      page.url = "/about/"
      tags = builder.test_alternate_output_tags(page, config)
      tags.split("\n").size.should eq(2)
      tags.should contain(%(href="https://example.com/about/index.json"))
      tags.should contain(%(href="https://example.com/about/index.xml"))
    end

    it "resolves under a subpath base_url" do
      builder = Hwaro::Core::Build::Builder.new
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com/blog"
      config.outputs.page = ["json"]
      page = Hwaro::Models::Page.new("about.md")
      page.url = "/about/"
      tags = builder.test_alternate_output_tags(page, config)
      tags.should contain(%(href="https://example.com/blog/about/index.json"))
    end
  end
end
