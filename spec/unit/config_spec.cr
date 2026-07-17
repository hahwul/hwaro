require "../spec_helper"
require "../../src/services/defaults/config"

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
  # ---------------------------------------------------------------------------
  # Classified error surface: Models::Config.load raises HwaroError directly
  # so callers don't have to substring-match plain exceptions. See
  # src/models/config.cr and src/utils/errors.cr.
  # ---------------------------------------------------------------------------

  describe ".load classified errors" do
    it "raises HwaroError(HWARO_E_CONFIG) when the file is missing" do
      Dir.mktmpdir do |dir|
        missing_path = File.join(dir, "config.toml")
        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::Models::Config.load(missing_path)
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        err.exit_code.should eq(Hwaro::Errors::EXIT_CONFIG)
        (err.message || "").should contain(missing_path)
      end
    end

    it "raises HwaroError(HWARO_E_CONFIG) for malformed TOML" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "config.toml")
        File.write(path, "this = = broken\n")
        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::Models::Config.load(path)
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        err.exit_code.should eq(Hwaro::Errors::EXIT_CONFIG)
        (err.message || "").should contain(path)
        (err.message || "").downcase.should contain("invalid toml")
      end
    end

    it "raises HwaroError(HWARO_E_CONFIG) when an env override file has malformed TOML" do
      Dir.mktmpdir do |dir|
        base_path = File.join(dir, "config.toml")
        env_path = File.join(dir, "config.production.toml")
        File.write(base_path, %(title = "Base"))
        File.write(env_path, "this = = broken\n")
        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::Models::Config.load(base_path, env: "production")
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        (err.message || "").should contain(env_path)
      end
    end

    it "raises HwaroError(HWARO_E_CONFIG) for an invalid base_url in config.toml" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "config.toml")
        File.write(path, %(base_url = "not a valid url"))
        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::Models::Config.load(path)
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        err.exit_code.should eq(Hwaro::Errors::EXIT_CONFIG)
        (err.message || "").should contain("Invalid base_url")
      end
    end

    it "raises HwaroError(HWARO_E_CONFIG) for a base_url with no scheme" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "config.toml")
        File.write(path, %(base_url = "example.com"))
        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::Models::Config.load(path)
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      end
    end
  end

  describe ".validate_base_url!" do
    it "accepts the empty string (default — no base URL)" do
      Hwaro::Models::Config.validate_base_url!("")
    end

    it "accepts http(s) URLs with host" do
      [
        "http://example.com",
        "https://example.com",
        "https://example.com/subpath",
        "https://example.com/deep/subpath/",
        "http://localhost:3000",
        "http://127.0.0.1:8080",
      ].each do |value|
        Hwaro::Models::Config.validate_base_url!(value)
      end
    end

    it "rejects values without a scheme" do
      expect_raises(ArgumentError, /Invalid base_url/) do
        Hwaro::Models::Config.validate_base_url!("example.com")
      end
      expect_raises(ArgumentError, /Invalid base_url/) do
        Hwaro::Models::Config.validate_base_url!("/subpath")
      end
    end

    it "rejects a base_url carrying a query string or fragment" do
      # base_path drops query/fragment, so the raw base_url and derived base_path
      # would silently disagree and corrupt absolute links.
      expect_raises(ArgumentError, /query string or fragment/) do
        Hwaro::Models::Config.validate_base_url!("https://x.com/repo?utm=1")
      end
      expect_raises(ArgumentError, /query string or fragment/) do
        Hwaro::Models::Config.validate_base_url!("https://x.com/repo#section")
      end
    end

    it "rejects non-http schemes" do
      expect_raises(ArgumentError, /Invalid base_url/) do
        Hwaro::Models::Config.validate_base_url!("ftp://example.com")
      end
      expect_raises(ArgumentError, /Invalid base_url/) do
        Hwaro::Models::Config.validate_base_url!("file:///local/path")
      end
    end

    it "rejects garbage strings" do
      expect_raises(ArgumentError, /Invalid base_url/) do
        Hwaro::Models::Config.validate_base_url!("not a valid url")
      end
    end
  end

  describe "#base_url= normalization" do
    # A trailing slash makes `{{ base_url }}/path` templates and canonical/og
    # URLs emit `//`; the setter strips it so config.toml and --base-url agree.
    it "strips a trailing slash on assignment" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com/"
      config.base_url.should eq("https://example.com")
      config.base_url_stripped.should eq("https://example.com")
    end

    it "strips a trailing slash from a subpath base_url" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com/sub/"
      config.base_url.should eq("https://example.com/sub")
    end

    it "leaves a slash-free base_url unchanged" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com/sub"
      config.base_url.should eq("https://example.com/sub")
    end
  end

  describe "#base_path" do
    it "returns the path component for a subpath deployment" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com/myblog/"
      config.base_path.should eq("/myblog")
    end

    it "returns a nested path component" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com/a/b"
      config.base_path.should eq("/a/b")
    end

    it "returns an empty string for a domain-root base_url" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.base_path.should eq("")
    end

    it "returns an empty string for an empty base_url" do
      config = Hwaro::Models::Config.new
      config.base_url = ""
      config.base_path.should eq("")
    end

    it "recomputes after base_url is reassigned" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com/one"
      config.base_path.should eq("/one")
      config.base_url = "https://example.com/two"
      config.base_path.should eq("/two")
    end

    it "returns an empty string when the URI parse path is just \"/\"" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com/"
      config.base_path.should eq("")
    end

    it "returns an empty string for a malformed base_url (URI::Error rescue)" do
      config = Hwaro::Models::Config.new
      # A bracketed host with no closing bracket is not a parseable URI; the
      # rescue must swallow URI::Error and fall back to "".
      config.base_url = "http://[::1"
      config.base_path.should eq("")
    end
  end

  describe "#with_base_path" do
    it "prefixes a root-relative path under a subpath deployment" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://x.com/repo"
      config.with_base_path("/posts/a/").should eq("/repo/posts/a/")
    end

    it "leaves protocol-relative URLs untouched" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://x.com/repo"
      # Without the // guard this would become /repo//cdn.example.com/x.
      config.with_base_path("//cdn.example.com/x").should eq("//cdn.example.com/x")
    end

    it "leaves absolute http(s) URLs untouched" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://x.com/repo"
      config.with_base_path("http://y.com/z").should eq("http://y.com/z")
      config.with_base_path("https://y.com/z").should eq("https://y.com/z")
    end

    it "leaves a non-leading-slash path unchanged" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://x.com/repo"
      config.with_base_path("posts/a/").should eq("posts/a/")
    end

    it "is a no-op when base_path is empty (domain-root deploy)" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://x.com"
      config.with_base_path("/posts/").should eq("/posts/")
    end
  end

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
  # Environment-specific configuration override
  # ---------------------------------------------------------------------------

  describe "environment-specific config override" do
    it "merges env config on top of base config" do
      Dir.cd(Dir.tempdir) do
        File.write("config.toml", <<-TOML)
          title = "My Site"
          base_url = "http://localhost"
          description = "Base desc"
          TOML

        File.write("config.production.toml", <<-TOML)
          base_url = "https://example.com"
          TOML

        config = Hwaro::Models::Config.load("config.toml", env: "production")
        config.title.should eq("My Site")
        config.base_url.should eq("https://example.com")
        config.description.should eq("Base desc")
      end
    end

    it "deep-merges nested sections" do
      Dir.cd(Dir.tempdir) do
        File.write("config.toml", <<-TOML)
          title = "My Site"
          [sitemap]
          enabled = true
          changefreq = "weekly"
          TOML

        File.write("config.staging.toml", <<-TOML)
          [sitemap]
          changefreq = "daily"
          TOML

        config = Hwaro::Models::Config.load("config.toml", env: "staging")
        config.sitemap.enabled.should be_true
        config.sitemap.changefreq.should eq("daily")
      end
    end

    it "loads without error when env config file does not exist" do
      Dir.cd(Dir.tempdir) do
        File.write("config.toml", %(title = "Test"))
        config = Hwaro::Models::Config.load("config.toml", env: "nonexistent")
        config.title.should eq("Test")
      end
    end

    it "warns with both the env name and the missing path when the override is absent" do
      # Missing-override is the most common way to ship a localhost build to
      # production by accident (typo `--env prdo`, file uncommitted). The
      # message must name *both* the requested env and the path we looked at,
      # so the user can pick the right fix (rename the file vs. fix the flag).
      Dir.cd(Dir.tempdir) do
        File.write("config.toml", %(title = "Test"))
        captured = IO::Memory.new
        original_io = Hwaro::Logger.io
        Hwaro::Logger.io = captured
        begin
          Hwaro::Models::Config.load("config.toml", env: "prdo")
        ensure
          Hwaro::Logger.io = original_io
        end
        output = captured.to_s
        output.should contain("--env prdo")
        output.should contain("config.prdo.toml")
        output.should contain("base config.toml")
      end
    end

    it "loads normally when env is nil" do
      Dir.cd(Dir.tempdir) do
        File.write("config.toml", %(title = "No Env"))
        config = Hwaro::Models::Config.load("config.toml", env: nil)
        config.title.should eq("No Env")
      end
    end

    it "supports env var substitution in env config file" do
      ENV["HWARO_PROD_URL"] = "https://prod.example.com"
      Dir.cd(Dir.tempdir) do
        File.write("config.toml", %(base_url = "http://localhost"))
        File.write("config.production.toml", %(base_url = "${HWARO_PROD_URL}"))

        config = Hwaro::Models::Config.load("config.toml", env: "production")
        config.base_url.should eq("https://prod.example.com")
      end
    ensure
      ENV.delete("HWARO_PROD_URL")
    end
  end

  # ---------------------------------------------------------------------------
  # Environment variable substitution
  # ---------------------------------------------------------------------------

  describe "environment variable substitution" do
    it "substitutes ${VAR} in config values" do
      ENV["HWARO_CFG_URL"] = "https://mysite.com"
      config = load_config(%(base_url = "${HWARO_CFG_URL}"))
      config.base_url.should eq("https://mysite.com")
    ensure
      ENV.delete("HWARO_CFG_URL")
    end

    it "substitutes bare $VAR in config values" do
      ENV["HWARO_CFG_TITLE"] = "Env Title"
      config = load_config(%(title = "$HWARO_CFG_TITLE"))
      config.title.should eq("Env Title")
    ensure
      ENV.delete("HWARO_CFG_TITLE")
    end

    it "uses default value when env var is unset" do
      ENV.delete("HWARO_CFG_MISS")
      config = load_config(%(base_url = "${HWARO_CFG_MISS:-https://fallback.com}"))
      config.base_url.should eq("https://fallback.com")
    end

    it "keeps original text for missing vars without defaults" do
      ENV.delete("HWARO_CFG_MISS2")
      config = load_config(%(title = "${HWARO_CFG_MISS2}"))
      config.title.should eq("${HWARO_CFG_MISS2}")
    end
  end

  # ---------------------------------------------------------------------------
  # Sitemap
  # ---------------------------------------------------------------------------

  describe "sitemap configuration" do
    it "has default sitemap configuration" do
      config = Hwaro::Models::Config.new
      config.sitemap.enabled.should be_false
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
      config.robots.enabled.should be_true
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
      config.llms.enabled.should be_true
      config.llms.filename.should eq("llms.txt")
      config.llms.instructions.should eq("")
      config.llms.full_enabled.should be_false
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
      config.feeds.enabled.should be_false
      config.feeds.filename.should eq("")
      config.feeds.type.should eq("rss")
      config.feeds.truncate.should eq(0)
      config.feeds.limit.should eq(10)
      config.feeds.sections.should eq([] of String)
      config.feeds.default_language_only.should be_true
    end

    it "can update feeds settings" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "atom"
      config.feeds.truncate = 200
      config.feeds.limit = 50
      config.feeds.sections = ["blog", "news"]
      config.feeds.default_language_only = false

      config.feeds.enabled.should be_true
      config.feeds.type.should eq("atom")
      config.feeds.truncate.should eq(200)
      config.feeds.limit.should eq(50)
      config.feeds.sections.should eq(["blog", "news"])
      config.feeds.default_language_only.should be_false
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
        default_language_only = false
        TOML

      config.feeds.enabled.should be_true
      config.feeds.filename.should eq("feed.xml")
      config.feeds.type.should eq("atom")
      config.feeds.truncate.should eq(100)
      config.feeds.limit.should eq(25)
      config.feeds.sections.should eq(["blog", "news"])
      config.feeds.default_language_only.should be_false
    end

    it "loads default_language_only as true from TOML" do
      config = load_config(<<-TOML)
        title = "Test"

        [feeds]
        enabled = true
        default_language_only = true
        TOML

      config.feeds.default_language_only.should be_true
    end

    it "defaults default_language_only to true when not specified in TOML" do
      config = load_config(<<-TOML)
        title = "Test"

        [feeds]
        enabled = true
        TOML

      config.feeds.default_language_only.should be_true
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
      config.search.enabled.should be_false
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
  # `hwaro new` content scaffold defaults
  # ---------------------------------------------------------------------------

  describe "content.new configuration" do
    it "defaults to TOML front matter with a description field" do
      config = Hwaro::Models::Config.new
      config.content_new.front_matter_format.should eq("toml")
      config.content_new.default_fields.should eq(["description"])
      config.content_new.toml?.should be_true
    end

    it "loads front_matter_format and default_fields from [content.new]" do
      config = load_config(<<-TOML)
        [content.new]
        front_matter_format = "yaml"
        default_fields = ["description", "summary"]
        TOML

      config.content_new.front_matter_format.should eq("yaml")
      config.content_new.default_fields.should eq(["description", "summary"])
      config.content_new.toml?.should be_false
    end

    it "accepts flat keys on [content] as a shorthand" do
      config = load_config(<<-TOML)
        [content]
        front_matter_format = "YAML"
        TOML

      # Case-insensitive normalization keeps configs tolerant of casing.
      config.content_new.front_matter_format.should eq("yaml")
    end

    it "accepts 'json' as a front_matter_format value" do
      config = load_config(<<-TOML)
        [content.new]
        front_matter_format = "json"
        TOML

      config.content_new.front_matter_format.should eq("json")
      config.content_new.json?.should be_true
      config.content_new.toml?.should be_false
    end

    it "keeps the default format when the configured value is unknown" do
      config = load_config(<<-TOML)
        [content.new]
        front_matter_format = "xml"
        TOML

      config.content_new.front_matter_format.should eq("toml")
    end

    it "filters built-in fields out of extra_fields" do
      config = Hwaro::Models::Config.new
      config.content_new.default_fields = ["title", "description", "date", "author"]
      config.content_new.extra_fields.should eq(["description", "author"])
    end

    it "defaults bundle to false and loads it from [content.new]" do
      Hwaro::Models::Config.new.content_new.bundle.should be_false

      config = load_config(<<-TOML)
        [content.new]
        bundle = true
        TOML
      config.content_new.bundle.should be_true
    end
  end

  # ---------------------------------------------------------------------------
  # Pagination
  # ---------------------------------------------------------------------------

  describe "pagination configuration" do
    it "has default pagination configuration" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled.should be_false
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
      config.highlight.enabled.should be_true
      config.highlight.theme.should eq("github")
      config.highlight.use_cdn.should be_true
      config.highlight.line_numbers.should be_false
      config.highlight.mode.should eq("server")
      config.highlight.copy.should be_false
    end

    it "can update highlight settings" do
      config = Hwaro::Models::Config.new
      config.highlight.enabled = false
      config.highlight.theme = "monokai"
      config.highlight.use_cdn = false
      config.highlight.line_numbers = true

      config.highlight.enabled.should be_false
      config.highlight.theme.should eq("monokai")
      config.highlight.use_cdn.should be_false
      config.highlight.line_numbers.should be_true
    end

    it "loads all highlight settings from TOML" do
      config = load_config(<<-TOML)
        title = "Test"

        [highlight]
        enabled = true
        theme = "dracula"
        use_cdn = true
        line_numbers = true
        TOML

      config.highlight.enabled.should be_true
      config.highlight.theme.should eq("dracula")
      config.highlight.use_cdn.should be_true
      config.highlight.line_numbers.should be_true
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

    it "defaults line_numbers to false when omitted from TOML" do
      config = load_config(<<-TOML)
        title = "Test"

        [highlight]
        enabled = true
        TOML

      config.highlight.line_numbers.should be_false
    end

    it "loads highlight copy = true from TOML (overrides default false)" do
      config = load_config(<<-TOML)
        title = "Test"

        [highlight]
        copy = true
        TOML

      config.highlight.copy.should be_true
    end

    it "loads highlight mode = \"client\" from TOML (overrides default server)" do
      config = load_config(<<-TOML)
        title = "Test"

        [highlight]
        mode = "client"
        TOML

      config.highlight.mode.should eq("client")
    end

    it "keeps the server default on an unknown highlight mode" do
      config = load_config(<<-TOML)
        title = "Test"

        [highlight]
        mode = "browser"
        TOML

      config.highlight.mode.should eq("server")
    end
  end

  # ---------------------------------------------------------------------------
  # Auto includes
  # ---------------------------------------------------------------------------

  describe "auto_includes configuration" do
    it "has default auto_includes configuration" do
      config = Hwaro::Models::Config.new
      config.auto_includes.enabled.should be_false
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

    it "defaults sorting to date / not reversed / name-ordered terms" do
      tax = Hwaro::Models::TaxonomyConfig.new("tags")
      tax.sort_by.should eq("date")
      tax.reverse.should be_false
      tax.terms_sort_by.should eq("name")
    end

    it "loads taxonomy sort_by / reverse / terms_sort_by from TOML" do
      config = load_config(<<-TOML)
        title = "Test"

        [[taxonomies]]
        name = "tags"
        sort_by = "title"
        reverse = true
        terms_sort_by = "count"
        TOML

      config.taxonomies[0].sort_by.should eq("title")
      config.taxonomies[0].reverse.should be_true
      config.taxonomies[0].terms_sort_by.should eq("count")
    end

    it "warns and keeps the defaults on invalid sort_by / terms_sort_by values" do
      config = load_config(<<-TOML)
        title = "Test"

        [[taxonomies]]
        name = "tags"
        sort_by = "popularity"
        terms_sort_by = "size"
        TOML

      config.taxonomies[0].sort_by.should eq("date")
      config.taxonomies[0].terms_sort_by.should eq("name")
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
  # Serve (dev server) configuration
  # ---------------------------------------------------------------------------

  describe "serve configuration" do
    it "has default (empty) serve headers" do
      config = Hwaro::Models::Config.new
      config.serve.headers.should eq({} of String => String)
    end

    it "loads custom serve headers from TOML" do
      config = load_config(<<-TOML)
        title = "Test"
        base_url = "http://localhost"

        [serve.headers]
        X-Frame-Options = "SAMEORIGIN"
        X-Content-Type-Options = "nosniff"
        Referrer-Policy = "strict-origin-when-cross-origin"
        TOML

      config.serve.headers["X-Frame-Options"].should eq("SAMEORIGIN")
      config.serve.headers["X-Content-Type-Options"].should eq("nosniff")
      config.serve.headers.size.should eq(3)
    end

    it "ignores non-string values and dangerous header names (colon)" do
      config = load_config(<<-TOML)
        title = "Test"
        base_url = "http://localhost"

        [serve.headers]
        "Good-Header" = "safe-value"
        "Bad:Name" = "x"
        ignored = 123
        also_ignored = ["array", "not", "string"]
        TOML

      config.serve.headers.has_key?("Good-Header").should be_true
      config.serve.headers.has_key?("Bad:Name").should be_false
      config.serve.headers.size.should eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Markdown
  # ---------------------------------------------------------------------------

  describe "markdown configuration" do
    it "has default markdown configuration" do
      config = Hwaro::Models::Config.new
      config.markdown.safe.should be_false
      config.markdown.lazy_loading.should be_false
      config.markdown.emoji.should be_false
    end

    it "can update markdown settings" do
      config = Hwaro::Models::Config.new
      config.markdown.safe = true
      config.markdown.lazy_loading = true
      config.markdown.emoji = true

      config.markdown.safe.should be_true
      config.markdown.lazy_loading.should be_true
      config.markdown.emoji.should be_true
    end

    it "loads all markdown settings from TOML" do
      config = load_config(<<-TOML)
        title = "Test"

        [markdown]
        safe = true
        lazy_loading = true
        emoji = true
        TOML

      config.markdown.safe.should be_true
      config.markdown.lazy_loading.should be_true
      config.markdown.emoji.should be_true
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

    it "loads markdown emoji = false from TOML" do
      config = load_config(<<-TOML)
        title = "Test"

        [markdown]
        emoji = false
        TOML

      config.markdown.emoji.should be_false
    end

    it "loads markdown emoji = true from TOML (overrides default false)" do
      config = load_config(<<-TOML)
        title = "Test"

        [markdown]
        emoji = true
        TOML

      config.markdown.emoji.should be_true
    end
  end

  describe "markdown configuration — F10/F9 inline markup flags" do
    it "defaults ins/mark/sub/sup/attributes to false" do
      config = Hwaro::Models::Config.new
      config.markdown.ins.should be_false
      config.markdown.mark.should be_false
      config.markdown.sub.should be_false
      config.markdown.sup.should be_false
      config.markdown.attributes.should be_false
    end

    it "loads ins/mark/sub/sup/attributes from TOML" do
      config = load_config(<<-TOML)
        title = "Test"

        [markdown]
        ins = true
        mark = true
        sub = true
        sup = true
        attributes = true
        TOML

      config.markdown.ins.should be_true
      config.markdown.mark.should be_true
      config.markdown.sub.should be_true
      config.markdown.sup.should be_true
      config.markdown.attributes.should be_true
    end

    it "keeps ins/mark/sub/sup/attributes false when the [markdown] table omits them" do
      config = load_config(<<-TOML)
        title = "Test"

        [markdown]
        safe = true
        TOML

      config.markdown.ins.should be_false
      config.markdown.mark.should be_false
      config.markdown.sub.should be_false
      config.markdown.sup.should be_false
      config.markdown.attributes.should be_false
    end

    it "changes cache_fingerprint when any one of the five new flags flips" do
      base_fp = Hwaro::Models::MarkdownConfig.new.cache_fingerprint

      ins_only = Hwaro::Models::MarkdownConfig.new
      ins_only.ins = true
      ins_only.cache_fingerprint.should_not eq(base_fp)

      mark_only = Hwaro::Models::MarkdownConfig.new
      mark_only.mark = true
      mark_only.cache_fingerprint.should_not eq(base_fp)

      sub_only = Hwaro::Models::MarkdownConfig.new
      sub_only.sub = true
      sub_only.cache_fingerprint.should_not eq(base_fp)

      sup_only = Hwaro::Models::MarkdownConfig.new
      sup_only.sup = true
      sup_only.cache_fingerprint.should_not eq(base_fp)

      attributes_only = Hwaro::Models::MarkdownConfig.new
      attributes_only.attributes = true
      attributes_only.cache_fingerprint.should_not eq(base_fp)
    end

    it "loads insert_anchor_links and rejects unknown values" do
      config = load_config(<<-TOML)
        [markdown]
        insert_anchor_links = "right"
        TOML
      config.markdown.insert_anchor_links.should eq("right")

      config = load_config(<<-TOML)
        [markdown]
        insert_anchor_links = "heading"
        TOML
      config.markdown.insert_anchor_links.should eq("none")

      base_fp = Hwaro::Models::MarkdownConfig.new.cache_fingerprint
      right = Hwaro::Models::MarkdownConfig.new
      right.insert_anchor_links = "right"
      right.cache_fingerprint.should_not eq(base_fp)
    end

    it "loads smart_punctuation and includes it in cache_fingerprint" do
      base_fp = Hwaro::Models::MarkdownConfig.new.cache_fingerprint

      smart_only = Hwaro::Models::MarkdownConfig.new
      smart_only.smart_punctuation = true
      smart_only.cache_fingerprint.should_not eq(base_fp)

      config = load_config(<<-TOML)
        [markdown]
        smart_punctuation = true
        TOML
      config.markdown.smart_punctuation.should be_true
      Hwaro::Models::MarkdownConfig.new.smart_punctuation.should be_false
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

    it "inherits the global taxonomy set when a language omits the taxonomies key" do
      # A `[languages.<code>]` block without a `taxonomies` key must inherit the
      # full global `[[taxonomies]]` set, not the hardcoded `["tags",
      # "categories"]` default — otherwise a third taxonomy (e.g. `authors`)
      # silently vanishes from that language's output (a regression for the
      # default language served at the root).
      config = load_config(<<-TOML)
        title = "Test"
        default_language = "en"

        [[taxonomies]]
        name = "tags"
        [[taxonomies]]
        name = "categories"
        [[taxonomies]]
        name = "authors"

        [languages.en]
        language_name = "English"

        [languages.ko]
        language_name = "한국어"
        taxonomies = ["tags"]
        TOML

      # Omitted key → inherit every global taxonomy.
      config.languages["en"].taxonomies.should eq(["tags", "categories", "authors"])
      # Explicit key → honored verbatim (narrowing is still possible).
      config.languages["ko"].taxonomies.should eq(["tags"])
    end

    it "honors an explicit empty taxonomies list (no inheritance)" do
      config = load_config(<<-TOML)
        title = "Test"

        [[taxonomies]]
        name = "tags"

        [languages.ko]
        language_name = "한국어"
        taxonomies = []
        TOML

      # Explicit `[]` means "no taxonomies", distinct from an omitted key.
      config.languages["ko"].taxonomies.should eq([] of String)
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

    it "strips surrounding slashes from both source keys and targets" do
      config = load_config(<<-TOML)
        title = "Test"

        [permalinks]
        "/posts" = "/blog/"
        TOML

      # The slash-free key matches the slash-free directory path, and the
      # slash-free target avoids double-slash URLs (http://host//blog//p/).
      config.permalinks.has_key?("/posts").should be_false
      config.permalinks["posts"].should eq("blog")
    end

    it "preserves the interior of token patterns and only trims outer slashes" do
      config = load_config(<<-TOML)
        title = "Test"

        [permalinks]
        "posts" = "/:year/:month/:day/:slug/"
        TOML

      config.permalinks["posts"].should eq(":year/:month/:day/:slug")
    end

    it "raises a classified config error for a pattern with an unknown token" do
      ex = expect_raises(Hwaro::HwaroError, /Unknown token ':tokne'/) do
        load_config(<<-TOML)
          title = "Test"

          [permalinks]
          "posts" = "/:year/:tokne/"
          TOML
      end
      ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
    end
  end

  # ---------------------------------------------------------------------------
  # Links
  # ---------------------------------------------------------------------------

  describe "links configuration" do
    it "defaults broken_internal to warn" do
      config = Hwaro::Models::Config.new
      config.links.broken_internal.should eq("warn")
    end

    it "loads broken_internal = error" do
      config = load_config(<<-TOML)
        title = "Test"

        [links]
        broken_internal = "error"
        TOML

      config.links.broken_internal.should eq("error")
    end

    it "keeps the warn default for an unknown broken_internal value" do
      config = load_config(<<-TOML)
        title = "Test"

        [links]
        broken_internal = "explode"
        TOML

      config.links.broken_internal.should eq("warn")
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

    # Regression for gh#529: `path = "..."` is the obvious shape for
    # the local-filesystem case (Hugo / Jekyll users try it first).
    # Treat it as an alias for `url`.
    it "accepts `path = \"...\"` as an alias for `url` on a deployment target (gh#529)" do
      config = load_config(<<-TOML)
        title = "Test"

        [[deployment.targets]]
        name = "local"
        path = "/tmp/site-out"
        TOML

      config.deployment.targets.size.should eq(1)
      config.deployment.targets[0].name.should eq("local")
      config.deployment.targets[0].url.should eq("/tmp/site-out")
    end

    it "prefers `url` over `path` when both are set (gh#529)" do
      config = load_config(<<-TOML)
        title = "Test"

        [[deployment.targets]]
        name = "local"
        url = "s3://primary"
        path = "/tmp/fallback"
        TOML

      config.deployment.targets[0].url.should eq("s3://primary")
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
      #   feeds.enabled                false -> true (identity: false)
      #   feeds.default_language_only  true  -> true (identity: true)
      #   feeds.default_language_only  true  -> false
      #   search.enabled               false -> true
      #   pagination.enabled           false -> true
      #   highlight.enabled            true  -> false
      #   highlight.use_cdn            true  -> false
      #   auto_includes.enabled        false -> true
      #   markdown.safe                false -> true
      #   markdown.lazy_loading        false -> true
      #   markdown.emoji               false -> true
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
        default_language_only = false

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
        emoji = true

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
      config.feeds.default_language_only.should be_false
      config.search.enabled.should be_true
      config.pagination.enabled.should be_true
      config.highlight.enabled.should be_false
      config.highlight.use_cdn.should be_false
      config.auto_includes.enabled.should be_true
      config.markdown.safe.should be_true
      config.markdown.lazy_loading.should be_true
      config.markdown.emoji.should be_true
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
        default_language_only = true

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
        emoji = false

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
      config.feeds.default_language_only.should be_true
      config.search.enabled.should be_false
      config.pagination.enabled.should be_false
      config.highlight.enabled.should be_true
      config.highlight.use_cdn.should be_true
      config.auto_includes.enabled.should be_false
      config.markdown.safe.should be_false
      config.markdown.lazy_loading.should be_false
      config.markdown.emoji.should be_false
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
      config.sitemap.enabled.should be_false       # default: false
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
      config.markdown.emoji.should be_false        # default: false
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
    config.enabled.should be_false
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
    config.enabled.should be_true
    config.filename.should eq("robots.txt")
    config.rules.should eq([] of Hwaro::Models::RobotsRule)
  end
