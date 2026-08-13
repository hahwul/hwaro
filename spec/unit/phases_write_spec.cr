require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose private Write helpers for testing.
module Hwaro::Core::Build
  class Builder
    def test_generate_404_page(site, templates, output_dir, minify, verbose)
      generate_404_page(site, templates, output_dir, minify, verbose)
    end

    def test_process_raw_files(raw_files, output_dir, minify, verbose, written = Set(String).new) : Int32
      process_raw_files(raw_files, output_dir, minify, verbose, written)
    end

    def test_process_assets(pages, output_dir, verbose, already_written = Set(String).new)
      process_assets(pages, output_dir, verbose, already_written)
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

    it "raises HWARO_E_TEMPLATE when the 404 template is malformed" do
      # A broken templates/404.html must abort the Write phase (fail loud)
      # rather than ship a green build. apply_template wraps the Crinja parse
      # error as HWARO_E_TEMPLATE; generate_404_page has no rescue around it.
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")
          site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
          templates = {"404" => "{{ unclosed"}

          builder = Hwaro::Core::Build::Builder.new
          err = expect_raises(Hwaro::HwaroError) do
            builder.test_generate_404_page(site, templates, "public", false, false)
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_TEMPLATE)
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

    it "skips a raw-file symlink pointing outside the project" do
      # Mirrors the bundle-asset guard in process_assets: FileUtils.cp
      # follows symlinks, so a `content/leak.json -> /outside/secret.json`
      # link would publish a file from outside the site.
      Dir.mktmpdir do |dir|
        outside = File.join(dir, "outside.json")
        File.write(outside, %({"secret": true}))
        project = File.join(dir, "proj")
        FileUtils.mkdir_p(File.join(project, "content"))
        FileUtils.mkdir_p(File.join(project, "public"))
        Dir.cd(project) do
          File.symlink(outside, "content/leak.json")
          raw = Hwaro::Core::Lifecycle::RawFile.new("content/leak.json", "leak.json")
          builder = Hwaro::Core::Build::Builder.new

          log = with_captured_log do
            builder.test_process_raw_files([raw], "public", false, false).should eq(0)
          end

          File.exists?("public/leak.json").should be_false
          log.should contain("symlink")
        end
      end
    end

    it "still copies an in-project raw-file symlink" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("public")
          File.write("content/real.json", "{}")
          File.symlink(File.expand_path("content/real.json"), "content/link.json")

          raw = Hwaro::Core::Lifecycle::RawFile.new("content/link.json", "link.json")
          builder = Hwaro::Core::Build::Builder.new

          builder.test_process_raw_files([raw], "public", false, false).should eq(1)
          File.exists?("public/link.json").should be_true
        end
      end
    end

    # Regression: the copy-as-is branch used FileUtils.cp, which truncates the
    # destination and then streams it. `hwaro serve` re-runs the Write phase on
    # every rebuild while HTTP fibers stream those same files to the browser, so
    # a request landing mid-copy was answered with a zero-length or partial body
    # that nothing retried. The window is not deterministic in a spec, so assert
    # the property behind it: a reader holding the destination open across a
    # re-copy must keep seeing one complete revision. Both revisions have the
    # same length, so only atomicity can satisfy it.
    it "replaces a raw file atomically instead of truncating it in place" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("public")
          old_bytes = %({"a":"#{"x" * 4000}"})
          new_bytes = %({"a":"#{"y" * 4000}"})
          File.write("content/data.json", old_bytes)

          raw = Hwaro::Core::Lifecycle::RawFile.new("content/data.json", "data.json")
          builder = Hwaro::Core::Build::Builder.new
          builder.test_process_raw_files([raw], "public", false, false)

          reader = File.open("public/data.json")
          begin
            File.write("content/data.json", new_bytes)
            builder.test_process_raw_files([raw], "public", false, false)

            reader.gets_to_end.should eq(old_bytes)
          ensure
            reader.close
          end

          File.read("public/data.json").should eq(new_bytes)
          Dir.glob("public/*.tmp").should be_empty
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

    # Regression: a `.json`/`.xml` file inside a page bundle that
    # `[content.files]` also publishes is written twice — minified here, then
    # copied verbatim by process_assets. The asset copy ran last and silently
    # undid `--minify` for that file.
    it "keeps its minified output when the same path is also a bundle asset" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/post")
          File.write("content/post/index.md", "+++\ntitle = \"P\"\n+++\n")
          File.write("content/post/data.json", "{\n    \"a\": 1\n}\n")
          FileUtils.mkdir_p("public")

          raw = Hwaro::Core::Lifecycle::RawFile.new("content/post/data.json", "post/data.json")
          page = Hwaro::Models::Page.new("post/index.md")
          page.url = "/post/"
          page.assets = ["post/data.json"]

          builder = Hwaro::Core::Build::Builder.new
          written = Set(String).new
          builder.test_process_raw_files([raw], "public", true, false, written)
          builder.test_process_assets([page], "public", false, written)

          File.read("public/post/data.json").should eq(%({"a":1}))
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

    # Same atomicity invariant as the raw-file copy above: bundle assets are
    # re-copied on every serve rebuild while the browser streams them, and
    # FileUtils.cp truncated the live destination before streaming into it.
    it "replaces a changed bundle asset atomically instead of truncating it" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/blog/post")
          File.write("content/blog/post/index.md", "---\ntitle: Post\n---\n")
          old_bytes = "old-image-bytes" * 500
          new_bytes = "new-image-bytes" * 500
          File.write("content/blog/post/cover.png", old_bytes)
          FileUtils.mkdir_p("public")

          page = Hwaro::Models::Page.new("blog/post/index.md")
          page.url = "/blog/post/"
          page.assets = ["blog/post/cover.png"]

          builder = Hwaro::Core::Build::Builder.new
          builder.test_process_assets([page], "public", false)

          reader = File.open("public/blog/post/cover.png")
          begin
            File.write("content/blog/post/cover.png", new_bytes)
            # Both revisions are the same size, so the skip-unchanged check
            # would compare mtimes that could land in the same filesystem tick.
            # Backdate the source to make "changed" unambiguous and keep the
            # test about atomicity rather than timing.
            File.utime(Time.utc, Time.utc - 1.hour, "content/blog/post/cover.png")
            builder.test_process_assets([page], "public", false)

            reader.gets_to_end.should eq(old_bytes)
          ensure
            reader.close
          end

          File.read("public/blog/post/cover.png").should eq(new_bytes)
          Dir.glob("public/blog/post/*.tmp").should be_empty
        end
      end
    end

    it "skips a bundle asset symlink whose target escapes the project" do
      Dir.mktmpdir do |outside|
        secret = File.join(outside, "secret.txt")
        File.write(secret, "leak")

        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/blog/post")
            File.write("content/blog/post/index.md", "---\ntitle: Post\n---\n")
            File.symlink(secret, "content/blog/post/leak.txt")
            FileUtils.mkdir_p("public")

            page = Hwaro::Models::Page.new("blog/post/index.md")
            page.url = "/blog/post/"
            page.assets = ["blog/post/leak.txt"]

            builder = Hwaro::Core::Build::Builder.new
            builder.test_process_assets([page], "public", false)

            File.exists?("public/blog/post/leak.txt").should be_false
          end
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
