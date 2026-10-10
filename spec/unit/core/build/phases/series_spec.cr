require "../../../../spec_helper"
require "../../../../../src/models/config"
require "../../../../../src/models/page"
require "../../../../../src/models/site"
require "../../../../../src/core/build/builder"
require "../../../../support/build_helper"

# Reopen Builder to expose private method for testing
module Hwaro::Core::Build
  class Builder
    def test_compute_series(site)
      compute_series(site)
    end

    # Same signature as phases_transform_spec.cr's: both files reopen
    # Builder, and the later definition wins in a whole-suite build.
    def test_recompute_series_for_pages(site, changed, old_names = {} of String => String?)
      recompute_series_for_pages(site, changed, old_names)
    end
  end
end

describe "SeriesConfig" do
  it "has correct defaults" do
    config = Hwaro::Models::SeriesConfig.new
    config.enabled.should be_false
  end
end

describe "Series support" do
  it "groups pages by series name and assigns index" do
    builder = Hwaro::Core::Build::Builder.new
    config = Hwaro::Models::Config.new
    config.series.enabled = true
    site = Hwaro::Models::Site.new(config)

    p1 = Hwaro::Models::Page.new("posts/a.md")
    p1.title = "Part 1"
    p1.series = "Crystal Tutorial"
    p1.date = Time.utc(2025, 1, 1)
    p1.url = "/posts/a/"

    p2 = Hwaro::Models::Page.new("posts/b.md")
    p2.title = "Part 2"
    p2.series = "Crystal Tutorial"
    p2.date = Time.utc(2025, 1, 2)
    p2.url = "/posts/b/"

    p3 = Hwaro::Models::Page.new("posts/c.md")
    p3.title = "Part 3"
    p3.series = "Crystal Tutorial"
    p3.date = Time.utc(2025, 1, 3)
    p3.url = "/posts/c/"

    site.pages = [p3, p1, p2] # intentionally unordered

    builder.test_compute_series(site)

    p1.series_index.should eq(1)
    p2.series_index.should eq(2)
    p3.series_index.should eq(3)

    p1.series_pages.size.should eq(3)
    p1.series_pages[0].title.should eq("Part 1")
    p1.series_pages[1].title.should eq("Part 2")
    p1.series_pages[2].title.should eq("Part 3")
  end

  it "sorts by series_weight first, then date" do
    builder = Hwaro::Core::Build::Builder.new
    config = Hwaro::Models::Config.new
    config.series.enabled = true
    site = Hwaro::Models::Site.new(config)

    p1 = Hwaro::Models::Page.new("posts/a.md")
    p1.title = "Should be second"
    p1.series = "My Series"
    p1.series_weight = 2
    p1.date = Time.utc(2025, 1, 1)
    p1.url = "/posts/a/"

    p2 = Hwaro::Models::Page.new("posts/b.md")
    p2.title = "Should be first"
    p2.series = "My Series"
    p2.series_weight = 1
    p2.date = Time.utc(2025, 1, 5)
    p2.url = "/posts/b/"

    site.pages = [p1, p2]

    builder.test_compute_series(site)

    p2.series_index.should eq(1)
    p1.series_index.should eq(2)
  end

  # An undated part used to sort as 1970-01-01: ahead of every part dated
  # later, while list sorting (SortUtils) puts undated pages last.
  it "puts an undated part after every dated part" do
    builder = Hwaro::Core::Build::Builder.new
    config = Hwaro::Models::Config.new
    site = Hwaro::Models::Site.new(config)

    undated = Hwaro::Models::Page.new("posts/a.md")
    undated.title = "A"
    undated.series = "S"
    old = Hwaro::Models::Page.new("posts/b.md")
    old.title = "B"
    old.series = "S"
    old.date = Time.utc(1969, 7, 20)
    recent = Hwaro::Models::Page.new("posts/c.md")
    recent.title = "C"
    recent.series = "S"
    recent.date = Time.utc(2025, 1, 1)

    site.pages = [undated, recent, old]
    builder.test_compute_series(site)

    old.series_index.should eq(1)
    recent.series_index.should eq(2)
    undated.series_index.should eq(3)
  end

  it "handles multiple series independently" do
    builder = Hwaro::Core::Build::Builder.new
    config = Hwaro::Models::Config.new
    config.series.enabled = true
    site = Hwaro::Models::Site.new(config)

    p1 = Hwaro::Models::Page.new("posts/a.md")
    p1.title = "Series A - Part 1"
    p1.series = "Series A"
    p1.date = Time.utc(2025, 1, 1)
    p1.url = "/posts/a/"

    p2 = Hwaro::Models::Page.new("posts/b.md")
    p2.title = "Series B - Part 1"
    p2.series = "Series B"
    p2.date = Time.utc(2025, 1, 1)
    p2.url = "/posts/b/"

    p3 = Hwaro::Models::Page.new("posts/c.md")
    p3.title = "Series A - Part 2"
    p3.series = "Series A"
    p3.date = Time.utc(2025, 1, 2)
    p3.url = "/posts/c/"

    site.pages = [p1, p2, p3]

    builder.test_compute_series(site)

    p1.series_pages.size.should eq(2)
    # A single-post series carries no series_pages (so the scaffold renders no
    # orphan series-nav box); Series B independence still holds — it never
    # absorbs Series A's posts.
    p2.series_pages.size.should eq(0)
    p3.series_pages.size.should eq(2)
  end

  it "excludes drafts from series" do
    builder = Hwaro::Core::Build::Builder.new
    config = Hwaro::Models::Config.new
    config.series.enabled = true
    site = Hwaro::Models::Site.new(config)

    p1 = Hwaro::Models::Page.new("posts/a.md")
    p1.title = "Part 1"
    p1.series = "My Series"
    p1.date = Time.utc(2025, 1, 1)
    p1.url = "/posts/a/"

    p2 = Hwaro::Models::Page.new("posts/b.md")
    p2.title = "Draft Part"
    p2.series = "My Series"
    p2.draft = true
    p2.date = Time.utc(2025, 1, 2)
    p2.url = "/posts/b/"

    site.pages = [p1, p2]

    builder.test_compute_series(site)

    # The draft is excluded, leaving a single real member — so series_pages is
    # empty (no nav). If the draft had leaked in, the series would have 2 members
    # and series_pages.size would be 2, so this still guards draft exclusion.
    p1.series_pages.size.should eq(0)
    p1.series_index.should eq(1)
  end

  it "does not assign series data to pages without series" do
    builder = Hwaro::Core::Build::Builder.new
    config = Hwaro::Models::Config.new
    config.series.enabled = true
    site = Hwaro::Models::Site.new(config)

    p1 = Hwaro::Models::Page.new("posts/a.md")
    p1.title = "No series"
    p1.url = "/posts/a/"

    site.pages = [p1]

    builder.test_compute_series(site)

    p1.series.should be_nil
    p1.series_index.should eq(0)
    p1.series_pages.should be_empty
  end