end

describe Hwaro::Models::LlmsConfig do
  it "has default values" do
    config = Hwaro::Models::LlmsConfig.new
    config.enabled.should be_true
    config.filename.should eq("llms.txt")
    config.instructions.should eq("")
    config.full_enabled.should be_false
    config.full_filename.should eq("llms-full.txt")
  end
end

describe Hwaro::Models::SearchConfig do
  it "has default values" do
    config = Hwaro::Models::SearchConfig.new
    config.enabled.should be_false
    config.format.should eq("fuse_json")
    config.fields.should eq(["title", "content"])
    config.filename.should eq("search.json")
  end
end

describe Hwaro::Models::FeedConfig do
  it "has default values" do
    config = Hwaro::Models::FeedConfig.new
    config.enabled.should be_false
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
    config.enabled.should be_false
    config.per_page.should eq(10)
  end
end

describe Hwaro::Models::HighlightConfig do
  it "has default values" do
    config = Hwaro::Models::HighlightConfig.new
    config.enabled.should be_true
    config.theme.should eq("github")
    config.use_cdn.should be_true
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
    it "returns empty string in the default server mode" do
      config = Hwaro::Models::HighlightConfig.new
      config.js_tag.should eq("")
    end

    it "returns CDN script when use_cdn is true (client mode)" do
      config = Hwaro::Models::HighlightConfig.new
      config.mode = "client"
      config.js_tag.should contain("cdnjs.cloudflare.com")
      config.js_tag.should contain("highlight.min.js")
    end
  end

  describe "tags" do
    it "returns both CSS and JS tags in client mode" do
      config = Hwaro::Models::HighlightConfig.new
      config.mode = "client"
      config.tags.should contain("stylesheet")
      config.tags.should contain("highlight.min.js")
    end
  end
