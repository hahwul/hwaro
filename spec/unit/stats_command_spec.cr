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
        output.should contain("counted: no content found")
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

        # Plain (non-TTY) forms: receipt heading + rows, sections, outcome.
        output.should contain("hwaro: stats")
        output.should contain("total: 2 files")
        output.should contain("words:")
        output.should contain("tags:")
        output.should contain("crystal")
        output.should contain("monthly:")
        output.should contain("counted: 2 files, 2 published, 0 drafts")
      end
    end

    # Regression: the tag chart padded and truncated by CODEPOINTS, so CJK or
    # emoji labels (2 columns per glyph) misaligned every row after them.
    it "pads tag labels by display width so CJK tags stay aligned" do
      Dir.mktmpdir do |dir|
        File.write(
          File.join(dir, "one.md"),
          "---\ntitle: One\ntags:\n  - 한글태그\n  - aa\n---\nwords here\n"
        )
        File.write(
          File.join(dir, "two.md"),
          "---\ntitle: Two\ntags:\n  - 한글태그\n---\nmore words\n"
        )

        output = with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::StatsCommand.new
          cmd.run(["-c", dir])
        end

        # The label column is 8 display columns wide (한글태그 = 4 chars × 2
        # columns), so "aa" gets 6 columns of padding before the 2-space gap
        # and the 4-wide right-aligned count. Codepoint padding gave it 2.
        output.should contain("한글태그  " + "   2")
        output.should contain("aa" + " " * 6 + "  " + "   1")
      end
    end

    it "truncates overlong tag labels by display width" do
      Dir.mktmpdir do |dir|
        long_tag = "가" * 12 # 24 columns wide, but only 12 codepoints
        File.write(
          File.join(dir, "one.md"),
          "---\ntitle: One\ntags:\n  - #{long_tag}\n---\nwords\n"
        )

        output = with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::StatsCommand.new
          cmd.run(["-c", dir])
        end

        # 24 columns exceed the 20-column cap: 9 chars (18 columns) fit the
        # 19-column budget, then the ellipsis. Codepoint truncation saw only
        # 12 "characters" and never truncated at all.
        output.should_not contain(long_tag)
        output.should contain("#{"가" * 9}…")
      end
    end
  end
end
