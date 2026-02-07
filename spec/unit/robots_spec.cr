require "../spec_helper"

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

    it "generates robots.txt when enabled" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)
        File.exists?(File.join(output_dir, "robots.txt")).should be_true
      end
    end

    it "generates default allow-all rule when no rules are configured" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true
      config.robots.rules = [] of Hwaro::Models::RobotsRule

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        content = File.read(File.join(output_dir, "robots.txt"))
        content.should contain("User-agent: *")
        content.should contain("Allow: /")
      end
    end

    it "generates robots.txt with a single custom rule" do
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

    it "generates robots.txt with multiple rules" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true

      rule1 = Hwaro::Models::RobotsRule.new("*")
      rule1.allow = ["/"]
      rule1.disallow = ["/private/"]

      rule2 = Hwaro::Models::RobotsRule.new("BadBot")
      rule2.allow = [] of String
      rule2.disallow = ["/"]

      config.robots.rules = [rule1, rule2]

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        content = File.read(File.join(output_dir, "robots.txt"))
        content.should contain("User-agent: *")
        content.should contain("Allow: /")
        content.should contain("Disallow: /private/")
        content.should contain("User-agent: BadBot")
        content.should contain("Disallow: /")
      end
    end

    it "includes sitemap URL when sitemap is enabled and base_url is set" do
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

    it "uses custom sitemap filename in Sitemap directive" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true
      config.sitemap.enabled = true
      config.sitemap.filename = "custom-sitemap.xml"
      config.base_url = "https://example.com"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        content = File.read(File.join(output_dir, "robots.txt"))
        content.should contain("Sitemap: https://example.com/custom-sitemap.xml")
      end
    end

    it "does not include sitemap directive when sitemap is disabled" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true
      config.sitemap.enabled = false
      config.base_url = "https://example.com"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        content = File.read(File.join(output_dir, "robots.txt"))
        content.should_not contain("Sitemap:")
      end
    end

    it "does not include sitemap directive when base_url is empty" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true
      config.sitemap.enabled = true
      config.base_url = ""

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        content = File.read(File.join(output_dir, "robots.txt"))
        content.should_not contain("Sitemap:")
      end
    end

    it "strips trailing slash from base_url in sitemap directive" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true
      config.sitemap.enabled = true
      config.base_url = "https://example.com/"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        content = File.read(File.join(output_dir, "robots.txt"))
        content.should contain("Sitemap: https://example.com/sitemap.xml")
        content.should_not contain("Sitemap: https://example.com//sitemap.xml")
      end
    end

    it "generates a rule with only allow directives" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true

      rule = Hwaro::Models::RobotsRule.new("*")
      rule.allow = ["/", "/public/"]
      rule.disallow = [] of String
      config.robots.rules = [rule]

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        content = File.read(File.join(output_dir, "robots.txt"))
        content.should contain("User-agent: *")
        content.should contain("Allow: /")
        content.should contain("Allow: /public/")
        content.should_not contain("Disallow:")
      end
    end

    it "generates a rule with only disallow directives" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true

      rule = Hwaro::Models::RobotsRule.new("*")
      rule.allow = [] of String
      rule.disallow = ["/secret/", "/admin/"]
      config.robots.rules = [rule]

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        content = File.read(File.join(output_dir, "robots.txt"))
        content.should contain("User-agent: *")
        content.should contain("Disallow: /secret/")
        content.should contain("Disallow: /admin/")
        content.should_not contain("Allow:")
      end
    end

    it "uses default robots.txt filename" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)
        File.exists?(File.join(output_dir, "robots.txt")).should be_true
      end
    end

    it "uses custom robots.txt filename" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true
      config.robots.filename = "custom-robots.txt"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)
        File.exists?(File.join(output_dir, "custom-robots.txt")).should be_true
      end
    end

    it "generates complete robots.txt with rules and sitemap" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true
      config.sitemap.enabled = true
      config.base_url = "https://mysite.com"

      rule1 = Hwaro::Models::RobotsRule.new("*")
      rule1.allow = ["/"]
      rule1.disallow = ["/admin/", "/private/"]

      rule2 = Hwaro::Models::RobotsRule.new("GPTBot")
      rule2.allow = [] of String
      rule2.disallow = ["/"]

      config.robots.rules = [rule1, rule2]

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        content = File.read(File.join(output_dir, "robots.txt"))

        # Verify structure and ordering
        content.should contain("User-agent: *")
        content.should contain("Allow: /")
        content.should contain("Disallow: /admin/")
        content.should contain("Disallow: /private/")
        content.should contain("User-agent: GPTBot")
        content.should contain("Sitemap: https://mysite.com/sitemap.xml")

        # Verify Sitemap is at the end
        sitemap_pos = content.index("Sitemap:").not_nil!
        last_disallow_pos = content.rindex("Disallow:").not_nil!
        sitemap_pos.should be > last_disallow_pos
      end
    end

    it "handles a rule with empty allow and disallow lists" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true

      rule = Hwaro::Models::RobotsRule.new("SomeBot")
      rule.allow = [] of String
      rule.disallow = [] of String
      config.robots.rules = [rule]

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        content = File.read(File.join(output_dir, "robots.txt"))
        content.should contain("User-agent: SomeBot")
        content.should_not contain("Allow:")
        content.should_not contain("Disallow:")
      end
    end

    it "separates multiple rules with blank lines" do
      config = Hwaro::Models::Config.new
      config.robots.enabled = true

      rule1 = Hwaro::Models::RobotsRule.new("Googlebot")
      rule1.allow = ["/"]

      rule2 = Hwaro::Models::RobotsRule.new("Bingbot")
      rule2.allow = ["/"]

      config.robots.rules = [rule1, rule2]

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Robots.generate(config, output_dir)

        content = File.read(File.join(output_dir, "robots.txt"))

        # Check that rules are separated by a blank line
        googlebot_idx = content.index("User-agent: Googlebot").not_nil!
        bingbot_idx = content.index("User-agent: Bingbot").not_nil!
        between = content[googlebot_idx..bingbot_idx]
        between.should contain("\n\n")
      end
    end
  end
