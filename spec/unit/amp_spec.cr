require "../spec_helper"

private def make_amp_config(toml : String = "") : Hwaro::Models::Config
  config_str = <<-TOML
  title = "Test Site"
  description = "A test site"
  base_url = "https://example.com"
  #{toml}
  TOML

  File.tempfile("hwaro-amp", ".toml") do |file|
    file.print(config_str)
    file.flush
    return Hwaro::Models::Config.load(file.path)
  end
  raise "unreachable"
end

describe Hwaro::Models::AmpConfig do
  describe "defaults" do
    it "is disabled by default" do
      config = Hwaro::Models::Config.new
      config.amp.enabled.should be_false
      config.amp.path_prefix.should eq("amp")
      config.amp.sections.should be_empty
    end
  end

  describe "loading from TOML" do
    it "loads amp config" do
      config = make_amp_config(<<-TOML)
      [amp]
      enabled = true
      path_prefix = "mobile"
      sections = ["posts", "blog"]
      TOML

      config.amp.enabled.should be_true
      config.amp.path_prefix.should eq("mobile")
      config.amp.sections.should eq(["posts", "blog"])
    end
  end

  describe "#section_enabled?" do
    it "returns true for any section when sections is empty" do
      config = Hwaro::Models::Config.new
      config.amp.section_enabled?("posts").should be_true
      config.amp.section_enabled?("anything").should be_true
    end

    it "returns true only for configured sections" do
      config = make_amp_config(<<-TOML)
      [amp]
      enabled = true
      sections = ["posts"]
      TOML

      config.amp.section_enabled?("posts").should be_true
      config.amp.section_enabled?("pages").should be_false
    end
  end
end

describe Hwaro::Content::Seo::Amp do
  describe ".convert_to_amp" do
    it "adds amp attribute to html tag" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      html = "<html lang=\"en\"><head></head><body>Hello</body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<html amp lang=\"en\">")
    end

    it "converts img to amp-img with fill layout when no dimensions" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><img src="/photo.jpg" alt="Photo"></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<amp-img")
      result.should contain("layout=\"fill\"")
      result.should contain("amp-img-container")
      result.should_not contain("<img ")
    end

    it "converts img to amp-img with responsive layout when dimensions present" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><img src="/photo.jpg" width="800" height="600"></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<amp-img")
      result.should contain("layout=\"responsive\"")
      # The img should NOT be wrapped in a container div
      result.should_not contain(%(<div class="amp-img-container"><amp-img))
    end

    it "removes inline style attributes" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><div style="color: red">text</div></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should_not contain("style=")
      result.should contain("text")
    end

    it "injects AMP boilerplate CSS" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = "<html><head></head><body>Hello</body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("amp-boilerplate")
      result.should contain("cdn.ampproject.org")
    end

    it "adds canonical link to original page" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/posts/hello/"
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      html = "<html><head></head><body>Hello</body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain(%(rel="canonical"))
      result.should contain("https://example.com/posts/hello/")
    end

    it "removes disallowed script tags" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head><script>alert(1)</script></head><body>Hello</body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should_not contain("alert(1)")
    end

    it "removes multiline script tags" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = "<html><head><script>\nconsole.log('hello');\nalert(1);\n</script></head><body>Hello</body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should_not contain("console.log")
      result.should_not contain("alert(1)")
    end

    it "preserves ld+json scripts" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head><script type="application/ld+json">{"@type":"Article"}</script></head><body>Hello</body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("application/ld+json")
    end

    it "converts iframe to amp-iframe" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><iframe src="https://example.com"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<amp-iframe")
      result.should_not contain("<iframe")
    end
  end

  describe ".generate" do
    it "does nothing when disabled" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        pages = [] of Hwaro::Models::Page
        Hwaro::Content::Seo::Amp.generate(pages, config, dir)

        Dir.glob(File.join(dir, "**/*")).should be_empty
      end
    end

    it "generates AMP page from canonical HTML" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
        [amp]
        enabled = true
        sections = ["posts"]
        TOML

        page = Hwaro::Models::Page.new("test.md")
        page.url = "/posts/hello/"
        page.title = "Hello"
        page.section = "posts"
        page.render = true

        # Write a canonical HTML file
        canonical_dir = File.join(dir, "posts", "hello")
        FileUtils.mkdir_p(canonical_dir)
        File.write(File.join(canonical_dir, "index.html"), "<html><head></head><body><p>Hello World</p></body></html>")

        Hwaro::Content::Seo::Amp.generate([page], config, dir)

        # AMP version should exist
        amp_path = File.join(dir, "amp", "posts", "hello", "index.html")
        File.exists?(amp_path).should be_true

        amp_content = File.read(amp_path)
        amp_content.should contain("<html amp>")
        amp_content.should contain("amp-boilerplate")

        # Canonical page should have amphtml link
        canonical_content = File.read(File.join(canonical_dir, "index.html"))
        canonical_content.should contain("rel=\"amphtml\"")
        canonical_content.should contain("/amp/posts/hello/")
      end
    end

    it "skips sections not in configured list" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
        [amp]
        enabled = true
        sections = ["posts"]
        TOML

        page = Hwaro::Models::Page.new("test.md")
        page.url = "/about/"
        page.section = "pages"
        page.render = true

        canonical_dir = File.join(dir, "about")
        FileUtils.mkdir_p(canonical_dir)
        File.write(File.join(canonical_dir, "index.html"), "<html><head></head><body>About</body></html>")

        Hwaro::Content::Seo::Amp.generate([page], config, dir)

        File.exists?(File.join(dir, "amp", "about", "index.html")).should be_false
      end
    end

    it "uses custom path prefix" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
        [amp]
        enabled = true
        path_prefix = "mobile"
        TOML

        page = Hwaro::Models::Page.new("test.md")
        page.url = "/posts/hello/"
        page.section = "posts"
        page.render = true

        canonical_dir = File.join(dir, "posts", "hello")
        FileUtils.mkdir_p(canonical_dir)
        File.write(File.join(canonical_dir, "index.html"), "<html><head></head><body>Hello</body></html>")

        Hwaro::Content::Seo::Amp.generate([page], config, dir)

        File.exists?(File.join(dir, "mobile", "posts", "hello", "index.html")).should be_true
      end
    end

    it "skips draft pages" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
        [amp]
        enabled = true
        TOML

        page = Hwaro::Models::Page.new("test.md")
        page.url = "/posts/draft/"
        page.section = "posts"
        page.draft = true
        page.render = true

        Hwaro::Content::Seo::Amp.generate([page], config, dir)
        File.exists?(File.join(dir, "amp", "posts", "draft", "index.html")).should be_false
      end
    end
  end
end
