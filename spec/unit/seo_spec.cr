require "../spec_helper"

describe Hwaro::Content::Seo::Sitemap do
  describe ".generate" do
    it "does not generate sitemap when disabled" do
      config = Hwaro::Models::Config.new
      config.sitemap.enabled = false

      site = Hwaro::Models::Site.new(config)

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Sitemap.generate([] of Hwaro::Models::Page, site, output_dir)
        File.exists?(File.join(output_dir, "sitemap.xml")).should be_false
      end
    end

    it "generates sitemap when enabled with pages" do
      config = Hwaro::Models::Config.new
      config.sitemap.enabled = true
      config.base_url = "https://example.com"

      site = Hwaro::Models::Site.new(config)

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test Page"
      page.url = "/test/"
      page.render = true
      page.in_sitemap = true

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Sitemap.generate([page], site, output_dir)

        sitemap_path = File.join(output_dir, "sitemap.xml")
        File.exists?(sitemap_path).should be_true

        content = File.read(sitemap_path)
        content.should contain("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        content.should contain("<urlset")
        content.should contain("https://example.com/test/")
        content.should_not contain("<changefreq>")
        content.should_not contain("<priority>")
      end
    end

    it "excludes pages with in_sitemap = false" do
      config = Hwaro::Models::Config.new
      config.sitemap.enabled = true
      config.base_url = "https://example.com"

      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("included.md")
      page1.url = "/included/"
      page1.render = true
      page1.in_sitemap = true

      page2 = Hwaro::Models::Page.new("excluded.md")
      page2.url = "/excluded/"
      page2.render = true
      page2.in_sitemap = false

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Sitemap.generate([page1, page2], site, output_dir)

        content = File.read(File.join(output_dir, "sitemap.xml"))
        content.should contain("/included/")
        content.should_not contain("/excluded/")
      end
    end

    it "excludes pages with render = false" do
      config = Hwaro::Models::Config.new
      config.sitemap.enabled = true
      config.base_url = "https://example.com"

      site = Hwaro::Models::Site.new(config)

      page = Hwaro::Models::Page.new("norender.md")
      page.url = "/norender/"
      page.render = false
      page.in_sitemap = true

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Sitemap.generate([page], site, output_dir)

        # Sitemap should be empty or not generated
        sitemap_path = File.join(output_dir, "sitemap.xml")
        if File.exists?(sitemap_path)
          content = File.read(sitemap_path)
          content.should_not contain("/norender/")
        end
      end
    end

    it "uses custom sitemap filename" do
      config = Hwaro::Models::Config.new
      config.sitemap.enabled = true
      config.sitemap.filename = "custom-sitemap.xml"
      config.base_url = "https://example.com"

      site = Hwaro::Models::Site.new(config)

      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      page.render = true
      page.in_sitemap = true

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Sitemap.generate([page], site, output_dir)
        File.exists?(File.join(output_dir, "custom-sitemap.xml")).should be_true
      end
    end

    it "includes lastmod from page date" do
      config = Hwaro::Models::Config.new
      config.sitemap.enabled = true
      config.base_url = "https://example.com"

      site = Hwaro::Models::Site.new(config)

      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      page.render = true
      page.in_sitemap = true
      page.date = Time.utc(2024, 6, 15)

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Sitemap.generate([page], site, output_dir)

        content = File.read(File.join(output_dir, "sitemap.xml"))
        content.should contain("<lastmod>2024-06-15</lastmod>")
      end
    end

    it "prefers updated over date for lastmod" do
      config = Hwaro::Models::Config.new
      config.sitemap.enabled = true
      config.base_url = "https://example.com"

      site = Hwaro::Models::Site.new(config)

      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      page.render = true
      page.in_sitemap = true
      page.date = Time.utc(2024, 1, 1)
      page.updated = Time.utc(2024, 6, 15)

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Sitemap.generate([page], site, output_dir)

        content = File.read(File.join(output_dir, "sitemap.xml"))
        content.should contain("<lastmod>2024-06-15</lastmod>")
      end
    end
  end
end

describe Hwaro::Content::Seo::Robots do
  describe ".generate" do
    it "does not generate robots.txt when disabled" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = false

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)
        File.exists?(File.join(output_dir, "robots.txt")).should be_false
      end
    end

    it "generates robots.txt with default rule when enabled" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        robots_path = File.join(output_dir, "robots.txt")
        File.exists?(robots_path).should be_true

        content = File.read(robots_path)
        content.should contain("User-agent: *")
        content.should contain("Allow: /")
      end
    end

    it "includes sitemap directive when sitemap is enabled" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true
      config.sitemap.enabled = true
      config.base_url = "https://example.com"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        content = File.read(File.join(output_dir, "robots.txt"))
        content.should contain("Sitemap: https://example.com/sitemap.xml")
      end
    end

    it "uses custom filename" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true
      config.robots.filename = "custom-robots.txt"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)
        File.exists?(File.join(output_dir, "custom-robots.txt")).should be_true
      end
    end

    it "includes custom rules" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true

      rule = Hwaro::Models::RobotsRule.new("Googlebot")
      rule.allow = ["/public/"]
      rule.disallow = ["/private/", "/admin/"]
      config.robots.rules = [rule]

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        content = File.read(File.join(output_dir, "robots.txt"))
        content.should contain("User-agent: Googlebot")
        content.should contain("Allow: /public/")
        content.should contain("Disallow: /private/")
        content.should contain("Disallow: /admin/")
      end
    end
  end
