require "./support/build_helper"

# =============================================================================
# Regression specs for cache fingerprint gaps (issue ledger C1/C2/C3/R7).
#
#   * C1: the page-set fingerprint omitted `image`, `updated`, `authors`,
#     `series`, `toc`; the section-set fingerprint omitted `date`, `assets`,
#     `sort_by`, `reverse`, `transparent`, `paginate` — so listings kept the
#     previous build's values after a front-matter-only edit under --cache.
#   * C2: a page bundle's colocated assets were absent from every cache key,
#     so adding/removing an asset left the page HTML (which renders
#     `page.assets`) stale while the file itself was copied.
#   * C3: literal template refs the snapshot loader cannot serve (./-prefixed,
#     non-template extensions, shadowed extension variants) were hashed as a
#     constant or as the wrong winner, so edits to those files never
#     invalidated anything.
#   * R7: tags/taxonomies joined with bare `,`/`;` — `["a,b"]` and
#     `["a", "b"]` fingerprinted identically, hiding the edit from listings.
# =============================================================================

private FP_CONFIG = <<-TOML
  title = "FP Site"
  base_url = "http://localhost"
  TOML

private def fp_run_builder(output_dir : String, cache : Bool)
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: output_dir, parallel: false, cache: cache,
    minify: false, highlight: false))
end

private def fp_cached_build(output_dir : String = "public")
  fp_run_builder(output_dir, true)
end

private def fp_clean_build(output_dir : String = "public")
  FileUtils.rm_rf(output_dir)
  FileUtils.rm_rf(".hwaro_cache.json")
  fp_run_builder(output_dir, false)
end

# A listing template iterating `site.pages` (the page-set marker), so the
# homepage re-renders only when the page-set fingerprint moves.
private def fp_listing_project(listing_body : String)
  File.write("config.toml", FP_CONFIG)
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("content/index.md", "---\ntitle: Home\n---\nHome")
  File.write("templates/index.html",
    "{% for p in site.pages %}#{listing_body}{% endfor %}")
  File.write("templates/page.html", "{{ content }}")
  File.write("templates/section.html", "{{ content }}")
end

describe "cache: page-set fingerprint covers listing-rendered front matter (C1)" do
  it "re-renders listings when image/updated/authors/series/toc change" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        fp_listing_project(%([{{ p.image }}|{{ p.series }}|{{ p.toc }}|{{ p.authors | join("+") }}|{{ p.updated }}]))
        File.write("content/posts/p1.md", <<-MD)
          +++
          title = "P1"
          image = "/img/a.png"
          series = "alpha"
          toc = false
          authors = ["alice"]
          updated = "2026-01-02"
          +++

          body
          MD

        fp_cached_build
        home = File.read("public/index.html")
        home.should contain("/img/a.png")
        home.should contain("alpha")
        home.should contain("alice")
        home.should contain("2026-01-02")

        sleep 150.milliseconds
        File.write("content/posts/p1.md", <<-MD)
          +++
          title = "P1"
          image = "/img/b.png"
          series = "beta"
          toc = true
          authors = ["bob"]
          updated = "2026-02-03"
          +++

          body
          MD

        fp_cached_build
        warm = File.read("public/index.html")

        fp_clean_build
        warm.should eq(File.read("public/index.html"))
        warm.should contain("/img/b.png")
        warm.should contain("beta")
        warm.should contain("bob")
        warm.should contain("2026-02-03")
        warm.should_not contain("/img/a.png")
      end
    end
  end
end

describe "cache: section-set fingerprint covers nav-rendered section fields (C1)" do
  it "re-renders section-set consumers when date/sort_by/reverse/transparent/paginate change" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", FP_CONFIG)
        FileUtils.mkdir_p("content/posts")
        FileUtils.mkdir_p("templates")
        File.write("content/index.md", "---\ntitle: Home\n---\nHome")
        File.write("templates/index.html",
          %({% for s in site.sections %}[{{ s.date }}|{{ s.sort_by }}|{{ s.reverse }}|{{ s.transparent }}|{{ s.paginate }}]{% endfor %}))
        File.write("templates/page.html", "{{ content }}")
        File.write("templates/section.html", "{{ content }}")
        File.write("content/posts/_index.md", <<-MD)
          +++
          title = "Posts"
          date = "2026-01-01"
          sort_by = "weight"
          transparent = false
          paginate = 2
          +++
          MD
        File.write("content/posts/one.md", "---\ntitle: One\n---\nOne")

        fp_cached_build
        home = File.read("public/index.html")
        home.should contain("2026-01-01")
        home.should contain("weight")

        sleep 150.milliseconds
        File.write("content/posts/_index.md", <<-MD)
          +++
          title = "Posts"
          date = "2026-05-05"
          sort_by = "date"
          reverse = true
          transparent = true
          paginate = 7
          +++
          MD

        fp_cached_build
        warm = File.read("public/index.html")

        fp_clean_build
        warm.should eq(File.read("public/index.html"))
        warm.should contain("2026-05-05")
        warm.should contain("date")
        warm.should contain("|7]")
        warm.should_not contain("2026-01-01")
      end
    end
  end
