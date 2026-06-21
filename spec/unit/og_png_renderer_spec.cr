require "../spec_helper"

describe Hwaro::Content::Seo::OgPngRenderer do
  describe ".parse_hex_color" do
    it "parses hex color strings" do
      Hwaro::Content::Seo::OgPngRenderer.parse_hex_color("#ff0000").should eq(0xff0000_u32)
      Hwaro::Content::Seo::OgPngRenderer.parse_hex_color("#00ff00").should eq(0x00ff00_u32)
      Hwaro::Content::Seo::OgPngRenderer.parse_hex_color("#1a1a2e").should eq(0x1a1a2e_u32)
    end

    it "handles color without hash" do
      Hwaro::Content::Seo::OgPngRenderer.parse_hex_color("ffffff").should eq(0xffffff_u32)
    end

    it "expands 3-digit shorthand" do
      Hwaro::Content::Seo::OgPngRenderer.parse_hex_color("#fff").should eq(0xffffff_u32)
      Hwaro::Content::Seo::OgPngRenderer.parse_hex_color("#f00").should eq(0xff0000_u32)
      Hwaro::Content::Seo::OgPngRenderer.parse_hex_color("#1a2").should eq(0x11aa22_u32)
    end

    it "drops the alpha byte from 8-digit hex" do
      Hwaro::Content::Seo::OgPngRenderer.parse_hex_color("#ff0000aa").should eq(0xff0000_u32)
    end

    it "returns 0 for invalid input" do
      Hwaro::Content::Seo::OgPngRenderer.parse_hex_color("not-a-color").should eq(0_u32)
      Hwaro::Content::Seo::OgPngRenderer.parse_hex_color("#12345").should eq(0_u32)
      Hwaro::Content::Seo::OgPngRenderer.parse_hex_color("#gggggg").should eq(0_u32)
    end
  end

  describe ".find_system_font" do
    it "returns a string or nil" do
      result = Hwaro::Content::Seo::OgPngRenderer.find_system_font
      if result
        File.exists?(result).should be_true
      end
    end
  end

  describe ".available?" do
    it "always returns true (bundled font fallback)" do
      Hwaro::Content::Seo::OgPngRenderer.available?.should be_true
    end
  end

  describe ".load_fonts" do
    it "returns FontContext without arguments (bundled fallback)" do
      ctx = Hwaro::Content::Seo::OgPngRenderer.load_fonts
      ctx.should_not be_nil
    end

    it "returns FontContext with nil custom path" do
      ctx = Hwaro::Content::Seo::OgPngRenderer.load_fonts(nil)
      ctx.should_not be_nil
    end

    it "falls back when custom font path does not exist" do
      ctx = Hwaro::Content::Seo::OgPngRenderer.load_fonts("/nonexistent/font.ttf")
      ctx.should_not be_nil
    end

    it "returns a FontContext when prefer_cjk is set" do
      ctx = Hwaro::Content::Seo::OgPngRenderer.load_fonts(nil, prefer_cjk: true)
      ctx.should_not be_nil
    end

    # Regression (#8): CJK titles rendered as blank "tofu" boxes because the
    # font search list was Latin-only. When a CJK-capable system font exists,
    # prefer_cjk must load it so Hangul/Han/kana glyphs are available.
    it "loads a CJK-capable font that covers Hangul when one is installed" do
      cjk_path = Hwaro::Content::Seo::OgPngRenderer.find_cjk_font
      next if cjk_path.nil? # no CJK font on this machine (e.g. minimal CI) — skip

      ctx = Hwaro::Content::Seo::OgPngRenderer.load_fonts(nil, prefer_cjk: true)
      ctx.should_not be_nil
      # U+D55C '한' (Hangul) must resolve to a real glyph in the loaded font.
      Hwaro::Content::Seo::OgPngRenderer.font_has_glyph?(ctx.not_nil!.bold_info, 0xD55C).should be_true
    end
  end

  describe ".find_cjk_font" do
    it "returns an existing font path or nil" do
      result = Hwaro::Content::Seo::OgPngRenderer.find_cjk_font
      if result
        File.exists?(result).should be_true
      else
        result.should be_nil
      end
    end
  end

  describe ".render_png" do
    it "renders a PNG file when fonts are available" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      Dir.mktmpdir do |dir|
        page = Hwaro::Models::Page.new("test.md")
        page.title = "Hello PNG World"
        page.description = "Testing PNG rendering"

        config = Hwaro::Models::Config.new
        config.title = "Test Site"
        config.og.auto_image.enabled = true

        png_path = File.join(dir, "test.png")
        result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path)

        result.should be_true
        File.exists?(png_path).should be_true
        # PNG files start with the magic bytes
        data = File.open(png_path, "rb", &.getb_to_end)
        data.size.should be > 1000 # Reasonable PNG size
        data[0].should eq(0x89_u8) # PNG magic byte
        data[1].should eq(0x50_u8) # 'P'
        data[2].should eq(0x4E_u8) # 'N'
        data[3].should eq(0x47_u8) # 'G'
      end
    end

    it "renders with custom colors" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      Dir.mktmpdir do |dir|
        page = Hwaro::Models::Page.new("test.md")
        page.title = "Colored"

        config = Hwaro::Models::Config.new
        config.og.auto_image.background = "#ff0000"
        config.og.auto_image.text_color = "#00ff00"
        config.og.auto_image.accent_color = "#0000ff"

        png_path = File.join(dir, "colored.png")
        result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path)
        result.should be_true
        File.exists?(png_path).should be_true
      end
    end

    it "renders with dots style" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      Dir.mktmpdir do |dir|
        page = Hwaro::Models::Page.new("test.md")
        page.title = "Dots Style"

        config = Hwaro::Models::Config.new
        config.og.auto_image.style = "dots"

        png_path = File.join(dir, "dots.png")
        result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path)
        result.should be_true
      end
    end

    it "renders with minimal style (no accent bars)" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      Dir.mktmpdir do |dir|
        page = Hwaro::Models::Page.new("test.md")
        page.title = "Minimal"

        config = Hwaro::Models::Config.new
        config.og.auto_image.style = "minimal"

        png_path = File.join(dir, "minimal.png")
        result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path)
        result.should be_true
      end
    end

    it "renders geometric styles (split / band / brutalist)" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      ctx = Hwaro::Content::Seo::OgPngRenderer.load_fonts
      Dir.mktmpdir do |dir|
        %w[split band brutalist].each do |style|
          page = Hwaro::Models::Page.new("test.md")
          page.title = "Geometric #{style}"
          page.description = "bold layout"

          config = Hwaro::Models::Config.new
          config.title = "Site"
          config.og.auto_image.style = style

          png_path = File.join(dir, "#{style}.png")
          result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path, font_ctx: ctx)
          result.should be_true
          File.exists?(png_path).should be_true
        end
      end
    end

    it "renders signature styles (terminal / bauhaus / halftone)" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      ctx = Hwaro::Content::Seo::OgPngRenderer.load_fonts
      Dir.mktmpdir do |dir|
        %w[terminal bauhaus halftone].each do |style|
          page = Hwaro::Models::Page.new("test.md")
          page.title = "Signature #{style}"
          page.description = "self-contained composition"

          config = Hwaro::Models::Config.new
          config.title = "Site"
          config.og.auto_image.style = style

          png_path = File.join(dir, "#{style}.png")
          result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path, font_ctx: ctx)
          result.should be_true
          File.exists?(png_path).should be_true
        end
      end
    end

    it "renders modern styles with generated backgrounds (gradient / glow / frame)" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      ctx = Hwaro::Content::Seo::OgPngRenderer.load_fonts
      Dir.mktmpdir do |dir|
        %w[editorial framed artistic hero surreal monument].each do |style|
          page = Hwaro::Models::Page.new("test.md")
          page.title = "Modern #{style}"
          page.description = "distinct background signature"

          config = Hwaro::Models::Config.new
          config.title = "Site"
          config.og.auto_image.style = style

          png_path = File.join(dir, "#{style}.png")
          result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path, font_ctx: ctx)
          result.should be_true
          File.exists?(png_path).should be_true
        end
      end
    end

    it "renders with an explicit secondary_color" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      Dir.mktmpdir do |dir|
        page = Hwaro::Models::Page.new("test.md")
        page.title = "Two Tone"

        config = Hwaro::Models::Config.new
        config.og.auto_image.style = "split"
        config.og.auto_image.accent_color = "#ff3b6b"
        config.og.auto_image.secondary_color = "#00f3b7"

        png_path = File.join(dir, "split2.png")
        result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path)
        result.should be_true
        File.exists?(png_path).should be_true
      end
    end

    it "renders without site name when show_title is false" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      Dir.mktmpdir do |dir|
        page = Hwaro::Models::Page.new("test.md")
        page.title = "No Title"

        config = Hwaro::Models::Config.new
        config.og.auto_image.show_title = false

        png_path = File.join(dir, "notitle.png")
        result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path)
        result.should be_true
      end
    end

    it "renders with a logo image" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      Dir.mktmpdir do |dir|
        # Create a small valid PNG (1x1 red pixel)
        logo_path = File.join(dir, "logo.png")
        # Write minimal valid 1x1 PNG
        pixel = Pointer(UInt8).malloc(4)
        pixel[0] = 255_u8; pixel[1] = 0_u8; pixel[2] = 0_u8; pixel[3] = 255_u8
        LibStb.stbi_write_png(logo_path, 1, 1, 4, pixel.as(Void*), 4)
        GC.free(pixel.as(Void*))

        page = Hwaro::Models::Page.new("test.md")
        page.title = "With Logo"

        config = Hwaro::Models::Config.new
        config.og.auto_image.logo = logo_path

        png_path = File.join(dir, "withlogo.png")
        result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path, logo_path)
        result.should be_true
      end
    end

    it "renders with background image and overlay" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      Dir.mktmpdir do |dir|
        # Create a small valid PNG for background
        bg_path = File.join(dir, "bg.png")
        pixel = Pointer(UInt8).malloc(4)
        pixel[0] = 0_u8; pixel[1] = 0_u8; pixel[2] = 255_u8; pixel[3] = 255_u8
        LibStb.stbi_write_png(bg_path, 1, 1, 4, pixel.as(Void*), 4)
        GC.free(pixel.as(Void*))

        page = Hwaro::Models::Page.new("test.md")
        page.title = "With BG"

        config = Hwaro::Models::Config.new
        config.og.auto_image.background_image = bg_path
        config.og.auto_image.overlay_opacity = 0.7

        png_path = File.join(dir, "withbg.png")
        result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path, nil, bg_path)
        result.should be_true
      end
    end

    # config.cr only rejects non-finite opacity; a finite but out-of-range
    # value (e.g. 1.8 or -0.5) passes through from TOML. Every opacity branch
    # relies on .clamp(0.0,1.0) before .to_u8 (the gradient branch even carries
    # a comment that a missing clamp raises OverflowError). These render with
    # out-of-range opacities to pin that no OverflowError aborts the build.
    {1.8, -0.5}.each do |opacity|
      it "renders dots style with out-of-range pattern_opacity #{opacity} without OverflowError" do
        next unless Hwaro::Content::Seo::OgPngRenderer.available?

        Dir.mktmpdir do |dir|
          page = Hwaro::Models::Page.new("test.md")
          page.title = "Dots Opacity"

          config = Hwaro::Models::Config.new
          config.og.auto_image.style = "dots"
          config.og.auto_image.pattern_opacity = opacity

          png_path = File.join(dir, "dots-opacity.png")
          result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path)
          result.should be_true
          data = File.open(png_path, "rb", &.getb_to_end)
          data[0].should eq(0x89_u8) # PNG magic byte
        end
      end

      it "renders gradient style with out-of-range pattern_opacity #{opacity} without OverflowError" do
        next unless Hwaro::Content::Seo::OgPngRenderer.available?

        Dir.mktmpdir do |dir|
          page = Hwaro::Models::Page.new("test.md")
          page.title = "Gradient Opacity"

          config = Hwaro::Models::Config.new
          config.og.auto_image.style = "gradient"
          config.og.auto_image.pattern_opacity = opacity

          png_path = File.join(dir, "gradient-opacity.png")
          result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path)
          result.should be_true
          data = File.open(png_path, "rb", &.getb_to_end)
          data[0].should eq(0x89_u8) # PNG magic byte
        end
      end
    end

    it "renders a background overlay with out-of-range overlay_opacity without OverflowError" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      Dir.mktmpdir do |dir|
        bg_path = File.join(dir, "bg.png")
        pixel = Pointer(UInt8).malloc(4)
        pixel[0] = 0_u8; pixel[1] = 0_u8; pixel[2] = 255_u8; pixel[3] = 255_u8
        LibStb.stbi_write_png(bg_path, 1, 1, 4, pixel.as(Void*), 4)
        GC.free(pixel.as(Void*))

        page = Hwaro::Models::Page.new("test.md")
        page.title = "Overlay Opacity"

        config = Hwaro::Models::Config.new
        config.og.auto_image.background_image = bg_path
        config.og.auto_image.overlay_opacity = 2.0

        png_path = File.join(dir, "overlay-opacity.png")
        result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path, nil, bg_path)
        result.should be_true
        data = File.open(png_path, "rb", &.getb_to_end)
        data[0].should eq(0x89_u8) # PNG magic byte
      end
    end

    # render_png's only failure signal is the boolean return from
    # stbi_write_png. Writing into a read-only directory makes the write fail;
    # render_png must return false (not raise) and leave no file behind.
    it "returns false without raising when the png cannot be written" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?
      next if LibC.getuid == 0 # root bypasses chmod-based unwritability

      Dir.mktmpdir do |dir|
        ro_dir = File.join(dir, "readonly")
        Dir.mkdir_p(ro_dir)
        File.chmod(ro_dir, 0o500)
        begin
          page = Hwaro::Models::Page.new("test.md")
          page.title = "Write Failure"

          config = Hwaro::Models::Config.new

          png_path = File.join(ro_dir, "out.png")
          result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path)
          result.should be_false
          File.exists?(png_path).should be_false
        ensure
          File.chmod(ro_dir, 0o700) # restore so mktmpdir cleanup succeeds
        end
      end
    end

    # An empty / whitespace-only title yields title_lines == [] from
    # word_wrap_measured. The terminal-cursor branch (!title_lines.empty?) and
    # the hero ghost branch (page.title.split.first? / unless empty?) are
    # load-bearing guards; render must no-op those branches without raising.
    ["", "   "].each do |blank|
      label = blank.empty? ? "empty" : "whitespace-only"

      it "renders terminal style with an #{label} title without raising" do
        next unless Hwaro::Content::Seo::OgPngRenderer.available?

        Dir.mktmpdir do |dir|
          page = Hwaro::Models::Page.new("test.md")
          page.title = blank

          config = Hwaro::Models::Config.new
          config.og.auto_image.style = "terminal"

          png_path = File.join(dir, "terminal-blank.png")
          result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path)
          result.should be_true
        end
      end

      it "renders hero style with an #{label} title without raising" do
        next unless Hwaro::Content::Seo::OgPngRenderer.available?

        Dir.mktmpdir do |dir|
          page = Hwaro::Models::Page.new("test.md")
          page.title = blank

          config = Hwaro::Models::Config.new
          config.og.auto_image.style = "hero"

          png_path = File.join(dir, "hero-blank.png")
          result = Hwaro::Content::Seo::OgPngRenderer.render_png(page, config, png_path)
          result.should be_true
        end
      end
    end
  end

  describe ".load_image" do
    # load_image decodes/resizes logo & bg images via stb. Its failure guards
    # must each return nil cleanly (and free the source buffer) rather than
    # raise or segfault on a user-supplied corrupt or missing image.
    it "returns nil for a corrupt (non-image) file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "corrupt.png")
        File.write(path, "this is not an image")
        Hwaro::Content::Seo::OgPngRenderer.load_image(path, 48, 48).should be_nil
      end
    end

    it "returns nil for a nonexistent path" do
      Hwaro::Content::Seo::OgPngRenderer.load_image("/nonexistent/logo.png", 48, 48).should be_nil
    end
  end

  describe "integration with OgImage.generate" do
    it "generates PNG files directly when format is png" do
      next unless Hwaro::Content::Seo::OgPngRenderer.available?

      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        config.title = "My Site"
        config.og.auto_image.enabled = true
        config.og.auto_image.format = "png"

        page = Hwaro::Models::Page.new("test.md")
        page.title = "PNG Integration"
        page.url = "/posts/png-test/"
        page.render = true

        Hwaro::Content::Seo::OgImage.generate([page], config, dir)

        # Should generate PNG directly
        png_path = File.join(dir, "og-images", "posts-png-test.png")
        File.exists?(png_path).should be_true
        page.image.should eq("/og-images/posts-png-test.png")

        # Should NOT leave an SVG behind
        svg_path = File.join(dir, "og-images", "posts-png-test.svg")
        File.exists?(svg_path).should be_false
      end
    end
  end
end
