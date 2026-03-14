require "../spec_helper"
require "../../src/models/config"
require "../../src/models/page"
require "../../src/models/site"
require "../../src/core/build/builder"

# Reopen Builder to expose private method for testing
module Hwaro::Core::Build
  class Builder
    def test_compute_series(site)
      compute_series(site)
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
    p2.series_pages.size.should eq(1)
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

    p1.series_pages.size.should eq(1)
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