end

# Regression: series were grouped by name only, so a post and its
# translation sharing `series = "…"` formed one interleaved series — the
# English part 2 reported `series_index = 3` and its series nav linked the
# Korean pages. Series are per language (like related posts and prev/next).
describe "Series language scoping" do
  it "keeps translations in separate per-language series" do
    builder = Hwaro::Core::Build::Builder.new
    config = Hwaro::Models::Config.new
    config.series.enabled = true
    config.default_language = "en"
    config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
    site = Hwaro::Models::Site.new(config)

    make = ->(path : String, weight : Int32, lang : String?) do
      pg = Hwaro::Models::Page.new(path)
      pg.title = path
      pg.series = "Intro"
      pg.series_weight = weight
      pg.language = lang
      pg
    end
    en1 = make.call("posts/a.md", 1, nil)
    en2 = make.call("posts/b.md", 2, nil)
    ko1 = make.call("posts/a.ko.md", 1, "ko")
    ko2 = make.call("posts/b.ko.md", 2, "ko")
    site.pages = [en1, ko1, en2, ko2]

    builder.test_compute_series(site)

    en2.series_index.should eq(2)
    en2.series_pages.map(&.path).should eq(["posts/a.md", "posts/b.md"])
    ko2.series_index.should eq(2)
    ko2.series_pages.map(&.path).should eq(["posts/a.ko.md", "posts/b.ko.md"])

    # The incremental path regroups the same way, and a language whose
    # series shrinks to nothing is cleared without touching the other.
    ko1.draft = true
    ko2.draft = true
    builder.test_recompute_series_for_pages(site, [ko1, ko2])
    ko2.series_index.should eq(0)
    en2.series_index.should eq(2)
    en1.series_pages.map(&.path).should eq(["posts/a.md", "posts/b.md"])
  end
end

describe "Series navigation in a build" do
  # A draft built with --drafts keeps its `series` but is left out of the
  # group (series_index 0). Rendered before a member, it used to seed the
  # group's shared series list with its own empty one, wiping the nav on
  # every member.
  it "keeps the members' list when an excluded page names the series" do
    build_site(
      "title = \"T\"\nbase_url = \"http://localhost\"\n\n[series]\nenabled = true\n",
      content_files: {
        "blog/_index.md" => "+++\ntitle = \"Blog\"\n+++\n",
        "blog/a1.md"     => "+++\ntitle = \"One\"\nseries = \"S\"\nseries_weight = 1\n+++\n",
        "blog/b2.md"     => "+++\ntitle = \"Two\"\nseries = \"S\"\nseries_weight = 2\ndraft = true\n+++\n",
        "blog/c3.md"     => "+++\ntitle = \"Three\"\nseries = \"S\"\nseries_weight = 3\n+++\n",
      },
      template_files: {
        "page.html"    => "{{ page.series_index }}:{% for p in page.series_pages %}[{{ p.title }}]{% endfor %}",
        "section.html" => "S",
      },
      drafts: true,
    ) do
      File.read("public/blog/a1/index.html").should eq("1:[One][Three]")
      File.read("public/blog/c3/index.html").should eq("2:[One][Three]")
      File.read("public/blog/b2/index.html").should eq("0:")
    end
  end
end
