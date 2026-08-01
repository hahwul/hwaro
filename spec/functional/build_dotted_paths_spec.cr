require "./support/build_helper"

# =============================================================================
# Content whose path contains dots.
#
# `PathUtils.sanitize_path` rejects any segment *containing* `..`, then joins
# whatever survives. For a page that meant it literally — `content/a..b/` —
# the segment was dropped and the page was written to the JOINED remainder:
# `/a..b/` collapsed to `""`, so the page landed on `<output>/index.html` and
# destroyed the site's homepage, while the sitemap still advertised `/a..b/`
# (a 404). With several such pages the winner was whichever rendered last.
#
# Only a segment that IS `.`/`..` can traverse. A segment that merely contains
# dots is an ordinary name and must be published as authored; a segment that
# really would traverse must be refused LOUDLY, never silently relocated.
# =============================================================================

private DOTS_CONFIG = <<-TOML
  title = "Dots Site"
  base_url = "http://localhost"
  TOML

private def dots_project
  File.write("config.toml", DOTS_CONFIG)
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates")
  File.write("content/index.md", "---\ntitle: Home\n---\nHomepage body")
  File.write("templates/index.html", "HOME:{{ content }}")
  File.write("templates/page.html", "PAGE:{{ page.title }}:{{ content }}")
  File.write("templates/section.html", "SECTION:{{ content }}")
end

private def dots_build(output_dir : String = "public")
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: output_dir, parallel: false, highlight: false))
end

describe "build: content paths containing dots" do
  it "publishes a directory whose name contains .. at its own URL" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        FileUtils.mkdir_p("content/a..b")
        File.write("content/a..b/index.md", "---\ntitle: DirDots\n---\ndirdots body")

        dots_build.should be_true

        File.exists?("public/a..b/index.html").should be_true
        File.read("public/a..b/index.html").should contain("dirdots body")
      end
    end
  end

  it "publishes a file whose name contains .. at its own URL" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.write("content/x..y.md", "---\ntitle: FileDots\n---\nfiledots body")

        dots_build.should be_true

        File.exists?("public/x..y/index.html").should be_true
        File.read("public/x..y/index.html").should contain("filedots body")
      end
    end
  end

  it "leaves the homepage intact when several dotted pages exist" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        FileUtils.mkdir_p("content/a..b")
        File.write("content/a..b/index.md", "---\ntitle: DirDots\n---\ndirdots body")
        File.write("content/x..y.md", "---\ntitle: FileDots\n---\nfiledots body")

        dots_build.should be_true

        home = File.read("public/index.html")
        home.should contain("HOME:")
        home.should contain("Homepage body")
        home.should_not contain("dirdots body")
        home.should_not contain("filedots body")
      end
    end
  end

  it "keeps the sitemap URL and the written file in agreement" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.write("config.toml", "#{DOTS_CONFIG}\n\n[sitemap]\nenabled = true\n")
        FileUtils.mkdir_p("content/a..b")
        File.write("content/a..b/index.md", "---\ntitle: DirDots\n---\ndirdots body")

        dots_build.should be_true

        # The sitemap advertises /a..b/ — a file must exist behind it.
        File.read("public/sitemap.xml").should contain("/a..b/")
        File.exists?("public/a..b/index.html").should be_true
      end
    end
  end
end

describe "build: content paths that really would traverse" do
  it "refuses a page whose front-matter path climbs out, and says so" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.write("content/escaper.md", "+++\ntitle = \"Escaper\"\npath = \"../../escaped\"\n+++\n\nescape body\n")

        log = with_captured_log { dots_build }

        log.should contain("Not publishing escaper.md")
        log.should contain("escaped")
        # Never relocated to a "cleaned" path, and never written anywhere else.
        Dir.glob("public/**/*.html").each do |path|
          File.read(path).should_not contain("escape body")
        end
        File.read("public/index.html").should contain("Homepage body")
      end
    end
  end

  it "refuses a page whose slug is .. instead of overwriting the homepage" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.write("content/dotslug.md", "+++\ntitle = \"DotSlug\"\nslug = \"..\"\n+++\n\ndotslug body\n")

        log = with_captured_log { dots_build }

        log.should contain("Not publishing dotslug.md")
        home = File.read("public/index.html")
        home.should contain("Homepage body")
        home.should_not contain("dotslug body")
      end
    end
  end

  it "refuses a traversing alias but still writes the safe ones" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.write("content/aliased.md",
          "+++\ntitle = \"Aliased\"\naliases = [\"/../evil/\", \"/ok-alias/\"]\n+++\n\nalias body\n")

        log = with_captured_log { dots_build }

        log.should contain("Skipping alias")
        File.exists?("public/ok-alias/index.html").should be_true
        Dir.exists?("public/evil").should be_false
        File.exists?("public/aliased/index.html").should be_true
      end
    end
  end
end

describe "build: dotted names outside content/" do
  it "publishes static files in and with dotted names" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        FileUtils.mkdir_p("static/s..d")
        File.write("static/s..d/asset.txt", "STATIC-IN-DOTTED-DIR")
        File.write("static/s..f.txt", "STATIC-DOTTED-FILE")

        dots_build.should be_true

        File.read("public/s..d/asset.txt").should eq("STATIC-IN-DOTTED-DIR")
        File.read("public/s..f.txt").should eq("STATIC-DOTTED-FILE")
      end
    end
  end

  it "publishes a raw content file with a dotted name" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.write("config.toml", "#{DOTS_CONFIG}\n\n[content.files]\nallow_extensions = [\"txt\"]\n")
        File.write("content/raw..file.txt", "CONTENT-RAW-DOTTED")

        dots_build.should be_true

        File.read("public/raw..file.txt").should eq("CONTENT-RAW-DOTTED")
      end
    end
  end
end
