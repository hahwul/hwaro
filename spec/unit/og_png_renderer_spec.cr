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

    it "returns 0 for invalid input" do
      Hwaro::Content::Seo::OgPngRenderer.parse_hex_color("not-a-color").should eq(0_u32)
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
    it "returns a boolean" do
      result = Hwaro::Content::Seo::OgPngRenderer.available?
      (result == true || result == false).should be_true
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
        data = File.open(png_path, "rb") { |f| f.getb_to_end }
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
