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
end
