require "../spec_helper"

private def make_og_config(toml : String = "") : Hwaro::Models::Config
  config_str = <<-TOML
  title = "Test Site"
  description = "A test site"
  base_url = "https://example.com"
  #{toml}
  TOML

  File.tempfile("hwaro-og", ".toml") do |file|
    file.print(config_str)
    file.flush
    return Hwaro::Models::Config.load(file.path)
  end
  raise "unreachable"
end

describe Hwaro::Models::AutoImageConfig do
  describe "defaults" do
    it "is disabled by default" do
      config = Hwaro::Models::Config.new
      config.og.auto_image.enabled.should be_false
      config.og.auto_image.background.should eq("#1a1a2e")
      config.og.auto_image.text_color.should eq("#ffffff")
      config.og.auto_image.font_size.should eq(48)
      config.og.auto_image.output_dir.should eq("og-images")
    end

    it "has correct defaults for new properties" do
      config = Hwaro::Models::Config.new
      ai = config.og.auto_image
      ai.show_title.should be_true
      ai.style.should eq("default")
      ai.pattern_opacity.should eq(0.15)
      ai.pattern_scale.should eq(1.0)
      ai.background_image.should be_nil
      ai.overlay_opacity.should eq(0.5)
      ai.format.should eq("svg")
    end
  end

  describe "loading from TOML" do
    it "loads auto_image config from [og.auto_image]" do
      config = make_og_config(<<-TOML)
      [og.auto_image]
      enabled = true
      background = "#000000"
      text_color = "#ff0000"
      accent_color = "#00ff00"
      font_size = 64
      logo = "static/logo.png"
      output_dir = "social"
      TOML

      ai = config.og.auto_image
      ai.enabled.should be_true
      ai.background.should eq("#000000")
      ai.text_color.should eq("#ff0000")
      ai.accent_color.should eq("#00ff00")
      ai.font_size.should eq(64)
      ai.logo.should eq("static/logo.png")
      ai.output_dir.should eq("social")
    end

    it "loads new properties from TOML" do
      config = make_og_config(<<-TOML)
      [og.auto_image]
      enabled = true
      show_title = false
      style = "dots"
      pattern_opacity = 0.3
      pattern_scale = 2.0
      background_image = "static/bg.jpg"
      overlay_opacity = 0.7
      format = "png"
      TOML

      ai = config.og.auto_image
      ai.show_title.should be_false
      ai.style.should eq("dots")
      ai.pattern_opacity.should eq(0.3)
      ai.pattern_scale.should eq(2.0)
      ai.background_image.should eq("static/bg.jpg")
      ai.overlay_opacity.should eq(0.7)
      ai.format.should eq("png")
    end
  end
end

