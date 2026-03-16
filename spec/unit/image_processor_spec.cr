require "../spec_helper"
require "../../src/content/processors/image_processor"

describe Hwaro::Content::Processors::ImageProcessor do
  describe ".image?" do
    it "returns true for supported image extensions" do
      Hwaro::Content::Processors::ImageProcessor.image?("photo.jpg").should be_true
      Hwaro::Content::Processors::ImageProcessor.image?("photo.jpeg").should be_true
      Hwaro::Content::Processors::ImageProcessor.image?("icon.png").should be_true
      Hwaro::Content::Processors::ImageProcessor.image?("scan.bmp").should be_true
    end

    it "returns false for unsupported formats" do
      Hwaro::Content::Processors::ImageProcessor.image?("anim.gif").should be_false
      Hwaro::Content::Processors::ImageProcessor.image?("pic.webp").should be_false
      Hwaro::Content::Processors::ImageProcessor.image?("raw.tiff").should be_false
      Hwaro::Content::Processors::ImageProcessor.image?("photo.tga").should be_false
    end

    it "returns false for non-image files" do
      Hwaro::Content::Processors::ImageProcessor.image?("style.css").should be_false
      Hwaro::Content::Processors::ImageProcessor.image?("script.js").should be_false
      Hwaro::Content::Processors::ImageProcessor.image?("page.md").should be_false
      Hwaro::Content::Processors::ImageProcessor.image?("data.json").should be_false
    end

    it "is case insensitive" do
      Hwaro::Content::Processors::ImageProcessor.image?("PHOTO.JPG").should be_true
      Hwaro::Content::Processors::ImageProcessor.image?("Image.PNG").should be_true
    end

    it "returns false for empty string" do
      Hwaro::Content::Processors::ImageProcessor.image?("").should be_false
    end

    it "returns false for extensionless file" do
      Hwaro::Content::Processors::ImageProcessor.image?("Makefile").should be_false
    end
  end

  describe ".resized_filename" do
    it "generates width-based filename" do
      Hwaro::Content::Processors::ImageProcessor.resized_filename("photo.jpg", 800).should eq("photo_800w.jpg")
    end

    it "preserves directory path" do
      Hwaro::Content::Processors::ImageProcessor.resized_filename("images/photo.png", 320).should eq("images/photo_320w.png")
    end

    it "handles filenames with dots" do
      Hwaro::Content::Processors::ImageProcessor.resized_filename("my.photo.jpg", 640).should eq("my.photo_640w.jpg")
    end

    it "handles nested directory paths" do
      Hwaro::Content::Processors::ImageProcessor.resized_filename("a/b/c/img.png", 100).should eq("a/b/c/img_100w.png")
    end
  end

  describe ".resize" do
    it "resizes a PNG image and verifies dimensions" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "test.png")
        dest = File.join(dir, "test_2w.png")

        pixels = Bytes.new(4 * 4 * 3, 255_u8)
        LibStb.stbi_write_png(src, 4, 4, 3, pixels.to_unsafe.as(Void*), 4 * 3)

        result = Hwaro::Content::Processors::ImageProcessor.resize(src, dest, 2, 0, 85)
        result.should eq(dest)
        File.exists?(dest).should be_true

        w = uninitialized LibC::Int
        h = uninitialized LibC::Int
        c = uninitialized LibC::Int
        out_pixels = LibStb.stbi_load(dest, pointerof(w), pointerof(h), pointerof(c), 0)
        out_pixels.null?.should be_false
        w.should eq(2)
        h.should eq(2)
        LibStb.stbi_image_free(out_pixels.as(Void*))
      end
    end

    it "resizes a JPG image" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "test.jpg")
        dest = File.join(dir, "test_2w.jpg")

        pixels = Bytes.new(4 * 4 * 3, 128_u8)
        LibStb.stbi_write_jpg(src, 4, 4, 3, pixels.to_unsafe.as(Void*), 90)

        result = Hwaro::Content::Processors::ImageProcessor.resize(src, dest, 2, 0, 85)
        result.should eq(dest)
        File.exists?(dest).should be_true
      end
    end

    it "resizes a BMP image" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "test.bmp")
        dest = File.join(dir, "test_2w.bmp")

        pixels = Bytes.new(4 * 4 * 3, 100_u8)
        LibStb.stbi_write_bmp(src, 4, 4, 3, pixels.to_unsafe.as(Void*))

        result = Hwaro::Content::Processors::ImageProcessor.resize(src, dest, 2, 0, 85)
        result.should eq(dest)
        File.exists?(dest).should be_true
      end
    end

    it "handles RGBA (4-channel) images" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "rgba.png")
        dest = File.join(dir, "rgba_2w.png")

        # 4 channels (RGBA)
        pixels = Bytes.new(4 * 4 * 4, 200_u8)
        LibStb.stbi_write_png(src, 4, 4, 4, pixels.to_unsafe.as(Void*), 4 * 4)

        result = Hwaro::Content::Processors::ImageProcessor.resize(src, dest, 2, 0, 85)
        result.should eq(dest)

        w = uninitialized LibC::Int
        h = uninitialized LibC::Int
        c = uninitialized LibC::Int
        out_pixels = LibStb.stbi_load(dest, pointerof(w), pointerof(h), pointerof(c), 0)
        out_pixels.null?.should be_false
        w.should eq(2)
        h.should eq(2)
        c.should eq(4) # channels preserved
        LibStb.stbi_image_free(out_pixels.as(Void*))
      end
    end

    it "returns nil for non-existent file" do
      result = Hwaro::Content::Processors::ImageProcessor.resize("/nonexistent.png", "/tmp/out.png", 100)
      result.should be_nil
    end

    it "returns nil for corrupted file" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "corrupt.png")
        dest = File.join(dir, "corrupt_2w.png")
        File.write(src, "this is not an image")

        result = Hwaro::Content::Processors::ImageProcessor.resize(src, dest, 2)
        result.should be_nil
        File.exists?(dest).should be_false
      end
    end

    it "copies file when target width >= source width" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "small.png")
        dest = File.join(dir, "small_1000w.png")

        pixels = Bytes.new(4 * 4 * 3, 200_u8)
        LibStb.stbi_write_png(src, 4, 4, 3, pixels.to_unsafe.as(Void*), 4 * 3)

        result = Hwaro::Content::Processors::ImageProcessor.resize(src, dest, 1000, 0, 85)
        result.should eq(dest)
        File.exists?(dest).should be_true
        File.size(dest).should eq(File.size(src))
      end
    end

    it "clamps quality to valid range" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "test.jpg")
        dest = File.join(dir, "test_2w.jpg")

        pixels = Bytes.new(4 * 4 * 3, 100_u8)
        LibStb.stbi_write_jpg(src, 4, 4, 3, pixels.to_unsafe.as(Void*), 90)

        # quality = 0 should be clamped to 1, not crash
        result = Hwaro::Content::Processors::ImageProcessor.resize(src, dest, 2, 0, 0)
        result.should eq(dest)
      end
    end

    it "preserves aspect ratio with width-only resize" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "wide.png")
        dest = File.join(dir, "wide_5w.png")

        # Create 10x4 image
        pixels = Bytes.new(10 * 4 * 3, 150_u8)
        LibStb.stbi_write_png(src, 10, 4, 3, pixels.to_unsafe.as(Void*), 10 * 3)

        result = Hwaro::Content::Processors::ImageProcessor.resize(src, dest, 5, 0, 85)
        result.should eq(dest)

        w = uninitialized LibC::Int
        h = uninitialized LibC::Int
        c = uninitialized LibC::Int
        out_pixels = LibStb.stbi_load(dest, pointerof(w), pointerof(h), pointerof(c), 0)
        out_pixels.null?.should be_false
        w.should eq(5)
        h.should eq(2) # 4 * (5/10) = 2
        LibStb.stbi_image_free(out_pixels.as(Void*))
      end
    end

    it "preserves aspect ratio with height-only resize" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "tall.png")
        dest = File.join(dir, "tall_h2.png")

        # Create 4x10 image
        pixels = Bytes.new(4 * 10 * 3, 150_u8)
        LibStb.stbi_write_png(src, 4, 10, 3, pixels.to_unsafe.as(Void*), 4 * 3)

        result = Hwaro::Content::Processors::ImageProcessor.resize(src, dest, 0, 5, 85)
        result.should eq(dest)

        w = uninitialized LibC::Int
        h = uninitialized LibC::Int
        c = uninitialized LibC::Int
        out_pixels = LibStb.stbi_load(dest, pointerof(w), pointerof(h), pointerof(c), 0)
        out_pixels.null?.should be_false
        w.should eq(2) # 4 * (5/10) = 2
        h.should eq(5)
        LibStb.stbi_image_free(out_pixels.as(Void*))
      end
    end

    it "fits within box when both width and height specified" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "rect.png")
        dest = File.join(dir, "rect_fit.png")

        # Create 20x10 image, fit into 5x5 box -> should be 5x2 (limited by width)
        pixels = Bytes.new(20 * 10 * 3, 150_u8)
        LibStb.stbi_write_png(src, 20, 10, 3, pixels.to_unsafe.as(Void*), 20 * 3)

        result = Hwaro::Content::Processors::ImageProcessor.resize(src, dest, 5, 5, 85)
        result.should eq(dest)

        w = uninitialized LibC::Int
        h = uninitialized LibC::Int
        c = uninitialized LibC::Int
        out_pixels = LibStb.stbi_load(dest, pointerof(w), pointerof(h), pointerof(c), 0)
        out_pixels.null?.should be_false
        # scale = min(5/20, 5/10) = min(0.25, 0.5) = 0.25
        # w=20*0.25=5, h=10*0.25=2.5 -> round=2 (banker's rounding)
        w.should eq(5)
        h.should eq(2)
        LibStb.stbi_image_free(out_pixels.as(Void*))
      end
    end

    it "creates destination directory if missing" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "test.png")
        dest = File.join(dir, "sub", "dir", "test_2w.png")

        pixels = Bytes.new(4 * 4 * 3, 255_u8)
        LibStb.stbi_write_png(src, 4, 4, 3, pixels.to_unsafe.as(Void*), 4 * 3)

        result = Hwaro::Content::Processors::ImageProcessor.resize(src, dest, 2, 0, 85)
        result.should eq(dest)
        File.exists?(dest).should be_true
      end
    end
  end

  describe ".process_configured_widths" do
    it "generates multiple resized variants" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "photo.png")
        pixels = Bytes.new(100 * 80 * 3, 150_u8)
        LibStb.stbi_write_png(src, 100, 80, 3, pixels.to_unsafe.as(Void*), 100 * 3)

        output_base = File.join(dir, "out")
        Dir.mkdir(output_base)

        results = Hwaro::Content::Processors::ImageProcessor.process_configured_widths(
          src, output_base, "/images", [20, 50], 85
        )

        results.size.should eq(2)
        results[0][1].should eq(20)
        results[0][2].should eq("/images/photo_20w.png")
        results[1][1].should eq(50)
        results[1][2].should eq("/images/photo_50w.png")

        File.exists?(File.join(output_base, "photo_20w.png")).should be_true
        File.exists?(File.join(output_base, "photo_50w.png")).should be_true
      end
    end

    it "returns empty array for non-existent source" do
      results = Hwaro::Content::Processors::ImageProcessor.process_configured_widths(
        "/nonexistent.png", "/tmp", "/images", [100], 85
      )
      results.should be_empty
    end

    it "skips widths larger than source" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "tiny.png")
        pixels = Bytes.new(4 * 4 * 3, 150_u8)
        LibStb.stbi_write_png(src, 4, 4, 3, pixels.to_unsafe.as(Void*), 4 * 3)

        output_base = File.join(dir, "out")
        Dir.mkdir(output_base)

        # width=2 will resize, width=1000 will copy (still succeeds)
        results = Hwaro::Content::Processors::ImageProcessor.process_configured_widths(
          src, output_base, "/img", [2, 1000], 85
        )
        results.size.should eq(2)
      end
    end
  end

  describe ".resize_multi_widths" do
    it "decodes once and generates all widths" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "photo.png")
        pixels = Bytes.new(100 * 80 * 3, 150_u8)
        LibStb.stbi_write_png(src, 100, 80, 3, pixels.to_unsafe.as(Void*), 100 * 3)

        out_dir = File.join(dir, "out")
        result = Hwaro::Content::Processors::ImageProcessor.resize_multi_widths(src, out_dir, [20, 50], 85)

        result.size.should eq(2)
        result.has_key?(20).should be_true
        result.has_key?(50).should be_true
        File.exists?(result[20]).should be_true
        File.exists?(result[50]).should be_true
      end
    end

    it "returns empty hash for non-existent source" do
      result = Hwaro::Content::Processors::ImageProcessor.resize_multi_widths("/nonexistent.png", "/tmp", [100], 85)
      result.should be_empty
    end

    it "returns empty hash for corrupted file" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "corrupt.png")
        File.write(src, "not an image")
        result = Hwaro::Content::Processors::ImageProcessor.resize_multi_widths(src, dir, [100], 85)
        result.should be_empty
      end
    end

    it "copies file for widths larger than source" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "tiny.png")
        pixels = Bytes.new(4 * 4 * 3, 150_u8)
        LibStb.stbi_write_png(src, 4, 4, 3, pixels.to_unsafe.as(Void*), 4 * 3)

        out_dir = File.join(dir, "out")
        result = Hwaro::Content::Processors::ImageProcessor.resize_multi_widths(src, out_dir, [2, 1000], 85)

        result.size.should eq(2)
        # width=1000 should be a copy (same size as original)
        File.size(result[1000]).should eq(File.size(src))
      end
    end

    it "handles RGBA images" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "rgba.png")
        pixels = Bytes.new(20 * 20 * 4, 200_u8)
        LibStb.stbi_write_png(src, 20, 20, 4, pixels.to_unsafe.as(Void*), 20 * 4)

        out_dir = File.join(dir, "out")
        result = Hwaro::Content::Processors::ImageProcessor.resize_multi_widths(src, out_dir, [10], 85)

        result.size.should eq(1)
        # Verify output dimensions
        w = uninitialized LibC::Int
        h = uninitialized LibC::Int
        c = uninitialized LibC::Int
        out_pixels = LibStb.stbi_load(result[10], pointerof(w), pointerof(h), pointerof(c), 0)
        out_pixels.null?.should be_false
        w.should eq(10)
        h.should eq(10)
        c.should eq(4)
        LibStb.stbi_image_free(out_pixels.as(Void*))
      end
    end
  end