end

describe Hwaro::Content::Seo::Llms do
  describe ".generate" do
    it "does not generate llms.txt when disabled" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = false

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, output_dir)
        File.exists?(File.join(output_dir, "llms.txt")).should be_false
      end
    end

    it "generates llms.txt with instructions when enabled" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.instructions = "This is a test site."

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, output_dir)

        llms_path = File.join(output_dir, "llms.txt")
        File.exists?(llms_path).should be_true

        content = File.read(llms_path)
        content.should contain("This is a test site.")
      end
    end

    it "uses custom filename" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.filename = "ai-instructions.txt"
      config.llms.instructions = "Custom AI instructions"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, output_dir)
        File.exists?(File.join(output_dir, "ai-instructions.txt")).should be_true
      end
    end

    it "adds newline at end if not present" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.instructions = "No newline"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, output_dir)

        content = File.read(File.join(output_dir, "llms.txt"))
        content.should eq("No newline\n")
      end
    end

    it "does not generate llms-full.txt when full generation disabled" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = false

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test Page"
      page.url = "/test/"
      page.render = true
      page.raw_content = "Hello world"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, [page], output_dir)
        File.exists?(File.join(output_dir, "llms-full.txt")).should be_false
      end
    end

    it "generates llms-full.txt when full generation enabled" do
      config = Hwaro::Models::Config.new
      config.title = "Test Site"
      config.llms.enabled = true
      config.llms.full_enabled = true

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test Page"
      page.url = "/test/"
      page.render = true
      page.raw_content = "Hello world"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, [page], output_dir)

        full_path = File.join(output_dir, "llms-full.txt")
        File.exists?(full_path).should be_true
        File.read(full_path).should contain("Hello world")
      end
    end
  end
end

