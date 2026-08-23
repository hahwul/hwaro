require "../spec_helper"

# Regression specs for `hwaro tool agents-md --write` merging.
#
# The `## Site-Specific Instructions` marker used to be located by FIRST
# SUBSTRING occurrence, so a mention of the heading inside a code fence or
# mid-prose shifted the merge point — duplicating stale generated content or
# silently discarding user sections above the real heading. The marker is now
# matched as a full line, skipping fenced code blocks.
describe "agents-md site-section merge" do
  marker = Hwaro::Services::Defaults::AgentsMd::SITE_SECTION_MARKER

  it "ignores a marker mentioned inside a code fence" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("AGENTS.md", <<-MD)
          # AGENTS.md - AI Agent Instructions for Hwaro Site

          Some stale generated body.

          ```markdown
          #{marker}
          ```

          More stale generated body.

          #{marker}

          - Always deploy on Friday
          MD

        with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::AgentsMdCommand.new
          cmd.run(["--write", "--force"])
        end

        merged = File.read("AGENTS.md")
        # The user's section survives...
        merged.should contain("Always deploy on Friday")
        # ...but the merge point is the REAL heading, not the fenced mention:
        # nothing between the fence and the real heading leaks through, and
        # the heading appears exactly once.
        merged.should_not contain("More stale generated body")
        merged.scan(/^#{Regex.escape(marker)}$/m).size.should eq(1)
      end
    end
  end

  it "ignores a marker mentioned mid-prose" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("AGENTS.md", <<-MD)
          # AGENTS.md - AI Agent Instructions for Hwaro Site

          See the #{marker} heading below for user rules.

          #{marker}

          - My custom rule
          MD

        with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::AgentsMdCommand.new
          cmd.run(["--write", "--force"])
        end

        merged = File.read("AGENTS.md")
        merged.should contain("- My custom rule")
        # The prose sentence belongs to the replaced generated body; a
        # substring match used to cut the file mid-sentence there.
        merged.should_not contain("heading below for user rules")
      end
    end
  end

  it "still preserves a normal user section across regeneration" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        with_captured_log do
          Hwaro::CLI::Commands::Tool::AgentsMdCommand.new.run(["--write"])
        end
        File.write("AGENTS.md", File.read("AGENTS.md") + "\n- Custom: use pnpm\n")

        output = with_captured_log do
          Hwaro::CLI::Commands::Tool::AgentsMdCommand.new.run(["--write", "--force"])
        end

        output.should contain("site-specific section preserved")
        File.read("AGENTS.md").should contain("- Custom: use pnpm")
      end
    end
  end

  it "treats a file whose only marker is fenced as having no marker (full rewrite)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("AGENTS.md", <<-MD)
          # Some other document

          ```markdown
          #{marker}
          ```

          - not a real site section
          MD

        output = with_captured_log do
          Hwaro::CLI::Commands::Tool::AgentsMdCommand.new.run(["--write", "--force"])
        end

        # The warning names the missing heading, and the file is regenerated
        # wholesale instead of being stitched at the fenced mention.
        output.should contain("no '#{marker}' heading")
        File.read("AGENTS.md").should eq(Hwaro::Services::Defaults::AgentsMd.content)
      end
    end
  end

  # Review follow-up: a marker indented 1-3 spaces still renders as the same
  # heading and used to be preserved by the substring search; the line-anchored
  # regex must keep matching it.
  it "preserves a user section under a slightly indented marker" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("AGENTS.md", <<-MD)
          # AGENTS.md - AI Agent Instructions for Hwaro Site

          Stale body.

           #{marker}

          - Always deploy on Friday
          MD

        with_captured_log do
          Hwaro::CLI::Commands::Tool::AgentsMdCommand.new.run(["--write", "--force"])
        end

        File.read("AGENTS.md").should contain("Always deploy on Friday")
      end
    end
  end

  # Review follow-up: requiring the marker to be the ENTIRE line meant a
  # user-annotated heading was no longer found and --force discarded the
  # section the annotation asked to keep.
  it "preserves a user section under an annotated marker heading" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("AGENTS.md", <<-MD)
          # AGENTS.md - AI Agent Instructions for Hwaro Site

          Stale body.

          #{marker} (do not delete)

          - Always deploy on Friday
          MD

        with_captured_log do
          Hwaro::CLI::Commands::Tool::AgentsMdCommand.new.run(["--write", "--force"])
        end

        File.read("AGENTS.md").should contain("Always deploy on Friday")
      end
    end
  end

  # Review follow-up: a closing fence carries no info string (CommonMark), so
  # a ```text line inside an open block must NOT flip the parity and expose a
  # quoted marker as the merge point.
  it "does not treat an info-string fence line as a closer" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("AGENTS.md", <<-MD)
          # AGENTS.md - AI Agent Instructions for Hwaro Site

          ```markdown
          ```text
          #{marker}
          ```

          Stale generated body.

          #{marker}

          - Always deploy on Friday
          MD

        with_captured_log do
          Hwaro::CLI::Commands::Tool::AgentsMdCommand.new.run(["--write", "--force"])
        end

        merged = File.read("AGENTS.md")
        merged.should contain("Always deploy on Friday")
        merged.should_not contain("Stale generated body")
      end
    end
  end

  # Review follow-up: the unclosed-fence fallback must scan only FROM the
  # open fence — a marker quoted in an earlier properly CLOSED fence must
  # never become the merge point.
  it "ignores a closed-fence quote even when a later fence is unclosed" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("AGENTS.md", <<-MD)
          # AGENTS.md - AI Agent Instructions for Hwaro Site

          ```markdown
          #{marker}
          ```

          Stale generated body.

          ```bash
          hwaro build

          #{marker}

          - Always deploy on Friday
          MD

        with_captured_log do
          Hwaro::CLI::Commands::Tool::AgentsMdCommand.new.run(["--write", "--force"])
        end

        merged = File.read("AGENTS.md")
        merged.should contain("Always deploy on Friday")
        merged.should_not contain("Stale generated body")
      end
    end
  end

  # Review follow-up: an unclosed fence above the marker swallowed the rest of
  # the file, so the real heading was invisible and --force destroyed the
  # user's section. The scanner now falls back to a fence-blind pass when the
  # file ends inside an open fence.
  it "preserves a user section below an unclosed fence" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("AGENTS.md", <<-MD)
          # AGENTS.md - AI Agent Instructions for Hwaro Site

          ```bash
          hwaro build

          #{marker}

          - Always deploy on Friday
          MD

        with_captured_log do
          Hwaro::CLI::Commands::Tool::AgentsMdCommand.new.run(["--write", "--force"])
        end

        File.read("AGENTS.md").should contain("Always deploy on Friday")
      end
    end
  end
end
