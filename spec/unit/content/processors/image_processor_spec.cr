require "../../../spec_helper"
require "../../../../src/content/processors/image_processor"

# One variant through the build's resize path (`resize_and_lqip`, no LQIP),
# written next to the source as `<name>_<width>w.<ext>`.
private def resize_variant(src : String, width : Int32, quality : Int32 = 85) : String?
  Hwaro::Content::Processors::ImageProcessor.resize_and_lqip(src, File.dirname(src), [width], quality, 0)[0].values.first?
end

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

  describe ".resize_and_lqip variants" do
    it "resizes a PNG image and verifies dimensions" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "test.png")
        dest = File.join(dir, "test_2w.png")

        pixels = Bytes.new(4 * 4 * 3, 255_u8)
        LibStb.stbi_write_png(src, 4, 4, 3, pixels.to_unsafe.as(Void*), 4 * 3)

        result = resize_variant(src, 2, 85)
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

        result = resize_variant(src, 2, 85)
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

        result = resize_variant(src, 2, 85)
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

        result = resize_variant(src, 2, 85)
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

    # Regression: stb's writers open the destination with O_TRUNC and then
    # stream the encoded bytes, so a variant being regenerated (serve rebuild,
    # warm `--cache` build) was observably 0 bytes and then every intermediate
    # size — and `hwaro serve` streams that very `_32w.png` to the browser from
    # a fiber of the same process. The window is not deterministic in a spec, so
    # assert the property behind it: a reader holding the old variant open
    # across the regeneration must keep seeing it whole. The second run encodes
    # different pixels, so a truncate-in-place writer would hand the reader the
    # new bytes.
    it "replaces an existing variant atomically instead of truncating it" do
      posix_only!("Windows can't rename over a file that is open")
      Dir.mktmpdir do |dir|
        src = File.join(dir, "photo.png")
        dest = File.join(dir, "photo_32w.png")

        white = Bytes.new(64 * 64 * 3, 255_u8)
        LibStb.stbi_write_png(src, 64, 64, 3, white.to_unsafe.as(Void*), 64 * 3)
        resize_variant(src, 32, 85).should eq(dest)
        first = File.open(dest, &.getb_to_end)

        reader = File.open(dest)
        begin
          black = Bytes.new(64 * 64 * 3, 0_u8)
          LibStb.stbi_write_png(src, 64, 64, 3, black.to_unsafe.as(Void*), 64 * 3)
          resize_variant(src, 32, 85).should eq(dest)

          reader.getb_to_end.should eq(first)
        ensure
          reader.close
        end

        File.open(dest, &.getb_to_end).should_not eq(first)
        Dir.glob(File.join(dir, "*.tmp")).should be_empty
      end
    end

    # Same invariant for the no-upscale branch, which copies the source
    # verbatim instead of encoding.
    it "replaces a copied too-small variant atomically" do
      posix_only!("Windows can't rename over a file that is open")
      Dir.mktmpdir do |dir|
        src = File.join(dir, "small.png")
        dest = File.join(dir, "small_8w.png")

        white = Bytes.new(8 * 8 * 3, 255_u8)
        LibStb.stbi_write_png(src, 8, 8, 3, white.to_unsafe.as(Void*), 8 * 3)
        resize_variant(src, 1000, 85).should eq(dest)
        first = File.open(dest, &.getb_to_end)

        reader = File.open(dest)
        begin
          black = Bytes.new(8 * 8 * 3, 0_u8)
          LibStb.stbi_write_png(src, 8, 8, 3, black.to_unsafe.as(Void*), 8 * 3)
          resize_variant(src, 1000, 85).should eq(dest)

          reader.getb_to_end.should eq(first)
        ensure
          reader.close
        end

        Dir.glob(File.join(dir, "*.tmp")).should be_empty
      end
    end

    it "clamps quality to valid range" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "test.jpg")
        dest = File.join(dir, "test_2w.jpg")

        pixels = Bytes.new(4 * 4 * 3, 100_u8)
        LibStb.stbi_write_jpg(src, 4, 4, 3, pixels.to_unsafe.as(Void*), 90)

        # quality = 0 should be clamped to 1, not crash
        result = resize_variant(src, 2, 0)
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

        result = resize_variant(src, 5, 85)
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
  end

  describe ".resize_and_lqip widths" do
    it "decodes once and generates all widths" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "photo.png")
        pixels = Bytes.new(100 * 80 * 3, 150_u8)
        LibStb.stbi_write_png(src, 100, 80, 3, pixels.to_unsafe.as(Void*), 100 * 3)

        out_dir = File.join(dir, "out")
        result = Hwaro::Content::Processors::ImageProcessor.resize_and_lqip(src, out_dir, [20, 50], 85, 0)[0]

        result.size.should eq(2)
        result.has_key?(20).should be_true
        result.has_key?(50).should be_true
        File.exists?(result[20]).should be_true
        File.exists?(result[50]).should be_true
      end
    end

    it "returns empty hash for non-existent source" do
      result = Hwaro::Content::Processors::ImageProcessor.resize_and_lqip("/nonexistent.png", "/tmp", [100], 85, 0)[0]
      result.should be_empty
    end

    it "returns empty hash for corrupted file" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "corrupt.png")
        File.write(src, "not an image")
        result = Hwaro::Content::Processors::ImageProcessor.resize_and_lqip(src, dir, [100], 85, 0)[0]
        result.should be_empty
      end
    end

    it "keys an upscale-clamped variant by the true source width, not the requested width" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "tiny.png")
        pixels = Bytes.new(4 * 4 * 3, 150_u8)
        LibStb.stbi_write_png(src, 4, 4, 3, pixels.to_unsafe.as(Void*), 4 * 3)

        out_dir = File.join(dir, "out")
        result = Hwaro::Content::Processors::ImageProcessor.resize_and_lqip(src, out_dir, [2, 1000], 85, 0)[0]

        # width=2 downscales; width=1000 exceeds the 4px source, so rather than a
        # dishonest "1000w" copy it is keyed at the true intrinsic width (4) — no
        # false srcset descriptor, no byte-identical duplicate.
        result.size.should eq(2)
        result.has_key?(2).should be_true
        result.has_key?(1000).should be_false
        File.size(result[4]).should eq(File.size(src)) # full-size copy keyed by src width
      end
    end

    it "handles RGBA images" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "rgba.png")
        pixels = Bytes.new(20 * 20 * 4, 200_u8)
        LibStb.stbi_write_png(src, 20, 20, 4, pixels.to_unsafe.as(Void*), 20 * 4)

        out_dir = File.join(dir, "out")
        result = Hwaro::Content::Processors::ImageProcessor.resize_and_lqip(src, out_dir, [10], 85, 0)[0]

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

