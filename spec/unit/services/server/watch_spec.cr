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

      # How often the watcher asked whether a path is ignored.
      class_property watch_spec_ignore_probes = 0

      private def content_ignored?(path : String) : Bool
        Server.watch_spec_ignore_probes += 1
        previous_def
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

# `[content] ignore` (#890): the build never reads an ignored path, so its
# edits, additions and removals are not changes; editing the patterns is a
# config change and runs the full rebuild that applies them.
describe "serve: [content] ignore" do
  it "reports no change for an ignored path and still reports real content" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "t"\nbase_url = "https://example.com"\n[content]\nignore = ["_templates"]\n))
        FileUtils.mkdir_p("content/_templates")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ content }}")
        File.write("content/p.md", "+++\ntitle = \"P\"\n+++\none\n")
        File.write("content/_templates/n.md", "# n\n")

        server = Hwaro::Services::Server.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        server.watch_spec_builder.run(options).should be_true
        Dir.exists?("public/_templates").should be_false

        before = server.watch_spec_scan
        File.write("content/_templates/n.md", "# edited, and longer\n")
        File.write("content/_templates/new.md", "# new\n")
        File.write("content/_templates/pic.png", "png")
        after = server.watch_spec_scan
        server.watch_spec_detect(before, after).empty?.should be_true

        File.delete("content/_templates/n.md")
        server.watch_spec_detect(after, server.watch_spec_scan).empty?.should be_true

        before = server.watch_spec_scan
        File.write("content/p.md", "+++\ntitle = \"P\"\n+++\ntwo, longer\n")
        server.watch_spec_detect(before, server.watch_spec_scan).modified_content.should eq(["content/p.md"])
      end
    end
  end

  # The watcher diffs every poll; an unchanged path must cost only the stamp
  # compare, never a pattern match.
  it "does not match unchanged paths against the ignore list" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "t"\nbase_url = "https://example.com"\n[content]\nignore = ["_templates"]\n))
        FileUtils.mkdir_p("content/_templates")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ content }}")
        File.write("content/p.md", "+++\ntitle = \"P\"\n+++\n")
        File.write("content/_templates/n.md", "# n\n")

        server = Hwaro::Services::Server.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        server.watch_spec_builder.run(options).should be_true

        snapshot = server.watch_spec_scan
        Hwaro::Services::Server.watch_spec_ignore_probes = 0
        server.watch_spec_detect(snapshot, snapshot.dup).empty?.should be_true
        Hwaro::Services::Server.watch_spec_ignore_probes.should eq(0)
      end
    end
  end

  it "applies an edited ignore list through a full rebuild" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "t"\nbase_url = "https://example.com"\n[content]\nignore = ["README.md"]\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ content }}")
        File.write("content/README.md", "readme\n")

        server = Hwaro::Services::Server.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        server.watch_spec_builder.run(options).should be_true
        File.exists?("public/README/index.html").should be_false

        before = server.watch_spec_scan
        File.write("config.toml", %(title = "t"\nbase_url = "https://example.com"\n))
        changeset = server.watch_spec_detect(before, server.watch_spec_scan)
        changeset.needs_full_rebuild?.should be_true
        server.watch_spec_apply(changeset, options)
        File.exists?("public/README/index.html").should be_true
      end
    end
  end

  # Ignoring a partials folder hides it from discovery, not from
  # `include_md` or `load_data()`: an edit must re-render the readers.
  it "rebuilds when an ignored include_md or load_data source changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "t"\nbase_url = "https://example.com"\n[content]\nignore = ["_snippets"]\n))
        FileUtils.mkdir_p("content/_snippets")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", %({{ content }}|{{ load_data(path="content/_snippets/d.json").v }}))
        File.write("content/_snippets/s.md", "snippet one\n")
        File.write("content/_snippets/d.json", %({"v": "data one"}))
        File.write("content/_snippets/other.md", "unread\n")
        File.write("content/p.md", "+++\ntitle = \"P\"\n+++\n{{ include_md(path=\"content/_snippets/s.md\") }}\n")

        server = Hwaro::Services::Server.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        server.watch_spec_builder.run(options).should be_true
        File.read("public/p/index.html").should contain("snippet one")
        Dir.exists?("public/_snippets").should be_false

        before = server.watch_spec_scan
        File.write("content/_snippets/s.md", "snippet two, longer\n")
        changeset = server.watch_spec_detect(before, server.watch_spec_scan)
        changeset.needs_full_rebuild?.should be_true
        server.watch_spec_apply(changeset, options)
        File.read("public/p/index.html").should contain("snippet two")

        before = server.watch_spec_scan
        File.write("content/_snippets/d.json", %({"v": "data two, longer"}))
        changeset = server.watch_spec_detect(before, server.watch_spec_scan)
        changeset.needs_full_rebuild?.should be_true
        server.watch_spec_apply(changeset, options)
        File.read("public/p/index.html").should contain("data two")
        Dir.exists?("public/_snippets").should be_false

        # A file of the same folder that nothing reads stays no change.
        before = server.watch_spec_scan
        File.write("content/_snippets/other.md", "still unread, longer\n")
        server.watch_spec_detect(before, server.watch_spec_scan).empty?.should be_true
      end
    end
  end
end
