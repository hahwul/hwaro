require "../spec_helper"

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

        File.exists?(File.join(dir, "sitemap.xml")).should be_false
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
  end
end
