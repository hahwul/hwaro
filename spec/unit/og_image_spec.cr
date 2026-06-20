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
      ai.pattern_opacity.should eq(0.12)
      ai.pattern_scale.should eq(1.0)
      ai.background_image.should be_nil
      ai.overlay_opacity.should eq(0.45)
      ai.format.should eq("png")
      ai.font_path.should be_nil
      ai.accent_bars.should be_false
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

    it "has default logo_position of bottom-left" do
      config = Hwaro::Models::Config.new
      config.og.auto_image.logo_position.should eq("bottom-left")
    end

    it "loads logo_position from TOML" do
      config = make_og_config(<<-TOML)
        [og.auto_image]
        enabled = true
        logo_position = "top-right"
        TOML

      config.og.auto_image.logo_position.should eq("top-right")
    end

    it "ignores invalid logo_position values" do
      config = make_og_config(<<-TOML)
        [og.auto_image]
        enabled = true
        logo_position = "center"
        TOML

      config.og.auto_image.logo_position.should eq("bottom-left")
    end

    it "loads font_path from TOML" do
      config = make_og_config(<<-TOML)
        [og.auto_image]
        enabled = true
        font_path = "fonts/Pretendard-Bold.ttf"
        TOML

      config.og.auto_image.font_path.should eq("fonts/Pretendard-Bold.ttf")
    end

    it "loads secondary_color from TOML" do
      config = make_og_config(<<-TOML)
        [og.auto_image]
        enabled = true
        style = "brutalist"
        secondary_color = "#ff5b2e"
        TOML

      config.og.auto_image.secondary_color.should eq("#ff5b2e")
    end

    it "leaves secondary_color nil when not set" do
      config = make_og_config(<<-TOML)
        [og.auto_image]
        enabled = true
        TOML

      config.og.auto_image.secondary_color.should be_nil
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
        config.og.auto_image.logo = logo_path

        # Pre-compute data URI as generate() would
        logo_data_uri = Hwaro::Content::Seo::OgImage.file_to_data_uri(logo_path)
        svg = Hwaro::Content::Seo::OgImage.render_svg(page, config, logo_data_uri)

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

    it "places logo at bottom-right when logo_position is bottom-right" do
      Dir.mktmpdir do |dir|
        logo_path = File.join(dir, "logo.png")
        File.open(logo_path, "wb") { |f| f.write(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) }

        page = Hwaro::Models::Page.new("test.md")
        page.title = "Test"

        config = Hwaro::Models::Config.new
        config.og.auto_image.logo = logo_path
        config.og.auto_image.logo_position = "bottom-right"

        logo_data_uri = Hwaro::Content::Seo::OgImage.file_to_data_uri(logo_path)
        svg = Hwaro::Content::Seo::OgImage.render_svg(page, config, logo_data_uri)

        svg.should contain("x=\"1072\"")
      end
    end

    it "places logo at top-left when logo_position is top-left" do
      Dir.mktmpdir do |dir|
        logo_path = File.join(dir, "logo.png")
        File.open(logo_path, "wb") { |f| f.write(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) }

        page = Hwaro::Models::Page.new("test.md")
        page.title = "Test"

        config = Hwaro::Models::Config.new
        config.og.auto_image.logo = logo_path
        config.og.auto_image.logo_position = "top-left"

        logo_data_uri = Hwaro::Content::Seo::OgImage.file_to_data_uri(logo_path)
        svg = Hwaro::Content::Seo::OgImage.render_svg(page, config, logo_data_uri)

        svg.should contain("x=\"80\" y=\"20\"")
      end
    end

    it "places logo at top-right when logo_position is top-right" do
      Dir.mktmpdir do |dir|
        logo_path = File.join(dir, "logo.png")
        File.open(logo_path, "wb") { |f| f.write(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) }

        page = Hwaro::Models::Page.new("test.md")
        page.title = "Test"

        config = Hwaro::Models::Config.new
        config.og.auto_image.logo = logo_path
        config.og.auto_image.logo_position = "top-right"

        logo_data_uri = Hwaro::Content::Seo::OgImage.file_to_data_uri(logo_path)
        svg = Hwaro::Content::Seo::OgImage.render_svg(page, config, logo_data_uri)

        svg.should contain("x=\"1072\" y=\"20\"")
      end
    end

    it "does not offset site name when logo is bottom-right" do
      Dir.mktmpdir do |dir|
        logo_path = File.join(dir, "logo.png")
        File.open(logo_path, "wb") { |f| f.write(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) }

        page = Hwaro::Models::Page.new("test.md")
        page.title = "Test"

        config = Hwaro::Models::Config.new
        config.title = "My Site"
        config.og.auto_image.logo = logo_path
        config.og.auto_image.logo_position = "bottom-right"

        logo_data_uri = Hwaro::Content::Seo::OgImage.file_to_data_uri(logo_path)
        svg = Hwaro::Content::Seo::OgImage.render_svg(page, config, logo_data_uri)

        # Site name should be at x=80 (not offset to 140) since logo is not bottom-left
        svg.should contain("<text x=\"80\" y=\"#{Hwaro::Content::Seo::OgImage::HEIGHT - 65}\"")
      end
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

    it "omits accent bars by default for pattern styles" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "dots"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)

      # accent_bars defaults to false, so no 6px top/bottom bars
      svg.should_not contain("height=\"6\"")
    end

    it "draws accent bars for pattern styles when accent_bars is enabled" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "dots"
      config.og.auto_image.accent_bars = true

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)

      # Opting in brings back both the top and bottom 6px accent bars
      svg.scan(/height="6"/).size.should eq(2)
    end

    it "keeps accent bars off for modern styles even when enabled" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"

      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "editorial"
      config.og.auto_image.accent_bars = true

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)

      # no_accent_bars? styles never draw the bars, regardless of the flag
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

        bg_data_uri = Hwaro::Content::Seo::OgImage.file_to_data_uri(bg_path)
        svg = Hwaro::Content::Seo::OgImage.render_svg(page, config, nil, bg_data_uri)
        svg.should contain("data:image/jpeg;base64,")
        svg.should contain("preserveAspectRatio=\"xMidYMid slice\"")
        svg.should contain("opacity=\"0.45\"")
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

        bg_data_uri = Hwaro::Content::Seo::OgImage.file_to_data_uri(bg_path)
        svg = Hwaro::Content::Seo::OgImage.render_svg(page, config, nil, bg_data_uri)
        svg.should contain("opacity=\"0.8\"")
      end
    end

    it "renders the split style as a diagonal color block" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Split"
      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "split"
      config.og.auto_image.accent_color = "#ff3b6b"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain("<polygon")
      svg.should contain("fill=\"#ff3b6b\"")
      # Geometric styles drop the classic 6px accent bars.
      svg.should_not contain("height=\"6\"")
    end

    it "renders the band style as a full-width color band" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Band"
      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "band"
      config.og.auto_image.accent_color = "#ffd23f"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain(%(<rect x="0" y="#{Hwaro::Content::Seo::OgImage::BAND_TOP}" width="1200" height="#{Hwaro::Content::Seo::OgImage::BAND_HEIGHT}" fill="#ffd23f" />))
    end

    it "renders the brutalist style with a framed panel and offset shadow" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Brutalist"
      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "brutalist"
      config.og.auto_image.accent_color = "#161616"
      config.og.auto_image.secondary_color = "#ff5b2e"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain("stroke=\"#161616\"") # thick frame border
      svg.should contain("fill=\"#ff5b2e\"")   # offset shadow uses secondary color
    end

    it "renders generated backdrops for modern styles" do
      {"artistic" => "linearGradient", "hero" => "radialGradient", "surreal" => "radialGradient"}.each do |style, marker|
        page = Hwaro::Models::Page.new("test.md")
        page.title = "Modern"
        config = Hwaro::Models::Config.new
        config.og.auto_image.style = style
        Hwaro::Content::Seo::OgImage.render_svg(page, config).should contain(marker)
      end
    end

    it "renders the framed style as an inset stroked frame" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Framed"
      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "framed"
      config.og.auto_image.accent_color = "#e2c044"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain("fill=\"none\" stroke=\"#e2c044\"")
    end

    it "skips the generated gradient when a background image is present" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Artistic"
      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "artistic"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config, nil, "data:image/png;base64,AAAA")
      svg.should_not contain("linearGradient")
    end

    it "renders the terminal style as a window with prompt and cursor" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Terminal"
      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "terminal"
      config.og.auto_image.accent_color = "#2ee66b"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain("#ff5f57")                                 # traffic light
      svg.should contain(%(fill="#2ee66b">$</text>))                # prompt
      svg.should contain(%(<tspan fill="#2ee66b">&#x2588;</tspan>)) # block cursor
    end

    it "renders the bauhaus style as flat geometric shapes" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Bauhaus"
      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "bauhaus"
      config.og.auto_image.accent_color = "#e8453c"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain(%(<circle cx="950" cy="150" r="220" fill="#e8453c" />))
      svg.should contain("<polygon")
    end

    it "renders the halftone style as a growing dot field" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Halftone"
      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "halftone"
      config.og.auto_image.accent_color = "#ff2e88"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain(%(fill="#ff2e88" opacity="0.92"))
    end

    it "renders a ghost echo of the first title word for hero" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Velocity matters"
      config = Hwaro::Models::Config.new
      config.og.auto_image.style = "hero"

      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      svg.should contain(%(opacity="0.07">VELOCITY</text>))
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

  describe "color helpers" do
    it "derives a complementary secondary color from the accent" do
      sec = Hwaro::Content::Seo::OgImage.derive_secondary("#ff3b6b")
      sec.should start_with("#")
      sec.size.should eq(7)
      sec.should_not eq("#ff3b6b")
    end

    it "round-trips pure and gray colors through HSL" do
      Hwaro::Content::Seo::OgImage.hsl_to_hex(*Hwaro::Content::Seo::OgImage.hex_to_hsl("#ff0000")).should eq("#ff0000")
      Hwaro::Content::Seo::OgImage.hsl_to_hex(*Hwaro::Content::Seo::OgImage.hex_to_hsl("#808080")).should eq("#808080")
    end

    it "prefers an explicit secondary_color" do
      ai = Hwaro::Models::AutoImageConfig.new
      ai.accent_color = "#ff3b6b"
      ai.secondary_color = "#00f3b7"
      Hwaro::Content::Seo::OgImage.resolve_secondary(ai).should eq("#00f3b7")
    end

    it "falls back to a derived secondary color when unset" do
      ai = Hwaro::Models::AutoImageConfig.new
      ai.accent_color = "#ff3b6b"
      ai.secondary_color = nil
      Hwaro::Content::Seo::OgImage.resolve_secondary(ai).should eq(Hwaro::Content::Seo::OgImage.derive_secondary("#ff3b6b"))
    end
  end

  describe "text & layout helpers" do
    it "detects CJK / kana / hangul characters" do
      Hwaro::Content::Seo::OgImage.contains_cjk?("Hello World").should be_false
      Hwaro::Content::Seo::OgImage.contains_cjk?("café résumé").should be_false # Latin-1, covered
      Hwaro::Content::Seo::OgImage.contains_cjk?("한글 제목").should be_true
      Hwaro::Content::Seo::OgImage.contains_cjk?("日本語のタイトル").should be_true
      Hwaro::Content::Seo::OgImage.contains_cjk?("Mixed 中文 text").should be_true
    end

    it "caps band title lines to what fits the fixed-height band" do
      # BAND_HEIGHT is 200: a 52px line (+8 gap) fits 3 lines, a 60px line fits 2.
      Hwaro::Content::Seo::OgImage.band_line_capacity(52).should eq(3)
      Hwaro::Content::Seo::OgImage.band_line_capacity(60).should eq(2)
      Hwaro::Content::Seo::OgImage.band_line_capacity(1000).should eq(1) # never zero
    end

    it "marks band title truncation with an ellipsis" do
      lines = ["One", "Two", "Three", "Four"]
      # 60px → capacity 2; the kept lines gain an ellipsis on the last one.
      Hwaro::Content::Seo::OgImage.cap_band_title(lines, 60).should eq(["One", "Two…"])
      # Within capacity → untouched, no ellipsis.
      Hwaro::Content::Seo::OgImage.cap_band_title(["Only"], 60).should eq(["Only"])
    end
  end

  describe "style predicates" do
    it "classifies geometric styles" do
      Hwaro::Content::Seo::OgImage.geometric?("split").should be_true
      Hwaro::Content::Seo::OgImage.geometric?("band").should be_true
      Hwaro::Content::Seo::OgImage.geometric?("brutalist").should be_true
      Hwaro::Content::Seo::OgImage.geometric?("default").should be_false
    end

    it "classifies signature styles" do
      Hwaro::Content::Seo::OgImage.signature?("terminal").should be_true
      Hwaro::Content::Seo::OgImage.signature?("bauhaus").should be_true
      Hwaro::Content::Seo::OgImage.signature?("halftone").should be_true
      Hwaro::Content::Seo::OgImage.signature?("editorial").should be_false
    end

    it "drops accent bars for minimal / modern / geometric / signature styles" do
      Hwaro::Content::Seo::OgImage.no_accent_bars?("minimal").should be_true
      Hwaro::Content::Seo::OgImage.no_accent_bars?("editorial").should be_true
      Hwaro::Content::Seo::OgImage.no_accent_bars?("split").should be_true
      Hwaro::Content::Seo::OgImage.no_accent_bars?("terminal").should be_true
      Hwaro::Content::Seo::OgImage.no_accent_bars?("default").should be_false
      Hwaro::Content::Seo::OgImage.no_accent_bars?("dots").should be_false
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
        config.og.auto_image.format = "svg" # explicit SVG path coverage

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
        config.og.auto_image.format = "svg" # pin SVG: asserts the .svg output path
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
        config.og.auto_image.format = "svg" # pin SVG: asserts the .svg output paths

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

    # Two distinct URLs that collapse to the same slug after gsub("/", "-")
    # (/posts/foo/ and /posts-foo/ both -> "posts-foo") must each own a
    # distinct on-disk path. The first to claim the slug keeps the bare slug;
    # the second gets a SHA256(url)[0,8] suffix. Without this disambiguation,
    # both pages would write to ONE path (torn file under -Dpreview_mt) and one
    # page would advertise an OG image rendered for the other.
    it "disambiguates colliding URL slugs with a stable URL-hash suffix" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.og.auto_image.enabled = true
        config.og.auto_image.format = "svg"

        page1 = Hwaro::Models::Page.new("a.md")
        page1.title = "Slashed Foo"
        page1.url = "/posts/foo/"
        page1.render = true

        page2 = Hwaro::Models::Page.new("b.md")
        page2.title = "Hyphen Foo"
        page2.url = "/posts-foo/"
        page2.render = true

        Hwaro::Content::Seo::OgImage.generate([page1, page2], config, dir)

        # First-seen page keeps the bare slug.
        bare_path = File.join(dir, "og-images", "posts-foo.svg")
        File.exists?(bare_path).should be_true
        page1.image.should eq("/og-images/posts-foo.svg")

        # Second-seen colliding page gets the SHA256(url)[0,8] suffix.
        suffix = Digest::SHA256.hexdigest(page2.url)[0, 8]
        suffixed_path = File.join(dir, "og-images", "posts-foo-#{suffix}.svg")
        File.exists?(suffixed_path).should be_true
        page2.image.should eq("/og-images/posts-foo-#{suffix}.svg")

        # The two pages own distinct files (no overwrite).
        page1.image.should_not eq(page2.image)
        File.read(bare_path).should contain("Slashed Foo")
        File.read(suffixed_path).should contain("Hyphen Foo")
      end
    end

    # When the PNG renderer fails (e.g. stbi_write_png cannot open the target
    # path) generate() must fall back to writing an SVG, still set page.image,
    # and log a warning. Force the failure by pre-creating <slug>.png as a
    # directory so stbi_write_png returns 0.
    it "falls back to SVG and warns when PNG rendering fails" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.og.auto_image.enabled = true
        config.og.auto_image.format = "png"

        page = Hwaro::Models::Page.new("test.md")
        page.title = "Fallback Title"
        page.url = "/posts/png-test/"
        page.render = true

        # Block the PNG write: create <slug>.png as a directory.
        img_dir = File.join(dir, "og-images")
        Dir.mkdir_p(img_dir)
        Dir.mkdir_p(File.join(img_dir, "posts-png-test.png"))

        log = with_captured_log do
          Hwaro::Content::Seo::OgImage.generate([page], config, dir)
        end

        page.image.not_nil!.ends_with?(".svg").should be_true
        page.image.should eq("/og-images/posts-png-test.svg")

        svg_path = File.join(img_dir, "posts-png-test.svg")
        File.exists?(svg_path).should be_true
        File.read(svg_path).should contain("Fallback Title")

        log.should contain("PNG render failed")
      end
    end

    it "generates an image when png format is set" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.og.auto_image.enabled = true
        config.og.auto_image.format = "png"

        page = Hwaro::Models::Page.new("test.md")
        page.title = "PNG Test"
        page.url = "/posts/png-test/"
        page.render = true

        Hwaro::Content::Seo::OgImage.generate([page], config, dir)

        # Should generate either PNG (if font available) or SVG (fallback)
        page.image.should_not be_nil
      end
    end
  end

  describe ".compute_config_hash" do
    it "returns consistent hash for same config" do
      config = Hwaro::Models::Config.new
      config.title = "My Site"
      hash1 = Hwaro::Content::Seo::OgImage.compute_config_hash(config)
      hash2 = Hwaro::Content::Seo::OgImage.compute_config_hash(config)
      hash1.should eq(hash2)
      hash1.size.should eq(64)
    end

    it "returns different hash when config changes" do
      config = Hwaro::Models::Config.new
      config.title = "My Site"
      hash1 = Hwaro::Content::Seo::OgImage.compute_config_hash(config)

      config.og.auto_image.accent_color = "#ff0000"
      hash2 = Hwaro::Content::Seo::OgImage.compute_config_hash(config)
      hash1.should_not eq(hash2)
    end

    it "returns different hash when the logo file content changes" do
      Dir.mktmpdir do |dir|
        logo_path = File.join(dir, "logo.png")
        File.write(logo_path, "old logo bytes")

        config = Hwaro::Models::Config.new
        config.og.auto_image.logo = logo_path
        hash1 = Hwaro::Content::Seo::OgImage.compute_config_hash(config)

        # Same path, new pixels — cached OG images must be invalidated.
        File.write(logo_path, "new logo bytes")
        hash2 = Hwaro::Content::Seo::OgImage.compute_config_hash(config)
        hash1.should_not eq(hash2)
      end
    end
  end

  describe ".compute_page_hash" do
    it "returns consistent hash for same page" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Hello"
      page.description = "World"
      page.url = "/posts/hello/"
      hash1 = Hwaro::Content::Seo::OgImage.compute_page_hash(page)
      hash2 = Hwaro::Content::Seo::OgImage.compute_page_hash(page)
      hash1.should eq(hash2)
    end

    it "returns different hash when title changes" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Hello"
      page.url = "/posts/hello/"
      hash1 = Hwaro::Content::Seo::OgImage.compute_page_hash(page)

      page.title = "Changed"
      hash2 = Hwaro::Content::Seo::OgImage.compute_page_hash(page)
      hash1.should_not eq(hash2)
    end
  end

  describe "manifest" do
    it "creates manifest file after generation" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.title = "My Site"
        config.og.auto_image.enabled = true

        page = Hwaro::Models::Page.new("test.md")
        page.title = "My Post"
        page.url = "/posts/my-post/"
        page.render = true

        Hwaro::Content::Seo::OgImage.generate([page], config, dir)

        manifest_path = File.join(dir, "og-images", ".og_manifest.json")
        File.exists?(manifest_path).should be_true

        data = JSON.parse(File.read(manifest_path))
        data["version"].should eq(1)
        data["config_hash"].as_s.size.should eq(64)
        data["entries"].as_h.has_key?("posts-my-post").should be_true
      end
    end

    it "skips unchanged pages on second generation" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.title = "My Site"
        config.og.auto_image.enabled = true
        config.og.auto_image.format = "svg" # pin SVG: asserts the .svg path + mtime

        page = Hwaro::Models::Page.new("test.md")
        page.title = "My Post"
        page.url = "/posts/my-post/"
        page.render = true

        Hwaro::Content::Seo::OgImage.generate([page], config, dir)

        svg_path = File.join(dir, "og-images", "posts-my-post.svg")
        mtime1 = File.info(svg_path).modification_time

        # Reset page.image to simulate fresh build context
        page.image = nil
        sleep 100.milliseconds

        Hwaro::Content::Seo::OgImage.generate([page], config, dir)

        mtime2 = File.info(svg_path).modification_time
        mtime2.should eq(mtime1)
        page.image.should eq("/og-images/posts-my-post.svg")
      end
    end

    it "regenerates when title changes" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.title = "My Site"
        config.og.auto_image.enabled = true
        config.og.auto_image.format = "svg" # pin SVG: reads rendered text from the file

        page = Hwaro::Models::Page.new("test.md")
        page.title = "Original Title"
        page.url = "/posts/my-post/"
        page.render = true

        Hwaro::Content::Seo::OgImage.generate([page], config, dir)
        svg_path = File.join(dir, "og-images", "posts-my-post.svg")
        content1 = File.read(svg_path)

        page.image = nil
        page.title = "Updated Title"
        Hwaro::Content::Seo::OgImage.generate([page], config, dir)

        content2 = File.read(svg_path)
        content2.should_not eq(content1)
        content2.should contain("Updated Title")
      end
    end

    it "regenerates all when config changes" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.title = "My Site"
        config.og.auto_image.enabled = true
        config.og.auto_image.format = "svg" # pin SVG: compares rendered file contents

        page = Hwaro::Models::Page.new("test.md")
        page.title = "My Post"
        page.url = "/posts/my-post/"
        page.render = true

        Hwaro::Content::Seo::OgImage.generate([page], config, dir)
        svg_path = File.join(dir, "og-images", "posts-my-post.svg")
        content1 = File.read(svg_path)

        page.image = nil
        config.og.auto_image.accent_color = "#ff0000"
        Hwaro::Content::Seo::OgImage.generate([page], config, dir)

        content2 = File.read(svg_path)
        content2.should_not eq(content1)
      end
    end

    it "regenerates when file is missing despite manifest entry" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.title = "My Site"
        config.og.auto_image.enabled = true
        config.og.auto_image.format = "svg" # pin SVG: asserts the .svg path

        page = Hwaro::Models::Page.new("test.md")
        page.title = "My Post"
        page.url = "/posts/my-post/"
        page.render = true

        Hwaro::Content::Seo::OgImage.generate([page], config, dir)

        svg_path = File.join(dir, "og-images", "posts-my-post.svg")
        File.delete(svg_path)

        page.image = nil
        Hwaro::Content::Seo::OgImage.generate([page], config, dir)

        File.exists?(svg_path).should be_true
      end
    end

    it "round-trips manifest correctly" do
      Dir.mktmpdir do |dir|
        manifest_path = File.join(dir, "manifest.json")
        entries = {"slug-a" => "hash1", "slug-b" => "hash2"}
        Hwaro::Content::Seo::OgImage.save_manifest(manifest_path, "confighash", entries)

        config_hash, loaded = Hwaro::Content::Seo::OgImage.load_manifest(manifest_path)
        config_hash.should eq("confighash")
        loaded.should eq(entries)
      end
    end

    it "returns empty manifest for missing file" do
      config_hash, entries = Hwaro::Content::Seo::OgImage.load_manifest("/nonexistent/path.json")
      config_hash.should eq("")
      entries.should be_empty
    end

    # Default `partial: false` truncates the manifest each pass so
    # entries for pages that no longer exist don't accumulate. Without
    # this, an `--fast-start` regression that started writing partial
    # manifests in full builds would leak slugs forever — the cache
    # check `old_entries[slug]? == page_hash` would keep matching
    # against stale entries and the on-disk OG file for a removed
    # page would never get cleaned up.
    it "prunes manifest entries for pages no longer in the input (full mode)" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.title = "My Site"
        config.og.auto_image.enabled = true

        page_a = Hwaro::Models::Page.new("a.md")
        page_a.title = "A"
        page_a.url = "/a/"
        page_a.render = true

        page_b = Hwaro::Models::Page.new("b.md")
        page_b.title = "B"
        page_b.url = "/b/"
        page_b.render = true

        Hwaro::Content::Seo::OgImage.generate([page_a, page_b], config, dir)

        manifest_path = File.join(dir, "og-images", ".og_manifest.json")
        entries = JSON.parse(File.read(manifest_path))["entries"].as_h
        entries.has_key?("a").should be_true
        entries.has_key?("b").should be_true

        # Second pass with only page_a — page_b's manifest entry must drop.
        page_a.image = nil
        Hwaro::Content::Seo::OgImage.generate([page_a], config, dir)

        entries = JSON.parse(File.read(manifest_path))["entries"].as_h
        entries.has_key?("a").should be_true
        entries.has_key?("b").should be_false
      end
    end

    # Partial mode is the `--fast-start` two-pass path: the priority
    # pass writes a manifest, the deferred pass writes another for the
    # remainder. The second call must NOT truncate the first call's
    # entries, otherwise the next cold start would re-render every
    # priority page's OG image from scratch.
    it "accumulates manifest entries across calls (partial mode)" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.title = "My Site"
        config.og.auto_image.enabled = true

        priority_page = Hwaro::Models::Page.new("home.md")
        priority_page.title = "Home"
        priority_page.url = "/"
        priority_page.render = true

        deferred_page = Hwaro::Models::Page.new("old.md")
        deferred_page.title = "Old Post"
        deferred_page.url = "/old/"
        deferred_page.render = true

        Hwaro::Content::Seo::OgImage.generate([priority_page], config, dir, partial: true)
        Hwaro::Content::Seo::OgImage.generate([deferred_page], config, dir, partial: true)

        manifest_path = File.join(dir, "og-images", ".og_manifest.json")
        entries = JSON.parse(File.read(manifest_path))["entries"].as_h
        entries.has_key?("home").should be_true # slugified from title since "/" yields empty URL slug
        entries.has_key?("old").should be_true
      end
    end
  end

  describe ".split_into_segments" do
    it "splits Latin text by whitespace" do
      segments = Hwaro::Content::Seo::OgImage.split_into_segments("Hello World")
      segments.should eq(["Hello", " ", "World"])
    end

    it "splits CJK text into individual characters" do
      segments = Hwaro::Content::Seo::OgImage.split_into_segments("안녕하세요")
      segments.should eq(["안", "녕", "하", "세", "요"])
    end

    it "handles mixed Latin and CJK" do
      segments = Hwaro::Content::Seo::OgImage.split_into_segments("Hello 세계")
      segments.should eq(["Hello", " ", "세", "계"])
    end

    it "handles Japanese text" do
      segments = Hwaro::Content::Seo::OgImage.split_into_segments("こんにちは")
      segments.size.should eq(5)
    end

    it "returns empty for empty string" do
      segments = Hwaro::Content::Seo::OgImage.split_into_segments("")
      segments.should be_empty
    end
  end

  describe "word_wrap with CJK" do
    it "wraps CJK text into multiple lines in SVG" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "이것은 매우 긴 한국어 제목입니다 테스트를 위한 문장"

      config = Hwaro::Models::Config.new
      svg = Hwaro::Content::Seo::OgImage.render_svg(page, config)
      # Each line becomes a separate <text> element
      text_elements = svg.scan(/<text x="80"/)
      text_elements.size.should be > 1
    end
  end
end