describe Hwaro::Content::Seo::OgImage do
  describe ".render_svg" do
    it "renders a valid SVG with page title" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Hello World"
      page.description = "A great post about things"

      config = Hwaro::Models::Config.new
      config.title = "My Site"
      config.og.auto_image.enabled = true

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)

      svg.should contain("<?xml")
      svg.should contain("<svg")
      svg.should contain("1200")
      svg.should contain("630")
      svg.should contain("Hello World")
      svg.should contain("A great post about things")
      svg.should contain("My Site")
    end

    it "uses configured colors" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.og.auto_image.background = "#ff0000"
      config.og.auto_image.text_color = "#00ff00"
      config.og.auto_image.accent_color = "#0000ff"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)

      svg.should contain("#ff0000")
      svg.should contain("#00ff00")
      svg.should contain("#0000ff")
    end

    it "wraps long titles" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "This is a very long title that should be wrapped across multiple lines to fit"

      config = Hwaro::Models::Config.new
      config.og.auto_image.enabled = true

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)

      # Should have multiple <text> elements for wrapped title
      text_count = svg.scan(/<text[^>]*font-weight="700"/).size
      text_count.should be > 1
    end

    it "escapes XML special characters in title" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "A <b>bold</b> & \"quoted\" title"

      config = Hwaro::Models::Config.new
      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)

      svg.should contain("&lt;b&gt;")
      svg.should contain("&amp;")
    end

    it "includes logo with base64 data URI for binary files" do
      Dir.mktmpdir do |dir|
        # Create a file with real binary data (PNG magic bytes + padding)
        logo_path = File.join(dir, "logo.png")
        File.open(logo_path, "wb") { |f| f.write(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) }

        page = Hwaro::Models::Page.new("test.md")
        page.title = "Test"

        config = Hwaro::Models::Config.new
        config.og.auto_image.logo = File.join(dir, "logo.png")

        # Use absolute path so file_to_data_uri works
        svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)

        svg.should contain("<image")
        svg.should contain("data:image/png;base64,")
      end
    end

    it "falls back to URL reference when logo file does not exist" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.og.auto_image.logo = "static/nonexistent-logo.png"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)

      svg.should contain("<image")
      svg.should contain("/nonexistent-logo.png")
    end

    it "hides site name when show_title is false" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.title = "My Site"
      config.og.auto_image.show_title = false

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)

      # The page title should still appear (it's the main title text)
      svg.should contain("Test")
      # But the site name should not be rendered as the bottom text
      svg.should_not contain("font-size=\"22\"")
    end

    it "shows site name by default" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.title = "My Site"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain("My Site")
      svg.should contain("font-size=\"22\"")
    end

    it "renders dots style pattern" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "dots"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain("<pattern id=\"dots\"")
      svg.should contain("<circle")
    end

    it "renders grid style pattern" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "grid"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain("<pattern id=\"grid\"")
    end

    it "renders diagonal style pattern" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "diagonal"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain("<pattern id=\"diagonal\"")
      svg.should contain("patternTransform=\"rotate(45)\"")
    end

    it "renders gradient style" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "gradient"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain("<linearGradient id=\"grad\"")
    end

    it "renders waves style" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "waves"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain("<path d=\"M 0")
    end

    it "minimal style removes accent bars" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "minimal"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)

      # Should not have 6px accent bars
      svg.should_not contain("height=\"6\"")
    end

    it "default style has no pattern overlay" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "default"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should_not contain("<pattern")
      svg.should_not contain("<linearGradient")
    end

    it "renders background image with overlay when file exists" do
      Dir.mktmpdir do |dir|
        bg_path = File.join(dir, "bg.jpg")
        File.open(bg_path, "wb") { |f| f.write(Bytes[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]) }

        page = Hwaro::Models::Page.new("test.md")
        page.title = "Test"

        config = Hwaro::Models::Config.new
        config.og.auto_image.background_image = bg_path

        svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
        svg.should contain("data:image/jpeg;base64,")
        svg.should contain("preserveAspectRatio=\"xMidYMid slice\"")
        svg.should contain("opacity=\"0.5\"")
      end
    end

    it "respects custom overlay opacity for background image" do
      Dir.mktmpdir do |dir|
        bg_path = File.join(dir, "bg.png")
        File.open(bg_path, "wb") { |f| f.write(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) }

        page = Hwaro::Models::Page.new("test.md")
        page.title = "Test"

        config = Hwaro::Models::Config.new
        config.og.auto_image.background_image = bg_path
        config.og.auto_image.overlay_opacity = 0.8

        svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
        svg.should contain("opacity=\"0.8\"")
      end
    end
  end

  describe ".render_style_pattern" do
    it "returns empty string for default style" do
      result = Hwaro::Content::Seo::OgImage.render_style_pattern("default", "#e94560", "#1a1a2e", 0.15, 1.0)
      result.should eq("")
    end

    it "returns empty string for minimal style" do
      result = Hwaro::Content::Seo::OgImage.render_style_pattern("minimal", "#e94560", "#1a1a2e", 0.15, 1.0)
      result.should eq("")
    end

    it "returns empty string for unknown style" do
      result = Hwaro::Content::Seo::OgImage.render_style_pattern("unknown", "#e94560", "#1a1a2e", 0.15, 1.0)
      result.should eq("")
    end

    it "respects pattern_scale for dots" do
      result1 = Hwaro::Content::Seo::OgImage.render_style_pattern("dots", "#e94560", "#1a1a2e", 0.15, 1.0)
      result2 = Hwaro::Content::Seo::OgImage.render_style_pattern("dots", "#e94560", "#1a1a2e", 0.15, 2.0)
      # Different scale should produce different pattern sizes
      result1.should_not eq(result2)
    end
  end

  describe ".generate" do
    it "does nothing when disabled" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        pages = [] of Hwaro::Models::Page
        Hwaro::Content::Seo::OgImage.generate(pages, config, dir)

        Dir.exists?(File.join(dir, "og-images")).should be_false
      end
    end

    it "generates SVG files and sets page.image" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.title = "My Site"
        config.og.auto_image.enabled = true

        page = Hwaro::Models::Page.new("test.md")
        page.title = "My Post"
        page.url = "/posts/my-post/"
        page.render = true

        Hwaro::Content::Seo::OgImage.generate([page], config, dir)

        # SVG file should exist (slug derived from URL path)
        svg_path = File.join(dir, "og-images", "posts-my-post.svg")
        File.exists?(svg_path).should be_true

        # SVG content should be valid
        svg = File.read(svg_path)
        svg.should contain("<svg")
        svg.should contain("My Post")

        # page.image should be set
        page.image.should eq("/og-images/posts-my-post.svg")
      end
    end

    it "skips pages that already have a custom image" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.og.auto_image.enabled = true

        page = Hwaro::Models::Page.new("test.md")
        page.title = "Has Image"
        page.url = "/posts/has-image/"
        page.image = "/images/custom.png"
        page.render = true

        Hwaro::Content::Seo::OgImage.generate([page], config, dir)

        # Should NOT generate an OG image
        File.exists?(File.join(dir, "og-images", "posts-has-image.svg")).should be_false

        # Original image should remain
        page.image.should eq("/images/custom.png")
      end
    end

    it "skips draft pages" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.og.auto_image.enabled = true

        page = Hwaro::Models::Page.new("test.md")
        page.title = "Draft"
        page.url = "/posts/draft/"
        page.draft = true
        page.render = true

        Hwaro::Content::Seo::OgImage.generate([page], config, dir)
        File.exists?(File.join(dir, "og-images", "posts-draft.svg")).should be_false
      end
    end

    it "uses custom output directory" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.og.auto_image.enabled = true
        config.og.auto_image.output_dir = "social-images"

        page = Hwaro::Models::Page.new("test.md")
        page.title = "Custom Dir"
        page.url = "/posts/custom/"
        page.render = true

        Hwaro::Content::Seo::OgImage.generate([page], config, dir)

        File.exists?(File.join(dir, "social-images", "posts-custom.svg")).should be_true
        page.image.should eq("/social-images/posts-custom.svg")
      end
    end

    it "generates unique files for multiple pages" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.og.auto_image.enabled = true

        page1 = Hwaro::Models::Page.new("a.md")
        page1.title = "First Post"
        page1.url = "/posts/first/"
        page1.render = true

        page2 = Hwaro::Models::Page.new("b.md")
        page2.title = "Second Post"
        page2.url = "/posts/second/"
        page2.render = true

        Hwaro::Content::Seo::OgImage.generate([page1, page2], config, dir)

        File.exists?(File.join(dir, "og-images", "posts-first.svg")).should be_true
        File.exists?(File.join(dir, "og-images", "posts-second.svg")).should be_true
        page1.image.should_not eq(page2.image)
      end
    end

    it "falls back to SVG when png format is set but no tool is available" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.og.auto_image.enabled = true
        config.og.auto_image.format = "png"

        page = Hwaro::Models::Page.new("test.md")
        page.title = "PNG Test"
        page.url = "/posts/png-test/"
        page.render = true

        Hwaro::Content::Seo::OgImage.generate([page], config, dir)

        # Should still generate something (SVG fallback if no tool)
        page.image.should_not be_nil
      end
    end
  end
end
