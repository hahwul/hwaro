require "../spec_helper"
require "json"

# Write a minimal valid PNG of the given dimensions. Only the 8-byte
# signature + IHDR chunk matter for `sizes` inference, but we include a
# tiny IDAT/IEND so the file is a structurally valid PNG.
private def write_png(path : String, width : UInt32, height : UInt32)
  io = IO::Memory.new
  io.write(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
  ihdr = IO::Memory.new
  ihdr.write_bytes(width, IO::ByteFormat::BigEndian)
  ihdr.write_bytes(height, IO::ByteFormat::BigEndian)
  ihdr.write(Bytes[8, 6, 0, 0, 0]) # bit depth, color type, compression, filter, interlace
  ihdr_bytes = ihdr.to_slice
  io.write_bytes(ihdr_bytes.size.to_u32, IO::ByteFormat::BigEndian)
  io.write("IHDR".to_slice)
  io.write(ihdr_bytes)
  io.write_bytes(0_u32, IO::ByteFormat::BigEndian) # placeholder CRC (not validated)
  # IEND
  io.write_bytes(0_u32, IO::ByteFormat::BigEndian)
  io.write("IEND".to_slice)
  io.write_bytes(0_u32, IO::ByteFormat::BigEndian)
  File.write(path, io.to_slice)
end

private def make_site(pwa_toml : String = "", base_url : String = "https://example.com") : Hwaro::Models::Site
  config_str = <<-TOML
    title = "Test Site"
    description = "A test site"
    base_url = "#{base_url}"
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

    # `sizes` must reflect the icon's REAL pixel dimensions, read from the
    # PNG IHDR — not guessed from the filename. A 200x60 logo.png whose name
    # carries no size hint used to be declared "512x512".
    it "reads real PNG dimensions for icon sizes instead of guessing from the filename" do
      Dir.mktmpdir do |dir|
        write_png(File.join(dir, "logo.png"), 200_u32, 60_u32)
        site = make_site(<<-TOML)
          [pwa]
          enabled = true
          icons = ["static/logo.png"]
          TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        manifest = JSON.parse(File.read(File.join(dir, "manifest.json")))
        manifest["icons"].as_a[0]["sizes"].as_s.should eq("200x60")
      end
    end

    # Real dimensions win even when the filename contains a misleading number
    # (e.g. a year), which the filename heuristic would have used.
    it "prefers PNG header dimensions over a year-like number in the filename" do
      Dir.mktmpdir do |dir|
        write_png(File.join(dir, "icon-2024.png"), 192_u32, 192_u32)
        site = make_site(<<-TOML)
          [pwa]
          enabled = true
          icons = ["static/icon-2024.png"]
          TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        manifest = JSON.parse(File.read(File.join(dir, "manifest.json")))
        manifest["icons"].as_a[0]["sizes"].as_s.should eq("192x192")
      end
    end

    # When the PNG bytes can't be read (missing output file), fall back to the
    # filename heuristic rather than crashing.
    it "falls back to the filename-derived size when the PNG can't be read" do
      Dir.mktmpdir do |dir|
        # No icon-512.png file written to the output dir.
        site = make_site(<<-TOML)
          [pwa]
          enabled = true
          icons = ["static/icon-512.png"]
          TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        manifest = JSON.parse(File.read(File.join(dir, "manifest.json")))
        manifest["icons"].as_a[0]["sizes"].as_s.should eq("512x512")
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

    it "generates sw.js with a deterministic content-derived cache version" do
      Dir.mktmpdir do |dir|
        site = make_site(<<-TOML)
          [pwa]
          enabled = true
          TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        content = File.read(File.join(dir, "sw.js"))
        # Cache name is a content hash (hex), not a wall-clock timestamp, so
        # identical input yields byte-identical sw.js across builds.
        content.should match(/CACHE_NAME = 'hwaro-[0-9a-f]+'/)
        content.should_not contain("hwaro-v1")

        # Regenerating from identical input must produce the same cache name.
        Dir.mktmpdir do |dir2|
          Hwaro::Content::Seo::Pwa.generate(site, dir2)
          File.read(File.join(dir2, "sw.js")).should eq(content)
        end
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
        # Precache entries are only emitted when their output file exists
        # (cache.addAll is all-or-nothing), so materialize them in the dir.
        FileUtils.mkdir_p(File.join(dir, "css"))
        FileUtils.mkdir_p(File.join(dir, "js"))
        File.write(File.join(dir, "css", "main.css"), "body{}")
        File.write(File.join(dir, "js", "app.js"), "console.log(1)")
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
        File.write(File.join(dir, "offline.html"), "<html>offline</html>")
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

    # cache.addAll() is all-or-nothing: one 404 aborts the whole SW install.
    # A precache URL with no backing output file must be dropped from
    # PRECACHE_URLS (the build emits a warning).
    it "drops precache URLs that have no matching output file" do
      Dir.mktmpdir do |dir|
        # Only one of the two precached files exists in the output dir.
        File.write(File.join(dir, "real.css"), "body{}")
        site = make_site(<<-TOML)
          [pwa]
          enabled = true
          precache_urls = ["/real.css", "/ghost.css"]
          TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        content = File.read(File.join(dir, "sw.js"))
        content.should contain("/real.css")
        content.should_not contain("/ghost.css")
      end
    end

    # The launch URL is always kept even when its output file isn't present
    # in the dir we generate into (it's the navigation fallback target).
    it "keeps the start_url in precache even without a backing file" do
      Dir.mktmpdir do |dir|
        site = make_site(<<-TOML)
          [pwa]
          enabled = true
          TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        content = File.read(File.join(dir, "sw.js"))
        content.should contain(%("/"))
      end
    end

    # External http(s):// precache URLs aren't our files, so they bypass the
    # existence check and stay in the list.
    it "keeps external precache URLs without trying to resolve them on disk" do
      Dir.mktmpdir do |dir|
        site = make_site(<<-TOML)
          [pwa]
          enabled = true
          precache_urls = ["https://cdn.example.com/lib.js"]
          TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        content = File.read(File.join(dir, "sw.js"))
        content.should contain("https://cdn.example.com/lib.js")
      end
    end

    # A missing offline_page must not become the navigation fallback (it would
    # 404 offline). Fall back to the launch URL instead.
    it "falls back the navigation offline target to start_url when offline_page is missing" do
      Dir.mktmpdir do |dir|
        site = make_site(<<-TOML)
          [pwa]
          enabled = true
          offline_page = "/nope-offline.html"
          TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        content = File.read(File.join(dir, "sw.js"))
        # The missing offline page is dropped from precache...
        content.should_not contain("/nope-offline.html")
        # ...and the navigation fallback uses the root instead.
        content.should contain(%(caches.match("/")))
      end
    end

    it "uses a real offline_page as the navigation target when its file exists" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "offline.html"), "<html>offline</html>")
        site = make_site(<<-TOML)
          [pwa]
          enabled = true
          offline_page = "/offline.html"
          TOML

        Hwaro::Content::Seo::Pwa.generate(site, dir)

        content = File.read(File.join(dir, "sw.js"))
        content.should contain(%(caches.match("/offline.html")))
      end
    end

    # GitHub/GitLab project pages serve the site under a subpath. Every
    # site-internal root-relative PWA URL must carry that prefix or the
    # installed app launches the wrong origin and the precache keys never
    # match the requests the page actually makes.
    context "with a subpath base_url" do
      it "prefixes start_url and icon srcs in the manifest" do
        Dir.mktmpdir do |dir|
          site = make_site(<<-TOML, base_url: "https://user.github.io/myrepo/")
            [pwa]
            enabled = true
            icons = ["static/icon-192.png", "https://cdn.example.com/icon.png"]
            TOML

          Hwaro::Content::Seo::Pwa.generate(site, dir)

          manifest = JSON.parse(File.read(File.join(dir, "manifest.json")))
          manifest["start_url"].as_s.should eq("/myrepo/")
          icons = manifest["icons"].as_a
          icons[0]["src"].as_s.should eq("/myrepo/icon-192.png")
          # Absolute icon URLs are left untouched.
          icons[1]["src"].as_s.should eq("https://cdn.example.com/icon.png")
        end
      end

      it "prefixes precache URLs, offline page, and the navigation fallback in sw.js" do
        Dir.mktmpdir do |dir|
          # Output files are addressed by the base_path-stripped relative path.
          FileUtils.mkdir_p(File.join(dir, "css"))
          File.write(File.join(dir, "css", "main.css"), "body{}")
          File.write(File.join(dir, "offline.html"), "<html>offline</html>")
          site = make_site(<<-TOML, base_url: "https://user.github.io/myrepo/")
            [pwa]
            enabled = true
            offline_page = "/offline.html"
            precache_urls = ["/", "/css/main.css"]
            cache_strategy = "network-first"
            TOML

          Hwaro::Content::Seo::Pwa.generate(site, dir)

          content = File.read(File.join(dir, "sw.js"))
          content.should contain(%("/myrepo/"))
          content.should contain(%("/myrepo/css/main.css"))
          content.should contain(%("/myrepo/offline.html"))
          # The hardcoded root fallback must follow the subpath too.
          content.should contain(%(caches.match("/myrepo/offline.html") || caches.match("/myrepo/")))
          # No bare-root key should leak through.
          content.should_not contain(%(caches.match("/")))
        end
      end

      it "leaves URLs untouched for a domain-root base_url" do
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, "css"))
          File.write(File.join(dir, "css", "main.css"), "body{}")
          site = make_site(<<-TOML, base_url: "https://example.com")
            [pwa]
            enabled = true
            precache_urls = ["/css/main.css"]
            TOML

          Hwaro::Content::Seo::Pwa.generate(site, dir)

          manifest = JSON.parse(File.read(File.join(dir, "manifest.json")))
          manifest["start_url"].as_s.should eq("/")
          File.read(File.join(dir, "sw.js")).should contain(%("/css/main.css"))
        end
      end
    end
  end
end
