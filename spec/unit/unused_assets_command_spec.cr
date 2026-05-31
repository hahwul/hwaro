require "../spec_helper"

# Capture human-readable Logger output while running a block, restoring all
# global Logger state afterwards.
private def capture_unused_log(&)
  previous_io = Hwaro::Logger.io
  previous_level = Hwaro::Logger.level
  previous_quiet = Hwaro::Logger.quiet?
  sink = IO::Memory.new
  Hwaro::Logger.io = sink
  Hwaro::Logger.level = Hwaro::Logger::Level::Info
  Hwaro::Logger.quiet = false
  begin
    yield
    sink.to_s
  ensure
    Hwaro::Logger.io = previous_io
    Hwaro::Logger.level = previous_level
    Hwaro::Logger.quiet = previous_quiet
  end
end

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

        output = capture_unused_log do
          cmd = Hwaro::CLI::Commands::Tool::UnusedAssetsCommand.new
          cmd.run(["-c", content_dir, "-s", static_dir])
        end

        output.should contain("Scanning for unused assets")
        output.should contain("No unused assets found")
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

        output = capture_unused_log do
          cmd = Hwaro::CLI::Commands::Tool::UnusedAssetsCommand.new
          cmd.run(["-c", content_dir, "-s", static_dir])
        end

        output.should contain("Total assets:")
        output.should contain("Unused files:")
        output.should contain("orphan.png")
      end
    end
  end
end
