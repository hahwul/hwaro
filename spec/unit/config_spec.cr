require "../spec_helper"

describe Hwaro::Models::Config do
  describe "#initialize" do
    it "has default values" do
      config = Hwaro::Models::Config.new
      config.title.should eq("Hwaro Site")
      config.description.should eq("")
      config.base_url.should eq("")
      config.default_language.should eq("en")
    end
  end

  describe "sitemap configuration" do
    it "has default sitemap configuration" do
      config = Hwaro::Models::Config.new
      config.sitemap.enabled.should eq(false)
      config.sitemap.filename.should eq("sitemap.xml")
      config.sitemap.changefreq.should eq("weekly")
      config.sitemap.priority.should eq(0.5)
    end

    it "can update sitemap settings" do
      config = Hwaro::Models::Config.new
      config.sitemap.enabled = true
      config.sitemap.filename = "custom-sitemap.xml"
      config.sitemap.changefreq = "daily"
      config.sitemap.priority = 0.8

      config.sitemap.enabled.should be_true
      config.sitemap.filename.should eq("custom-sitemap.xml")
      config.sitemap.changefreq.should eq("daily")
      config.sitemap.priority.should eq(0.8)
    end
  end

  describe "robots configuration" do
    it "has default robots configuration" do
      config = Hwaro::Models::Config.new
      config.robots.enabled.should eq(true)
      config.robots.filename.should eq("robots.txt")
      config.robots.rules.should eq([] of Hwaro::Models::RobotsRule)
    end

    it "can add robots rules" do
      config = Hwaro::Models::Config.new
      rule = Hwaro::Models::RobotsRule.new("Googlebot")
      rule.allow = ["/public/"]
      rule.disallow = ["/private/"]
      config.robots.rules = [rule]

      config.robots.rules.size.should eq(1)
      config.robots.rules[0].user_agent.should eq("Googlebot")
      config.robots.rules[0].allow.should eq(["/public/"])
      config.robots.rules[0].disallow.should eq(["/private/"])
    end
  end

  describe "llms configuration" do
    it "has default llms configuration" do
      config = Hwaro::Models::Config.new
      config.llms.enabled.should eq(true)
      config.llms.filename.should eq("llms.txt")
      config.llms.instructions.should eq("")
    end

    it "can update llms settings" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.instructions = "AI instructions here"

      config.llms.enabled.should be_true
      config.llms.instructions.should eq("AI instructions here")
    end
  end

  describe "feeds configuration" do
    it "has default feeds configuration" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled.should eq(false)
      config.feeds.filename.should eq("")
      config.feeds.type.should eq("rss")
      config.feeds.truncate.should eq(0)
      config.feeds.limit.should eq(10)
      config.feeds.sections.should eq([] of String)
    end

    it "can update feeds settings" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "atom"
      config.feeds.truncate = 200
      config.feeds.limit = 50
      config.feeds.sections = ["blog", "news"]

      config.feeds.enabled.should be_true
      config.feeds.type.should eq("atom")
      config.feeds.truncate.should eq(200)
      config.feeds.limit.should eq(50)
      config.feeds.sections.should eq(["blog", "news"])
    end
  end

  describe "search configuration" do
    it "has default search configuration" do
      config = Hwaro::Models::Config.new
      config.search.enabled.should eq(false)
      config.search.format.should eq("fuse_json")
      config.search.fields.should eq(["title", "content"])
      config.search.filename.should eq("search.json")
    end

    it "can update search settings" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.format = "fuse_javascript"
      config.search.fields = ["title", "content", "tags", "url"]
      config.search.filename = "search-index.json"

      config.search.enabled.should be_true
      config.search.format.should eq("fuse_javascript")
      config.search.fields.should eq(["title", "content", "tags", "url"])
      config.search.filename.should eq("search-index.json")
    end
  end

  describe "plugin configuration" do
    it "has default plugin configuration" do
      config = Hwaro::Models::Config.new
      config.plugins.processors.should eq(["markdown"])
    end

    it "can update plugin settings" do
      config = Hwaro::Models::Config.new
      config.plugins.processors = ["markdown", "custom"]

      config.plugins.processors.should eq(["markdown", "custom"])
    end
  end

  describe "content files configuration" do
    it "is disabled by default" do
      config = Hwaro::Models::Config.new
      config.content_files.enabled?.should be_false
      config.content_files.allow_extensions.should eq([] of String)
      config.content_files.disallow_extensions.should eq([] of String)
      config.content_files.disallow_paths.should eq([] of String)
    end

    it "loads allow/deny rules from config.toml" do
      toml = <<-TOML
      title = "Test"

      [content.files]
      allow_extensions = ["jpg", ".png", "MD"]
      disallow_extensions = ["png"]
      disallow_paths = ["private/**", "**/_*"]
      TOML

      File.tempfile("hwaro-config") do |file|
        file.print(toml)
        file.flush

        config = Hwaro::Models::Config.load(file.path)
        config.content_files.enabled?.should be_true
        config.content_files.allow_extensions.should eq([".jpg", ".png", ".md"])
        config.content_files.disallow_extensions.should eq([".png"])
        config.content_files.disallow_paths.should eq(["private/**", "**/_*"])

        config.content_files.publish?("about/profile.jpg").should be_true
        config.content_files.publish?("about/job.png").should be_false
        config.content_files.publish?("private/file.jpg").should be_false
        config.content_files.publish?("about/_secret.jpg").should be_false

        # Never publish markdown as a raw file
        config.content_files.publish?("notes/readme.md").should be_false
      end
    end
  end

  describe "pagination configuration" do
    it "has default pagination configuration" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled.should eq(false)
      config.pagination.per_page.should eq(10)
    end

    it "can update pagination settings" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled = true
      config.pagination.per_page = 20

      config.pagination.enabled.should be_true
      config.pagination.per_page.should eq(20)
    end
  end

  describe "highlight configuration" do
    it "has default highlight configuration" do
      config = Hwaro::Models::Config.new
      config.highlight.enabled.should eq(true)
      config.highlight.theme.should eq("github")
      config.highlight.use_cdn.should eq(true)
    end

    it "can update highlight settings" do
      config = Hwaro::Models::Config.new
      config.highlight.enabled = false
      config.highlight.theme = "monokai"
      config.highlight.use_cdn = false

      config.highlight.enabled.should be_false
      config.highlight.theme.should eq("monokai")
      config.highlight.use_cdn.should be_false
    end
  end

  describe "auto_includes configuration" do
    it "has default auto_includes configuration" do
      config = Hwaro::Models::Config.new
      config.auto_includes.enabled.should eq(false)
      config.auto_includes.dirs.should eq([] of String)
    end

    it "can update auto_includes settings" do
      config = Hwaro::Models::Config.new
      config.auto_includes.enabled = true
      config.auto_includes.dirs = ["assets/css", "assets/js"]

      config.auto_includes.enabled.should be_true
      config.auto_includes.dirs.should eq(["assets/css", "assets/js"])
    end
  end

  describe "opengraph configuration" do
    it "has default opengraph configuration" do
      config = Hwaro::Models::Config.new
      config.og.default_image.should be_nil
      config.og.twitter_card.should eq("summary_large_image")
      config.og.twitter_site.should be_nil
      config.og.twitter_creator.should be_nil
      config.og.fb_app_id.should be_nil
      config.og.og_type.should eq("article")
    end

    it "can update opengraph settings" do
      config = Hwaro::Models::Config.new
      config.og.default_image = "/images/og-default.png"
      config.og.twitter_card = "summary"
      config.og.twitter_site = "@mysite"
      config.og.twitter_creator = "@author"
      config.og.fb_app_id = "123456789"
      config.og.og_type = "article"

      config.og.default_image.should eq("/images/og-default.png")
      config.og.twitter_card.should eq("summary")
      config.og.twitter_site.should eq("@mysite")
      config.og.twitter_creator.should eq("@author")
      config.og.fb_app_id.should eq("123456789")
      config.og.og_type.should eq("article")
    end
  end

  describe "taxonomies configuration" do
    it "has empty taxonomies by default" do
      config = Hwaro::Models::Config.new
      config.taxonomies.should eq([] of Hwaro::Models::TaxonomyConfig)
    end

    it "can add taxonomies" do
      config = Hwaro::Models::Config.new
      tags_config = Hwaro::Models::TaxonomyConfig.new("tags")
      categories_config = Hwaro::Models::TaxonomyConfig.new("categories")
      categories_config.feed = true
      categories_config.paginate_by = 10

      config.taxonomies = [tags_config, categories_config]

      config.taxonomies.size.should eq(2)
      config.taxonomies[0].name.should eq("tags")
      config.taxonomies[1].name.should eq("categories")
      config.taxonomies[1].feed.should be_true
      config.taxonomies[1].paginate_by.should eq(10)
    end
  end

  describe "build configuration" do
    it "has default build hooks configuration" do
      config = Hwaro::Models::Config.new
      config.build.hooks.pre.should eq([] of String)
      config.build.hooks.post.should eq([] of String)
    end

    it "can add build hooks" do
      config = Hwaro::Models::Config.new
      config.build.hooks.pre = ["npm install", "npm run build"]
      config.build.hooks.post = ["npm run minify"]

      config.build.hooks.pre.should eq(["npm install", "npm run build"])
      config.build.hooks.post.should eq(["npm run minify"])
    end
  end

  describe "markdown configuration" do
    it "has default markdown configuration" do
      config = Hwaro::Models::Config.new
      config.markdown.safe.should eq(false)
    end

    it "can update markdown settings" do
      config = Hwaro::Models::Config.new
      config.markdown.safe = true

      config.markdown.safe.should be_true
    end
  end

  describe "multilingual configuration" do
    it "has default language configuration" do
      config = Hwaro::Models::Config.new
      config.default_language.should eq("en")
      config.languages.should eq({} of String => Hwaro::Models::LanguageConfig)
    end

    it "returns false for multilingual? when no languages configured" do
      config = Hwaro::Models::Config.new
      config.multilingual?.should be_false
    end

    it "returns true for multilingual? when multiple languages configured" do
      config = Hwaro::Models::Config.new
      en = Hwaro::Models::LanguageConfig.new("en")
      ko = Hwaro::Models::LanguageConfig.new("ko")
      config.languages["en"] = en
      config.languages["ko"] = ko

      config.multilingual?.should be_true
    end

    it "can configure multiple languages" do
      config = Hwaro::Models::Config.new

      en = Hwaro::Models::LanguageConfig.new("en")
      en.language_name = "English"
      en.weight = 1

      ko = Hwaro::Models::LanguageConfig.new("ko")
      ko.language_name = "한국어"
      ko.weight = 2

      config.languages["en"] = en
      config.languages["ko"] = ko

      config.languages.size.should eq(2)
      config.languages["en"].language_name.should eq("English")
      config.languages["ko"].language_name.should eq("한국어")
    end
  end
