require "../support/build_helper"

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

  # An alias names an incoming path ON THIS SITE. An absolute URL used to be
  # treated as plain path text: `aliases = ["http://evil.com/x"]` created the
  # directory `public/http:/evil.com/x/` — nonsense on POSIX, and a hard build
  # failure on Windows, where `:` is not a legal path character. A
  # protocol-relative `//evil.com/` lost one slash and became `public/evil.com/`.
  it "refuses an absolute or protocol-relative alias" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.write("content/ext.md",
          "+++\ntitle = \"Ext\"\naliases = [\"http://evil.com/x\", \"//evil.com/\", \"/kept/\"]\n+++\n\next body\n")

        log = with_captured_log { dots_build }

        log.should contain("an alias is a path on this site")
        Dir.exists?("public/http:").should be_false
        Dir.exists?("public/evil.com").should be_false
        File.exists?("public/kept/index.html").should be_true
        File.exists?("public/ext/index.html").should be_true
      end
    end
  end
end

describe "build: redirect_to pages take a second sink" do
  # `render_page` short-circuits on `page.has_redirect?` and returns BEFORE
  # `write_output`, so the refusal warning on the main sink never fired for a
  # redirect page. Its stub was written to whatever `sanitize_path` collapsed
  # the URL to: `/../` became `<output>/index.html`, so on a site with no
  # `content/index.md` of its own the redirect stub BECAME the homepage.
  it "refuses a redirect page whose slug traverses, loudly" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.write("content/zzslug.md",
          "+++\ntitle = \"DotSlug\"\nslug = \"..\"\nredirect_to = \"/elsewhere/\"\n+++\n\nbody\n")

        log = with_captured_log { dots_build }

        log.should contain("Not publishing zzslug.md")
        # The homepage keeps its own content, and no redirect stub is anywhere.
        File.read("public/index.html").should contain("Homepage body")
        Dir.glob("public/**/*.html").each do |path|
          File.read(path).should_not contain("elsewhere")
        end
      end
    end
  end

  it "does not turn the output root into the redirect stub when there is no homepage" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.delete("content/index.md")
        File.write("content/zzslug.md",
          "+++\ntitle = \"DotSlug\"\nslug = \"..\"\nredirect_to = \"/elsewhere/\"\n+++\n\nbody\n")

        log = with_captured_log { dots_build }

        log.should contain("Not publishing zzslug.md")
        # Before the fix this file existed and was the redirect stub.
        File.exists?("public/index.html").should be_false
      end
    end
  end

  it "still publishes a redirect page whose URL is fine" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.write("content/moved.md", "+++\ntitle = \"Moved\"\nredirect_to = \"/elsewhere/\"\n+++\n\n")

        dots_build.should be_true

        File.exists?("public/moved/index.html").should be_true
        File.read("public/moved/index.html").should contain("/elsewhere/")
      end
    end
  end
end

describe "build: the reported page count" do
  it "does not count a page no sink could publish" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        builder.run(Hwaro::Config::Options::BuildOptions.new(
          output_dir: "public", parallel: false, highlight: false))
        baseline = builder.context.not_nil!.stats.pages_rendered

        File.write("content/zzslug.md",
          "+++\ntitle = \"DotSlug\"\nslug = \"..\"\nredirect_to = \"/elsewhere/\"\n+++\n\nbody\n")

        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(Hwaro::Config::Options::BuildOptions.new(
          output_dir: "public", parallel: false, highlight: false))

        # The unpublishable page must not inflate the count.
        builder2.context.not_nil!.stats.pages_rendered.should eq(baseline)
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

describe "build: alias targets that name the same file" do
  # `/foo/`, `/foo/index.html` and `/foo/index.htm` are one file on disk, so
  # they must share a collision key. `aliases = ["/index.html"]` kept its own
  # key, never collided with the homepage's `/`, and wrote its redirect stub
  # straight over `public/index.html`.
  it "does not let /index.html alias overwrite the homepage" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.write("content/al.md", "+++\ntitle = \"Aliaser\"\naliases = [\"/index.html\"]\n+++\n\naliaser body\n")

        dots_build.should be_true

        home = File.read("public/index.html")
        home.should contain("Homepage body")
        home.should_not contain("http-equiv")
      end
    end
  end

  it "still writes a non-colliding .html alias" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.write("content/al.md", "+++\ntitle = \"Aliaser\"\naliases = [\"/legacy.html\"]\n+++\n\naliaser body\n")

        dots_build.should be_true

        File.read("public/legacy.html").should contain("http-equiv")
        File.read("public/index.html").should contain("Homepage body")
      end
    end
  end
end

describe "build: the receipt and JSON contracts" do
  it "reports published pages and summarises skipped ones" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.write("content/ok.md", "---\ntitle: Ok\n---\nok body")
        File.write("content/zz.md",
          "+++\ntitle = \"DotSlug\"\nslug = \"..\"\nredirect_to = \"/elsewhere/\"\n+++\n\nbody\n")

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        builder.run(Hwaro::Config::Options::BuildOptions.new(
          output_dir: "public", parallel: false, highlight: false))

        stats = builder.context.not_nil!.stats
        # index.md + ok.md wrote files; zz.md did not.
        stats.pages_rendered.should eq(2)
        stats.pages_unpublished.should eq(1)
      end
    end
  end

  it "reports nothing skipped on a healthy site" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        File.write("content/ok.md", "---\ntitle: Ok\n---\nok body")

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        builder.run(Hwaro::Config::Options::BuildOptions.new(
          output_dir: "public", parallel: false, highlight: false))

        stats = builder.context.not_nil!.stats
        stats.pages_rendered.should eq(2)
        stats.pages_unpublished.should eq(0)
      end
    end
  end
end

describe "build: output directory is checked on the incremental path too" do
  it "refuses -o content under --cache" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        dots_project
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        expect_raises(Hwaro::HwaroError) do
          builder.run(Hwaro::Config::Options::BuildOptions.new(
            output_dir: "content", parallel: false, highlight: false, cache: true))
        end
        # Sources untouched: no generated files scattered through content/.
        Dir.glob("content/**/*.html").should be_empty
        File.exists?("content/index.md").should be_true
      end
    end
  end
end