end

describe Hwaro::Content::Hooks::ImageHooks do
  # Helper to set up and tear down test resize map
  before_each do
    Hwaro::Content::Hooks::ImageHooks.set_resize_map({
      "/images/photo.jpg" => {
        320  => "/images/photo_320w.jpg",
        640  => "/images/photo_640w.jpg",
        1024 => "/images/photo_1024w.jpg",
      } of Int32 => String,
    } of String => Hash(Int32, String))
  end

  after_each do
    Hwaro::Content::Hooks::ImageHooks.set_resize_map({} of String => Hash(Int32, String))
  end

  describe ".find_resized" do
    it "returns exact match" do
      Hwaro::Content::Hooks::ImageHooks.find_resized("/images/photo.jpg", 640).should eq("/images/photo_640w.jpg")
    end

    it "returns nil for non-matching width" do
      Hwaro::Content::Hooks::ImageHooks.find_resized("/images/photo.jpg", 500).should be_nil
    end

    it "returns nil for unknown URL" do
      Hwaro::Content::Hooks::ImageHooks.find_resized("/nonexistent.jpg", 640).should be_nil
    end
  end

  describe ".find_closest" do
    it "returns exact match when available" do
      Hwaro::Content::Hooks::ImageHooks.find_closest("/images/photo.jpg", 640).should eq("/images/photo_640w.jpg")
    end

    it "returns smallest width >= requested" do
      # Request 500 -> should get 640 (smallest >= 500)
      Hwaro::Content::Hooks::ImageHooks.find_closest("/images/photo.jpg", 500).should eq("/images/photo_640w.jpg")
    end

    it "returns smallest width >= requested (boundary)" do
      # Request 321 -> should get 640 (320 < 321, so 640 is smallest >=)
      Hwaro::Content::Hooks::ImageHooks.find_closest("/images/photo.jpg", 321).should eq("/images/photo_640w.jpg")
    end

    it "falls back to largest when nothing >= requested" do
      # Request 2000 -> nothing >= 2000, fall back to largest (1024)
      Hwaro::Content::Hooks::ImageHooks.find_closest("/images/photo.jpg", 2000).should eq("/images/photo_1024w.jpg")
    end

    it "returns smallest width for very small request" do
      # Request 1 -> should get 320 (smallest >= 1)
      Hwaro::Content::Hooks::ImageHooks.find_closest("/images/photo.jpg", 1).should eq("/images/photo_320w.jpg")
    end

    it "returns nil for unknown URL" do
      Hwaro::Content::Hooks::ImageHooks.find_closest("/nonexistent.jpg", 800).should be_nil
    end
  end

  describe ".resize_map" do
    it "returns a snapshot copy" do
      map = Hwaro::Content::Hooks::ImageHooks.resize_map
      map.should be_a(Hash(String, Hash(Int32, String)))
      map.has_key?("/images/photo.jpg").should be_true
    end
  end
