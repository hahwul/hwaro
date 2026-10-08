require "../../../spec_helper"
require "../../../../src/services/server/server"

# Serve: a static / content-file save must refresh the outputs derived from
# those bytes (sw.js content-hashes precached files; auto OG images embed the
# logo / background image), like a cold build does.

module Hwaro
  module Services
    class Server
      def derived_spec_builder : Hwaro::Core::Build::Builder
        @builder
      end

      def derived_spec_apply(changeset : ChangeSet, options : Config::Options::BuildOptions)
        apply_changeset(changeset, options)
      end
    end
  end
end

private def derived_options : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false)
  options.serve_mode = true
  options.preserve_output = true
  options
end

private def derived_changeset(static : Array(String) = [] of String, content_files : Array(String) = [] of String) : Hwaro::Services::ChangeSet
  Hwaro::Services::ChangeSet.new([] of String, [] of String, static, [] of String, [] of String, false, content_files)
end

private def derived_cache_name : String
  File.read("public/sw.js")[/CACHE_NAME = '([^']+)'/, 1]
end

describe "serve: outputs derived from copied files" do
  it "regenerates sw.js after a static-only save of a precached file" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "t"\nbase_url = "https://example.com"\n[pwa]\nenabled = true\nprecache_urls = ["/css/main.css"]\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        FileUtils.mkdir_p("static/css")
        File.write("templates/page.html", "<main>{{ content }}</main>")
        File.write("content/index.md", "+++\ntitle = \"Home\"\n+++\nhi\n")
        File.write("static/css/main.css", "body{color:red}")

        server = Hwaro::Services::Server.new
        options = derived_options
        server.derived_spec_builder.run(options).should be_true
        before = derived_cache_name

        File.write("static/css/main.css", "body{color:blue}")
        server.derived_spec_apply(derived_changeset(static: ["static/css/main.css"]), options)

        File.read("public/css/main.css").should eq("body{color:blue}")
        derived_cache_name.should_not eq(before)
      end
    end
  end

  it "regenerates sw.js after a content-file save of a precached file" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "t"\nbase_url = "https://example.com"\n[pwa]\nenabled = true\nprecache_urls = ["/posts/foo/data.json"]\n[content.files]\nallow_extensions = ["json"]\n))
        FileUtils.mkdir_p("content/posts/foo")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "<main>{{ content }}</main>")
        File.write("content/index.md", "+++\ntitle = \"Home\"\n+++\nhi\n")
        File.write("content/posts/foo/data.json", %({"a":1}))

        server = Hwaro::Services::Server.new
        options = derived_options
        server.derived_spec_builder.run(options).should be_true
        before = derived_cache_name

        File.write("content/posts/foo/data.json", %({"a":2}))
        server.derived_spec_apply(derived_changeset(content_files: ["content/posts/foo/data.json"]), options)

        File.read("public/posts/foo/data.json").should eq(%({"a":2}))
        derived_cache_name.should_not eq(before)
      end
    end
  end

  it "regenerates auto OG images after the logo file changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "t"\nbase_url = "https://example.com"\n[og.auto_image]\nenabled = true\nformat = "svg"\nlogo = "static/logo.svg"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        FileUtils.mkdir_p("static")
        File.write("templates/page.html", "<main>{{ content }}</main>")
        File.write("content/index.md", "+++\ntitle = \"Home\"\n+++\nhi\n")
        File.write("static/logo.svg", %(<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8" fill="red"/></svg>))

        server = Hwaro::Services::Server.new
        options = derived_options
        server.derived_spec_builder.run(options).should be_true
        images = Dir.glob("public/og-images/*.svg")
        images.should_not be_empty
        before = images.map { |f| File.read(f) }

        File.write("static/logo.svg", %(<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8" fill="blue"/></svg>))
        server.derived_spec_apply(derived_changeset(static: ["static/logo.svg"]), options)

        Dir.glob("public/og-images/*.svg").map { |f| File.read(f) }.should_not eq(before)
      end
    end
  end
end
