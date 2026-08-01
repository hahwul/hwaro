require "./support/build_helper"

# =============================================================================
# `build --cache` must converge on the same bytes a clean build produces.
#
# Each example below is a case where it did not:
#   * an output-affecting CLI flag (--minify, --skip-highlighting) was absent
#     from the invalidation key, so a warm build re-published unprocessed HTML
#   * a page's [extra] table and its content-derived values (summary,
#     word_count, reading_time) were absent from the page-set fingerprint, so
#     listings kept the previous build's values
#   * a static file whose mtime moved BACKWARDS (git checkout / stash pop /
#     rsync --times) was never re-copied
#   * alternating output directories left the older tree permanently stale
# =============================================================================

private CACHE_CONFIG = <<-TOML
  title = "Cache Site"
  base_url = "http://localhost"
  TOML

private def run_builder(output_dir : String, cache : Bool, minify : Bool, highlight : Bool, workers : Int32)
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: output_dir, parallel: false, cache: cache,
    minify: minify, highlight: highlight, workers: workers))
end

private def cached_build(output_dir : String = "public", minify : Bool = false,
                         highlight : Bool = false, workers : Int32 = 0)
  run_builder(output_dir, true, minify, highlight, workers)
end

private def clean_build(output_dir : String = "public", minify : Bool = false,
                        highlight : Bool = false)
  FileUtils.rm_rf(output_dir)
  FileUtils.rm_rf(".hwaro_cache.json")
  run_builder(output_dir, false, minify, highlight, 0)
end

# A listing template: it iterates `site.pages`, which is what marks a template
# as page-set dependent and therefore subject to the set fingerprint.
private def listing_project(listing_body : String)
  File.write("config.toml", CACHE_CONFIG)
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("content/index.md", "---\ntitle: Home\n---\nHome")
  File.write("templates/index.html",
    "{% for p in site.pages %}#{listing_body}{% endfor %}")
  File.write("templates/page.html", "{{ content }}")
  File.write("templates/section.html", "{{ content }}")
end

describe "cache: output-affecting CLI flags" do
  it "re-renders cached pages when --minify is added" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", CACHE_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/about.md", "---\ntitle: About\n---\nAbout body")
        File.write("templates/page.html", "<html>\n  <body>\n    {{ content }}\n  </body>\n</html>")

        cached_build
        cached_build(minify: true)
        warm = File.read("public/about/index.html")

        clean_build(minify: true)
        clean = File.read("public/about/index.html")

        warm.should eq(clean)
      end
    end
  end

  it "re-renders cached pages when --skip-highlighting is added" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", "#{CACHE_CONFIG}\n\n[highlight]\nenabled = true\nmode = \"server\"\n")
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/code.md", "---\ntitle: Code\n---\n\n```ruby\nputs 1\n```\n")
        File.write("templates/page.html", "{{ content }}")

        cached_build(highlight: true)
        cached_build(highlight: false)
        warm = File.read("public/code/index.html")

        clean_build(highlight: false)
        clean = File.read("public/code/index.html")

        warm.should eq(clean)
      end
    end
  end

  it "keeps the cache warm for flags that do not change output" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", CACHE_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/about.md", "---\ntitle: About\n---\nAbout body")
        File.write("templates/page.html", "{{ content }}")

        cached_build
        before = File.info("public/about/index.html").modification_time

        # --jobs / --no-parallel must not force a re-render.
        cached_build(workers: 4)
        File.info("public/about/index.html").modification_time.should eq(before)
      end
    end
  end
end