# Exposes the private dimension math so the saturation guard can be asserted
# without producing a multi-gigapixel image.
module Hwaro::Content::Processors
  module ImageProcessor
    def self.calculate_dimensions_for_test(src_w, src_h, target_w)
      calculate_dimensions(src_w, src_h, target_w)
    end
  end
end

describe "ImageProcessor#calculate_dimensions overflow" do
  # `[image_processing] widths` is only bounded below (`> 0`), so an absurd
  # entry made the proportional side exceed Int32 and `.round.to_i32` raised a
  # bare OverflowError — an unclassified crash of the whole build rather than a
  # skipped variant. It now saturates so the MAX_PIXELS guard can decline it.
  it "saturates instead of raising for an oversized target width" do
    w, h = Hwaro::Content::Processors::ImageProcessor
      .calculate_dimensions_for_test(200, 500, 2_000_000_000)
    w.should eq(2_000_000_000)
    h.should eq(Int32::MAX)
  end

  it "saturates instead of raising for an extreme source aspect ratio" do
    Hwaro::Content::Processors::ImageProcessor
      .calculate_dimensions_for_test(1, 2_000_000_000, 2_000_000_000)
      .last.should eq(Int32::MAX)
  end

  it "leaves ordinary proportional scaling unchanged" do
    Hwaro::Content::Processors::ImageProcessor
      .calculate_dimensions_for_test(200, 500, 100).should eq({100, 250})
  end

  it "never returns a dimension below 1" do
    w, h = Hwaro::Content::Processors::ImageProcessor
      .calculate_dimensions_for_test(10_000, 3, 1)
    w.should eq(1)
    h.should eq(1)
  end
