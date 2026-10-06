require "../spec_helper"
require "../../src/services/server/server"

# Serve: a save of a file an include call or a transclusion read re-renders
# the pages that include it, including files outside every watch root (#838).

module Hwaro
  module Services
    class Server
      def include_spec_builder : Hwaro::Core::Build::Builder
        @builder
      end

      def include_spec_scan : Hash(String, FileStamp)
        scan_mtimes
      end

      def include_spec_detect(old_mtimes : Hash(String, FileStamp), new_mtimes : Hash(String, FileStamp)) : ChangeSet
        detect_changes(old_mtimes, new_mtimes)
      end

      def include_spec_apply(changeset : ChangeSet, options : Config::Options::BuildOptions)
        apply_changeset(changeset, options)
      end
    end
  end
end

private def include_serve_options : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false)
  options.serve_mode = true
  options.preserve_output = true
  options
end

private def include_serve_site(wikilinks : Bool = false) : Nil
  File.write("config.toml", %(title = "t"\nbase_url = "https://example.com"\n) + (wikilinks ? "[markdown]\nwikilinks = true\n" : ""))
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates")
  FileUtils.mkdir_p("examples")
  File.write("templates/page.html", "<main>{{ content }}</main>")
  File.write("examples/a.cr", "puts 1\n")
  File.write("content/p.md", %(+++\ntitle = "P"\n+++\n{{ include_code(path="examples/a.cr") }}\n))
end

describe "serve: include sources" do
  it "watches an included file outside the roots and re-renders its includer" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        include_serve_site
        server = Hwaro::Services::Server.new
        options = include_serve_options
        before = server.include_spec_scan
        server.include_spec_builder.run(options).should be_true
        File.read("public/p/index.html").should contain("puts 1")

        # Learned from the build; its first stamp is not a change.
        after_build = server.include_spec_scan
        after_build.has_key?("examples/a.cr").should be_true
        server.include_spec_detect(before, after_build).empty?.should be_true

        File.write("examples/a.cr", "puts 2\n")
        File.touch("examples/a.cr", Time.local + 2.seconds)
        changeset = server.include_spec_detect(after_build, server.include_spec_scan)
        changeset.empty?.should be_false
        server.include_spec_apply(changeset, options)
        File.read("public/p/index.html").should contain("puts 2")
      end
    end
  end

  it "reports an edit made before the first scan, but not a byte-identical rewrite" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        include_serve_site
        server = Hwaro::Services::Server.new
        before = server.include_spec_scan
        server.include_spec_builder.run(include_serve_options).should be_true

        # Saved between the build's read and the watcher's first stamp.
        File.write("examples/a.cr", "puts 3\n")
        first = server.include_spec_scan
        server.include_spec_detect(before, first).modified_data.should eq(["examples/a.cr"])

        # A hook (or an editor) rewriting the same bytes is not a change.
        File.write("examples/a.cr", "puts 3\n")
        File.touch("examples/a.cr", Time.local + 2.seconds)
        server.include_spec_detect(first, server.include_spec_scan).empty?.should be_true
      end
    end
  end

  it "never watches a refused path, which could loop on serve's own output" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        include_serve_site
        File.write("content/p.md", %(+++\ntitle = "P"\n+++\n{{ include_code(path=".hwaro/serve/p/index.html") }}\n))
        server = Hwaro::Services::Server.new
        expect_raises(Hwaro::HwaroError, "inside the build output") { server.include_spec_builder.run(include_serve_options) }
        server.include_spec_builder.include_sources.should be_empty
      end
    end
  end

  it "re-renders the transcluding page when the transcluded page is saved" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        include_serve_site(wikilinks: true)
        File.write("content/note.md", "+++\ntitle = \"Note\"\n+++\nfirst\n")
        File.write("content/t.md", "+++\ntitle = \"T\"\n+++\n![[note]]\n")
        server = Hwaro::Services::Server.new
        options = include_serve_options
        server.include_spec_builder.run(options).should be_true
        File.read("public/t/index.html").should contain("first")

        File.write("content/note.md", "+++\ntitle = \"Note\"\n+++\nsecond\n")
        File.touch("content/note.md", Time.local + 2.seconds)
        changeset = Hwaro::Services::ChangeSet.new(
          modified_content: ["content/note.md"],
          modified_templates: [] of String,
          modified_static: [] of String,
          added_files: [] of String,
          removed_files: [] of String,
          config_changed: false,
        )
        server.include_spec_apply(changeset, options)
        File.read("public/t/index.html").should contain("second")
      end
    end
  end

  it "forgets a file no page includes any more on the next full build" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        include_serve_site
        server = Hwaro::Services::Server.new
        builder = server.include_spec_builder
        builder.run(include_serve_options).should be_true
        tracked = server.include_spec_scan
        builder.include_source_changed?(["examples/a.cr"]).should be_true

        File.write("content/p.md", "+++\ntitle = \"P\"\n+++\nplain\n")
        builder.run(include_serve_options).should be_true
        builder.include_source_changed?(["examples/a.cr"]).should be_false
        # Leaving the snapshot is not a deletion.
        server.include_spec_detect(tracked, server.include_spec_scan).removed_files.should be_empty
      end
    end
  end
end
