require "../../../spec_helper"
require "../../../../src/services/server/server"

module Hwaro
  module Services
    class Server
      def watch_spec_builder : Hwaro::Core::Build::Builder
        @builder
      end

      def watch_spec_scan : Hash(String, FileStamp)
        scan_mtimes
      end

      def watch_spec_detect(old_mtimes : Hash(String, FileStamp), new_mtimes : Hash(String, FileStamp)) : ChangeSet
        detect_changes(old_mtimes, new_mtimes)
      end

      def watch_spec_apply(changeset : ChangeSet, options : Config::Options::BuildOptions)
        apply_changeset(changeset, options)
      end
    end
  end
end

# A literal `load_data()` path outside every watch root was never stamped, so
# editing it rebuilt nothing for the rest of the session.
describe "serve: load_data sources outside the watch roots" do
  it "rebuilds the pages printing the data when the file changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "t"\nbase_url = "https://example.com"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        FileUtils.mkdir_p("extra")
        File.write("templates/page.html", %({{ load_data(path="extra/m.json").v }}))
        File.write("extra/m.json", %({"v": "one"}))
        File.write("content/p.md", "+++\ntitle = \"P\"\n+++\n")

        server = Hwaro::Services::Server.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        server.watch_spec_builder.run(options).should be_true
        File.read("public/p/index.html").should eq("one")

        before = server.watch_spec_scan
        File.write("extra/m.json", %({"v": "three"}))
        changeset = server.watch_spec_detect(before, server.watch_spec_scan)
        changeset.empty?.should be_false
        server.watch_spec_apply(changeset, options)
        File.read("public/p/index.html").should eq("three")
      end
    end
  end
end

# Same for the auto OG images' logo: `logo = "brand/logo.png"` sits outside
# every root, so swapping it never regenerated the images.
describe "serve: OG image assets outside the watch roots" do
  it "reports a logo edit as a full-rebuild change" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "t"\nbase_url = "https://example.com"\n[og.auto_image]\nenabled = true\nlogo = "brand/logo.png"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("brand")
        File.write("brand/logo.png", "old")
        File.write("content/p.md", "+++\ntitle = \"P\"\n+++\n")

        server = Hwaro::Services::Server.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, skip_og_image: true)
        options.serve_mode = true
        server.watch_spec_builder.run(options).should be_true

        before = server.watch_spec_scan
        File.write("brand/logo.png", "newer")
        server.watch_spec_detect(before, server.watch_spec_scan).needs_full_rebuild?.should be_true
      end
    end
  end
end