end

describe Hwaro::Content::Hooks::ImageHooks do
  # Helper to set up and tear down test resize map
  before_each do
    Hwaro::Content::Hooks::ImageHooks.set_resize_map({
      "/images/photo.jpg" => {
         320 => "/images/photo_320w.jpg",
         640 => "/images/photo_640w.jpg",
        1024 => "/images/photo_1024w.jpg",
      } of Int32 => String,
    } of String => Hash(Int32, String))
  end

  after_each do
    Hwaro::Content::Hooks::ImageHooks.set_resize_map({} of String => Hash(Int32, String))
  end

  describe ".find_closest_variant" do
    it "returns exact match when available" do
      Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/images/photo.jpg", 640).try(&.[1]).should eq("/images/photo_640w.jpg")
    end

    it "returns smallest width >= requested" do
      # Request 500 -> should get 640 (smallest >= 500)
      Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/images/photo.jpg", 500).try(&.[1]).should eq("/images/photo_640w.jpg")
    end

    it "returns smallest width >= requested (boundary)" do
      # Request 321 -> should get 640 (320 < 321, so 640 is smallest >=)
      Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/images/photo.jpg", 321).try(&.[1]).should eq("/images/photo_640w.jpg")
    end

    it "falls back to largest when nothing >= requested" do
      # Request 2000 -> nothing >= 2000, fall back to largest (1024)
      Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/images/photo.jpg", 2000).try(&.[1]).should eq("/images/photo_1024w.jpg")
    end

    it "returns smallest width for very small request" do
      # Request 1 -> should get 320 (smallest >= 1)
      Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/images/photo.jpg", 1).try(&.[1]).should eq("/images/photo_320w.jpg")
    end

    it "returns nil for unknown URL" do
      Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/nonexistent.jpg", 800).should be_nil
    end
  end
end

