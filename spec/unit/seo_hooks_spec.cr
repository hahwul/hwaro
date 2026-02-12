require "../spec_helper"
require "../../src/content/hooks/seo_hooks"
require "../../src/models/config"
require "../../src/models/site"
require "../../src/models/page"
require "../../src/core/lifecycle"
require "../../src/config/options/build_options"
require "json"

describe Hwaro::Content::Hooks::SeoHooks do
  it "generates SEO files on BeforeGenerate and search index on AfterGenerate" do
    Dir.mktmpdir do |output_dir|
      # 1. Setup Config
      config = Hwaro::Models::Config.new
      config.title = "Test Site"
      config.base_url = "https://example.com"
      config.sitemap.enabled = true
      config.robots.enabled = true
      config.feeds.enabled = true
      config.llms.enabled = true
      config.search.enabled = true
      config.search.fields = ["title", "content"]

      # 2. Setup Site and Pages
      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("page1.md")
      page1.title = "Page 1"
      page1.url = "/page1/"
      page1.raw_content = "This is the content of page 1."
      page1.date = Time.utc(2024, 1, 1)
      page1.render = true
      page1.in_sitemap = true
      page1.in_search_index = true

      page2 = Hwaro::Models::Page.new("page2.md")
      page2.title = "Page 2"
      page2.url = "/page2/"
      page2.raw_content = "This is the content of page 2."
      page2.date = Time.utc(2024, 1, 1)
      page2.render = true
      page2.in_sitemap = true
      page2.in_search_index = true

      site.pages << page1
      site.pages << page2

      # 3. Setup Lifecycle
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::SeoHooks.new
      hooks.register_hooks(manager)

      options = Hwaro::Config::Options::BuildOptions.new(output_dir: output_dir)
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.site = site
      ctx.pages << page1
      ctx.pages << page2

      # 4. Trigger BeforeGenerate (SEO Files)
      manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate, ctx)

      # Verify Sitemap
      sitemap_path = File.join(output_dir, "sitemap.xml")
      File.file?(sitemap_path).should be_true
      sitemap_content = File.read(sitemap_path)
      sitemap_content.should contain("https://example.com/page1/")
      sitemap_content.should contain("https://example.com/page2/")

      # Verify Robots
      robots_path = File.join(output_dir, "robots.txt")
      File.file?(robots_path).should be_true
      robots_content = File.read(robots_path)
      robots_content.should contain("User-agent: *")
      robots_content.should contain("Sitemap: https://example.com/sitemap.xml")

      # Verify Feeds
      rss_path = File.join(output_dir, "rss.xml")
      File.file?(rss_path).should be_true
      rss_content = File.read(rss_path)
      rss_content.should contain("<title>Page 1</title>")
      rss_content.should contain("<link>https://example.com/page1/</link>")

      # Verify LLMs
      llms_path = File.join(output_dir, "llms.txt")
      File.file?(llms_path).should be_true

      # 5. Trigger AfterGenerate (Search Index)
      manager.trigger(Hwaro::Core::Lifecycle::HookPoint::AfterGenerate, ctx)

      # Verify Search Index
      search_path = File.join(output_dir, "search.json")
      File.file?(search_path).should be_true

      search_content = File.read(search_path)
      json_data = JSON.parse(search_content)
      json_data.as_a.size.should eq(2)

      titles = json_data.as_a.map { |item| item["title"].as_s }
      titles.should contain("Page 1")
      titles.should contain("Page 2")
    end
  end

  it "respects configuration to disable SEO files" do
    Dir.mktmpdir do |output_dir|
      config = Hwaro::Models::Config.new
      config.sitemap.enabled = false
      config.robots.enabled = false
      config.feeds.enabled = false
      config.llms.enabled = false
      config.search.enabled = false

      site = Hwaro::Models::Site.new(config)
      page1 = Hwaro::Models::Page.new("page1.md")
      page1.render = true

      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::SeoHooks.new
      hooks.register_hooks(manager)

      options = Hwaro::Config::Options::BuildOptions.new(output_dir: output_dir)
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.site = site
      ctx.pages << page1

      manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate, ctx)
      manager.trigger(Hwaro::Core::Lifecycle::HookPoint::AfterGenerate, ctx)

      File.file?(File.join(output_dir, "sitemap.xml")).should be_false
      File.file?(File.join(output_dir, "robots.txt")).should be_false
      File.file?(File.join(output_dir, "rss.xml")).should be_false
      File.file?(File.join(output_dir, "llms.txt")).should be_false
      File.file?(File.join(output_dir, "search.json")).should be_false
    end
  end
end