end

describe Hwaro::Models::SitemapConfig do
  it "has default values" do
    config = Hwaro::Models::SitemapConfig.new
    config.enabled.should eq(false)
    config.filename.should eq("sitemap.xml")
    config.changefreq.should eq("weekly")
    config.priority.should eq(0.5)
  end
end

describe Hwaro::Models::RobotsRule do
  it "initializes with user agent" do
    rule = Hwaro::Models::RobotsRule.new("Googlebot")
    rule.user_agent.should eq("Googlebot")
    rule.allow.should eq([] of String)
    rule.disallow.should eq([] of String)
  end
end

describe Hwaro::Models::RobotsConfig do
  it "has default values" do
    config = Hwaro::Models::RobotsConfig.new
    config.enabled.should eq(true)
    config.filename.should eq("robots.txt")
    config.rules.should eq([] of Hwaro::Models::RobotsRule)
  end
end

describe Hwaro::Models::LlmsConfig do
  it "has default values" do
    config = Hwaro::Models::LlmsConfig.new
    config.enabled.should eq(true)
    config.filename.should eq("llms.txt")
    config.instructions.should eq("")
  end
end

describe Hwaro::Models::SearchConfig do
  it "has default values" do
    config = Hwaro::Models::SearchConfig.new
    config.enabled.should eq(false)
    config.format.should eq("fuse_json")
    config.fields.should eq(["title", "content"])
    config.filename.should eq("search.json")
  end