end

describe Hwaro::Models::TaxonomyConfig do
  it "has default values" do
    config = Hwaro::Models::TaxonomyConfig.new("tags")
    config.name.should eq("tags")
    config.feed.should be_false
    config.sitemap.should be_true
    config.paginate_by.should be_nil
    config.sort_by.should eq("date")
    config.reverse.should be_false
    config.terms_sort_by.should eq("name")
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
    config.safe.should be_false
    config.lazy_loading.should be_false
    config.emoji.should be_false
  end

  describe "#math_tags" do
    # The markdown processor emits `\(…\)`/`\[…\]` with `class="math math-*"`
    # but doesn't load the renderer. Setting `math = true` must also inject
    # the right CDN script tags so the feature actually works in the
    # browser — otherwise users see literal TeX source.
    it "returns empty string when math is disabled" do
      Hwaro::Models::MarkdownConfig.new.math_tags.should be_empty
    end

    it "emits KaTeX auto-render scripts when math = true (default engine)" do
      config = Hwaro::Models::MarkdownConfig.new
      config.math = true
      tags = config.math_tags
      tags.should contain("katex.min.css")
      tags.should contain("katex.min.js")
      tags.should contain("auto-render.min.js")
      tags.should contain("renderMathInElement")
    end

    it "emits MathJax tags when math_engine = mathjax" do
      config = Hwaro::Models::MarkdownConfig.new
      config.math = true
      config.math_engine = "mathjax"
      tags = config.math_tags
      tags.should contain("mathjax")
      tags.should contain("inlineMath")
      tags.should_not contain("katex")
    end

    it "stays silent for an unknown math_engine instead of guessing" do
      # A typo in `math_engine` shouldn't silently load a wrong renderer.
      # Doctor already validates this on config load; this guards the
      # rendering path so a misconfigured site fails closed.
      config = Hwaro::Models::MarkdownConfig.new
      config.math = true
      config.math_engine = "asciimath"
      config.math_tags.should be_empty
    end
  end

  describe "#mermaid_tags" do
    it "returns empty string when mermaid is disabled" do
      Hwaro::Models::MarkdownConfig.new.mermaid_tags.should be_empty
    end

    it "emits a Mermaid.js ESM import when mermaid = true" do
      config = Hwaro::Models::MarkdownConfig.new
      config.mermaid = true
      tags = config.mermaid_tags
      tags.should contain("mermaid")
      tags.should contain("mermaid.initialize")
      tags.should contain("startOnLoad")
    end
  end
