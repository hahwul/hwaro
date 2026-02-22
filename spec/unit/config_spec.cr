require "../spec_helper"

# Helper to load a Config from a TOML string via a temp file.
private def load_config(toml : String) : Hwaro::Models::Config
  File.tempfile("hwaro-config", ".toml") do |file|
    file.print(toml)
    file.flush
    return Hwaro::Models::Config.load(file.path)
  end
  raise "unreachable"
end

describe Hwaro::Models::Config do
  describe "#initialize" do
    it "has default values" do
      config = Hwaro::Models::Config.new
      config.title.should eq("Hwaro Site")
      config.description.should eq("")
      config.base_url.should eq("")
      config.default_language.should eq("en")
      config.deployment.source_dir.should eq("public")
      config.deployment.targets.should eq([] of Hwaro::Models::DeploymentTarget)
    end
  end

  # ---------------------------------------------------------------------------
  # TOML round-trip: top-level properties
  # ---------------------------------------------------------------------------

  describe "loading top-level properties from TOML" do
    it "loads title, description, base_url, default_language" do
      config = load_config(<<-TOML)
      title = "My Site"
      description = "A great site"
      base_url = "https://example.com"
      default_language = "ko"
      TOML

      config.title.should eq("My Site")
      config.description.should eq("A great site")
      config.base_url.should eq("https://example.com")
      config.default_language.should eq("ko")
    end

    it "keeps defaults when keys are absent" do
      config = load_config("title = \"Only Title\"")
      config.title.should eq("Only Title")
      config.description.should eq("")
      config.base_url.should eq("")
      config.default_language.should eq("en")
    end
  end

  # ---------------------------------------------------------------------------
  # Sitemap
  # ---------------------------------------------------------------------------

  describe "sitemap configuration" do
    it "has default sitemap configuration" do
      config = Hwaro::Models::Config.new
      config.sitemap.enabled.should eq(false)
      config.sitemap.filename.should eq("sitemap.xml")
      config.sitemap.changefreq.should eq("weekly")
      config.sitemap.priority.should eq(0.5)
      config.sitemap.exclude.should eq([] of String)
    end

    it "can update sitemap settings" do
      config = Hwaro::Models::Config.new
      config.sitemap.enabled = true
      config.sitemap.filename = "custom-sitemap.xml"
      config.sitemap.changefreq = "daily"
      config.sitemap.priority = 0.8
      config.sitemap.exclude = ["/private"]

      config.sitemap.enabled.should be_true
      config.sitemap.filename.should eq("custom-sitemap.xml")
      config.sitemap.changefreq.should eq("daily")
      config.sitemap.priority.should eq(0.8)
      config.sitemap.exclude.should eq(["/private"])
    end

    it "loads sitemap settings from TOML with enabled = true" do
      config = load_config(<<-TOML)
      title = "Test"

      [sitemap]
      enabled = true
      filename = "map.xml"
      changefreq = "daily"
      priority = 0.9
      exclude = ["/secret"]
      TOML

      config.sitemap.enabled.should be_true
      config.sitemap.filename.should eq("map.xml")
      config.sitemap.changefreq.should eq("daily")
      config.sitemap.priority.should eq(0.9)
      config.sitemap.exclude.should eq(["/secret"])
    end

    it "loads sitemap enabled = false from TOML (overrides default false)" do
      config = load_config(<<-TOML)
      title = "Test"

      [sitemap]
      enabled = false
      TOML

      config.sitemap.enabled.should be_false
    end

    it "handles backward-compatible boolean sitemap = true" do
      config = load_config(<<-TOML)
      title = "Test"
      sitemap = true
      TOML

      config.sitemap.enabled.should be_true
    end

    it "handles backward-compatible boolean sitemap = false" do
      config = load_config(<<-TOML)
      title = "Test"
      sitemap = false
      TOML

      # sitemap = false is parsed by as_bool? branch only when value is true,
      # so with false the sitemap_bool variable won't be truthy and we fall through.
      # The default is false, so it remains false.
      config.sitemap.enabled.should be_false
    end
  end

  # ---------------------------------------------------------------------------
  # Robots
  # ---------------------------------------------------------------------------

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

    it "loads robots enabled = true from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [robots]
      enabled = true
      filename = "bots.txt"
      TOML

      config.robots.enabled.should be_true
      config.robots.filename.should eq("bots.txt")
    end

    it "loads robots enabled = false from TOML (overrides default true)" do
      config = load_config(<<-TOML)
      title = "Test"

      [robots]
      enabled = false
      TOML

      config.robots.enabled.should be_false
    end

    it "loads robots rules from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [robots]
      enabled = true

      [[robots.rules]]
      user_agent = "Googlebot"
      allow = ["/public/"]
      disallow = ["/private/", "/admin/"]

      [[robots.rules]]
      user_agent = "*"
      disallow = ["/secret/"]
      TOML

      config.robots.rules.size.should eq(2)
      config.robots.rules[0].user_agent.should eq("Googlebot")
      config.robots.rules[0].allow.should eq(["/public/"])
      config.robots.rules[0].disallow.should eq(["/private/", "/admin/"])
      config.robots.rules[1].user_agent.should eq("*")
      config.robots.rules[1].disallow.should eq(["/secret/"])
    end
  end

  # ---------------------------------------------------------------------------
  # LLMs
  # ---------------------------------------------------------------------------

  describe "llms configuration" do
    it "has default llms configuration" do
      config = Hwaro::Models::Config.new
      config.llms.enabled.should eq(true)
      config.llms.filename.should eq("llms.txt")
      config.llms.instructions.should eq("")
      config.llms.full_enabled.should eq(false)
      config.llms.full_filename.should eq("llms-full.txt")
    end

    it "can update llms settings" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.instructions = "AI instructions here"
      config.llms.full_enabled = true
      config.llms.full_filename = "ai-docs.txt"

      config.llms.enabled.should be_true
      config.llms.instructions.should eq("AI instructions here")
      config.llms.full_enabled.should be_true
      config.llms.full_filename.should eq("ai-docs.txt")
    end

    it "loads all llms settings from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [llms]
      enabled = true
      filename = "ai.txt"
      instructions = "Do not crawl"
      full_enabled = true
      full_filename = "ai-full.txt"
      TOML

      config.llms.enabled.should be_true
      config.llms.filename.should eq("ai.txt")
      config.llms.instructions.should eq("Do not crawl")
      config.llms.full_enabled.should be_true
      config.llms.full_filename.should eq("ai-full.txt")
    end

    it "loads llms enabled = false from TOML (overrides default true)" do
      config = load_config(<<-TOML)
      title = "Test"

      [llms]
      enabled = false
      TOML

      config.llms.enabled.should be_false
    end

    it "loads llms full_enabled = false from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [llms]
      full_enabled = false
      TOML

      config.llms.full_enabled.should be_false
    end

    it "loads llms full_enabled = true from TOML (overrides default false)" do
      config = load_config(<<-TOML)
      title = "Test"

      [llms]
      full_enabled = true
      TOML

      config.llms.full_enabled.should be_true
    end
  end

  # ---------------------------------------------------------------------------
  # Feeds
  # ---------------------------------------------------------------------------

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

    it "loads all feeds settings from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [feeds]
      enabled = true
      filename = "feed.xml"
      type = "atom"
      truncate = 100
      limit = 25
      sections = ["blog", "news"]
      TOML

      config.feeds.enabled.should be_true
      config.feeds.filename.should eq("feed.xml")
      config.feeds.type.should eq("atom")
      config.feeds.truncate.should eq(100)
      config.feeds.limit.should eq(25)
      config.feeds.sections.should eq(["blog", "news"])
    end

    it "loads feeds enabled = false from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [feeds]
      enabled = false
      TOML

      config.feeds.enabled.should be_false
    end

    it "loads feeds enabled = true from TOML (overrides default false)" do
      config = load_config(<<-TOML)
      title = "Test"

      [feeds]
      enabled = true
      TOML

      config.feeds.enabled.should be_true
    end

    it "supports backward-compatible 'generate' key" do
      config = load_config(<<-TOML)
      title = "Test"

      [feeds]
      generate = true
      TOML

      config.feeds.enabled.should be_true
    end

    it "supports backward-compatible generate = false" do
      config = load_config(<<-TOML)
      title = "Test"

      [feeds]
      generate = false
      TOML

      config.feeds.enabled.should be_false
    end
  end

  # ---------------------------------------------------------------------------
  # Search
  # ---------------------------------------------------------------------------

  describe "search configuration" do
    it "has default search configuration" do
      config = Hwaro::Models::Config.new
      config.search.enabled.should eq(false)
      config.search.format.should eq("fuse_json")
      config.search.fields.should eq(["title", "content"])
      config.search.filename.should eq("search.json")
      config.search.exclude.should eq([] of String)
    end

    it "can update search settings" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.format = "fuse_javascript"
      config.search.fields = ["title", "content", "tags", "url"]
      config.search.filename = "search-index.json"
      config.search.exclude = ["/private"]

      config.search.enabled.should be_true
      config.search.format.should eq("fuse_javascript")
      config.search.fields.should eq(["title", "content", "tags", "url"])
      config.search.filename.should eq("search-index.json")
      config.search.exclude.should eq(["/private"])
    end

    it "loads all search settings from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [search]
      enabled = true
      format = "fuse_javascript"
      filename = "idx.json"
      fields = ["title", "tags", "url"]
      exclude = ["/draft/"]
      TOML

      config.search.enabled.should be_true
      config.search.format.should eq("fuse_javascript")
      config.search.filename.should eq("idx.json")
      config.search.fields.should eq(["title", "tags", "url"])
      config.search.exclude.should eq(["/draft/"])
    end

    it "loads search enabled = false from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [search]
      enabled = false
      TOML

      config.search.enabled.should be_false
    end

    it "loads search enabled = true from TOML (overrides default false)" do
      config = load_config(<<-TOML)
      title = "Test"

      [search]
      enabled = true
      TOML

      config.search.enabled.should be_true
    end
  end

  # ---------------------------------------------------------------------------
  # Plugins
  # ---------------------------------------------------------------------------

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

    it "loads plugins processors from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [plugins]
      processors = ["markdown", "html", "custom"]
      TOML

      config.plugins.processors.should eq(["markdown", "html", "custom"])
    end
  end

  # ---------------------------------------------------------------------------
  # Content files
  # ---------------------------------------------------------------------------

  describe "content files configuration" do
    it "is disabled by default" do
      config = Hwaro::Models::Config.new
      config.content_files.enabled?.should be_false
      config.content_files.allow_extensions.should eq([] of String)
      config.content_files.disallow_extensions.should eq([] of String)
      config.content_files.disallow_paths.should eq([] of String)
    end

    it "loads allow/deny rules from config.toml" do
      config = load_config(<<-TOML)
      title = "Test"

      [content.files]
      allow_extensions = ["jpg", ".png", "MD"]
      disallow_extensions = ["png"]
      disallow_paths = ["private/**", "**/_*"]
      TOML

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

  # ---------------------------------------------------------------------------
  # Pagination
  # ---------------------------------------------------------------------------

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

    it "loads all pagination settings from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [pagination]
      enabled = true
      per_page = 15
      TOML

      config.pagination.enabled.should be_true
      config.pagination.per_page.should eq(15)
    end

    it "loads pagination enabled = false from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [pagination]
      enabled = false
      TOML

      config.pagination.enabled.should be_false
    end

    it "loads pagination enabled = true from TOML (overrides default false)" do
      config = load_config(<<-TOML)
      title = "Test"

      [pagination]
      enabled = true
      TOML

      config.pagination.enabled.should be_true
    end
  end

  # ---------------------------------------------------------------------------
  # Highlight
  # ---------------------------------------------------------------------------

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

    it "loads all highlight settings from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [highlight]
      enabled = true
      theme = "dracula"
      use_cdn = true
      TOML

      config.highlight.enabled.should be_true
      config.highlight.theme.should eq("dracula")
      config.highlight.use_cdn.should be_true
    end

    it "loads highlight enabled = false from TOML (overrides default true)" do
      config = load_config(<<-TOML)
      title = "Test"

      [highlight]
      enabled = false
      TOML

      config.highlight.enabled.should be_false
    end

    it "loads highlight use_cdn = false from TOML (overrides default true)" do
      config = load_config(<<-TOML)
      title = "Test"

      [highlight]
      use_cdn = false
      TOML

      config.highlight.use_cdn.should be_false
    end
  end

  # ---------------------------------------------------------------------------
  # Auto includes
  # ---------------------------------------------------------------------------

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

    it "loads all auto_includes settings from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [auto_includes]
      enabled = true
      dirs = ["css", "js"]
      TOML

      config.auto_includes.enabled.should be_true
      config.auto_includes.dirs.should eq(["css", "js"])
    end

    it "loads auto_includes enabled = false from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [auto_includes]
      enabled = false
      TOML

      config.auto_includes.enabled.should be_false
    end

    it "loads auto_includes enabled = true from TOML (overrides default false)" do
      config = load_config(<<-TOML)
      title = "Test"

      [auto_includes]
      enabled = true
      TOML

      config.auto_includes.enabled.should be_true
    end
  end

  # ---------------------------------------------------------------------------
  # OpenGraph
  # ---------------------------------------------------------------------------

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

    it "loads all opengraph settings from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [og]
      default_image = "/img/og.png"
      twitter_card = "summary"
      twitter_site = "@site"
      twitter_creator = "@creator"
      fb_app_id = "999"
      type = "website"
      TOML

      config.og.default_image.should eq("/img/og.png")
      config.og.twitter_card.should eq("summary")
      config.og.twitter_site.should eq("@site")
      config.og.twitter_creator.should eq("@creator")
      config.og.fb_app_id.should eq("999")
      config.og.og_type.should eq("website")
    end
  end

  # ---------------------------------------------------------------------------
  # Taxonomies
  # ---------------------------------------------------------------------------

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

    it "loads taxonomies from TOML with all properties" do
      config = load_config(<<-TOML)
      title = "Test"

      [[taxonomies]]
      name = "tags"
      feed = true
      sitemap = true
      paginate_by = 20

      [[taxonomies]]
      name = "categories"
      feed = false
      sitemap = false
      TOML

      config.taxonomies.size.should eq(2)

      config.taxonomies[0].name.should eq("tags")
      config.taxonomies[0].feed.should be_true
      config.taxonomies[0].sitemap.should be_true
      config.taxonomies[0].paginate_by.should eq(20)

      config.taxonomies[1].name.should eq("categories")
      config.taxonomies[1].feed.should be_false
      config.taxonomies[1].sitemap.should be_false
    end

    it "loads taxonomy feed = true from TOML (overrides default false)" do
      config = load_config(<<-TOML)
      title = "Test"

      [[taxonomies]]
      name = "tags"
      feed = true
      TOML

      config.taxonomies[0].feed.should be_true
    end

    it "loads taxonomy feed = false from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [[taxonomies]]
      name = "tags"
      feed = false
      TOML

      config.taxonomies[0].feed.should be_false
    end

    it "loads taxonomy sitemap = false from TOML (overrides default true)" do
      config = load_config(<<-TOML)
      title = "Test"

      [[taxonomies]]
      name = "tags"
      sitemap = false
      TOML

      config.taxonomies[0].sitemap.should be_false
    end
  end

  # ---------------------------------------------------------------------------
  # Build hooks
  # ---------------------------------------------------------------------------

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

    it "loads build hooks from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [build.hooks]
      pre = ["npm ci", "npx tsc"]
      post = ["./deploy.sh"]
      TOML

      config.build.hooks.pre.should eq(["npm ci", "npx tsc"])
      config.build.hooks.post.should eq(["./deploy.sh"])
    end
  end

  # ---------------------------------------------------------------------------
  # Markdown
  # ---------------------------------------------------------------------------

  describe "markdown configuration" do
    it "has default markdown configuration" do
      config = Hwaro::Models::Config.new
      config.markdown.safe.should eq(false)
      config.markdown.lazy_loading.should eq(false)
    end

    it "can update markdown settings" do
      config = Hwaro::Models::Config.new
      config.markdown.safe = true
      config.markdown.lazy_loading = true

      config.markdown.safe.should be_true
      config.markdown.lazy_loading.should be_true
    end

    it "loads all markdown settings from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [markdown]
      safe = true
      lazy_loading = true
      TOML

      config.markdown.safe.should be_true
      config.markdown.lazy_loading.should be_true
    end

    it "loads markdown safe = false from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [markdown]
      safe = false
      TOML

      config.markdown.safe.should be_false
    end

    it "loads markdown safe = true from TOML (overrides default false)" do
      config = load_config(<<-TOML)
      title = "Test"

      [markdown]
      safe = true
      TOML

      config.markdown.safe.should be_true
    end

    it "loads markdown lazy_loading = false from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [markdown]
      lazy_loading = false
      TOML

      config.markdown.lazy_loading.should be_false
    end

    it "loads markdown lazy_loading = true from TOML (overrides default false)" do
      config = load_config(<<-TOML)
      title = "Test"

      [markdown]
      lazy_loading = true
      TOML

      config.markdown.lazy_loading.should be_true
    end
  end

  # ---------------------------------------------------------------------------
  # Multilingual / Languages
  # ---------------------------------------------------------------------------

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

    it "returns true for multilingual? when default language differs and one language configured" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      ko = Hwaro::Models::LanguageConfig.new("ko")
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

    it "loads languages from TOML with all properties" do
      config = load_config(<<-TOML)
      title = "Test"

      [languages.ko]
      language_name = "한국어"
      weight = 2
      generate_feed = true
      build_search_index = true
      taxonomies = ["tags", "categories"]

      [languages.ja]
      language_name = "日本語"
      weight = 3
      generate_feed = false
      build_search_index = false
      TOML

      config.languages.size.should eq(2)

      ko = config.languages["ko"]
      ko.language_name.should eq("한국어")
      ko.weight.should eq(2)
      ko.generate_feed.should be_true
      ko.build_search_index.should be_true
      ko.taxonomies.should eq(["tags", "categories"])

      ja = config.languages["ja"]
      ja.language_name.should eq("日本語")
      ja.weight.should eq(3)
      ja.generate_feed.should be_false
      ja.build_search_index.should be_false
    end

    it "loads language generate_feed = false from TOML (overrides default true)" do
      config = load_config(<<-TOML)
      title = "Test"

      [languages.ko]
      language_name = "Korean"
      generate_feed = false
      TOML

      config.languages["ko"].generate_feed.should be_false
    end

    it "loads language generate_feed = true from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [languages.ko]
      language_name = "Korean"
      generate_feed = true
      TOML

      config.languages["ko"].generate_feed.should be_true
    end

    it "loads language build_search_index = false from TOML (overrides default true)" do
      config = load_config(<<-TOML)
      title = "Test"

      [languages.ko]
      language_name = "Korean"
      build_search_index = false
      TOML

      config.languages["ko"].build_search_index.should be_false
    end

    it "loads language build_search_index = true from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [languages.ko]
      language_name = "Korean"
      build_search_index = true
      TOML

      config.languages["ko"].build_search_index.should be_true
    end
  end

  # ---------------------------------------------------------------------------
  # Permalinks
  # ---------------------------------------------------------------------------

  describe "permalinks configuration" do
    it "has empty permalinks by default" do
      config = Hwaro::Models::Config.new
      config.permalinks.should eq({} of String => String)
    end

    it "loads permalinks from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [permalinks]
      "old/posts" = "posts"
      "2023/drafts" = "archive/2023"
      TOML

      config.permalinks["old/posts"].should eq("posts")
      config.permalinks["2023/drafts"].should eq("archive/2023")
    end
  end

  # ---------------------------------------------------------------------------
  # Deployment
  # ---------------------------------------------------------------------------

  describe "deployment configuration" do
    it "loads deployment targets from config.toml" do
      config = load_config(<<-TOML)
      title = "Test"

      [deployment]
      target = "prod"
      confirm = true
      dryRun = true
      maxDeletes = 10
      source_dir = "dist"

      [[deployment.targets]]
      name = "prod"
      url = "file://./out"
      include = "**/*.html"
      exclude = "**/drafts/**"

      [[deployment.targets]]
      name = "s3"
      url = "s3://my-bucket"
      command = "aws s3 sync {source}/ {url} --delete"

      [[deployment.matchers]]
      pattern = "^.+\\\\.css$"
      cacheControl = "max-age=31536000"
      gzip = true
      TOML

      config.deployment.target.should eq("prod")
      config.deployment.confirm.should be_true
      config.deployment.dry_run.should be_true
      config.deployment.max_deletes.should eq(10)
      config.deployment.source_dir.should eq("dist")

      config.deployment.targets.size.should eq(2)
      config.deployment.targets[0].name.should eq("prod")
      config.deployment.targets[0].url.should eq("file://./out")
      config.deployment.targets[0].include.should eq("**/*.html")
      config.deployment.targets[0].exclude.should eq("**/drafts/**")

      config.deployment.targets[1].name.should eq("s3")
      config.deployment.targets[1].command.should eq("aws s3 sync {source}/ {url} --delete")

      config.deployment.matchers.size.should eq(1)
      config.deployment.matchers[0].pattern.should eq("^.+\\.css$")
      config.deployment.matchers[0].cache_control.should eq("max-age=31536000")
      config.deployment.matchers[0].gzip.should be_true
    end

    it "loads deployment confirm = false from TOML (overrides default false)" do
      config = load_config(<<-TOML)
      title = "Test"

      [deployment]
      confirm = false
      TOML

      config.deployment.confirm.should be_false
    end

    it "loads deployment confirm = true from TOML" do
      config = load_config(<<-TOML)
      title = "Test"

      [deployment]
      confirm = true
      TOML

      config.deployment.confirm.should be_true
    end
  end

  # ---------------------------------------------------------------------------
  # Comprehensive boolean round-trip: set every boolean to the OPPOSITE of its
  # default in a single TOML file, then verify all are loaded correctly.
  # This is the "catch-all" safety net for the `false || default` class of bugs.
  # ---------------------------------------------------------------------------

  describe "boolean round-trip: opposite-of-default values" do
    it "loads every boolean with the opposite of its default value" do
      # Defaults -> target value in this test:
      #   sitemap.enabled              false -> true
      #   robots.enabled               true  -> false
      #   llms.enabled                 true  -> false
      #   llms.full_enabled            false -> true
      #   feeds.enabled                false -> true
      #   search.enabled               false -> true
      #   pagination.enabled           false -> true
      #   highlight.enabled            true  -> false
      #   highlight.use_cdn            true  -> false
      #   auto_includes.enabled        false -> true
      #   markdown.safe                false -> true
      #   markdown.lazy_loading        false -> true
      #   deployment.confirm           false -> true
      #   taxonomy.feed                false -> true
      #   taxonomy.sitemap             true  -> false
      #   language.generate_feed       true  -> false
      #   language.build_search_index  true  -> false
      config = load_config(<<-TOML)
      title = "Bool Test"

      [sitemap]
      enabled = true

      [robots]
      enabled = false

      [llms]
      enabled = false
      full_enabled = true

      [feeds]
      enabled = true

      [search]
      enabled = true

      [pagination]
      enabled = true

      [highlight]
      enabled = false
      use_cdn = false

      [auto_includes]
      enabled = true

      [markdown]
      safe = true
      lazy_loading = true

      [deployment]
      confirm = true

      [[taxonomies]]
      name = "tags"
      feed = true
      sitemap = false

      [languages.ko]
      language_name = "Korean"
      generate_feed = false
      build_search_index = false
      TOML

      config.sitemap.enabled.should be_true
      config.robots.enabled.should be_false
      config.llms.enabled.should be_false
      config.llms.full_enabled.should be_true
      config.feeds.enabled.should be_true
      config.search.enabled.should be_true
      config.pagination.enabled.should be_true
      config.highlight.enabled.should be_false
      config.highlight.use_cdn.should be_false
      config.auto_includes.enabled.should be_true
      config.markdown.safe.should be_true
      config.markdown.lazy_loading.should be_true
      config.deployment.confirm.should be_true

      config.taxonomies[0].feed.should be_true
      config.taxonomies[0].sitemap.should be_false

      config.languages["ko"].generate_feed.should be_false
      config.languages["ko"].build_search_index.should be_false
    end

    it "loads every boolean matching its default value (identity round-trip)" do
      # Every boolean set to its default — must not silently flip.
      config = load_config(<<-TOML)
      title = "Identity Test"

      [sitemap]
      enabled = false

      [robots]
      enabled = true

      [llms]
      enabled = true
      full_enabled = false

      [feeds]
      enabled = false

      [search]
      enabled = false

      [pagination]
      enabled = false

      [highlight]
      enabled = true
      use_cdn = true

      [auto_includes]
      enabled = false

      [markdown]
      safe = false
      lazy_loading = false

      [deployment]
      confirm = false

      [[taxonomies]]
      name = "tags"
      feed = false
      sitemap = true

      [languages.ko]
      language_name = "Korean"
      generate_feed = true
      build_search_index = true
      TOML

      config.sitemap.enabled.should be_false
      config.robots.enabled.should be_true
      config.llms.enabled.should be_true
      config.llms.full_enabled.should be_false
      config.feeds.enabled.should be_false
      config.search.enabled.should be_false
      config.pagination.enabled.should be_false
      config.highlight.enabled.should be_true
      config.highlight.use_cdn.should be_true
      config.auto_includes.enabled.should be_false
      config.markdown.safe.should be_false
      config.markdown.lazy_loading.should be_false
      config.deployment.confirm.should be_false

      config.taxonomies[0].feed.should be_false
      config.taxonomies[0].sitemap.should be_true

      config.languages["ko"].generate_feed.should be_true
      config.languages["ko"].build_search_index.should be_true
    end

    it "preserves defaults when boolean keys are absent from TOML" do
      config = load_config(<<-TOML)
      title = "Absent Keys"

      [sitemap]
      filename = "map.xml"

      [robots]
      filename = "bots.txt"

      [llms]
      filename = "llms.txt"

      [search]
      format = "fuse_json"

      [pagination]
      per_page = 5

      [highlight]
      theme = "monokai"

      [auto_includes]
      dirs = ["css"]

      [markdown]

      [deployment]
      source_dir = "out"
      TOML

      # All booleans should remain at their defaults
      config.sitemap.enabled.should be_false      # default: false
      config.robots.enabled.should be_true         # default: true
      config.llms.enabled.should be_true           # default: true
      config.llms.full_enabled.should be_false     # default: false
      config.search.enabled.should be_false        # default: false
      config.pagination.enabled.should be_false    # default: false
      config.highlight.enabled.should be_true      # default: true
      config.highlight.use_cdn.should be_true      # default: true
      config.auto_includes.enabled.should be_false # default: false
      config.markdown.safe.should be_false         # default: false
      config.markdown.lazy_loading.should be_false # default: false
      config.deployment.confirm.should be_false    # default: false
    end
  end