describe Hwaro::Content::Seo::Feeds do
  describe ".generate" do
    it "does not generate feed when disabled" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = false

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([] of Hwaro::Models::Page, config, output_dir)
        File.exists?(File.join(output_dir, "rss.xml")).should be_false
        File.exists?(File.join(output_dir, "atom.xml")).should be_false
      end
    end

    it "generates RSS feed by default" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.description = "A test site"

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test Post"
      page.url = "/test/"
      page.draft = false
      page.render = true
      page.is_index = false
      page.raw_content = "Test content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page], config, output_dir)

        feed_path = File.join(output_dir, "rss.xml")
        File.exists?(feed_path).should be_true

        content = File.read(feed_path)
        content.should contain("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        content.should contain("<rss version=\"2.0\"")
        content.should contain("<title>Test Site</title>")
        content.should contain("<title>Test Post</title>")
        content.should contain("https://example.com/test/")
      end
    end

    it "generates Atom feed when configured" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "atom"
      config.base_url = "https://example.com"
      config.title = "Test Site"

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test Post"
      page.url = "/test/"
      page.draft = false
      page.render = true
      page.is_index = false
      page.raw_content = "Test content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page], config, output_dir)

        feed_path = File.join(output_dir, "atom.xml")
        File.exists?(feed_path).should be_true

        content = File.read(feed_path)
        content.should contain("<feed xmlns=\"http://www.w3.org/2005/Atom\">")
        content.should contain("<entry>")
      end
    end

    it "excludes draft pages from feed" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.base_url = "https://example.com"
      config.title = "Test Site"

      page1 = Hwaro::Models::Page.new("published.md")
      page1.title = "Published"
      page1.url = "/published/"
      page1.draft = false
      page1.render = true
      page1.is_index = false
      page1.raw_content = "Published content"

      page2 = Hwaro::Models::Page.new("draft.md")
      page2.title = "Draft"
      page2.url = "/draft/"
      page2.draft = true
      page2.render = true
      page2.is_index = false
      page2.raw_content = "Draft content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page1, page2], config, output_dir)

        content = File.read(File.join(output_dir, "rss.xml"))
        content.should contain("Published")
        content.should_not contain("<title>Draft</title>")
      end
    end

    it "excludes index pages from feed" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.base_url = "https://example.com"
      config.title = "Test Site"

      page1 = Hwaro::Models::Page.new("post.md")
      page1.title = "Post"
      page1.url = "/post/"
      page1.draft = false
      page1.render = true
      page1.is_index = false
      page1.raw_content = "Post content"

      page2 = Hwaro::Models::Page.new("index.md")
      page2.title = "Index"
      page2.url = "/"
      page2.draft = false
      page2.render = true
      page2.is_index = true
      page2.raw_content = "Index content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page1, page2], config, output_dir)

        content = File.read(File.join(output_dir, "rss.xml"))
        content.should contain("<title>Post</title>")
        content.should_not contain("<title>Index</title>")
      end
    end

    it "respects feed limit" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.limit = 2
      config.base_url = "https://example.com"
      config.title = "Test Site"

      pages = (1..5).map do |i|
        page = Hwaro::Models::Page.new("post#{i}.md")
        page.title = "Post #{i}"
        page.url = "/post#{i}/"
        page.draft = false
        page.render = true
        page.is_index = false
        page.date = Time.utc(2024, i, 1)
        page.raw_content = "Content #{i}"
        page
      end

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate(pages, config, output_dir)

        content = File.read(File.join(output_dir, "rss.xml"))
        # Should only have 2 items (latest first: Post 5 and Post 4)
        content.scan(/<item>/).size.should eq(2)
      end
    end

    it "uses custom filename" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "feed.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.draft = false
      page.render = true
      page.is_index = false
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page], config, output_dir)
        File.exists?(File.join(output_dir, "feed.xml")).should be_true
      end
    end

    it "truncates content when truncate is set" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.truncate = 10
      config.base_url = "https://example.com"
      config.title = "Test Site"

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.draft = false
      page.render = true
      page.is_index = false
      page.raw_content = "This is a very long content that should be truncated"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page], config, output_dir)

        content = File.read(File.join(output_dir, "rss.xml"))
        # Content should be truncated and end with "..."
        content.should contain("...")
      end
    end
  end

  describe ".generate_rss" do
    it "includes pubDate when page has date" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.title = "Test Site"

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.date = Time.utc(2024, 6, 15, 12, 0, 0)
      page.raw_content = "Content"

      rss = Hwaro::Content::Seo::Feeds.generate_rss([page], config, "rss.xml", false, config.title, "")
      rss.should contain("<pubDate>")
    end

    it "includes self-referencing atom:link" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.title = "Test Site"

      rss = Hwaro::Content::Seo::Feeds.generate_rss([] of Hwaro::Models::Page, config, "rss.xml", false, config.title, "")
      rss.should contain("atom:link")
      rss.should contain("rel=\"self\"")
      rss.should contain("https://example.com/rss.xml")
    end
  end

  describe ".generate_atom" do
    it "includes updated timestamp" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.title = "Test Site"

      atom = Hwaro::Content::Seo::Feeds.generate_atom([] of Hwaro::Models::Page, config, "atom.xml", false, config.title, "")
      atom.should contain("<updated>")
    end

    it "includes subtitle when description is set" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.description = "Site description"

      atom = Hwaro::Content::Seo::Feeds.generate_atom([] of Hwaro::Models::Page, config, "atom.xml", false, config.title, "")
      atom.should contain("<subtitle>Site description</subtitle>")
    end

    it "includes self-referencing link" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.title = "Test Site"

      atom = Hwaro::Content::Seo::Feeds.generate_atom([] of Hwaro::Models::Page, config, "atom.xml", false, config.title, "")
      atom.should contain("rel=\"self\"")
      atom.should contain("https://example.com/atom.xml")
    end
  end
end
