require "../support/build_helper"

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
        builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false, verbose: false, profile: false))

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
        builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false, verbose: false, profile: false))

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
        builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false, verbose: false, profile: false))

        html = File.read("public/page/index.html")
        html.should contain("/unknown.css")
      end
    end
  end
end

describe "Asset Pipeline: asset_integrity()" do
  it "hashes the emitted file for static paths and fails the build for an unknown asset" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", "title = \"T\"\nbase_url = \"https://example.com\"\n")
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        FileUtils.mkdir_p("static/css")
        File.write("static/css/site.css", "a{}")
        File.write("content/page.md", "---\ntitle: Test\n---\nHello")
        File.write("templates/page.html", %(<link integrity="{{ asset_integrity(name='/css/site.css') }}">))

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false)
        builder.run(options).should be_true
        File.read("public/page/index.html").should eq(%(<link integrity="#{Hwaro::Utils::DigestUtils.sri("a{}")}">))

        File.write("templates/page.html", %({{ asset_integrity(name='missing.css') }}))
        expect_raises(Exception, /asset_integrity: unknown asset 'missing.css'/) { builder.run(options) }
      end
    end
  end
end

private def integrity_build(cache : Bool = false, drafts : Bool = false, minify : Bool = false)
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public", parallel: false, highlight: false, cache: cache, drafts: drafts, minify: minify,
  )).should be_true
end

private def integrity_site(config_extra : String = "", &)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      File.write("config.toml", "title = \"T\"\nbase_url = \"https://example.com\"\n#{config_extra}")
      FileUtils.mkdir_p("content")
      FileUtils.mkdir_p("templates")
      FileUtils.mkdir_p("static")
      File.write("content/page.md", "---\ntitle: Test\n---\nHello")
      yield
    end
  end
end

describe "Asset Pipeline: asset_integrity() on content-copied files" do
  # Page-bundle assets are copied in the Write phase, after rendering: a cold
  # build found no emitted file, and a warm one hashed the previous copy.
  it "hashes a page-bundle asset's source on cold and warm builds" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", "title = \"T\"\nbase_url = \"https://example.com\"\n")
        FileUtils.mkdir_p("content/bund")
        FileUtils.mkdir_p("templates")
        File.write("content/bund/index.md", "+++\ntitle = \"B\"\n+++\nb")
        File.write("content/bund/app.js", "one()")
        File.write("templates/page.html", %(<s i="{{ asset_integrity(name='bund/app.js') }}">))

        started = Time.utc
        integrity_build(cache: true)
        File.read("public/bund/index.html").should eq(%(<s i="#{Hwaro::Utils::DigestUtils.sri("one()")}">))

        # Worst case for the copy's size + mtime skip (#857): the same-size
        # rewrite lands in the newest timestamp tick already on disk — the
        # source's own, or the copy's when the copy kept its write time.
        # Only reachable while that tick is recent.
        pending!("cold build outlasted the racy window") if Time.utc - started >= 2.seconds
        tick = {File.info("content/bund/app.js").modification_time, File.info("public/bund/app.js").modification_time}.max
        File.write("content/bund/app.js", "two()")
        File.touch("content/bund/app.js", tick)
        integrity_build(cache: true)
        File.read("public/bund/index.html").should eq(%(<s i="#{Hwaro::Utils::DigestUtils.sri("two()")}">))
        Hwaro::Utils::DigestUtils.sri_file("public/bund/app.js").should eq(Hwaro::Utils::DigestUtils.sri("two()"))
      end
    end
  end
end

describe "Asset Pipeline: [build] hooks.post and integrity" do
  # Integrity is printed at Render; a post hook rewriting the file afterwards
  # leaves every page pointing at bytes that no longer ship.
  it "warns when a post hook rewrites a file whose integrity was printed" do
    posix_only!("the hook is a POSIX shell command")
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", <<-TOML
          title = "T"
          base_url = "https://example.com"

          [build]
          hooks.post = ["sh -c 'printf x >> public/css/site.css'"]
          TOML
        )
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        FileUtils.mkdir_p("static/css")
        File.write("static/css/site.css", "a{}")
        File.write("content/page.md", "---\ntitle: Test\n---\nHello")
        File.write("templates/page.html", %(<link integrity="{{ asset_integrity(name='css/site.css') }}">))

        previous = Hwaro::Logger.err_io
        err = IO::Memory.new
        Hwaro::Logger.err_io = err
        begin
          integrity_build
        ensure
          Hwaro::Logger.err_io = previous
        end
        err.to_s.should contain("hooks.post changed #{File.expand_path("public/css/site.css")}")
      end
    end
  end
end

# A warm `--cache` build must agree with a cold one: the previous build's
# files stay in the output until Finalize prunes them, and hashing one of
# those printed the value of a file about to vanish.
describe "Asset Pipeline: asset_integrity() agrees between cold and --cache builds" do
  it "raises for a deleted static file on a warm build, as a cold build does" do
    integrity_site do
      File.write("static/old.css", "a{}")
      File.write("templates/page.html", %(<link integrity="{{ asset_integrity(name='old.css') }}">))
      integrity_build(cache: true)

      File.delete("static/old.css")
      expect_raises(Exception, /unknown asset 'old.css'/) { integrity_build(cache: true) }
    end
  end

  it "raises for the asset of a bundle that became withheld" do
    integrity_site do
      FileUtils.mkdir_p("content/dr")
      File.write("content/dr/index.md", "+++\ntitle = \"D\"\ndraft = true\n+++\nd")
      File.write("content/dr/s.js", "s()")
      File.write("templates/page.html", %(<s i="{{ asset_integrity(name='dr/s.js') }}">))
      integrity_build(cache: true, drafts: true)
      File.read("public/page/index.html").should contain(Hwaro::Utils::DigestUtils.sri("s()"))

      expect_raises(Exception, /unknown asset 'dr\/s.js'/) { integrity_build(cache: true) }
    end
  end

  # `--minify` rewrites raw .json/.xml/.html after rendering, so there are no
  # final bytes to hash yet: the call raises on every build, never answering
  # with the previous build's copy.
  it "raises for a --minify-rewritten raw file even when a previous copy exists" do
    integrity_site("[content.files]\nallow_extensions = [\"json\"]\n") do
      FileUtils.mkdir_p("content/docs")
      File.write("content/docs/data.json", %({ "a": 1 }))
      File.write("templates/page.html", %(<s i="{{ asset_integrity(name='docs/data.json') }}">))
      integrity_build(cache: true)
      File.exists?("public/docs/data.json").should be_true

      expect_raises(Exception, /unknown asset 'docs\/data.json'/) { integrity_build(cache: true, minify: true) }
    end
  end

  # The warm build's cache probe hashes the previous copy of a file Finalize
  # then prunes; that is the build's own doing, not the post hook's.
  it "does not blame hooks.post for a file the build itself removed" do
    posix_only!("the hook is a POSIX shell command")
    integrity_site("[build]\nhooks.post = [\"true\"]\n") do
      File.write("static/old.css", "a{}")
      File.write("templates/page.html", %(<link integrity="{{ asset_integrity(name='old.css') }}">))
      integrity_build(cache: true)

      File.delete("static/old.css")
      File.write("templates/page.html", %(<p>{{ content }}</p>))
      previous = Hwaro::Logger.err_io
      err = IO::Memory.new
      Hwaro::Logger.err_io = err
      begin
        integrity_build(cache: true)
      ensure
        Hwaro::Logger.err_io = previous
      end
      err.to_s.should_not contain("hooks.post changed")
    end
  end
end