describe Hwaro::Content::Processors::ImageProcessor do
  describe ".generate_lqip_with_color" do
    it "generates a base64 data URI from pixel data" do
      # Create a 20x20 RGB image in memory
      w = 20_i32
      h = 20_i32
      channels = 3_i32
      pixel_data = Bytes.new(w * h * channels, 128_u8)

      result = Hwaro::Content::Processors::ImageProcessor.generate_lqip_with_color(
        pixel_data.to_unsafe, w, h, channels, 8, 20
      )
      result.should_not be_nil
      result.not_nil![0].starts_with?("data:image/jpeg;base64,").should be_true
    end

    it "returns nil for invalid dimensions" do
      pixels = Bytes.new(1, 0_u8)
      result = Hwaro::Content::Processors::ImageProcessor.generate_lqip_with_color(
        pixels.to_unsafe, 0, 0, 3, 8, 20
      )
      result.should be_nil
    end

    it "returns nil when lqip_width is zero" do
      pixel_data = Bytes.new(20 * 20 * 3, 128_u8)
      result = Hwaro::Content::Processors::ImageProcessor.generate_lqip_with_color(
        pixel_data.to_unsafe, 20, 20, 3, 0, 20
      )
      result.should be_nil
    end

    it "handles RGBA images" do
      w = 16_i32
      h = 16_i32
      channels = 4_i32
      pixel_data = Bytes.new(w * h * channels, 200_u8)

      result = Hwaro::Content::Processors::ImageProcessor.generate_lqip_with_color(
        pixel_data.to_unsafe, w, h, channels, 8, 20
      )
      result.should_not be_nil
      result.not_nil![0].starts_with?("data:image/jpeg;base64,").should be_true
    end

    # JPEG has no alpha: the placeholder used to keep the black color bytes
    # under transparent pixels, so a logo's transparent border went black.
    it "flattens transparent pixels onto white and weights the color by alpha" do
      w = 16_i32
      h = 16_i32
      pixel_data = Bytes.new(w * h * 4, 0_u8) # transparent black
      (4...12).each do |y|
        (4...12).each do |x|
          o = (y * w + x) * 4
          pixel_data[o] = 255_u8     # R
          pixel_data[o + 3] = 255_u8 # A
        end
      end

      result = Hwaro::Content::Processors::ImageProcessor.generate_lqip_with_color(
        pixel_data.to_unsafe, w, h, 4, 16, 90
      ).not_nil!
      result[1].should eq("#ff0000")

      Dir.mktmpdir do |dir|
        jpg = File.join(dir, "lqip.jpg")
        File.write(jpg, Base64.decode(result[0].lchop("data:image/jpeg;base64,")))
        jw = uninitialized LibC::Int
        jh = uninitialized LibC::Int
        jc = uninitialized LibC::Int
        decoded = LibStb.stbi_load(jpg, pointerof(jw), pointerof(jh), pointerof(jc), 3)
        begin
          3.times { |c| decoded[c].should be > 240 } # top-left corner is white
        ensure
          LibStb.stbi_image_free(decoded.as(Void*))
        end
      end
    end
  end

  describe ".dominant_color" do
    it "computes average color as hex string" do
      w = 2_i32
      h = 2_i32
      channels = 3_i32
      # All pixels are (100, 150, 200)
      pixel_data = Bytes.new(w * h * channels)
      (w * h).times do |i|
        pixel_data[i * 3] = 100_u8
        pixel_data[i * 3 + 1] = 150_u8
        pixel_data[i * 3 + 2] = 200_u8
      end

      result = Hwaro::Content::Processors::ImageProcessor.dominant_color(
        pixel_data.to_unsafe, w, h, channels
      )
      result.should eq("#6496c8")
    end

    it "returns #000000 for invalid dimensions" do
      pixels = Bytes.new(1, 0_u8)
      result = Hwaro::Content::Processors::ImageProcessor.dominant_color(
        pixels.to_unsafe, 0, 0, 3
      )
      result.should eq("#000000")
    end

    it "handles grayscale images" do
      w = 2_i32
      h = 2_i32
      channels = 1_i32
      pixel_data = Bytes.new(w * h * channels, 128_u8)

      result = Hwaro::Content::Processors::ImageProcessor.dominant_color(
        pixel_data.to_unsafe, w, h, channels
      )
      result.should eq("#808080")
    end

    it "treats 2-channel (gray+alpha) as grayscale" do
      w = 2_i32
      h = 2_i32
      channels = 2_i32
      pixel_data = Bytes.new(w * h * channels)
      (w * h).times do |i|
        pixel_data[i * 2] = 100_u8     # gray
        pixel_data[i * 2 + 1] = 255_u8 # alpha
      end

      result = Hwaro::Content::Processors::ImageProcessor.dominant_color(
        pixel_data.to_unsafe, w, h, channels
      )
      result.should eq("#646464") # 100 = 0x64, all RGB channels same
    end

    it "leaves the RGBA average unchanged under uniform alpha" do
      w = 2_i32
      h = 2_i32
      channels = 4_i32
      pixel_data = Bytes.new(w * h * channels)
      (w * h).times do |i|
        pixel_data[i * 4] = 100_u8     # R
        pixel_data[i * 4 + 1] = 150_u8 # G
        pixel_data[i * 4 + 2] = 200_u8 # B
        pixel_data[i * 4 + 3] = 50_u8  # A
      end

      result = Hwaro::Content::Processors::ImageProcessor.dominant_color(
        pixel_data.to_unsafe, w, h, channels
      )
      result.should eq("#6496c8")
    end
  end

  describe ".resize_and_lqip" do
    it "resizes and generates LQIP in one pass" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "photo.png")
        pixels = Bytes.new(100 * 80 * 3, 150_u8)
        LibStb.stbi_write_png(src, 100, 80, 3, pixels.to_unsafe.as(Void*), 100 * 3)

        out_dir = File.join(dir, "out")
        result_map, lqip_uri, dom_color = Hwaro::Content::Processors::ImageProcessor.resize_and_lqip(
          src, out_dir, [20, 50], 85, 16, 20
        )

        result_map.size.should eq(2)
        result_map.has_key?(20).should be_true
        result_map.has_key?(50).should be_true

        lqip_uri.should_not be_nil
        lqip_uri.not_nil!.starts_with?("data:image/jpeg;base64,").should be_true

        dom_color.should eq("#969696") # 150 = 0x96
      end
    end

    it "skips LQIP when lqip_width is 0" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "photo.png")
        pixels = Bytes.new(20 * 20 * 3, 150_u8)
        LibStb.stbi_write_png(src, 20, 20, 3, pixels.to_unsafe.as(Void*), 20 * 3)

        out_dir = File.join(dir, "out")
        result_map, lqip_uri, dom_color = Hwaro::Content::Processors::ImageProcessor.resize_and_lqip(
          src, out_dir, [10], 85, 0, 20
        )

        result_map.size.should eq(1)
        lqip_uri.should be_nil
        dom_color.should eq("#000000")
      end
    end

    it "returns empty results for non-existent source" do
      result_map, lqip_uri, _dom_color = Hwaro::Content::Processors::ImageProcessor.resize_and_lqip(
        "/nonexistent.png", "/tmp", [100], 85, 16, 20
      )
      result_map.should be_empty
      lqip_uri.should be_nil
    end

    it "handles RGBA (4-channel) images with LQIP" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "rgba.png")
        pixels = Bytes.new(40 * 40 * 4, 180_u8)
        LibStb.stbi_write_png(src, 40, 40, 4, pixels.to_unsafe.as(Void*), 40 * 4)

        out_dir = File.join(dir, "out")
        result_map, lqip_uri, dom_color = Hwaro::Content::Processors::ImageProcessor.resize_and_lqip(
          src, out_dir, [20], 85, 16, 20
        )

        result_map.size.should eq(1)
        lqip_uri.should_not be_nil
        lqip_uri.not_nil!.starts_with?("data:image/jpeg;base64,").should be_true
        dom_color.should_not eq("#000000")
      end
    end

    it "handles grayscale (1-channel) images with LQIP" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "gray.png")
        pixels = Bytes.new(40 * 40 * 1, 100_u8)
        LibStb.stbi_write_png(src, 40, 40, 1, pixels.to_unsafe.as(Void*), 40 * 1)

        out_dir = File.join(dir, "out")
        result_map, lqip_uri, dom_color = Hwaro::Content::Processors::ImageProcessor.resize_and_lqip(
          src, out_dir, [20], 85, 16, 20
        )

        result_map.size.should eq(1)
        lqip_uri.should_not be_nil
        lqip_uri.not_nil!.starts_with?("data:image/jpeg;base64,").should be_true
        dom_color.should eq("#646464") # 100 = 0x64
      end
    end

    it "does not upscale when source is smaller than lqip_width" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "tiny.png")
        pixels = Bytes.new(8 * 8 * 3, 200_u8)
        LibStb.stbi_write_png(src, 8, 8, 3, pixels.to_unsafe.as(Void*), 8 * 3)

        out_dir = File.join(dir, "out")
        _result_map, lqip_uri, _dom_color = Hwaro::Content::Processors::ImageProcessor.resize_and_lqip(
          src, out_dir, [4], 85, 32, 20 # lqip_width=32 > src=8
        )

        # Should still produce LQIP (at src width, not upscaled to 32)
        lqip_uri.should_not be_nil
      end
    end
  end
