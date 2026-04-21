require "../spec_helper"

# Helper to build a pipeline config quickly
private def make_config(
  minify = false,
  fingerprint = false,
  source_dir = "static",
  output_dir = "assets",
)
  config = Hwaro::Models::AssetsConfig.new
  config.enabled = true
  config.minify = minify
  config.fingerprint = fingerprint
  config.source_dir = source_dir
  config.output_dir = output_dir
  config
end

describe Hwaro::Assets::Pipeline do
  # ===========================================================================
  # Bundling — combining files
  # ===========================================================================
  describe "#process — bundling" do
    it "bundles multiple CSS files" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(File.join(static_dir, "css"))
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "css", "reset.css"), "* { margin: 0; }")
        File.write(File.join(static_dir, "css", "style.css"), "body { color: red; }")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "main.css", files: ["css/reset.css", "css/style.css"]
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        content = File.read(File.join(output_dir, "assets", "main.css"))
        content.should contain("margin: 0")
        content.should contain("color: red")
      end
    end

    it "bundles multiple JS files" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(File.join(static_dir, "js"))
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "js", "util.js"), "function log(msg) { console.log(msg); }")
        File.write(File.join(static_dir, "js", "app.js"), "log('hello');")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "app.js", files: ["js/util.js", "js/app.js"]
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        content = File.read(File.join(output_dir, "assets", "app.js"))
        content.should contain("console.log")
        content.should contain("log('hello')")
      end
    end

    it "preserves file order in bundle" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "a.css"), "/* FILE A */")
        File.write(File.join(static_dir, "b.css"), "/* FILE B */")
        File.write(File.join(static_dir, "c.css"), "/* FILE C */")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "all.css", files: ["a.css", "b.css", "c.css"]
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        content = File.read(File.join(output_dir, "assets", "all.css"))
        idx_a = content.index!("FILE A")
        idx_b = content.index!("FILE B")
        idx_c = content.index!("FILE C")
        (idx_a < idx_b).should be_true
        (idx_b < idx_c).should be_true
      end
    end

    it "separates files with newlines in bundle" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "a.css"), ".a{}")
        File.write(File.join(static_dir, "b.css"), ".b{}")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "all.css", files: ["a.css", "b.css"]
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        content = File.read(File.join(output_dir, "assets", "all.css"))
        content.should contain("\n")
      end
    end

    it "does not add leading newline before first file" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "a.css"), ".a{}")
        File.write(File.join(static_dir, "b.css"), ".b{}")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "all.css", files: ["a.css", "b.css"]
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        content = File.read(File.join(output_dir, "assets", "all.css"))
        content.starts_with?(".a{}").should be_true
      end
    end

    it "handles single-file bundles" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "only.css"), "body { color: blue; }")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "only.css", files: ["only.css"]
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        File.read(File.join(output_dir, "assets", "only.css")).should contain("color: blue")
      end
    end

    it "handles multiple bundles" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "a.css"), ".a{}")
        File.write(File.join(static_dir, "b.js"), "var b;")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "style.css", files: ["a.css"])
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "script.js", files: ["b.js"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        File.exists?(File.join(output_dir, "assets", "style.css")).should be_true
        File.exists?(File.join(output_dir, "assets", "script.js")).should be_true
        pipeline.manifest.size.should eq(2)
      end
    end

    it "handles files with unicode content" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "i18n.css"), ".日本語 { content: '한국어'; }")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "i18n.css", files: ["i18n.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        content = File.read(File.join(output_dir, "assets", "i18n.css"))
        content.should contain("日本語")
        content.should contain("한국어")
      end
    end

    it "handles source file that is empty (0 bytes)" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "empty.css"), "")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "empty.css", files: ["empty.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        # Empty content → bundle not created
        pipeline.manifest.has_key?("empty.css").should be_false
      end
    end

    it "handles source file with only whitespace" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "ws.css"), "   \n\n   ")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "ws.css", files: ["ws.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        # Whitespace-only content is still non-empty
        pipeline.manifest.has_key?("ws.css").should be_true
      end
    end
  end

  # ===========================================================================
  # Minification
  # ===========================================================================
  describe "#process — minification" do
    it "minifies CSS bundles" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "style.css"), "body {\n  color: red;\n  /* comment */\n}")

        config = make_config(minify: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "style.css", files: ["style.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        content = File.read(File.join(output_dir, "assets", "style.css"))
        content.should_not contain("/* comment */")
        content.should_not contain("\n")
      end
    end

    it "minifies JS bundles" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "app.js"), "var x = 1; // comment\n\n\nvar y = 2;")

        config = make_config(minify: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "app.js", files: ["app.js"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        content = File.read(File.join(output_dir, "assets", "app.js"))
        content.should_not contain("// comment")
        content.should contain("var x = 1;")
      end
    end

    it "does not minify when disabled" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "style.css"), "body {\n  /* comment */\n  color: red;\n}")

        config = make_config(minify: false, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "style.css", files: ["style.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        content = File.read(File.join(output_dir, "assets", "style.css"))
        content.should contain("/* comment */")
      end
    end

    it "does not minify unknown file types" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        original = "some content with /* pseudo comment */"
        File.write(File.join(static_dir, "data.txt"), original)

        config = make_config(minify: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "data.txt", files: ["data.txt"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        content = File.read(File.join(output_dir, "assets", "data.txt"))
        content.should eq(original)
      end
    end

    it "minifies CSS with URL preservation" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        css = "body { background: url(http://example.com/bg.png); color: red; }"
        File.write(File.join(static_dir, "style.css"), css)

        config = make_config(minify: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "style.css", files: ["style.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        content = File.read(File.join(output_dir, "assets", "style.css"))
        content.should contain("url(http://example.com/bg.png)")
      end
    end

    it "minification + fingerprinting combined" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "style.css"), "body {\n  /* remove me */\n  color: red;\n}")

        config = make_config(minify: true, fingerprint: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "style.css", files: ["style.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        manifest_path = pipeline.manifest["style.css"]
        manifest_path.should match(/style\.[a-f0-9]{8}\.css/)

        content = File.read(File.join(output_dir, manifest_path.lstrip("/")))
        content.should_not contain("/* remove me */")
        content.should contain("color:red")
      end
    end
  end

  # ===========================================================================
  # Fingerprinting
  # ===========================================================================
  describe "#process — fingerprinting" do
    it "generates fingerprinted filenames" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "style.css"), "body { color: red; }")

        config = make_config(fingerprint: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "style.css", files: ["style.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        manifest_path = pipeline.manifest["style.css"]
        manifest_path.should match(/\/assets\/style\.[a-f0-9]{8}\.css/)
        File.exists?(File.join(output_dir, manifest_path.lstrip("/"))).should be_true
      end
    end

    it "produces consistent fingerprints for same content" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "a.css"), "body { color: blue; }")

        config = make_config(fingerprint: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "a.css", files: ["a.css"])

        p1 = Hwaro::Assets::Pipeline.new(config, "")
        p1.process(output_dir)

        p2 = Hwaro::Assets::Pipeline.new(config, "")
        p2.process(output_dir)

        p1.manifest["a.css"].should eq(p2.manifest["a.css"])
      end
    end

    it "produces different fingerprints for different content" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "style.css"), "body { color: red; }")

        config = make_config(fingerprint: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "style.css", files: ["style.css"])

        p1 = Hwaro::Assets::Pipeline.new(config, "")
        p1.process(output_dir)
        hash1 = p1.manifest["style.css"]

        File.write(File.join(static_dir, "style.css"), "body { color: blue; }")

        p2 = Hwaro::Assets::Pipeline.new(config, "")
        p2.process(output_dir)
        hash2 = p2.manifest["style.css"]

        hash1.should_not eq(hash2)
      end
    end

    it "handles bundle names with subdirectories" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(File.join(static_dir, "css"))
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "css", "a.css"), ".a{}")

        config = make_config(fingerprint: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "css/main.css", files: ["css/a.css"]
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        manifest_path = pipeline.manifest["css/main.css"]
        manifest_path.should match(/\/assets\/css\/main\.[a-f0-9]{8}\.css/)
        File.exists?(File.join(output_dir, manifest_path.lstrip("/"))).should be_true
      end
    end

    it "works without fingerprinting (plain filenames)" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "style.css"), "body{}")

        config = make_config(fingerprint: false, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "style.css", files: ["style.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        pipeline.manifest["style.css"].should eq("/assets/style.css")
      end
    end

    it "fingerprint hash is 8 hex chars" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "x.css"), "body{}")

        config = make_config(fingerprint: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "x.css", files: ["x.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        # Extract hash part
        manifest_path = pipeline.manifest["x.css"]
        match = manifest_path.match(/x\.([a-f0-9]+)\.css/)
        match.should_not be_nil
        match.not_nil![1].size.should eq(8)
      end
    end

    it "same content in different bundles produces same hash" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "shared.css"), "body{}")

        config = make_config(fingerprint: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "a.css", files: ["shared.css"])
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "b.css", files: ["shared.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        # Both should have same hash since content is identical
        hash_a = pipeline.manifest["a.css"].match!(/\.([a-f0-9]{8})\./)[1]
        hash_b = pipeline.manifest["b.css"].match!(/\.([a-f0-9]{8})\./)[1]
        hash_a.should eq(hash_b)
      end
    end
  end

  # ===========================================================================
  # Manifest
  # ===========================================================================
  describe "manifest" do
    it "maps bundle names to output paths" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "a.css"), ".a{}")
        File.write(File.join(static_dir, "b.js"), "var b;")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "a.css", files: ["a.css"])
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "b.js", files: ["b.js"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        pipeline.manifest["a.css"].should eq("/assets/a.css")
        pipeline.manifest["b.js"].should eq("/assets/b.js")
      end
    end

    it "starts empty before processing" do
      config = Hwaro::Models::AssetsConfig.new
      config.enabled = true
      pipeline = Hwaro::Assets::Pipeline.new(config, "")
      pipeline.manifest.empty?.should be_true
    end

    it "does not include empty bundles in manifest" do
      Dir.mktmpdir do |dir|
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(output_dir)

        config = make_config(source_dir: dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "missing.css", files: ["nonexistent.css"]
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        pipeline.manifest.has_key?("missing.css").should be_false
      end
    end

    it "uses custom output_dir in manifest paths" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "style.css"), "body{}")

        config = make_config(source_dir: static_dir, output_dir: "static/dist")
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "style.css", files: ["style.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        pipeline.manifest["style.css"].should eq("/static/dist/style.css")
        File.exists?(File.join(output_dir, "static", "dist", "style.css")).should be_true
      end
    end
  end

  # ===========================================================================
  # Edge cases and error handling
  # ===========================================================================
  describe "edge cases" do
    it "does nothing when disabled" do
      config = Hwaro::Models::AssetsConfig.new
      config.enabled = false

      pipeline = Hwaro::Assets::Pipeline.new(config, "")
      pipeline.process("/nonexistent")
      pipeline.manifest.empty?.should be_true
    end

    it "skips missing source file but processes remaining" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "exists.css"), ".a{}")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "bundle.css", files: ["missing.css", "exists.css"]
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        pipeline.manifest.has_key?("bundle.css").should be_true
        content = File.read(File.join(output_dir, "assets", "bundle.css"))
        content.should contain(".a{}")
      end
    end

    it "first file missing, second exists" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "second.css"), ".second{}")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "out.css", files: ["first.css", "second.css"]
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        pipeline.manifest.has_key?("out.css").should be_true
      end
    end

    it "handles all files missing in a bundle" do
      Dir.mktmpdir do |dir|
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(output_dir)

        config = make_config(source_dir: dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "empty.css", files: ["a.css", "b.css"]
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        pipeline.manifest.has_key?("empty.css").should be_false
      end
    end

    it "handles empty file list in bundle config" do
      Dir.mktmpdir do |dir|
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(output_dir)

        config = make_config(source_dir: dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "empty.css", files: [] of String
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        pipeline.manifest.has_key?("empty.css").should be_false
      end
    end

    it "handles no bundles configured" do
      Dir.mktmpdir do |dir|
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(output_dir)

        config = make_config(source_dir: dir)

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        pipeline.manifest.empty?.should be_true
      end
    end

    it "creates output subdirectories as needed" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "style.css"), "body{}")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "style.css", files: ["style.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        File.exists?(File.join(output_dir, "assets", "style.css")).should be_true
      end
    end

    it "handles duplicate files in a bundle" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "dup.css"), ".dup { color: red; }")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "duped.css", files: ["dup.css", "dup.css"]
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        content = File.read(File.join(output_dir, "assets", "duped.css"))
        content.scan(".dup").size.should eq(2)
      end
    end

    it "handles files with special characters in name" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "my-style_v2.css"), "body{}")

        config = make_config(fingerprint: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(
          name: "my-style_v2.css", files: ["my-style_v2.css"]
        )

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        pipeline.manifest["my-style_v2.css"].should match(/my-style_v2\.[a-f0-9]{8}\.css/)
      end
    end

    it "handles large CSS files" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        big_css = (1..1000).map { |i| ".c-#{i}{color:##{"%06x" % (i*137)}}" }.join("\n")
        File.write(File.join(static_dir, "big.css"), big_css)

        config = make_config(minify: true, fingerprint: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "big.css", files: ["big.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        pipeline.manifest.has_key?("big.css").should be_true
      end
    end

    it "processing twice is idempotent (overwrites cleanly)" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "style.css"), "body{color:red}")

        config = make_config(fingerprint: true, source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "style.css", files: ["style.css"])

        p1 = Hwaro::Assets::Pipeline.new(config, "")
        p1.process(output_dir)

        p2 = Hwaro::Assets::Pipeline.new(config, "")
        p2.process(output_dir)

        p1.manifest["style.css"].should eq(p2.manifest["style.css"])

        output_file = File.join(output_dir, p2.manifest["style.css"].lstrip("/"))
        File.exists?(output_file).should be_true
      end
    end

    it "deeply nested output directory" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "a", "b", "c", "public")
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "x.css"), ".x{}")

        config = make_config(source_dir: static_dir)
        config.bundles << Hwaro::Models::AssetBundleConfig.new(name: "x.css", files: ["x.css"])

        pipeline = Hwaro::Assets::Pipeline.new(config, "")
        pipeline.process(output_dir)

        File.exists?(File.join(output_dir, "assets", "x.css")).should be_true
      end
    end
  end
end