end

describe Hwaro::Models::ImageProcessingConfig do
  it "has sensible defaults" do
    config = Hwaro::Models::ImageProcessingConfig.new
    config.enabled.should be_false
    config.widths.should eq([] of Int32)
    config.quality.should eq(85)
  end
end

describe "Config.load image_processing" do
  it "loads image_processing from TOML" do
    Dir.cd(Dir.tempdir) do
      File.write("config.toml", <<-TOML
        title = "Test"
        [image_processing]
        enabled = true
        widths = [320, 640, 1024]
        quality = 90
        TOML
      )
      config = Hwaro::Models::Config.load
      config.image_processing.enabled.should be_true
      config.image_processing.widths.should eq([320, 640, 1024])
      config.image_processing.quality.should eq(90)
    end
  end

  it "uses defaults when not specified" do
    Dir.cd(Dir.tempdir) do
      File.write("config.toml", "title = \"Test\"")
      config = Hwaro::Models::Config.load
      config.image_processing.enabled.should be_false
      config.image_processing.widths.should eq([] of Int32)
      config.image_processing.quality.should eq(85)
    end
  end

  it "filters out zero and negative widths" do
    Dir.cd(Dir.tempdir) do
      File.write("config.toml", <<-TOML
        title = "Test"
        [image_processing]
        enabled = true
        widths = [0, -100, 320, 640]
        TOML
      )
      config = Hwaro::Models::Config.load
      config.image_processing.widths.should eq([320, 640])
    end
  end

  it "clamps quality to 1-100" do
    Dir.cd(Dir.tempdir) do
      File.write("config.toml", <<-TOML
        title = "Test"
        [image_processing]
        quality = 0
        TOML
      )
      config = Hwaro::Models::Config.load
      config.image_processing.quality.should eq(1)
    end
  end

  it "clamps quality over 100 down to 100" do
    Dir.cd(Dir.tempdir) do
      File.write("config.toml", <<-TOML
        title = "Test"
        [image_processing]
        quality = 200
        TOML
      )
      config = Hwaro::Models::Config.load
      config.image_processing.quality.should eq(100)
    end
  end
end