end

describe Hwaro::Models::LanguageConfig do
  it "has default values" do
    config = Hwaro::Models::LanguageConfig.new("en")
    config.code.should eq("en")
    config.language_name.should eq("en")
    config.weight.should eq(1)
    config.generate_feed.should be_true
    config.build_search_index.should be_true
    config.taxonomies.should eq(["tags", "categories"])
  end
end

describe Hwaro::Models::AutoIncludesConfig do
  it "has default values" do
    config = Hwaro::Models::AutoIncludesConfig.new
    config.enabled.should be_false
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

private def config_with(permalinks : Hash(String, String)) : Hwaro::Models::Config
  config = Hwaro::Models::Config.new
  config.permalinks = permalinks
  config
end

describe "Hwaro::Models::Config#resolve_permalink_dir" do
  it "returns the directory unchanged when no rules are configured" do
    config_with({} of String => String).resolve_permalink_dir("blog/posts").should eq("blog/posts")
  end

  it "returns the directory unchanged when no rule matches" do
    config_with({"old/posts" => "posts"}).resolve_permalink_dir("blog").should eq("blog")
  end

  it "remaps an exact directory match to the target" do
    config_with({"old/posts" => "posts"}).resolve_permalink_dir("old/posts").should eq("posts")
  end

  it "remaps an exact match with an empty target to the root" do
    config_with({"pages" => ""}).resolve_permalink_dir("pages").should eq("")
  end

  it "remaps a nested subdirectory and preserves the deeper path" do
    config_with({"old/posts" => "archive"}).resolve_permalink_dir("old/posts/2024").should eq("archive/2024")
  end

  it "maps a nested subdirectory to the root without a leading slash for an empty target" do
    config_with({"pages" => ""}).resolve_permalink_dir("pages/contact").should eq("contact")
  end

  it "honors the first matching rule" do
    permalinks = {
      "2023/drafts" => "archive/2023",
      "old/posts"   => "posts",
    }
    config_with(permalinks).resolve_permalink_dir("2023/drafts/wip").should eq("archive/2023/wip")
  end

  it "matches the source literally rather than as a regular expression" do
    config_with({"a.b" => "x"}).resolve_permalink_dir("a.b/c").should eq("x/c")
    config_with({"a.b" => "x"}).resolve_permalink_dir("axb/c").should eq("axb/c")
  end

  describe "related config" do
    it "clamps a negative limit to zero" do
      # A negative limit reaches Array#first(limit) in the incremental
      # related-posts rebuild and raises "Negative count"; clamp at the source.
      config = load_config(<<-TOML)
        [related]
        enabled = true
        limit = -1
        TOML
      config.related.limit.should eq(0)
    end

    it "keeps a valid positive limit" do
      config = load_config(<<-TOML)
        [related]
        enabled = true
        limit = 7
        TOML
      config.related.limit.should eq(7)
    end
  end

  describe "config value hardening" do
    it "does not crash on a malformed glob in [static] exclude" do
      config = load_config(<<-TOML)
        [static]
        exclude = ["[bad"]
        TOML
      # File.match? raises File::BadPatternError on the bad glob; excluded? must
      # treat it as non-matching instead of aborting the whole build.
      config.static.excluded?("foo/bar.txt").should be_false
    end

    it "keeps [sitemap] priority raw at load (doctor warns; the emitter clamps)" do
      # The loaded value is preserved so `hwaro doctor` can detect the
      # out-of-range value; the sitemap emitter clamps it to [0.0, 1.0].
      load_config("[sitemap]\npriority = 5.0").sitemap.priority.should eq(5.0)
    end

    it "clamps [og.auto_image] pattern_scale to a sane range" do
      # An oversized scale overflows Int32 in the pattern renderer; clamp it.
      load_config("[og.auto_image]\npattern_scale = 1e12").og.auto_image.pattern_scale.should eq(10.0)
      load_config("[og.auto_image]\npattern_scale = -3.0").og.auto_image.pattern_scale.should eq(0.1)
    end

    it "falls back to defaults for non-finite [og.auto_image] opacity values" do
      # TOML accepts `nan`/`inf` literals. NaN survives the renderer's
      # clamp(0.0, 1.0) (NaN comparisons are all false) and crashes the
      # pixel blend's `.to_u8` with OverflowError, so the loader must
      # reject non-finite values.
      load_config("[og.auto_image]\npattern_opacity = nan").og.auto_image.pattern_opacity.should eq(0.35)
      load_config("[og.auto_image]\noverlay_opacity = inf").og.auto_image.overlay_opacity.should eq(0.45)
      load_config("[og.auto_image]\ntext_panel = nan").og.auto_image.text_panel.should eq(0.0)
    end

    it "falls back to the default for a non-finite [sitemap] priority" do
      # Unlike the merely out-of-range value above, NaN passes both doctor's
      # range checks and the emitter's clamp, and would emit "NaN" into the XML.
      load_config("[sitemap]\npriority = nan").sitemap.priority.should eq(0.5)
    end

    it "falls back to the default for a wrong-typed numeric value" do
      load_config("[pagination]\nper_page = \"twenty\"").pagination.per_page.should eq(10)
    end

    it "clamps an oversized integer [pagination] per_page to Int32::MAX (int_value)" do
      # 9999999999 > Int32::MAX. int_value uses as_i64?+clamp so this yields a
      # clamped Int32 instead of raising OverflowError out of as_i?/to_i.
      load_config("[pagination]\nper_page = 9999999999").pagination.per_page.should eq(Int32::MAX)
    end

    it "clamps an oversized float [feeds] limit to Int32::MAX (int_value)" do
      load_config("[feeds]\nlimit = 1e30").feeds.limit.should eq(Int32::MAX)
    end

    it "clamps an oversized integer [deployment] max_deletes to Int32::MAX (int_or_nil)" do
      load_config("[deployment]\nmax_deletes = 99999999999").deployment.max_deletes.should eq(Int32::MAX)
    end
  end

  describe "unknown top-level key warnings" do
    it "warns with a did-you-mean suggestion for a typo'd section" do
      log = with_captured_log do
        load_config("[markdonw]\nemoji = true")
      end
      log.should contain("Unknown key 'markdonw'")
      log.should contain("Did you mean 'markdown'?")
    end

    it "warns with a did-you-mean suggestion for a typo'd scalar" do
      log = with_captured_log do
        load_config(%(titel = "My Site"))
      end
      log.should contain("Unknown key 'titel'")
      log.should contain("Did you mean 'title'?")
    end

    it "warns without a suggestion for a key nothing resembles" do
      log = with_captured_log do
        load_config("[zzqxy]\nfoo = 1")
      end
      log.should contain("Unknown key 'zzqxy'")
      log.should_not contain("Did you mean")
    end

    it "does not warn for any known top-level key" do
      toml = String.build do |io|
        io << %(title = "t"\ndescription = "d"\nbase_url = "https://example.com"\ndefault_language = "en"\n)
        (Hwaro::Models::Config::KNOWN_TOP_LEVEL_KEYS -
          %w[title description base_url default_language taxonomies menus outputs languages permalinks]).each do |key|
          io << "[" << key << "]\n"
        end
      end
      log = with_captured_log { load_config(toml) }
      log.should_not contain("Unknown key")
    end

    # Drift guard: every section doctor/config-snippets knows about must be
    # in the loader's known-key list, or a valid section would be flagged.
    it "covers every SECTION_REGISTRY section" do
      Hwaro::Services::ConfigSnippets::SECTION_REGISTRY.each_key do |section|
        Hwaro::Models::Config::KNOWN_TOP_LEVEL_KEYS.includes?(section).should be_true
      end
    end

    # Drift guard: the scaffolded default configs must load without any
    # unknown-key warning — they exercise the full documented key surface.
    it "does not warn on the generated default configs" do
      {
        Hwaro::Services::Defaults::ConfigSamples.config,
        Hwaro::Services::Defaults::ConfigSamples.config_without_taxonomies,
        Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en", "ko"]),
      }.each do |toml|
        log = with_captured_log { load_config(toml) }
        log.should_not contain("Unknown key")
      end
    end
  end
end