end

describe Hwaro::Content::Hooks::ImageHooks do
  describe ".find_lqip" do
    it "returns LQIP data when set" do
      Hwaro::Content::Hooks::ImageHooks.set_lqip_map({
        "/images/photo.jpg" => {
          "lqip"           => "data:image/jpeg;base64,abc",
          "dominant_color" => "#ff0000",
        },
      })

      result = Hwaro::Content::Hooks::ImageHooks.find_lqip("/images/photo.jpg")
      result.should_not be_nil
      result.not_nil!["lqip"].should eq("data:image/jpeg;base64,abc")
      result.not_nil!["dominant_color"].should eq("#ff0000")

      Hwaro::Content::Hooks::ImageHooks.set_lqip_map({} of String => Hash(String, String))
    end

    it "returns nil for unknown URL" do
      Hwaro::Content::Hooks::ImageHooks.set_lqip_map({} of String => Hash(String, String))
      Hwaro::Content::Hooks::ImageHooks.find_lqip("/nonexistent.jpg").should be_nil
    end
  end
end

describe Hwaro::Models::ImageProcessingConfig do
  it "has sensible defaults" do
    config = Hwaro::Models::ImageProcessingConfig.new
    config.enabled.should be_false
    config.widths.should eq([] of Int32)
    config.quality.should eq(85)
    config.lqip_enabled.should be_false
    config.lqip_width.should eq(32)
    config.lqip_quality.should eq(20)
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

  it "loads LQIP config from TOML" do
    Dir.cd(Dir.tempdir) do
      File.write("config.toml", <<-TOML
        title = "Test"
        [image_processing]
        enabled = true
        widths = [320]
        [image_processing.lqip]
        enabled = true
        width = 48
        quality = 30
        TOML
      )
      config = Hwaro::Models::Config.load
      config.image_processing.lqip_enabled.should be_true
      config.image_processing.lqip_width.should eq(48)
      config.image_processing.lqip_quality.should eq(30)
    end
  end

  it "clamps LQIP width to 8-128" do
    Dir.cd(Dir.tempdir) do
      File.write("config.toml", <<-TOML
        title = "Test"
        [image_processing.lqip]
        enabled = true
        width = 2
        TOML
      )
      config = Hwaro::Models::Config.load
      config.image_processing.lqip_width.should eq(8)
    end
  end

  it "uses LQIP defaults when not specified" do
    Dir.cd(Dir.tempdir) do
      File.write("config.toml", <<-TOML
        title = "Test"
        [image_processing]
        enabled = true
        TOML
      )
      config = Hwaro::Models::Config.load
      config.image_processing.lqip_enabled.should be_false
      config.image_processing.lqip_width.should eq(32)
      config.image_processing.lqip_quality.should eq(20)
    end
  end
