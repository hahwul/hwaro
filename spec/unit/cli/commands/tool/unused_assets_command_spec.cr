require "../../../../spec_helper"

# Command-level tests for `hwaro tool unused-assets`.
#
# The UnusedAssets service is exercised in spec/unit/unused_assets_spec.cr;
# these tests cover the command wrapper's metadata and its rendering of the
# scan summary, the "no unused assets" path, and the list of unused files.
describe Hwaro::CLI::Commands::Tool::UnusedAssetsCommand do
  describe ".metadata" do
    it "reports the command name and description" do
      meta = Hwaro::CLI::Commands::Tool::UnusedAssetsCommand.metadata
      meta.name.should eq("unused-assets")
      meta.description.should_not be_empty
    end

    it "exposes the static-dir, delete and json flags" do
      meta = Hwaro::CLI::Commands::Tool::UnusedAssetsCommand.metadata
      meta.flags.any? { |f| f.long == "--static-dir" }.should be_true
      meta.flags.any? { |f| f.long == "--delete" }.should be_true
      meta.flags.any? { |f| f.long == "--json" }.should be_true
    end
  end

  describe "#run" do
    it "reports when there are no unused assets" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        # A static asset that is referenced by content → not unused.
        File.write(File.join(static_dir, "logo.png"), "binary")
        File.write(
          File.join(content_dir, "page.md"),
          "---\ntitle: Page\n---\n\n![Logo](/logo.png)\n"
        )

        output = with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::UnusedAssetsCommand.new
          cmd.run(["-c", content_dir, "-s", static_dir])
        end

        output.should contain("hwaro: unused-assets")
        output.should contain("found: no unused assets")
      end
    end

    it "lists unused files and a scan summary" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        # An asset nothing references → reported as unused.
        File.write(File.join(static_dir, "orphan.png"), "binary")
        File.write(
          File.join(content_dir, "page.md"),
          "---\ntitle: Page\n---\n\nNo images referenced here.\n"
        )

        output = with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::UnusedAssetsCommand.new
          cmd.run(["-c", content_dir, "-s", static_dir])
        end

        output.should contain("total:")
        output.should contain("unused files:")
        output.should contain("orphan.png")
        output.should contain("found: 1 unused asset")
      end
    end

    # Regression: an explicitly passed `--templates-dir templates` was
    # indistinguishable from the default inside the service and got silently
    # re-rooted to <project_root>/templates — even though the command had
    # just existence-checked ./templates. Every template-referenced asset
    # then came back "unused", and `--delete --force` removed in-use files.
    it "scans an explicitly passed --templates-dir even when it matches the default name" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          # ./templates exists (the command existence-checks it) and holds
          # the only reference to keep.png...
          FileUtils.mkdir_p("templates")
          File.write(File.join("templates", "base.html"), %(<img src="/keep.png">))

          # ...while the project root resolves to proj/, which has no
          # templates directory of its own.
          proj = File.join(dir, "proj")
          FileUtils.mkdir_p(File.join(proj, "content"))
          FileUtils.mkdir_p(File.join(proj, "static"))
          File.write(File.join(proj, "config.toml"), "title = \"P\"\n")
          File.write(File.join(proj, "static", "keep.png"), "png")
          File.write(File.join(proj, "content", "post.md"), "---\ntitle: P\n---\nBody\n")

          output = with_captured_log do
            cmd = Hwaro::CLI::Commands::Tool::UnusedAssetsCommand.new
            cmd.run([
              "-c", File.join(proj, "content"),
              "-s", File.join(proj, "static"),
              "--templates-dir", "templates",
            ])
          end

          output.should contain("found: no unused assets")
        end
      end
    end
  end
end
