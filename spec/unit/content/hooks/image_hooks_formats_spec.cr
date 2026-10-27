require "../../../spec_helper"
require "../../../support/build_helper"

# `[image_processing] formats = ["webp"]`: WebP copies of the width variants,
# end to end through a real build.

private def write_png(path : String, w : Int32, h : Int32) : Nil
  FileUtils.mkdir_p(File.dirname(path))
  pixels = Bytes.new(w * h * 3) { |i| ((i // 3 % w) * 255 // w).to_u8 }
  LibStb.stbi_write_png(path, w, h, 3, pixels.to_unsafe.as(Void*), w * 3).should_not eq(0)
end

private def write_jpg(path : String, w : Int32, h : Int32) : Nil
  FileUtils.mkdir_p(File.dirname(path))
  pixels = Bytes.new(w * h * 3) { |i| ((i // 3 // w) * 255 // h).to_u8 }
  LibStb.stbi_write_jpg(path, w, h, 3, pixels.to_unsafe.as(Void*), 90).should_not eq(0)
end

private WEBP_CONFIG = <<-TOML
  title = "T"
  base_url = "https://example.com"

  [image_processing]
  enabled = true
  widths = [16, 64]
  formats = ["webp"]
  TOML

private def webp_build(config : String = WEBP_CONFIG, cache : Bool = true) : Nil
  File.write("config.toml", config)
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public", parallel: false, cache: cache, highlight: false,
  )).should be_true
end

private def with_webp_site(&)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      FileUtils.mkdir_p("templates")
      File.write("templates/page.html", "{{ content | safe }}")
      File.write("templates/section.html", "{{ content | safe }}")
      FileUtils.mkdir_p("content/posts")
      File.write("content/posts/a.md", "+++\ntitle = \"A\"\n+++\n\n![photo](/photo.png)\n")
      write_png("static/photo.png", 48, 32)
      # Variants written in the source's own mtime tick are never trusted
      # (racy-git), so a source that is "old" lets warm builds reuse them.
      File.touch("static/photo.png", Time.utc - 1.hour)
      yield
    end
  end
end

private def webp?(path : String) : Bool
  data = File.read(path).to_slice
  data.size > 12 && String.new(data[0, 4]) == "RIFF" && String.new(data[8, 4]) == "WEBP"
end

describe "image processing formats" do
  it "writes a WebP copy of every width variant and offers it through <picture>" do
    with_webp_site do
      webp_build
      webp?("public/photo_16w.webp").should be_true
      # 64 is wider than the 48px source: the source size is encoded instead.
      webp?("public/photo_48w.webp").should be_true
      Hwaro::Content::Processors::ImageProcessor.dimensions("public/photo_16w.webp").should eq({16, 11})
      File.exists?("public/photo_16w.png").should be_true

      html = File.read("public/posts/a/index.html")
      html.should contain(%(<picture><source type="image/webp" srcset="/photo_16w.webp 16w, /photo_48w.webp 48w" sizes="100vw"><img srcset="/photo_16w.png 16w, /photo_48w.png 48w"))
    end
  end

  it "reuses the WebP variants on a warm build and removes them once formats is dropped" do
    with_webp_site do
      webp_build
      log = with_captured_log { webp_build }
      log.should contain("Reused 1 cached image result")

      webp_build(WEBP_CONFIG.sub(%(formats = ["webp"]), ""))
      File.exists?("public/photo_16w.webp").should be_false
      File.exists?("public/photo_16w.png").should be_true
      File.read("public/posts/a/index.html").should_not contain("<picture")
    end
  end

  it "gives two sources that share a name the WebP names of the one that sorts first" do
    with_webp_site do
      write_jpg("static/dup/same.jpg", 20, 20)
      write_png("static/dup/same.png", 40, 40)
      log = with_captured_log { webp_build }
      log.should contain("static/dup/same.png: no webp variants, static/dup/same.jpg already writes those names")
      Hwaro::Content::Processors::ImageProcessor.dimensions("public/dup/same_16w.webp").should eq({16, 16})
      File.exists?("public/dup/same_20w.webp").should be_true
      File.exists?("public/dup/same_40w.webp").should be_false
      File.exists?("public/dup/same_40w.png").should be_true
    end
  end

  it "treats names that differ only in case as the same WebP names" do
    with_webp_site do
      write_jpg("static/dup/Same.jpg", 20, 20)
      write_png("static/dup/same.png", 40, 40)
      log = with_captured_log { webp_build }
      log.should contain("static/dup/same.png: no webp variants, static/dup/Same.jpg already writes those names")
      File.exists?("public/dup/Same_20w.webp").should be_true
      Dir.children("public/dup").count(&.downcase.==("same_16w.webp")).should eq(1)
    end
  end

  it "keeps WebP variants lossy at quality 100" do
    with_webp_site do
      webp_build(WEBP_CONFIG.sub("enabled = true", "enabled = true\nquality = 100"))
      String.new(File.read("public/photo_16w.webp").to_slice[12, 4]).should eq("VP8 ")
    end
  end

  it "never replaces a WebP file the site publishes under a variant's name" do
    with_webp_site do
      File.write("static/photo_16w.webp", "authored")
      webp_build
      File.read("public/photo_16w.webp").should eq("authored")
      webp?("public/photo_48w.webp").should be_true
      File.read("public/posts/a/index.html").should contain(%(srcset="/photo_48w.webp 48w"))
    end
  end

  it "resize_image(format=\"webp\") returns the WebP variant, and writes fill/crop as WebP" do
    with_webp_site do
      File.write("templates/page.html",
        %({{ resize_image(path="/photo.png", width=16, format="webp").url }}|) +
        %({{ resize_image(path="/photo.png", width=16).url }}|) +
        %({% set c = resize_image(path="/photo.png", width=10, height=10, op="fill", format="webp") %}{{ c.url }} {{ c.width }}x{{ c.height }}))
      webp_build
      File.read("public/posts/a/index.html").should eq(
        "https://example.com/photo_16w.webp|https://example.com/photo_16w.png|https://example.com/photo_10x10_fill_center.webp 10x10")
      webp?("public/photo_10x10_fill_center.webp").should be_true
    end
  end
end

describe "ImageHooks.reusable_widths(.webp)" do
  # WebP canvases stop at 16383px: a wider variant is never written, so it
  # must not make the set look incomplete (and the image re-encode on every
  # warm build).
  it "does not expect WebP widths beyond the format's canvas limit" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        header = IO::Memory.new
        header.write(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])
        header.write_bytes(20_000_u32, IO::ByteFormat::BigEndian)
        header.write_bytes(10_u32, IO::ByteFormat::BigEndian)
        File.write("pano.png", header.to_slice)
        File.touch("pano.png", Time.utc - 1.hour)
        Dir.mkdir("out")
        File.write("out/pano_16w.webp", "x")
        Hwaro::Content::Hooks::ImageHooks.reusable_widths("pano.png", "out", [16, 20_000], nil, nil, ".webp")
          .should eq({16 => "pano_16w.webp"})
      end
    end
  end
end

describe "resize_image(format=)" do
  it "falls back to the source-format variant when there is no WebP one" do
    prior = Hwaro::Content::Hooks::ImageHooks.resize_map
    begin
      Hwaro::Content::Hooks::ImageHooks.set_resize_map({"/p.png" => {100 => "/p_100w.png"}})
      render_crinja(%({{ resize_image(path="/p.png", width=100, format="webp").url }}), {"base_url" => "https://example.com"})
        .strip.should eq("https://example.com/p_100w.png")
    ensure
      Hwaro::Content::Hooks::ImageHooks.set_resize_map(prior)
    end
  end

  it "rejects an unknown format" do
    expect_raises(Exception, /unknown format "avif"/) do
      render_crinja(%({{ resize_image(path="/p.png", width=100, format="avif").url }}))
    end
  end
end
