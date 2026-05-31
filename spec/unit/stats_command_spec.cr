require "../spec_helper"

# Command-level tests for `hwaro tool stats`.
#
# The ContentStats service is exercised in spec/unit/content_stats_spec.cr;
# these tests cover the command wrapper's metadata and its human-readable
# rendering of the statistics (overview, word counts, tags, monthly buckets).
describe Hwaro::CLI::Commands::Tool::StatsCommand do
  describe ".metadata" do
    it "reports the command name and description" do
      meta = Hwaro::CLI::Commands::Tool::StatsCommand.metadata
      meta.name.should eq("stats")
      meta.description.should_not be_empty
    end

    it "exposes the content-dir and json flags" do
      meta = Hwaro::CLI::Commands::Tool::StatsCommand.metadata
      meta.flags.any? { |f| f.long == "--content-dir" }.should be_true
      meta.flags.any? { |f| f.long == "--json" }.should be_true
    end
  end

  describe "#run" do
    it "reports when no content is found" do
      Dir.mktmpdir do |dir|
        output = with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::StatsCommand.new
          cmd.run(["-c", dir])
        end
        output.should contain("No content found")
      end
    end

    it "renders an overview, word counts, tags and monthly frequency" do
      Dir.mktmpdir do |dir|
        File.write(
          File.join(dir, "first.md"),
          "---\ntitle: First\ndate: 2024-01-10\ntags:\n  - crystal\n  - web\n---\nHello world here are some words.\n"
        )
        File.write(
          File.join(dir, "second.md"),
          "---\ntitle: Second\ndate: 2024-02-20\ntags:\n  - crystal\n---\nMore content with several words inside.\n"
        )

        output = with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::StatsCommand.new
          cmd.run(["-c", dir])
        end

        output.should contain("Content statistics")
        output.should contain("Overview:")
        output.should contain("Total:")
        output.should contain("Word Count")
        output.should contain("Tags")
        output.should contain("crystal")
        output.should contain("Monthly Publishing")
      end
    end
  end
end