end

private def write_bytes(dir : String, name : String, bytes : Bytes) : String
  path = File.join(dir, name)
  File.write(path, bytes)
  path
end

private def le16(v : Int32) : Array(UInt8)
  [(v & 0xFF).to_u8, ((v >> 8) & 0xFF).to_u8]
end

private def le24(v : Int32) : Array(UInt8)
  le16(v) + [((v >> 16) & 0xFF).to_u8]
end

private def le32(v : Int32) : Array(UInt8)
  le24(v) + [((v >> 24) & 0xFF).to_u8]
end

private def webp_header(chunk : String, payload : Array(UInt8)) : Bytes
  bytes = "RIFF".bytes + [0_u8, 0_u8, 0_u8, 0_u8] + "WEBP".bytes + chunk.bytes + [0_u8, 0_u8, 0_u8, 0_u8] + payload
  bytes += [0_u8] * (30 - bytes.size) if bytes.size < 30
  Bytes.new(bytes.size) { |i| bytes[i] }
end

# 4×2 RGB image: left half red, right half blue.
private def write_halves_png(path : String) : Nil
  pixels = Bytes.new(4 * 2 * 3)
  2.times do |y|
    4.times do |x|
      o = (y * 4 + x) * 3
      if x < 2
        pixels[o] = 255_u8
      else
        pixels[o + 2] = 255_u8
      end
    end
  end
  LibStb.stbi_write_png(path, 4, 2, 3, pixels.to_unsafe.as(Void*), 4 * 3)