end

describe Hwaro::Models::RobotsRule do
  describe "#initialize" do
    it "initializes with user_agent" do
      rule = Hwaro::Models::RobotsRule.new("*")
      rule.user_agent.should eq("*")
      rule.allow.should eq([] of String)
      rule.disallow.should eq([] of String)
    end

    it "accepts custom user_agent" do
      rule = Hwaro::Models::RobotsRule.new("Googlebot")
      rule.user_agent.should eq("Googlebot")
    end
  end

  describe "property setters" do
    it "can set user_agent" do
      rule = Hwaro::Models::RobotsRule.new("*")
      rule.user_agent = "Googlebot"
      rule.user_agent.should eq("Googlebot")
    end

    it "can set allow paths" do
      rule = Hwaro::Models::RobotsRule.new("*")
      rule.allow = ["/public/", "/api/"]
      rule.allow.size.should eq(2)
      rule.allow.should contain("/public/")
      rule.allow.should contain("/api/")
    end

    it "can set disallow paths" do
      rule = Hwaro::Models::RobotsRule.new("*")
      rule.disallow = ["/admin/", "/private/", "/secret/"]
      rule.disallow.size.should eq(3)
      rule.disallow.should contain("/admin/")
      rule.disallow.should contain("/private/")
      rule.disallow.should contain("/secret/")
    end

    it "can append to allow paths" do
      rule = Hwaro::Models::RobotsRule.new("*")
      rule.allow << "/public/"
      rule.allow << "/api/"
      rule.allow.size.should eq(2)
    end

    it "can append to disallow paths" do
      rule = Hwaro::Models::RobotsRule.new("*")
      rule.disallow << "/admin/"
      rule.disallow << "/private/"
      rule.disallow.size.should eq(2)
    end
  end
end

describe Hwaro::Models::RobotsConfig do
  describe "#initialize" do
    it "has default values" do
      config = Hwaro::Models::RobotsConfig.new
      config.enabled.should be_true
      config.filename.should eq("robots.txt")
      config.rules.should eq([] of Hwaro::Models::RobotsRule)
    end
  end

  describe "property setters" do
    it "can set enabled" do
      config = Hwaro::Models::RobotsConfig.new
      config.enabled = true
      config.enabled.should be_true
    end

    it "can set filename" do
      config = Hwaro::Models::RobotsConfig.new
      config.filename = "custom-robots.txt"
      config.filename.should eq("custom-robots.txt")
    end

    it "can add rules" do
      config = Hwaro::Models::RobotsConfig.new

      rule = Hwaro::Models::RobotsRule.new("Googlebot")
      rule.allow = ["/"]

      config.rules << rule
      config.rules.size.should eq(1)
      config.rules.first.user_agent.should eq("Googlebot")
    end

    it "can set multiple rules" do
      config = Hwaro::Models::RobotsConfig.new

      rule1 = Hwaro::Models::RobotsRule.new("*")

      rule2 = Hwaro::Models::RobotsRule.new("GPTBot")

      config.rules = [rule1, rule2]
      config.rules.size.should eq(2)
    end
  end
end
