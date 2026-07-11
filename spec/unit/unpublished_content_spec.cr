require "../spec_helper"
require "../../src/models/page"
require "../../src/models/site"
require "../../src/content/seo/sitemap"
require "../../src/content/seo/feeds"
require "../../src/content/search"

# Pages outside their publication window (future `date` / past `expires`)
# only enter a build via --include-future / --include-expired. Those are
# preview flags: the HTML page renders, but — exactly like drafts under
# --drafts — the page must stay out of every public discovery surface
# (sitemap, feeds, search index, llms.txt) and generated listings.
describe "unpublished (future/expired) content exclusion" do
  describe "Page#refresh_unpublished!" do
    it "marks a future-dated page unpublished" do
      page = Hwaro::Models::Page.new("future.md")
      page.date = Time.utc(2099, 12, 31)
      page.refresh_unpublished!(Time.utc)
      page.unpublished.should be_true
    end

    it "marks an expired page unpublished" do
      page = Hwaro::Models::Page.new("expired.md")
      page.date = Time.utc(2020, 1, 1)
      page.expires = Time.utc(2021, 1, 1)
      page.refresh_unpublished!(Time.utc)
      page.unpublished.should be_true
    end

    it "leaves a published page unmarked" do
      page = Hwaro::Models::Page.new("live.md")
      page.date = Time.utc(2020, 1, 1)
      page.refresh_unpublished!(Time.utc)
      page.unpublished.should be_false
    end

    it "clears a stale flag when the window opens (re-parse path)" do
      page = Hwaro::Models::Page.new("was-future.md")
      page.date = Time.utc(2020, 1, 1)
      page.unpublished = true
      page.refresh_unpublished!(Time.utc)
      page.unpublished.should be_false
    end
  end

  describe "eligibility predicates" do
    it "excludes unpublished pages from the search index / llms.txt" do
      page = Hwaro::Models::Page.new("future.md")
      page.render = true
      page.in_search_index = true
      page.search_index_eligible?.should be_true
      page.unpublished = true
      page.search_index_eligible?.should be_false
    end

    it "excludes unpublished pages from generated listings" do
      page = Hwaro::Models::Page.new("future.md")
      page.excluded_from_listings?.should be_false
      page.unpublished = true
      page.excluded_from_listings?.should be_true
    end
  end

  describe "sitemap" do
    it "excludes unpublished pages even when they are in the build" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        site = Hwaro::Models::Site.new(config)

        live = Hwaro::Models::Page.new("live.md")
        live.url = "/live/"

        future = Hwaro::Models::Page.new("future.md")
        future.url = "/future/"
        future.unpublished = true

        Hwaro::Content::Seo::Sitemap.generate([live, future], site, dir)

        content = File.read(File.join(dir, "sitemap.xml"))
        content.should contain("<loc>https://example.com/live/</loc>")
        content.should_not contain("/future/")
      end
    end
  end

  describe "feeds" do
    it "excludes unpublished pages from the main feed" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.base_url = "https://example.com"
        config.feeds.enabled = true
        config.feeds.filename = "rss.xml"

        live = Hwaro::Models::Page.new("live.md")
        live.url = "/live/"
        live.title = "Live Post"
        live.date = Time.utc(2024, 1, 1)

        future = Hwaro::Models::Page.new("future.md")
        future.url = "/future/"
        future.title = "Scheduled Post"
        future.date = Time.utc(2099, 1, 1)
        future.unpublished = true

        Hwaro::Content::Seo::Feeds.generate([live, future], config, dir)

        content = File.read(File.join(dir, config.feeds.filename))
        content.should contain("Live Post")
        content.should_not contain("Scheduled Post")
      end
    end
  end

  describe "search index" do
    it "excludes unpublished pages from search.json" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.search.enabled = true

        live = Hwaro::Models::Page.new("live.md")
        live.url = "/live/"
        live.title = "Live Post"
        live.content = "<p>hello</p>"

        future = Hwaro::Models::Page.new("future.md")
        future.url = "/future/"
        future.title = "Scheduled Post"
        future.content = "<p>secret</p>"
        future.unpublished = true

        Hwaro::Content::Search.generate([live, future], config, dir)

        content = File.read(File.join(dir, File.basename(config.search.filename)))
        content.should contain("Live Post")
        content.should_not contain("Scheduled Post")
      end
    end
  end
end
