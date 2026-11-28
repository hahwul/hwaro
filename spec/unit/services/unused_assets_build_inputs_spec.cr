require "../../spec_helper"

# Files the build itself links or reads were invisible to the reference scan,
# so they were reported unused — and `--delete` removed files a build still
# ships.
private def build_input_unused(dir : String) : Array(String)
  Hwaro::Services::UnusedAssets.new(
    content_dir: File.join(dir, "content"),
    static_dir: File.join(dir, "static"),
    templates_dir: File.join(dir, "templates"),
  ).run.unused_files.map { |f| Path[f].relative_to(dir).to_s }.sort!
end

private def build_input_project(dir : String, config : String)
  %w[content static templates].each { |d| FileUtils.mkdir_p(File.join(dir, d)) }
  File.write(File.join(dir, "content", "_index.md"), "+++\ntitle = \"H\"\n+++\nBody")
  File.write(File.join(dir, "config.toml"), "title = \"T\"\nbase_url = \"https://example.com\"\n#{config}")
end

private def write_static(dir : String, relative : String)
  path = File.join(dir, "static", relative)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, "x")
end

describe Hwaro::Services::UnusedAssets do
  describe "self-hosted highlight.js" do
    it "keeps the files the build links when use_cdn = false" do
      Dir.mktmpdir do |dir|
        build_input_project(dir, "[highlight]\nenabled = true\ntheme = \"github\"\nuse_cdn = false\nmode = \"client\"\n")
        write_static(dir, "assets/css/highlight/github.min.css")
        write_static(dir, "assets/js/highlight.min.js")
        write_static(dir, "assets/css/highlight/monokai.min.css")

        build_input_unused(dir).should eq(["static/assets/css/highlight/monokai.min.css"])
      end
    end

    it "does not keep the script when highlighting runs at build time" do
      Dir.mktmpdir do |dir|
        build_input_project(dir, "[highlight]\nenabled = true\ntheme = \"github\"\nuse_cdn = false\nmode = \"server\"\n")
        write_static(dir, "assets/css/highlight/github.min.css")
        write_static(dir, "assets/js/highlight.min.js")

        build_input_unused(dir).should eq(["static/assets/js/highlight.min.js"])
      end
    end

    it "keeps nothing extra when the CDN serves highlight.js" do
      Dir.mktmpdir do |dir|
        build_input_project(dir, "[highlight]\nenabled = true\ntheme = \"github\"\nuse_cdn = true\n")
        write_static(dir, "assets/css/highlight/github.min.css")

        build_input_unused(dir).should eq(["static/assets/css/highlight/github.min.css"])
      end
    end
  end

  describe "asset pipeline source dir" do
    it "reads stylesheets under [assets] source_dir for references" do
      Dir.mktmpdir do |dir|
        build_input_project(dir, "[assets]\nenabled = true\nsource_dir = \"assets\"\n\n[[assets.bundles]]\nname = \"main.css\"\nfiles = [\"css/main.css\"]\n")
        FileUtils.mkdir_p(File.join(dir, "assets", "css"))
        File.write(File.join(dir, "assets", "css", "main.css"), "body{background:url(/images/bg.png)}")
        write_static(dir, "images/bg.png")
        write_static(dir, "images/orphan.png")

        build_input_unused(dir).should eq(["static/images/orphan.png"])
      end
    end
  end

  describe "environment config overrides" do
    it "keeps assets used by base and merged environment settings" do
      Dir.mktmpdir do |dir|
        build_input_project(dir, <<-TOML)
          [assets]
          enabled = true
          source_dir = "assets"

          [[assets.bundles]]
          name = "main.css"
          files = ["main.css"]

          [auto_includes]
          dirs = ["base-css"]
          TOML
        File.write(File.join(dir, "config.staging.toml"), "[assets]\nsource_dir = \"staging-assets\"\n")
        File.write(File.join(dir, "config.production.toml"), <<-TOML)
          [auto_includes]
          dirs = ["prod-css"]

          [highlight]
          enabled = true
          use_cdn = false
          theme = "github"
          TOML
        %w[assets staging-assets].each do |source|
          FileUtils.mkdir_p(File.join(dir, source))
          File.write(File.join(dir, source, "main.css"), "body{background:url(/images/#{source}.png)}")
          write_static(dir, "images/#{source}.png")
        end
        write_static(dir, "base-css/site.css")
        write_static(dir, "prod-css/site-production.css")
        write_static(dir, "assets/css/highlight/github.min.css")
        write_static(dir, "images/orphan.png")

        build_input_unused(dir).should eq(["static/images/orphan.png"])
      end
    end

    it "reads config.<env>.toml for references" do
      Dir.mktmpdir do |dir|
        build_input_project(dir, "")
        File.write(File.join(dir, "config.production.toml"), "[og]\ndefault_image = \"/images/prod-share.png\"\n")
        write_static(dir, "images/prod-share.png")
        write_static(dir, "images/orphan.png")

        build_input_unused(dir).should eq(["static/images/orphan.png"])
      end
    end
  end
end

describe "UnusedAssets: load_data() CSV sources" do
  it "keeps an image named only in a data/*.csv file load_data() reads" do
    Dir.mktmpdir do |dir|
      build_input_project(dir, "")
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "team.csv"), "name,avatar\nAlice,alice.png\n")
      write_static(dir, "img/alice.png")
      build_input_unused(dir).should be_empty
    end
  end
end
