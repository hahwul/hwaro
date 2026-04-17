require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose private Write helpers for testing.
module Hwaro::Core::Build
  class Builder
    def test_generate_404_page(site, templates, output_dir, minify, verbose)
      generate_404_page(site, templates, output_dir, minify, verbose)
    end

    def test_process_raw_files(raw_files, output_dir, minify, verbose) : Int32
      process_raw_files(raw_files, output_dir, minify, verbose)
    end

    def test_process_assets(pages, output_dir, verbose)
      process_assets(pages, output_dir, verbose)
    end

    def test_ensure_dir(dir : String)
      ensure_dir(dir)
    end
  end
end

describe Hwaro::Core::Build::Phases::Write do
  describe "#generate_404_page" do
    it "writes 404.html when a 404 template exists" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")
          site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
          templates = {"404" => "<h1>404 - {{ page_title }}</h1>"}

          builder = Hwaro::Core::Build::Builder.new
          builder.test_generate_404_page(site, templates, "public", false, false)

          File.exists?("public/404.html").should be_true
          File.read("public/404.html").should contain("404")
        end
      end
    end

    it "is a no-op when no 404 template exists" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")
          site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
          templates = {} of String => String

          builder = Hwaro::Core::Build::Builder.new
          builder.test_generate_404_page(site, templates, "public", false, false)

          File.exists?("public/404.html").should be_false
        end
      end
    end
  end

  describe "#process_raw_files" do
    it "copies raw files to the output directory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          File.write("content/data.json", "{}")
          FileUtils.mkdir_p("public")

          raw = Hwaro::Core::Lifecycle::RawFile.new("content/data.json", "data.json")
          builder = Hwaro::Core::Build::Builder.new

          count = builder.test_process_raw_files([raw], "public", false, false)

          count.should eq(1)
          File.exists?("public/data.json").should be_true
          File.read("public/data.json").should eq("{}")
        end
      end
    end

    it "creates intermediate directories for nested raw paths" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/data")
          File.write("content/data/feed.xml", "<rss/>")
          FileUtils.mkdir_p("public")

          raw = Hwaro::Core::Lifecycle::RawFile.new("content/data/feed.xml", "data/feed.xml")
          builder = Hwaro::Core::Build::Builder.new

          builder.test_process_raw_files([raw], "public", false, false)
          File.exists?("public/data/feed.xml").should be_true
        end
      end
    end

    it "returns zero when no raw files are provided" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")
          builder = Hwaro::Core::Build::Builder.new
          builder.test_process_raw_files([] of Hwaro::Core::Lifecycle::RawFile, "public", false, false).should eq(0)
        end
      end
    end
  end

  describe "#process_assets" do
    it "copies a page's collected assets next to the page output" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/blog/post")
          File.write("content/blog/post/index.md", "---\ntitle: Post\n---\n")
          File.write("content/blog/post/cover.png", "image-bytes")
          FileUtils.mkdir_p("public")

          page = Hwaro::Models::Page.new("blog/post/index.md")
          page.url = "/blog/post/"
          page.assets = ["blog/post/cover.png"]

          builder = Hwaro::Core::Build::Builder.new
          builder.test_process_assets([page], "public", false)

          File.exists?("public/blog/post/cover.png").should be_true
          File.read("public/blog/post/cover.png").should eq("image-bytes")
        end
      end
    end

    it "skips pages with no assets" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")
          page = Hwaro::Models::Page.new("about.md")
          page.url = "/about/"
          page.assets = [] of String

          builder = Hwaro::Core::Build::Builder.new
          builder.test_process_assets([page], "public", false)
          # No public/about/ should be created when there are no assets
          Dir.exists?("public/about").should be_false
        end
      end
    end

    it "is a no-op when the source asset is missing" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")
          page = Hwaro::Models::Page.new("blog/post/index.md")
          page.url = "/blog/post/"
          page.assets = ["blog/post/missing.png"]

          builder = Hwaro::Core::Build::Builder.new
          # Must not raise even though the source file doesn't exist
          builder.test_process_assets([page], "public", false)
          File.exists?("public/blog/post/missing.png").should be_false
        end
      end
    end
  end

  describe "#ensure_dir" do
    it "creates the directory once" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          target = File.join(dir, "ensured")
          builder.test_ensure_dir(target)
          Dir.exists?(target).should be_true

          # Calling again should be a no-op (idempotent)
          builder.test_ensure_dir(target)
          Dir.exists?(target).should be_true
        end
      end
    end
  end
end
