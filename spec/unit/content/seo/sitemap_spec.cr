require "../../../spec_helper"

describe Hwaro::Content::Seo::Sitemap do
  describe ".generate" do
    it "generates sitemap.xml with pages" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        site = Hwaro::Models::Site.new(config)

        page = Hwaro::Models::Page.new("blog/hello.md")
        page.url = "/blog/hello/"
        page.in_sitemap = true
        page.render = true
        page.date = Time.utc(2024, 6, 15)

        Hwaro::Content::Seo::Sitemap.generate([page], site, dir)

        sitemap_path = File.join(dir, "sitemap.xml")
        File.exists?(sitemap_path).should be_true

        content = File.read(sitemap_path)
        content.should contain("<loc>https://example.com/blog/hello/</loc>")
        content.should contain("<lastmod>2024-06-15</lastmod>")
        content.should contain("<changefreq>weekly</changefreq>")
        content.should contain("<priority>0.5</priority>")
      end
    end

    it "clamps an out-of-range priority to [0.0, 1.0] in the emitted XML" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        config.sitemap.priority = 5.0 # out of range (raw, as the doctor would see)
        site = Hwaro::Models::Site.new(config)

        page = Hwaro::Models::Page.new("a.md")
        page.url = "/a/"
        page.in_sitemap = true
        page.render = true

        Hwaro::Content::Seo::Sitemap.generate([page], site, dir)

        content = File.read(File.join(dir, "sitemap.xml"))
        content.should contain("<priority>1.0</priority>")
        content.should_not contain("<priority>5.0</priority>")
      end
    end

    it "rewrites sitemap.xml as an empty urlset when no eligible pages remain" do
      # Drafting the last sitemap-eligible page used to leave the previous
      # sitemap.xml on disk untouched (early return) — stale URLs kept being
      # served/deployed. An empty (valid) urlset is written instead.
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        site = Hwaro::Models::Site.new(config)

        page = Hwaro::Models::Page.new("blog/hello.md")
        page.url = "/blog/hello/"
        page.in_sitemap = true
        page.render = true

        Hwaro::Content::Seo::Sitemap.generate([page], site, dir)
        File.read(File.join(dir, "sitemap.xml")).should contain("<url>")

        page.draft = true
        Hwaro::Content::Seo::Sitemap.generate([page], site, dir)

        content = File.read(File.join(dir, "sitemap.xml"))
        content.should contain("<urlset")
        content.should_not contain("<url>")
      end
    end

    it "skips when sitemap is disabled" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = false
        site = Hwaro::Models::Site.new(config)

        page = Hwaro::Models::Page.new("blog/hello.md")
        page.url = "/blog/hello/"
        page.in_sitemap = true
        page.render = true

        Hwaro::Content::Seo::Sitemap.generate([page], site, dir)

        File.exists?(File.join(dir, "sitemap.xml")).should be_false
      end
    end

    it "filters out pages with in_sitemap=false" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        site = Hwaro::Models::Site.new(config)

        included = Hwaro::Models::Page.new("blog/yes.md")
        included.url = "/blog/yes/"
        included.in_sitemap = true
        included.render = true

        excluded = Hwaro::Models::Page.new("blog/no.md")
        excluded.url = "/blog/no/"
        excluded.in_sitemap = false
        excluded.render = true

        Hwaro::Content::Seo::Sitemap.generate([included, excluded], site, dir)

        content = File.read(File.join(dir, "sitemap.xml"))
        content.should contain("/blog/yes/")
        content.should_not contain("/blog/no/")
      end
    end

    it "filters out pages with render=false" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        site = Hwaro::Models::Site.new(config)

        page = Hwaro::Models::Page.new("blog/draft.md")
        page.url = "/blog/draft/"
        page.in_sitemap = true
        page.render = false

        Hwaro::Content::Seo::Sitemap.generate([page], site, dir)

        # An (empty, valid) sitemap is still written — a stale previous
        # sitemap must never survive on disk — but the filtered page is not
        # in it.
        content = File.read(File.join(dir, "sitemap.xml"))
        content.should contain("<urlset")
        content.should_not contain("<url>")
      end
    end

    it "excludes draft pages so --drafts builds don't leak them via sitemap" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        site = Hwaro::Models::Site.new(config)

        published = Hwaro::Models::Page.new("blog/published.md")
        published.url = "/blog/published/"
        published.in_sitemap = true
        published.render = true

        draft = Hwaro::Models::Page.new("blog/wip.md")
        draft.url = "/blog/wip/"
        draft.in_sitemap = true
        draft.render = true
        draft.draft = true

        Hwaro::Content::Seo::Sitemap.generate([published, draft], site, dir)

        content = File.read(File.join(dir, "sitemap.xml"))
        content.should contain("/blog/published/")
        content.should_not contain("/blog/wip/")
      end
    end

    it "excludes paths matching exclude patterns" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        config.sitemap.exclude = ["/admin"]
        site = Hwaro::Models::Site.new(config)

        public_page = Hwaro::Models::Page.new("blog/post.md")
        public_page.url = "/blog/post/"
        public_page.in_sitemap = true
        public_page.render = true

        admin_page = Hwaro::Models::Page.new("admin/index.md")
        admin_page.url = "/admin/"
        admin_page.in_sitemap = true
        admin_page.render = true

        Hwaro::Content::Seo::Sitemap.generate([public_page, admin_page], site, dir)

        content = File.read(File.join(dir, "sitemap.xml"))
        content.should contain("/blog/post/")
        content.should_not contain("/admin/")
      end
    end

    it "prefers updated date over date for lastmod" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        site = Hwaro::Models::Site.new(config)

        page = Hwaro::Models::Page.new("blog/hello.md")
        page.url = "/blog/hello/"
        page.in_sitemap = true
        page.render = true
        page.date = Time.utc(2024, 1, 1)
        page.updated = Time.utc(2024, 6, 15)

        Hwaro::Content::Seo::Sitemap.generate([page], site, dir)

        content = File.read(File.join(dir, "sitemap.xml"))
        content.should contain("<lastmod>2024-06-15</lastmod>")
        content.should_not contain("<lastmod>2024-01-01</lastmod>")
      end
    end

    it "escapes XML special characters in URLs" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        site = Hwaro::Models::Site.new(config)

        page = Hwaro::Models::Page.new("blog/a&b.md")
        page.url = "/blog/a&b/"
        page.in_sitemap = true
        page.render = true

        Hwaro::Content::Seo::Sitemap.generate([page], site, dir)

        content = File.read(File.join(dir, "sitemap.xml"))
        content.should contain("<loc>https://example.com/blog/a&amp;b/</loc>")
      end
    end

    it "omits lastmod when page has no date" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        site = Hwaro::Models::Site.new(config)

        page = Hwaro::Models::Page.new("blog/hello.md")
        page.url = "/blog/hello/"
        page.in_sitemap = true
        page.render = true

        Hwaro::Content::Seo::Sitemap.generate([page], site, dir)

        content = File.read(File.join(dir, "sitemap.xml"))
        content.should_not contain("<lastmod>")
      end
    end

    it "uses custom filename from config" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        config.sitemap.filename = "custom-sitemap.xml"
        site = Hwaro::Models::Site.new(config)

        page = Hwaro::Models::Page.new("blog/hello.md")
        page.url = "/blog/hello/"
        page.in_sitemap = true
        page.render = true

        Hwaro::Content::Seo::Sitemap.generate([page], site, dir)

        File.exists?(File.join(dir, "custom-sitemap.xml")).should be_true
      end
    end

    it "omits changefreq when config is empty" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        config.sitemap.changefreq = ""
        site = Hwaro::Models::Site.new(config)

        page = Hwaro::Models::Page.new("blog/hello.md")
        page.url = "/blog/hello/"
        page.in_sitemap = true
        page.render = true

        Hwaro::Content::Seo::Sitemap.generate([page], site, dir)

        content = File.read(File.join(dir, "sitemap.xml"))
        content.should_not contain("<changefreq>")
      end
    end

    it "generates valid XML structure" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        site = Hwaro::Models::Site.new(config)

        page = Hwaro::Models::Page.new("blog/hello.md")
        page.url = "/blog/hello/"
        page.in_sitemap = true
        page.render = true

        Hwaro::Content::Seo::Sitemap.generate([page], site, dir)

        content = File.read(File.join(dir, "sitemap.xml"))
        content.should start_with("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        content.should contain("<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">")
        content.should end_with("</urlset>\n")
      end
    end

    it "keeps the path-sort-first collision winner, matching the render phase" do
      # Regression (A6): on a URL collision the render phase writes the page
      # whose source path sorts FIRST (compute_output_url_winners); the
      # sitemap kept the LAST occurrence, advertising lastmod from the
      # unwritten loser.
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        site = Hwaro::Models::Site.new(config)

        winner = Hwaro::Models::Page.new("blog/a.md")
        winner.url = "/blog/same/"
        winner.in_sitemap = true
        winner.render = true
        winner.date = Time.utc(2024, 1, 1)

        loser = Hwaro::Models::Page.new("blog/z.md")
        loser.url = "/blog/same/"
        loser.in_sitemap = true
        loser.render = true
        loser.date = Time.utc(2025, 12, 31)

        Hwaro::Content::Seo::Sitemap.generate([winner, loser], site, dir)

        content = File.read(File.join(dir, "sitemap.xml"))
        content.scan("<loc>").size.should eq(1)
        content.should contain("<lastmod>2024-01-01</lastmod>")
        content.should_not contain("<lastmod>2025-12-31</lastmod>")
      end
    end

    it "excludes render=false translations from hreflang alternates" do
      # Regression (A17): a translation with render=false has no written
      # output; advertising it as an hreflang alternate points crawlers at
      # a 404.
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.sitemap.enabled = true
        config.base_url = "https://example.com"
        site = Hwaro::Models::Site.new(config)

        en_page = Hwaro::Models::Page.new("about.md")
        en_page.url = "/about/"
        en_page.in_sitemap = true
        en_page.render = true
        en_page.translations = [
          Hwaro::Models::TranslationLink.new(code: "en", url: "/about/", title: "About", is_current: true, is_default: true),
          Hwaro::Models::TranslationLink.new(code: "ko", url: "/ko/about/", title: "소개"),
        ]

        ko_page = Hwaro::Models::Page.new("about.ko.md")
        ko_page.url = "/ko/about/"
        ko_page.language = "ko"
        ko_page.in_sitemap = true
        ko_page.render = false

        Hwaro::Content::Seo::Sitemap.generate([en_page, ko_page], site, dir)

        content = File.read(File.join(dir, "sitemap.xml"))
        content.should contain("hreflang=\"en\"")
        content.should_not contain("hreflang=\"ko\"")
        content.should_not contain("/ko/about/")
      end
    end
  end
end