end

describe Hwaro::Models::FeedConfig do
  it "has default values" do
    config = Hwaro::Models::FeedConfig.new
    config.enabled.should eq(false)
    config.filename.should eq("")
    config.type.should eq("rss")
    config.truncate.should eq(0)
    config.limit.should eq(10)
    config.sections.should eq([] of String)
  end
end

describe Hwaro::Models::PluginConfig do
  it "has default values" do
    config = Hwaro::Models::PluginConfig.new
    config.processors.should eq(["markdown"])
  end
end

describe Hwaro::Models::PaginationConfig do
  it "has default values" do
    config = Hwaro::Models::PaginationConfig.new
    config.enabled.should eq(false)
    config.per_page.should eq(10)
  end
end

describe Hwaro::Models::HighlightConfig do
  it "has default values" do
    config = Hwaro::Models::HighlightConfig.new
    config.enabled.should eq(true)
    config.theme.should eq("github")
    config.use_cdn.should eq(true)
  end

  describe "css_tag" do
    it "returns CDN link when use_cdn is true" do
      config = Hwaro::Models::HighlightConfig.new
      config.css_tag.should contain("cdnjs.cloudflare.com")
      config.css_tag.should contain("github.min.css")
    end

    it "returns local link when use_cdn is false" do
      config = Hwaro::Models::HighlightConfig.new
      config.use_cdn = false
      config.css_tag.should contain("/assets/css/highlight/")
      config.css_tag.should_not contain("cdnjs.cloudflare.com")
    end

    it "returns empty string when disabled" do
      config = Hwaro::Models::HighlightConfig.new
      config.enabled = false
      config.css_tag.should eq("")
    end
  end

  describe "js_tag" do
    it "returns CDN script when use_cdn is true" do
      config = Hwaro::Models::HighlightConfig.new
      config.js_tag.should contain("cdnjs.cloudflare.com")
      config.js_tag.should contain("highlight.min.js")
      config.js_tag.should contain("hljs.highlightAll()")
    end

    it "returns local script when use_cdn is false" do
      config = Hwaro::Models::HighlightConfig.new
      config.use_cdn = false
      config.js_tag.should contain("/assets/js/highlight.min.js")
      config.js_tag.should_not contain("cdnjs.cloudflare.com")
    end

    it "returns empty string when disabled" do
      config = Hwaro::Models::HighlightConfig.new
      config.enabled = false
      config.js_tag.should eq("")
    end
  end

  describe "tags" do
    it "returns combined CSS and JS tags" do
      config = Hwaro::Models::HighlightConfig.new
      tags = config.tags
      tags.should contain("stylesheet")
      tags.should contain("highlight.min.js")
    end

    it "returns empty string when disabled" do
      config = Hwaro::Models::HighlightConfig.new
      config.enabled = false
      config.tags.should eq("")
    end
  end