end

# {width, height, first pixel RGB} of a decoded image.
private def probe(path : String) : {Int32, Int32, {UInt8, UInt8, UInt8}}
  w = uninitialized LibC::Int
  h = uninitialized LibC::Int
  c = uninitialized LibC::Int
  px = LibStb.stbi_load(path, pointerof(w), pointerof(h), pointerof(c), 3)
  raise "decode failed" if px.null?
  begin
    {w.to_i32, h.to_i32, {px[0], px[1], px[2]}}
  ensure
    LibStb.stbi_image_free(px.as(Void*))
  end
end

describe "ImageProcessor.dimensions (read-only formats)" do
  it "reads GIF logical screen size" do
    Dir.mktmpdir do |dir|
      path = write_bytes(dir, "a.gif", Bytes.new(10) { |i| ("GIF89a".bytes + le16(300) + le16(70))[i] })
      Hwaro::Content::Processors::ImageProcessor.dimensions(path).should eq({300, 70})
    end
  end

  it "reads lossy (VP8), lossless (VP8L) and extended (VP8X) WebP" do
    Dir.mktmpdir do |dir|
      vp8 = webp_header("VP8 ", [0_u8, 0_u8, 0_u8, 0x9D_u8, 0x01_u8, 0x2A_u8] + le16(640) + le16(480))
      Hwaro::Content::Processors::ImageProcessor.dimensions(write_bytes(dir, "a.webp", vp8)).should eq({640, 480})

      bits = (1316 - 1) | ((483 - 1) << 14)
      vp8l = webp_header("VP8L", [0x2F_u8] + le16(bits & 0xFFFF) + le16(bits >> 16))
      Hwaro::Content::Processors::ImageProcessor.dimensions(write_bytes(dir, "b.webp", vp8l)).should eq({1316, 483})

      vp8x = webp_header("VP8X", [0_u8, 0_u8, 0_u8, 0_u8] + le24(5000 - 1) + le24(20 - 1))
      Hwaro::Content::Processors::ImageProcessor.dimensions(write_bytes(dir, "c.webp", vp8x)).should eq({5000, 20})
    end
  end

  it "reads SVG width/height, falling back to the viewBox" do
    Dir.mktmpdir do |dir|
      dims = ->(svg : String) {
        File.write(File.join(dir, "x.svg"), svg)
        Hwaro::Content::Processors::ImageProcessor.dimensions(File.join(dir, "x.svg"))
      }
      dims.call(%(<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="120" height="40px" viewBox="0 0 12 4">)).should eq({120, 40})
      dims.call(%(<svg viewBox="0 0 24 12" stroke-width="2"></svg>)).should eq({24, 12})
      dims.call(%(<svg width="100" viewBox="0 0 24 12"></svg>)).should eq({100, 50})
      dims.call(%(<svg width="100%" height="100%"></svg>)).should be_nil
      dims.call(%(<html></html>)).should be_nil
    end
  end

  it "ignores an <svg> tag inside a comment before the real root" do
    Dir.mktmpdir do |dir|
      dims = ->(svg : String) {
        File.write(File.join(dir, "x.svg"), svg)
        Hwaro::Content::Processors::ImageProcessor.dimensions(File.join(dir, "x.svg"))
      }
      dims.call(%(<?xml version="1.0"?>\n<!-- <svg width="1" height="1"> -->\n<svg viewBox="0 0 24 12">)).should eq({24, 12})
      dims.call(%(<!-- a --><!-- <svg width="2" height="2"> --><svg width="30" height="20">)).should eq({30, 20})
      # A comment that never closes swallows the rest: no root, no guess.
      dims.call(%(<!-- <svg width="1" height="1">)).should be_nil
    end
  end

  it "reads the OS/2 (BITMAPCOREHEADER) BMP size from its 16-bit fields" do
    Dir.mktmpdir do |dir|
      core = Bytes.new(26) { |i| (("BM".bytes + [0_u8] * 12 + le32(12) + le16(123) + le16(77) + le16(1) + le16(24))[i]) }
      Hwaro::Content::Processors::ImageProcessor.dimensions(write_bytes(dir, "core.bmp", core)).should eq({123, 77})
      # An unknown DIB header size is not measured.
      odd = Bytes.new(26) { |i| (("BM".bytes + [0_u8] * 12 + le32(20) + le16(123) + le16(77) + le16(1) + le16(24))[i]) }
      Hwaro::Content::Processors::ImageProcessor.dimensions(write_bytes(dir, "odd.bmp", odd)).should be_nil
    end
  end

  it "returns nil for truncated or mislabelled headers" do
    Dir.mktmpdir do |dir|
      Hwaro::Content::Processors::ImageProcessor.dimensions(write_bytes(dir, "a.gif", Bytes[0x47, 0x49])).should be_nil
      Hwaro::Content::Processors::ImageProcessor.dimensions(write_bytes(dir, "a.webp", Bytes.new(40))).should be_nil
    end
  end