end

describe "cache: bundle assets are part of the page cache key (C2)" do
  it "re-renders a bundle page when a colocated asset is added" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", FP_CONFIG)
        FileUtils.mkdir_p("content/gallery")
        FileUtils.mkdir_p("templates")
        File.write("content/index.md", "---\ntitle: Home\n---\nHome")
        File.write("templates/index.html", "{{ content }}")
        File.write("templates/page.html",
          %({% for a in page.assets %}[{{ a }}]{% endfor %}))
        File.write("templates/section.html",
          %({% for a in page.assets %}[{{ a }}]{% endfor %}))
        File.write("content/gallery/index.md", "---\ntitle: Gallery\ntemplate: page\n---\nGallery")
        File.write("content/gallery/one.txt", "1")

        fp_cached_build
        File.read("public/gallery/index.html").should contain("one.txt")

        sleep 150.milliseconds
        File.write("content/gallery/two.txt", "2")

        fp_cached_build
        warm = File.read("public/gallery/index.html")

        fp_clean_build
        warm.should eq(File.read("public/gallery/index.html"))
        warm.should contain("one.txt")
        warm.should contain("two.txt")
      end
    end
  end

  it "still skips an unchanged bundle page on a warm rebuild" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", FP_CONFIG)
        FileUtils.mkdir_p("content/gallery")
        FileUtils.mkdir_p("templates")
        File.write("content/index.md", "---\ntitle: Home\n---\nHome")
        File.write("templates/index.html", "{{ content }}")
        File.write("templates/page.html",
          %({% for a in page.assets %}[{{ a }}]{% endfor %}))
        File.write("templates/section.html",
          %({% for a in page.assets %}[{{ a }}]{% endfor %}))
        File.write("content/gallery/index.md", "---\ntitle: Gallery\ntemplate: page\n---\nGallery")
        File.write("content/gallery/one.txt", "1")

        fp_cached_build
        before = File.info("public/gallery/index.html").modification_time

        fp_cached_build
        File.info("public/gallery/index.html").modification_time.should eq(before)
      end
    end
  end
end

describe "cache: refs outside the template snapshot invalidate (C3)" do
  it "re-renders when a shadowed extension variant (foo.j2 vs foo.html) is edited" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", FP_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates/partials")
        File.write("content/about.md", "---\ntitle: About\n---\nAbout")
        File.write("templates/page.html", %({% include "partials/note.j2" %} {{ content }}))
        File.write("templates/partials/note.html", "HTML-VARIANT")
        File.write("templates/partials/note.j2", "J2-OLD")

        fp_cached_build
        File.read("public/about/index.html").should contain("J2-OLD")

        sleep 150.milliseconds
        File.write("templates/partials/note.j2", "J2-NEW")

        fp_cached_build
        html = File.read("public/about/index.html")
        html.should contain("J2-NEW")
        html.should_not contain("J2-OLD")
      end
    end
  end

  it "re-renders when a ./-prefixed include target is edited" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", FP_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates/partials")
        File.write("content/about.md", "---\ntitle: About\n---\nAbout")
        File.write("templates/page.html", %({% include "./partials/nav.html" %} {{ content }}))
        File.write("templates/partials/nav.html", "NAV-OLD")

        fp_cached_build
        File.read("public/about/index.html").should contain("NAV-OLD")

        sleep 150.milliseconds
        File.write("templates/partials/nav.html", "NAV-NEW")

        fp_cached_build
        html = File.read("public/about/index.html")
        html.should contain("NAV-NEW")
        html.should_not contain("NAV-OLD")
      end
    end
  end

  it "re-renders when a non-template-extension include target is edited" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", FP_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates/partials")
        File.write("content/about.md", "---\ntitle: About\n---\nAbout")
        File.write("templates/page.html", %({% include "partials/legal.txt" %} {{ content }}))
        File.write("templates/partials/legal.txt", "LEGAL-OLD")

        fp_cached_build
        File.read("public/about/index.html").should contain("LEGAL-OLD")

        sleep 150.milliseconds
        File.write("templates/partials/legal.txt", "LEGAL-NEW")

        fp_cached_build
        html = File.read("public/about/index.html")
        html.should contain("LEGAL-NEW")
        html.should_not contain("LEGAL-OLD")
      end
    end
  end
end

describe "cache: fingerprint joins are collision-proof (R7)" do
  it "distinguishes tags [\"a,b\"] from tags [\"a\", \"b\"]" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        fp_listing_project(%([{{ p.tags | join("~") }}]))
        File.write("content/posts/t.md", "+++\ntitle = \"T\"\ntags = [\"a,b\"]\n+++\n\nbody\n")

        fp_cached_build
        File.read("public/index.html").should contain("[a,b]")

        sleep 150.milliseconds
        File.write("content/posts/t.md", "+++\ntitle = \"T\"\ntags = [\"a\", \"b\"]\n+++\n\nbody\n")

        fp_cached_build
        warm = File.read("public/index.html")

        fp_clean_build
        warm.should eq(File.read("public/index.html"))
        warm.should contain("[a~b]")
      end
    end
  end
end