end

# =============================================================================
# Individual config class default-value tests
# =============================================================================

describe Hwaro::Models::SitemapConfig do
  it "has default values" do
    config = Hwaro::Models::SitemapConfig.new
    config.enabled.should eq(false)
    config.filename.should eq("sitemap.xml")
    config.changefreq.should eq("weekly")
    config.priority.should eq(0.5)
    config.exclude.should eq([] of String)
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
    config.full_enabled.should eq(false)
    config.full_filename.should eq("llms-full.txt")
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

    it "uses custom theme in CDN link" do
      config = Hwaro::Models::HighlightConfig.new
      config.theme = "monokai"
      config.css_tag.should contain("monokai.min.css")
    end
  end

  describe "js_tag" do
    it "returns CDN script when use_cdn is true" do
      config = Hwaro::Models::HighlightConfig.new
      config.js_tag.should contain("cdnjs.cloudflare.com")
      config.js_tag.should contain("highlight.min.js")
    end
  end

  describe "tags" do
    it "returns both CSS and JS tags" do
      config = Hwaro::Models::HighlightConfig.new
      config.tags.should contain("stylesheet")
      config.tags.should contain("highlight.min.js")
    end
  end
end

describe Hwaro::Models::TaxonomyConfig do
  it "has default values" do
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
    config.lazy_loading.should eq(false)
  end
end

describe Hwaro::Models::LanguageConfig do
  it "has default values" do
    config = Hwaro::Models::LanguageConfig.new("en")
    config.code.should eq("en")
    config.language_name.should eq("en")
    config.weight.should eq(1)
    config.generate_feed.should eq(true)
    config.build_search_index.should eq(true)
    config.taxonomies.should eq(["tags", "categories"])
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
