require "../../../../../spec_helper"
require "../../../../../../src/core/build/builder"
require "../../../../../../src/content/hooks"
require "../../../../../../src/ext/stb_bindings"

# A warm `--cache` build must render what a cold build renders even when the
# input that changed is one templates read OUTSIDE the tracked files: the
# fingerprinted asset-bundle name, the `[auto_includes]` tags, the image
# behind `resize_image()`, an `env()` value, a `load_data()` file outside
# `data/`. None of them was in any cache key, so every cached page kept the
# old value — a 404ing stylesheet, the previous analytics ID.

private def render_inputs_build(cache_busting : Bool = true, output_dir : String = "public")
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: output_dir, parallel: false, cache: true, highlight: false,
    cache_busting: cache_busting,
  )).should be_true
end

private def integrity_in(html : String) : String
  html.match!(/integrity="(sha384-[^"]+)"/)[1]
end

# A cached page is not rewritten, so a marker appended to its output survives
# a warm build exactly when the page was served from the cache.
private def mark_outputs(paths : Array(String))
  paths.each { |path| File.write(path, File.read(path) + "<!--cached-->") }
end

private def cached?(path : String) : Bool
  File.read(path).ends_with?("<!--cached-->")
end

private def with_render_inputs_site(config_extra : String, head : String, &)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      File.write("config.toml", "title = \"T\"\nbase_url = \"http://localhost\"\n#{config_extra}")
      FileUtils.mkdir_p("content")
      File.write("content/a.md", "+++\ntitle = \"A\"\n+++\na")
      File.write("content/b.md", "+++\ntitle = \"B\"\n+++\nb")
      FileUtils.mkdir_p("templates")
      File.write("templates/page.html", "<head>#{head}</head><p>{{ content }}</p>")
      yield
    end
  end
end

private def write_solid_png(path : String, width : Int32, height : Int32, r : UInt8, g : UInt8, b : UInt8)
  pixels = Array(UInt8).new(width * height * 3) { |i| [r, g, b][i % 3] }
  FileUtils.mkdir_p(File.dirname(path))
  LibStb.stbi_write_png(path, width, height, 3, pixels.to_unsafe.as(Void*), width * 3)
end

