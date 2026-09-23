require "../../../../spec_helper"

# Command-level tests for `hwaro tool agents-md`.
#
# The generated content itself is exercised in spec/unit/defaults_agents_md_spec.cr;
# these tests cover the command wrapper: metadata and the `--write` path
# (local and remote) that persists AGENTS.md. The interactive overwrite prompt
# (which reads stdin and may `exit`) is intentionally not exercised here.
describe Hwaro::CLI::Commands::Tool::AgentsMdCommand do
  describe ".metadata" do
    it "reports the command name and description" do
      meta = Hwaro::CLI::Commands::Tool::AgentsMdCommand.metadata
      meta.name.should eq("agents-md")
      meta.description.should_not be_empty
    end

    it "exposes the remote, local, write and force flags" do
      meta = Hwaro::CLI::Commands::Tool::AgentsMdCommand.metadata
      meta.flags.any? { |f| f.long == "--remote" }.should be_true
      meta.flags.any? { |f| f.long == "--local" }.should be_true
      meta.flags.any? { |f| f.long == "--write" }.should be_true
      meta.flags.any? { |f| f.long == "--force" }.should be_true
    end
  end

  describe "#run" do
    it "writes the local AGENTS.md and logs success" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          output = with_captured_log do
            cmd = Hwaro::CLI::Commands::Tool::AgentsMdCommand.new
            cmd.run(["--write"])
          end

          output.should contain("local mode")
          File.exists?(File.join(dir, "AGENTS.md")).should be_true
          File.read(File.join(dir, "AGENTS.md")).should eq(Hwaro::Services::Defaults::AgentsMd.content)
        end
      end
    end

    it "writes the remote AGENTS.md variant when --remote is given" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          output = with_captured_log do
            cmd = Hwaro::CLI::Commands::Tool::AgentsMdCommand.new
            cmd.run(["--remote", "--write"])
          end

          output.should contain("remote mode")
          File.read(File.join(dir, "AGENTS.md")).should eq(Hwaro::Services::Defaults::AgentsMd.remote_content)
        end
      end
    end

    it "refuses to write through a dangling AGENTS.md symlink outside the project" do
      Dir.mktmpdir do |dir|
        project = File.join(dir, "project")
        outside = File.join(dir, "outside")
        Dir.mkdir(project)
        Dir.mkdir(outside)
        target = File.join(outside, "generated.md")
        Dir.cd(project) do
          File.symlink(target, "AGENTS.md")

          expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::Tool::AgentsMdCommand.new.run(["--write"])
          end
        end

        File.exists?(target).should be_false
      end
    end

    it "refuses to write through an AGENTS.md symlink to an existing file outside the project" do
      Dir.mktmpdir do |dir|
        project = File.join(dir, "project")
        Dir.mkdir(project)
        target = File.join(dir, "shared.md")
        File.write(target, "shared")
        Dir.cd(project) do
          File.symlink("../shared.md", "AGENTS.md")

          expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::Tool::AgentsMdCommand.new.run(["--write", "--force"])
          end
        end

        File.read(target).should eq("shared")
      end
    end

    it "writes through an AGENTS.md symlink to a file inside the project" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("CLAUDE.md", "old")
          File.symlink("CLAUDE.md", "AGENTS.md")

          with_captured_log do
            Hwaro::CLI::Commands::Tool::AgentsMdCommand.new.run(["--write", "--force"])
          end

          File.symlink?("AGENTS.md").should be_true
          File.read("CLAUDE.md").should eq(Hwaro::Services::Defaults::AgentsMd.content)
        end
      end
    end

    it "creates the target of a dangling AGENTS.md symlink inside the project" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          Dir.mkdir("docs")
          File.symlink("docs/agents.md", "AGENTS.md")

          with_captured_log do
            Hwaro::CLI::Commands::Tool::AgentsMdCommand.new.run(["--write"])
          end

          File.symlink?("AGENTS.md").should be_true
          File.read(File.join("docs", "agents.md")).should eq(Hwaro::Services::Defaults::AgentsMd.content)
        end
      end
    end

    it "overwrites an existing AGENTS.md when --force is given" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("AGENTS.md", "stale content")

          with_captured_log do
            cmd = Hwaro::CLI::Commands::Tool::AgentsMdCommand.new
            cmd.run(["--write", "--force"])
          end

          File.read(File.join(dir, "AGENTS.md")).should eq(Hwaro::Services::Defaults::AgentsMd.content)
        end
      end
    end

    it "logs 'updated' when overwriting an existing AGENTS.md with --force" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("AGENTS.md", "stale content")

          output = with_captured_log do
            cmd = Hwaro::CLI::Commands::Tool::AgentsMdCommand.new
            cmd.run(["--write", "--force"])
          end

          output.should contain("updated")
          output.should_not contain("created")
        end
      end
    end
  end
end
