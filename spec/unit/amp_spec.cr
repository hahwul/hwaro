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

    # Markdown renders images as self-closing `<img … />`. The conversion regex
    # greedily captured that trailing slash, producing the invalid
    # `<amp-img … / layout="fill">`. The slash must be stripped.
    it "does not leave a stray slash mid-tag for self-closing <img />" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<p><img src="https://example.com/a.png" alt="A diagram" /></p>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<amp-img")
      result.should_not contain("<img")
      result.should contain("</amp-img>")
      # No orphaned self-closing slash before the appended layout attribute.
      result.should_not match(/<amp-img[^>]*\/\s+layout=/)
      result.should_not contain(%(alt="A diagram" /))
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

    it "strips disallowed external stylesheets but keeps font-provider links" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = "<html><head>" +
             %(<link rel="stylesheet" href="/css/style.css">) +
             %(<link rel="stylesheet" href="https://cdnjs.cloudflare.com/highlight.min.css">) +
             %(<link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Inter">) +
             "</head><body>x</body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)

      # Disallowed stylesheets (site CSS, highlight.js CDN) are removed...
      result.should_not contain("/css/style.css")
      result.should_not contain("cdnjs.cloudflare.com")
      # ...but allowlisted font-provider stylesheets stay.
      result.should contain("fonts.googleapis.com")
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

    it "adds a sandbox attribute and amp-iframe extension script" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><iframe src="https://example.com"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<amp-iframe")
      result.should contain("sandbox=")
      result.should contain(%(custom-element="amp-iframe"))
      result.should contain("amp-iframe-0.1.js")
    end

    it "preserves an existing sandbox attribute on iframe" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><iframe src="https://example.com" sandbox="allow-scripts"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain(%(sandbox="allow-scripts"))
      # No duplicate sandbox attribute was appended.
      result.scan(/sandbox=/).size.should eq(1)
    end

    # AMP: "An amp-iframe must not be in the same origin as the container
    # unless they do not allow allow-same-origin in the sandbox attribute."
    it "grants allow-same-origin to a cross-origin iframe" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = make_amp_config

      html = %(<html><head></head><body><iframe src="https://www.youtube.com/embed/x"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain(%(sandbox="allow-scripts allow-same-origin allow-popups"))
    end

    it "withholds allow-same-origin from a same-origin iframe" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = make_amp_config

      html = %(<html><head></head><body><iframe src="https://example.com/embed/"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain(%(sandbox="allow-scripts allow-popups"))
      result.should_not contain("allow-same-origin")
    end

    it "withholds allow-same-origin from a root-relative iframe src" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = make_amp_config

      html = %(<html><head></head><body><iframe src="/embed/widget.html"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should_not contain("allow-same-origin")
    end

    it "keeps the iframe body when adding a sandbox" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = make_amp_config

      html = %(<html><head></head><body><iframe src="https://cdn.example.org/e"><p>fallback</p></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<p>fallback</p>")
    end

    describe ".same_origin_src?" do
      it "treats relative references as same-origin" do
        Hwaro::Content::Seo::Amp.same_origin_src?("/a/", "https://example.com").should be_true
        Hwaro::Content::Seo::Amp.same_origin_src?("a/b.html", "https://example.com").should be_true
      end

      it "compares scheme, host, and port" do
        Hwaro::Content::Seo::Amp.same_origin_src?("https://example.com/a", "https://example.com").should be_true
        Hwaro::Content::Seo::Amp.same_origin_src?("https://EXAMPLE.com/a", "https://example.com").should be_true
        Hwaro::Content::Seo::Amp.same_origin_src?("https://other.com/a", "https://example.com").should be_false
        Hwaro::Content::Seo::Amp.same_origin_src?("http://example.com/a", "https://example.com").should be_false
        Hwaro::Content::Seo::Amp.same_origin_src?("https://example.com:8443/a", "https://example.com").should be_false
      end

      it "treats an explicit default port as equal to an implicit one" do
        Hwaro::Content::Seo::Amp.same_origin_src?("https://example.com:443/a", "https://example.com").should be_true
      end

      it "resolves a protocol-relative src against the document scheme" do
        Hwaro::Content::Seo::Amp.same_origin_src?("//example.com/a", "https://example.com").should be_true
        Hwaro::Content::Seo::Amp.same_origin_src?("//other.com/a", "https://example.com").should be_false
      end

      it "treats opaque-origin schemes as cross-origin" do
        Hwaro::Content::Seo::Amp.same_origin_src?("data:text/html,hi", "https://example.com").should be_false
        Hwaro::Content::Seo::Amp.same_origin_src?("about:blank", "https://example.com").should be_false
      end

      it "handles a base_url carrying a subpath" do
        Hwaro::Content::Seo::Amp.same_origin_src?("/repo/e/", "https://user.github.io/repo").should be_true
        Hwaro::Content::Seo::Amp.same_origin_src?("https://user.github.io/repo/e/", "https://user.github.io/repo").should be_true
      end
    end

    it "adds amp-video extension script when video present" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><video src="/v.mp4" width="640" height="360"></video></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<amp-video")
      result.should contain(%(custom-element="amp-video"))
      result.should contain("amp-video-0.1.js")
    end

    it "injects missing extension scripts when boilerplate already present" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = "<html><head><style amp-boilerplate>body{}</style>" +
             %(<script async src="https://cdn.ampproject.org/v0.js"></script>) +
             "</head><body><iframe src=\"https://example.com\"></iframe></body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain(%(custom-element="amp-iframe"))
      result.should contain("amp-iframe-0.1.js")
    end

    it "does not duplicate extension scripts already declared" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = "<html><head><style amp-boilerplate>body{}</style>" +
             %(<script async src="https://cdn.ampproject.org/v0.js"></script>) +
             %(<script async custom-element="amp-iframe" src="https://cdn.ampproject.org/v0/amp-iframe-0.1.js"></script>) +
             "</head><body><iframe src=\"https://example.com\"></iframe></body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.scan(/custom-element="amp-iframe"/).size.should eq(1)
    end

    it "strips a self-referencing amphtml link (idempotent across builds)" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      # Simulate the on-disk canonical HTML from a prior run already carrying an
      # amphtml link.
      html = %(<html><head><link rel="amphtml" href="https://example.com/amp/test/"></head><body>Hi</body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should_not contain(%(rel="amphtml"))
    end

    it "unwraps a paragraph whose sole child is an amp-img container" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      # Markdown wraps a standalone image in <p>...</p>.
      html = %(<html><head></head><body><p><img src="/x.png" alt="x" /></p></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain(%(<div class="amp-img-container">))
      # The block container must not be nested directly inside <p>.
      result.should_not match(/<p>\s*<div class="amp-img-container"/)
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

    # A blank/slash-only path_prefix collapses amp_output_path onto the
    # canonical path, which would overwrite every page with its AMP variant.
    # The guard must skip generation, leaving canonical HTML untouched.
    it "skips generation when path_prefix is slash-only to avoid clobbering canonical pages" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
          [amp]
          enabled = true
          path_prefix = "/"
          TOML

        page = Hwaro::Models::Page.new("test.md")
        page.url = "/posts/hello/"
        page.section = "posts"
        page.render = true

        canonical_dir = File.join(dir, "posts", "hello")
        FileUtils.mkdir_p(canonical_dir)
        original = "<html><head></head><body><p>Hello World</p></body></html>"
        canonical_path = File.join(canonical_dir, "index.html")
        File.write(canonical_path, original)

        Hwaro::Content::Seo::Amp.generate([page], config, dir)

        # Canonical page is unchanged (not AMP-converted, not clobbered).
        content = File.read(canonical_path)
        content.should eq(original)
        content.should_not contain("<html amp")
      end
    end

    it "skips generation when path_prefix is empty to avoid clobbering canonical pages" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
          [amp]
          enabled = true
          path_prefix = ""
          TOML

        page = Hwaro::Models::Page.new("test.md")
        page.url = "/posts/hello/"
        page.section = "posts"
        page.render = true

        canonical_dir = File.join(dir, "posts", "hello")
        FileUtils.mkdir_p(canonical_dir)
        original = "<html><head></head><body><p>Hello World</p></body></html>"
        canonical_path = File.join(canonical_dir, "index.html")
        File.write(canonical_path, original)

        Hwaro::Content::Seo::Amp.generate([page], config, dir)

        content = File.read(canonical_path)
        content.should eq(original)
        content.should_not contain("<html amp")
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