describe "warm --cache builds and template inputs outside the tracked files" do
  it "re-renders cached pages when an asset bundle's fingerprint changes" do
    config = <<-TOML
      [assets]
      enabled = true
      fingerprint = true
      [[assets.bundles]]
      name = "main.css"
      files = ["css/s.css"]
      TOML
    with_render_inputs_site(config, %(<link href="{{ asset(name="main.css") }}">)) do
      FileUtils.mkdir_p("static/css")
      File.write("static/css/s.css", "body{color:red}")
      render_inputs_build
      before = File.read("public/a/index.html")

      File.write("static/css/s.css", "body{color:blue}")
      render_inputs_build

      html = File.read("public/a/index.html")
      html.should_not eq(before)
      href = html.match!(/href="http:\/\/localhost(\/[^"]+)"/)[1]
      # The page links the bundle this build published, not the pruned one.
      File.exists?(File.join("public", href)).should be_true
    end
  end

  it "re-renders cached pages when an auto-include file changes or is added" do
    config = "[auto_includes]\nenabled = true\ndirs = [\"inc\"]\n"
    with_render_inputs_site(config, "{{ auto_includes_css }}") do
      FileUtils.mkdir_p("static/inc")
      File.write("static/inc/a.css", "a{}")
      render_inputs_build
      before = File.read("public/a/index.html")

      File.write("static/inc/a.css", "a{color:green}")
      File.write("static/inc/b.css", "b{}")
      render_inputs_build

      html = File.read("public/a/index.html")
      html.should contain("/inc/b.css")
      html.should_not eq(before)
    end
  end

  it "re-renders cached pages and prunes the old variant when a resize_image() source is replaced" do
    config = "[image_processing]\nenabled = true\nwidths = [640, 1024]\n"
    head = %({% set im = resize_image(path="/img.png", width=1024) %}<img src="{{ im.url }}" width="{{ im.width }}">)
    with_render_inputs_site(config, head) do
      write_solid_png("static/img.png", 900, 30, 255_u8, 0_u8, 0_u8)
      render_inputs_build
      File.read("public/a/index.html").should contain("img_900w.png")

      write_solid_png("static/img.png", 2000, 30, 0_u8, 0_u8, 255_u8)
      render_inputs_build

      html = File.read("public/a/index.html")
      html.should contain(%(src="http://localhost/img_1024w.png" width="1024"))
      File.exists?("public/img_1024w.png").should be_true
      # A cold build never writes it; the warm one must not keep it.
      File.exists?("public/img_900w.png").should be_false
    end
  end

  it "re-renders cached pages when a resize_image() source changes colour at the same size" do
    config = "[image_processing]\nenabled = true\nwidths = [640]\n[image_processing.lqip]\nenabled = true\n"
    head = %({% set im = resize_image(path="/img.png", width=640) %}<i data-c="{{ im.dominant_color }}"></i>)
    with_render_inputs_site(config, head) do
      write_solid_png("static/img.png", 900, 30, 255_u8, 0_u8, 0_u8)
      render_inputs_build
      File.read("public/a/index.html").should contain(%(data-c="#ff0000"))

      write_solid_png("static/img.png", 900, 30, 0_u8, 0_u8, 255_u8)
      render_inputs_build
      File.read("public/a/index.html").should contain(%(data-c="#0000ff"))
    end
  end

  # A warm build that changed nothing must not read every source image: the
  # recorded stamp (mtime + size) stands in for the bytes, as it does for
  # content files. An unreadable file is the oracle — re-hashing it would
  # change the digest and re-render the page.
  it "does not re-read an unchanged resize_image() source on a warm build" do
    config = "[image_processing]\nenabled = true\nwidths = [640]\n"
    head = %({% set im = resize_image(path="/img.png", width=640) %}<img src="{{ im.url }}">)
    with_render_inputs_site(config, head) do
      write_solid_png("static/img.png", 900, 30, 255_u8, 0_u8, 0_u8)
      # A photo, not a file written a moment ago: a stamp taken inside the
      # file's mtime tick is not trusted (#857).
      File.touch("static/img.png", Time.utc - 1.hour)
      render_inputs_build
      render_inputs_build
      mark_outputs(["public/a/index.html"])
      File.chmod("static/img.png", 0o000)
      begin
        render_inputs_build
      ensure
        File.chmod("static/img.png", 0o644)
      end
      cached?("public/a/index.html").should be_true
    end
  end

  it "keeps pages cached when a resize_image() source is only touched" do
    config = "[image_processing]\nenabled = true\nwidths = [640]\n"
    head = %({% set im = resize_image(path="/img.png", width=640) %}<img src="{{ im.url }}">)
    with_render_inputs_site(config, head) do
      write_solid_png("static/img.png", 900, 30, 255_u8, 0_u8, 0_u8)
      render_inputs_build
      render_inputs_build
      mark_outputs(["public/a/index.html"])
      # A fresh checkout: new mtime, same bytes.
      File.touch("static/img.png", Time.utc + 5.seconds)
      render_inputs_build
      cached?("public/a/index.html").should be_true
    end
  end

  it "re-renders cached pages when an env() value changes, without storing the value" do
    name = "HWARO_SPEC_RENDER_INPUT_ENV"
    ENV[name] = "UA-OLD"
    begin
      with_render_inputs_site("", %(<meta content="{{ env("#{name}", default="none") }}">)) do
        render_inputs_build
        File.read("public/a/index.html").should contain("UA-OLD")

        ENV[name] = "UA-NEW"
        render_inputs_build
        File.read("public/a/index.html").should contain("UA-NEW")
        File.read("public/b/index.html").should contain("UA-NEW")
        # The value may be a secret: only the variable's name and a digest
        # reach the cache file.
        File.read(".hwaro_cache.json").should_not contain("UA-NEW")

        ENV.delete(name)
        render_inputs_build
        File.read("public/a/index.html").should contain(%(content="none"))
      end
    ensure
      ENV.delete(name)
    end
  end

  it "re-renders cached pages when a load_data() file outside data/ changes" do
    head = %({% set x = load_data(path="extdata/x.json") %}<meta content="{{ x.v }}">)
    with_render_inputs_site("", head) do
      FileUtils.mkdir_p("extdata")
      File.write("extdata/x.json", %({"v":"old"}))
      written = File.info("extdata/x.json").modification_time
      render_inputs_build
      File.read("public/a/index.html").should contain(%(content="old"))

      # Same size and, pinned, the same mtime: a rewrite inside the
      # timestamp tick the warm build's stamp was taken in (#857).
      File.write("extdata/x.json", %({"v":"new"}))
      File.utime(written, written, "extdata/x.json")
      render_inputs_build
      File.read("public/a/index.html").should contain(%(content="new"))
    end
  end

  it "keeps every page cached when no template input changed" do
    name = "HWARO_SPEC_RENDER_INPUT_STABLE"
    ENV[name] = "same"
    begin
      head = %({% set x = load_data(path="extdata/x.json") %}{{ x.v }}{{ env("#{name}") }})
      with_render_inputs_site("", head) do
        FileUtils.mkdir_p("extdata")
        File.write("extdata/x.json", %({"v":"v"}))
        render_inputs_build
        render_inputs_build
        mark_outputs(["public/a/index.html", "public/b/index.html"])
        render_inputs_build
        cached?("public/a/index.html").should be_true
        cached?("public/b/index.html").should be_true
      end
    ensure
      ENV.delete(name)
    end
  end

  it "keeps the reads of cached pages across a partial rebuild" do
    name = "HWARO_SPEC_RENDER_INPUT_PARTIAL"
    ENV[name] = "one"
    begin
      # Only page B reads the variable.
      head = %({% if page.title == "B" %}{{ env("#{name}") }}{% endif %})
      with_render_inputs_site("", head) do
        render_inputs_build
        # Re-render A alone: its render reads nothing, B stays cached.
        File.write("content/a.md", "+++\ntitle = \"A\"\n+++\na edited")
        render_inputs_build

        ENV[name] = "two"
        render_inputs_build
        File.read("public/b/index.html").should contain("two")
      end
    ensure
      ENV.delete(name)
    end
  end

  # A stale `integrity` makes the browser refuse the asset, so a warm build
  # must re-render every page that prints one when the emitted bytes move —
  # also when nothing else in the tag (no `?v=`) changes.
  it "updates [assets] sri integrity on cached pages when an auto-include changes" do
    config = "[assets]\nsri = true\n[auto_includes]\nenabled = true\ndirs = [\"inc\"]\n"
    with_render_inputs_site(config, "{{ auto_includes_css }}") do
      FileUtils.mkdir_p("static/inc")
      File.write("static/inc/a.css", "a{}")
      render_inputs_build(cache_busting: false)
      integrity_in(File.read("public/a/index.html")).should eq(Hwaro::Utils::DigestUtils.sri("a{}"))

      File.write("static/inc/a.css", "a{color:green}")
      render_inputs_build(cache_busting: false)

      integrity_in(File.read("public/a/index.html")).should eq(Hwaro::Utils::DigestUtils.sri("a{color:green}"))
      integrity_in(File.read("public/b/index.html")).should eq(Hwaro::Utils::DigestUtils.sri_file("public/inc/a.css"))
    end
  end

  it "updates asset_integrity() on cached pages when an unfingerprinted bundle changes" do
    config = <<-TOML
      [assets]
      enabled = true
      fingerprint = false
      [[assets.bundles]]
      name = "main.css"
      files = ["css/s.css"]
      TOML
    head = %(<link href="{{ asset(name="main.css") }}" integrity="{{ asset_integrity(name="main.css") }}">)
    with_render_inputs_site(config, head) do
      FileUtils.mkdir_p("static/css")
      File.write("static/css/s.css", "body { color: red; }")
      render_inputs_build
      before = integrity_in(File.read("public/a/index.html"))
      # Over the emitted (minified) bytes, not the source.
      before.should eq(Hwaro::Utils::DigestUtils.sri_file("public/assets/main.css"))
      before.should_not eq(Hwaro::Utils::DigestUtils.sri("body { color: red; }"))

      File.write("static/css/s.css", "body { color: blue; }")
      render_inputs_build

      after = integrity_in(File.read("public/a/index.html"))
      after.should_not eq(before)
      after.should eq(Hwaro::Utils::DigestUtils.sri_file("public/assets/main.css"))
    end
  end

  # The read is keyed by asset NAME, not by the output file's path: a path
  # outside the project (`-o ../site`, an absolute `-o`) is never recorded
  # as a file read, so those pages stayed cached with the old hash.
  it "updates asset_integrity() on cached pages for an output dir outside the project" do
    Dir.mktmpdir do |outside|
      [File.join(outside, "abs-out"), "../#{File.basename(outside)}/rel-out"].each do |output_dir|
        with_render_inputs_site("", %(<link integrity="{{ asset_integrity(name='css/site.css') }}">)) do
          FileUtils.mkdir_p("static/css")
          File.write("static/css/site.css", "a{}")
          render_inputs_build(output_dir: output_dir)
          page = File.join(output_dir, "a/index.html")
          integrity_in(File.read(page)).should eq(Hwaro::Utils::DigestUtils.sri("a{}"))

          File.write("static/css/site.css", "a{color:red}")
          render_inputs_build(output_dir: output_dir)

          integrity_in(File.read(page)).should eq(Hwaro::Utils::DigestUtils.sri("a{color:red}"))
        end
      end
    end
  end
end
