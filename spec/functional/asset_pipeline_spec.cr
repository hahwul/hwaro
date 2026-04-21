require "./support/build_helper"

describe "Asset Pipeline: End-to-end build" do
  it "processes asset bundles during build" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        config_toml = <<-TOML
          title = "Asset Test"
          base_url = "https://example.com"

          [assets]
          enabled = true
          minify = true
          fingerprint = true
          source_dir = "static"
          output_dir = "assets"

          [[assets.bundles]]
          name = "main.css"
          files = ["css/reset.css", "css/style.css"]
          TOML

        File.write("config.toml", config_toml)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        FileUtils.mkdir_p("static/css")

        File.write("static/css/reset.css", "* { margin: 0; padding: 0; }")
        File.write("static/css/style.css", "body {\n  color: #333;\n  /* base styles */\n}")
        File.write("content/page.md", "---\ntitle: Test\n---\nHello")
        File.write("templates/page.html", %(<link href="{{ asset(name='main.css') }}">\n{{ content }}))

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        builder.run(output_dir: "public", parallel: false, highlight: false, verbose: false, profile: false)

        # Check that fingerprinted bundle exists
        assets_dir = File.join("public", "assets")
        Dir.exists?(assets_dir).should be_true

        css_files = Dir.glob(File.join(assets_dir, "main.*.css"))
        css_files.size.should eq(1)

        # Check minified content
        content = File.read(css_files[0])
        content.should contain("margin:0")
        content.should contain("color:#333")
        content.should_not contain("/* base styles */")

        # Check that template resolved the asset path
        html = File.read("public/page/index.html")
        html.should match(/href="https:\/\/example\.com\/assets\/main\.[a-f0-9]{8}\.css"/)
      end
    end
  end

  it "works without fingerprinting" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        config_toml = <<-TOML
          title = "Asset Test"
          base_url = ""

          [assets]
          enabled = true
          minify = false
          fingerprint = false

          [[assets.bundles]]
          name = "bundle.js"
          files = ["app.js"]
          TOML

        File.write("config.toml", config_toml)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        FileUtils.mkdir_p("static")

        File.write("static/app.js", "console.log('hello');")
        File.write("content/page.md", "---\ntitle: Test\n---\nHello")
        File.write("templates/page.html", %(<script src="{{ asset(name='bundle.js') }}"></script>\n{{ content }}))

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        builder.run(output_dir: "public", parallel: false, highlight: false, verbose: false, profile: false)

        File.exists?("public/assets/bundle.js").should be_true
        File.read("public/assets/bundle.js").should contain("console.log('hello')")

        html = File.read("public/page/index.html")
        html.should contain(%(/assets/bundle.js))
      end
    end
  end

  it "falls back gracefully when asset not in manifest" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")

        File.write("content/page.md", "---\ntitle: Test\n---\nHello")
        File.write("templates/page.html", %(<link href="{{ asset(name='unknown.css') }}">\n{{ content }}))

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        builder.run(output_dir: "public", parallel: false, highlight: false, verbose: false, profile: false)

        html = File.read("public/page/index.html")
        html.should contain("/unknown.css")
      end
    end
  end
end
