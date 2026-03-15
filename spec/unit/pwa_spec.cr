require "../spec_helper"
require "json"

private def make_site(pwa_toml : String = "") : Hwaro::Models::Site
  config_str = <<-TOML
  title = "Test Site"
  description = "A test site"
  base_url = "https://example.com"
  #{pwa_toml}
  TOML

  File.tempfile("hwaro-pwa", ".toml") do |file|
    file.print(config_str)
    file.flush
    config = Hwaro::Models::Config.load(file.path)
    return Hwaro::Models::Site.new(config)
  end
  raise "unreachable"
end

describe Hwaro::Models::PwaConfig do
  describe "defaults" do
    it "is disabled by default" do
      config = Hwaro::Models::Config.new
      config.pwa.enabled.should be_false
    end

    it "has default theme and display values" do
      config = Hwaro::Models::Config.new
      config.pwa.theme_color.should eq("#ffffff")
      config.pwa.background_color.should eq("#ffffff")
      config.pwa.display.should eq("standalone")
      config.pwa.start_url.should eq("/")
    end
  end

  describe "loading from TOML" do
    it "loads pwa config" do
      site = make_site(<<-TOML)
      [pwa]
      enabled = true
      name = "My PWA"
      short_name = "PWA"
      theme_color = "#333333"
      background_color = "#000000"
      display = "fullscreen"
      icons = ["static/icon-192.png", "static/icon-512.png"]
      TOML

      site.config.pwa.enabled.should be_true
      site.config.pwa.name.should eq("My PWA")
      site.config.pwa.short_name.should eq("PWA")
      site.config.pwa.theme_color.should eq("#333333")
      site.config.pwa.background_color.should eq("#000000")
      site.config.pwa.display.should eq("fullscreen")
      site.config.pwa.icons.size.should eq(2)
    end

    it "loads precache_urls and offline_page" do
      site = make_site(<<-TOML)
      [pwa]
      enabled = true
      offline_page = "/offline.html"
      precache_urls = ["/", "/about/", "/css/main.css"]
      TOML

      site.config.pwa.offline_page.should eq("/offline.html")
      site.config.pwa.precache_urls.size.should eq(3)
    end
  end
end

describe Hwaro::Content::Seo::Pwa do
  describe ".generate" do
    it "does nothing when disabled" do
      Dir.mktmpdir do |dir|
        site = make_site("")
        Hwaro::Content::Seo::Pwa.generate(site, dir)

        File.exists?(File.join(dir, "manifest.json")).should be_false
        File.exists?(File.join(dir, "sw.js")).should be_false
      end
    end

    it "generates manifest.json with correct fields" do
      Dir.mktmpdir do |dir|
        site = make_site(<<-TOML)
        [pwa]
        enabled = true
        name = "My PWA"
        short_name = "PWA"
        theme_color = "#ff0000"
        background_color = "#00ff00"
        display = "standalone"
        icons = ["static/icon-192.png", "static/icon-512.png"]
        TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        manifest_path = File.join(dir, "manifest.json")
        File.exists?(manifest_path).should be_true

        manifest = JSON.parse(File.read(manifest_path))
        manifest["name"].as_s.should eq("My PWA")
        manifest["short_name"].as_s.should eq("PWA")
        manifest["theme_color"].as_s.should eq("#ff0000")
        manifest["background_color"].as_s.should eq("#00ff00")
        manifest["display"].as_s.should eq("standalone")
        manifest["start_url"].as_s.should eq("/")
        manifest["description"].as_s.should eq("A test site")
      end
    end

    it "falls back to site title when name is not set" do
      Dir.mktmpdir do |dir|
        site = make_site(<<-TOML)
        [pwa]
        enabled = true
        TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        manifest = JSON.parse(File.read(File.join(dir, "manifest.json")))
        manifest["name"].as_s.should eq("Test Site")
        manifest["short_name"].as_s.should eq("Test Site")
      end
    end

    it "generates manifest with icon entries" do
      Dir.mktmpdir do |dir|
        site = make_site(<<-TOML)
        [pwa]
        enabled = true
        icons = ["static/icon-192.png", "static/icon-512x512.png"]
        TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        manifest = JSON.parse(File.read(File.join(dir, "manifest.json")))
        icons = manifest["icons"].as_a
        icons.size.should eq(2)
        icons[0]["type"].as_s.should eq("image/png")
        icons[0]["sizes"].as_s.should eq("192x192")
        icons[1]["sizes"].as_s.should eq("512x512")

        # static/ prefix should be stripped from icon src
        icons[0]["src"].as_s.should eq("/icon-192.png")
        icons[1]["src"].as_s.should eq("/icon-512x512.png")
      end
    end

    it "normalizes icon paths with and without static/ prefix" do
      Dir.mktmpdir do |dir|
        site = make_site(<<-TOML)
        [pwa]
        enabled = true
        icons = ["static/icon.png", "/already-absolute.png", "relative.png"]
        TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        manifest = JSON.parse(File.read(File.join(dir, "manifest.json")))
        icons = manifest["icons"].as_a
        icons[0]["src"].as_s.should eq("/icon.png")
        icons[1]["src"].as_s.should eq("/already-absolute.png")
        icons[2]["src"].as_s.should eq("/relative.png")
      end
    end

    it "generates sw.js with build-specific cache version" do
      Dir.mktmpdir do |dir|
        site = make_site(<<-TOML)
        [pwa]
        enabled = true
        TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        content = File.read(File.join(dir, "sw.js"))
        content.should match(/CACHE_NAME = 'hwaro-\d+'/)
        content.should_not contain("hwaro-v1")
      end
    end

    it "generates sw.js" do
      Dir.mktmpdir do |dir|
        site = make_site(<<-TOML)
        [pwa]
        enabled = true
        TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        sw_path = File.join(dir, "sw.js")
        File.exists?(sw_path).should be_true

        content = File.read(sw_path)
        content.should contain("CACHE_NAME")
        content.should contain("addEventListener")
        content.should contain("install")
        content.should contain("fetch")
      end
    end

    it "includes precache_urls in service worker" do
      Dir.mktmpdir do |dir|
        site = make_site(<<-TOML)
        [pwa]
        enabled = true
        precache_urls = ["/css/main.css", "/js/app.js"]
        TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        content = File.read(File.join(dir, "sw.js"))
        content.should contain("/css/main.css")
        content.should contain("/js/app.js")
      end
    end

    it "includes offline_page in service worker" do
      Dir.mktmpdir do |dir|
        site = make_site(<<-TOML)
        [pwa]
        enabled = true
        offline_page = "/offline.html"
        TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        content = File.read(File.join(dir, "sw.js"))
        content.should contain("/offline.html")
      end
    end
  end
end