end

describe "ImageProcessor.transform" do
  it "crops an unscaled region at the anchor" do
    Dir.mktmpdir do |dir|
      src = File.join(dir, "h.png")
      write_halves_png(src)
      left = File.join(dir, "l.png")
      right = File.join(dir, "r.png")
      Hwaro::Content::Processors::ImageProcessor.transform(src, left, 2, 2, "crop", "left").should eq({2, 2})
      Hwaro::Content::Processors::ImageProcessor.transform(src, right, 2, 2, "crop", "top_right").should eq({2, 2})
      probe(left).should eq({2, 2, {255_u8, 0_u8, 0_u8}})
      probe(right).should eq({2, 2, {0_u8, 0_u8, 255_u8}})
    end
  end

  it "clamps a crop box larger than the source" do
    Dir.mktmpdir do |dir|
      src = File.join(dir, "h.png")
      write_halves_png(src)
      dest = File.join(dir, "c.png")
      Hwaro::Content::Processors::ImageProcessor.transform(src, dest, 10, 10, "crop", "center").should eq({4, 2})
    end
  end

  it "fills the exact box, upscaling to cover it" do
    Dir.mktmpdir do |dir|
      src = File.join(dir, "h.png")
      write_halves_png(src)
      dest = File.join(dir, "f.png")
      Hwaro::Content::Processors::ImageProcessor.transform(src, dest, 8, 8, "fill", "right").should eq({8, 8})
      probe(dest).should eq({8, 8, {0_u8, 0_u8, 255_u8}})
    end
  end

  it "returns nil for an undecodable source" do
    Dir.mktmpdir do |dir|
      src = write_bytes(dir, "bad.png", Bytes[1, 2, 3])
      Hwaro::Content::Processors::ImageProcessor.transform(src, File.join(dir, "o.png"), 2, 2, "fill", "center").should be_nil
    end
  end
end

describe "[image_processing] dimensions" do
  it "defaults to off and loads independently of enabled" do
    load_config(%(title = "T"\n)).image_processing.dimensions.should be_false
    config = load_config(%(title = "T"\n[image_processing]\ndimensions = true\n))
    config.image_processing.dimensions.should be_true
    config.image_processing.enabled.should be_false
  end
end

describe "ImageProcessor.dimensions on hostile SVG" do
  it "returns nil instead of raising for a backtracking-heavy length attribute" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "x.svg")
      File.write(path, %(<svg width="1#{" " * 6000}x" height="2">))
      Hwaro::Content::Processors::ImageProcessor.dimensions(path).should be_nil
    end
  end

  it "returns nil instead of raising for a number too long to parse" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "x.svg")
      File.write(path, %(<svg width="#{"9" * 400}" height="5">))
      Hwaro::Content::Processors::ImageProcessor.dimensions(path).should be_nil
    end
  end
end