end

describe Hwaro::Models::AutoIncludesConfig do
  it "has default values" do
    config = Hwaro::Models::AutoIncludesConfig.new
    config.enabled.should eq(false)
    config.dirs.should eq([] of String)
  end
end

describe Hwaro::Models::OpenGraphConfig do
  it "has default values" do
    config = Hwaro::Models::OpenGraphConfig.new
    config.default_image.should be_nil
    config.twitter_card.should eq("summary_large_image")
    config.twitter_site.should be_nil
    config.twitter_creator.should be_nil
    config.fb_app_id.should be_nil
    config.og_type.should eq("article")
  end
end

describe Hwaro::Models::TaxonomyConfig do
  it "initializes with name" do
    config = Hwaro::Models::TaxonomyConfig.new("tags")
    config.name.should eq("tags")
    config.feed.should eq(false)
    config.sitemap.should eq(true)
    config.paginate_by.should be_nil
  end
end

describe Hwaro::Models::BuildHooksConfig do
  it "has default values" do
    config = Hwaro::Models::BuildHooksConfig.new
    config.pre.should eq([] of String)
    config.post.should eq([] of String)
  end
end

describe Hwaro::Models::BuildConfig do
  it "has default values" do
    config = Hwaro::Models::BuildConfig.new
    config.hooks.pre.should eq([] of String)
    config.hooks.post.should eq([] of String)
  end
end

describe Hwaro::Models::MarkdownConfig do
  it "has default values" do
    config = Hwaro::Models::MarkdownConfig.new
    config.safe.should eq(false)
  end
end

describe Hwaro::Models::LanguageConfig do
  it "initializes with code" do
    config = Hwaro::Models::LanguageConfig.new("ko")
    config.code.should eq("ko")
    config.language_name.should eq("ko")
    config.weight.should eq(1)
    config.generate_feed.should eq(true)
    config.build_search_index.should eq(true)
    config.taxonomies.should eq(["tags", "categories"])
  end

  it "can set properties" do
    config = Hwaro::Models::LanguageConfig.new("ko")
    config.language_name = "한국어"
    config.weight = 1
    config.generate_feed = false
    config.build_search_index = false
    config.taxonomies = ["tags", "categories"]

    config.language_name.should eq("한국어")
    config.weight.should eq(1)
    config.generate_feed.should be_false
    config.build_search_index.should be_false
    config.taxonomies.should eq(["tags", "categories"])
  end
end