describe "cache: page-set fingerprint covers what listings read" do
  it "re-renders listings when a page's [extra] changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        listing_project("[{{ p.extra.badge }}]")
        File.write("content/posts/ext.md", "+++\ntitle = \"Ext\"\n\n[extra]\nbadge = \"V1\"\n+++\n\nbody\n")

        cached_build
        File.read("public/index.html").should contain("[V1]")

        sleep 1.1.seconds
        File.write("content/posts/ext.md", "+++\ntitle = \"Ext\"\n\n[extra]\nbadge = \"V2\"\n+++\n\nbody\n")
        cached_build
        warm = File.read("public/index.html")

        clean_build
        warm.should eq(File.read("public/index.html"))
        warm.should contain("[V2]")
        warm.should_not contain("[V1]")
      end
    end
  end

  it "re-renders listings when a page body changes its summary and word count" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        listing_project("[{{ p.summary }}|{{ p.word_count }}]")
        File.write("content/posts/sum.md",
          "---\ntitle: Sum\n---\nLEAD ONE.\n\n<!-- more -->\n\ntail\n")

        cached_build
        File.read("public/index.html").should contain("LEAD ONE.")

        sleep 1.1.seconds
        File.write("content/posts/sum.md",
          "---\ntitle: Sum\n---\nLEAD TWO CHANGED.\n\n<!-- more -->\n\ntail with several more words appended here\n")
        cached_build
        warm = File.read("public/index.html")

        clean_build
        warm.should eq(File.read("public/index.html"))
        warm.should contain("LEAD TWO CHANGED.")
        warm.should_not contain("LEAD ONE.")
      end
    end
  end

  it "leaves listings cached when no listing template reads those fields" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        # The listing reads only title/url, so a body edit must NOT re-render it.
        listing_project("[{{ p.title }}]")
        File.write("content/posts/body.md", "---\ntitle: Body\n---\noriginal body\n")

        cached_build
        listing_before = File.info("public/index.html").modification_time

        sleep 1.1.seconds
        File.write("content/posts/body.md", "---\ntitle: Body\n---\ncompletely different body\n")
        cached_build

        # The edited page re-rendered...
        File.read("public/posts/body/index.html").should contain("completely different body")
        # ...but the listing, which cannot show the difference, did not.
        File.info("public/index.html").modification_time.should eq(listing_before)
      end
    end
  end
end

describe "cache: static files whose mtime moves backwards" do
  it "re-copies a static file restored to an older revision" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", CACHE_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        FileUtils.mkdir_p("static")
        File.write("content/index.md", "---\ntitle: Home\n---\nHome")
        File.write("templates/index.html", "{{ content }}")
        File.write("templates/page.html", "{{ content }}")
        File.write("static/app.js", "VERSION_A")

        cached_build
        File.read("public/app.js").should eq("VERSION_A")

        # git checkout / stash pop / rsync --times: new content, OLDER mtime.
        File.write("static/app.js", "VERSION_B")
        File.touch("static/app.js", Time.utc(2020, 1, 1))

        cached_build
        File.read("public/app.js").should eq("VERSION_B")
      end
    end
  end

  it "still skips an unchanged static file on a warm build" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", CACHE_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        FileUtils.mkdir_p("static")
        File.write("content/index.md", "---\ntitle: Home\n---\nHome")
        File.write("templates/index.html", "{{ content }}")
        File.write("templates/page.html", "{{ content }}")
        File.write("static/app.js", "VERSION_A")

        cached_build
        source_mtime = File.info("static/app.js").modification_time
        # The copy carries the source mtime, which is what makes the skip an
        # equality test rather than a "destination is newer" test.
        File.info("public/app.js").modification_time.should eq(source_mtime)

        # Mark the destination so a needless re-copy is detectable. Same LENGTH
        # as the source: the skip requires size equality too.
        File.write("public/app.js", "SENTINEL!")
        File.touch("public/app.js", source_mtime)
        cached_build
        File.read("public/app.js").should eq("SENTINEL!")
      end
    end
  end
end

describe "cache: alternating output directories" do
  it "refreshes a stale tree when the output directory switches back" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", CACHE_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/about.md", "---\ntitle: About\n---\nORIGINAL\n")
        File.write("templates/page.html", "{{ content }}")

        cached_build("A")
        File.read("A/about/index.html").should contain("ORIGINAL")

        sleep 1.1.seconds
        File.write("content/about.md", "---\ntitle: About\n---\nUPDATED\n")

        cached_build("B")
        File.read("B/about/index.html").should contain("UPDATED")

        cached_build("A")
        File.read("A/about/index.html").should contain("UPDATED")
      end
    end
  end

  it "still skips unchanged pages when the output directory does not move" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", CACHE_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/about.md", "---\ntitle: About\n---\nORIGINAL\n")
        File.write("templates/page.html", "{{ content }}")

        cached_build("A")
        before = File.info("A/about/index.html").modification_time
        cached_build("A")
        File.info("A/about/index.html").modification_time.should eq(before)
      end
    end
  end
end
