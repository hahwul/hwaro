require "./support/build_helper"

# =============================================================================
# Output-directory handling for `hwaro build`
#
#  * `-o public/` (a trailing slash — what shell directory completion types)
#    made OutputGuard reject every page. The build reported success, wrote
#    only static assets, and the site root index.html ended up holding
#    whichever page rendered last (get_output_path's root fallback).
#
#  * `-o content` wiped the project's own sources: the cold-build `rm_rf` was
#    only guarded against `/`, `$HOME` and ancestors of the project.
# =============================================================================

private GUARD_CONFIG = <<-TOML
  title = "Guard Site"
  base_url = "http://localhost"
  TOML

private def guard_project(dir)
  File.write("config.toml", GUARD_CONFIG)
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  FileUtils.mkdir_p("static")
  File.write("content/index.md", "---\ntitle: Home\n---\nHomepage body")
  File.write("content/about.md", "---\ntitle: About\n---\nAbout body")
  File.write("content/posts/first.md", "---\ntitle: First\n---\nFirst body")
  File.write("static/asset.txt", "asset")
  File.write("templates/index.html", "HOME:{{ content }}")
  File.write("templates/page.html", "PAGE:{{ content }}")
  File.write("templates/section.html", "SECTION:{{ content }}")
end

private def run_build(output_dir : String)
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: output_dir, parallel: false, highlight: false))
end

describe "build: output directory with a trailing separator" do
  it "writes every page, exactly as it does without the slash" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)

        run_build("with_slash/").should be_true
        run_build("no_slash").should be_true

        with_slash = Dir.glob("with_slash/**/*.html").map(&.sub("with_slash/", "")).sort!
        no_slash = Dir.glob("no_slash/**/*.html").map(&.sub("no_slash/", "")).sort!

        with_slash.should eq(no_slash)
        with_slash.should contain("about/index.html")
        with_slash.should contain("posts/first/index.html")
      end
    end
  end

  it "keeps the homepage at the output root instead of the last page rendered" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        run_build("out/").should be_true

        root = File.read("out/index.html")
        root.should contain("HOME:")
        root.should contain("Homepage body")
        root.should_not contain("First body")
        root.should_not contain("About body")
      end
    end
  end

  it "produces byte-identical page output with and without the slash" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        run_build("with_slash/")
        run_build("no_slash")

        File.read("with_slash/about/index.html").should eq(File.read("no_slash/about/index.html"))
        File.read("with_slash/index.html").should eq(File.read("no_slash/index.html"))
      end
    end
  end
end

describe "build: refusing to delete project input directories" do
  it "refuses to use content/ as the output directory" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)

        err = expect_raises(Hwaro::HwaroError) { run_build("content") }
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        (err.message || "").should contain("content")
        (err.hint || "").should contain("public")

        # Sources survive.
        File.exists?("content/index.md").should be_true
        File.exists?("content/posts/first.md").should be_true
      end
    end
  end

  it "refuses templates/ and static/ too" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)

        expect_raises(Hwaro::HwaroError) { run_build("templates") }
        expect_raises(Hwaro::HwaroError) { run_build("static") }

        File.exists?("templates/page.html").should be_true
        File.exists?("static/asset.txt").should be_true
      end
    end
  end

  it "refuses a directory nested inside a project input directory" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        FileUtils.mkdir_p("content/generated")

        expect_raises(Hwaro::HwaroError) { run_build("content/generated") }
        File.exists?("content/index.md").should be_true
      end
    end
  end

  it "recognizes content/ written with a trailing separator" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)

        expect_raises(Hwaro::HwaroError) { run_build("content/") }
        File.exists?("content/index.md").should be_true
      end
    end
  end

  it "still allows an output directory that merely shares a prefix" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        # Pre-create them so the destructive-clean guard is actually reached.
        FileUtils.mkdir_p("contents")
        FileUtils.mkdir_p("static-site")

        run_build("contents").should be_true
        run_build("static-site").should be_true

        File.exists?("contents/about/index.html").should be_true
        File.exists?("static-site/about/index.html").should be_true
      end
    end
  end

  it "still allows the conventional public/ output directory" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        run_build("public").should be_true
        run_build("public").should be_true
        File.exists?("public/about/index.html").should be_true
      end
    end
  end
end
