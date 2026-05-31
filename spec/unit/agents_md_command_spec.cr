require "../spec_helper"

# Capture human-readable Logger output while running a block, restoring all
# global Logger state afterwards.
private def capture_agents_md_log(&)
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
          output = capture_agents_md_log do
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
          output = capture_agents_md_log do
            cmd = Hwaro::CLI::Commands::Tool::AgentsMdCommand.new
            cmd.run(["--remote", "--write"])
          end

          output.should contain("remote mode")
          File.read(File.join(dir, "AGENTS.md")).should eq(Hwaro::Services::Defaults::AgentsMd.remote_content)
        end
      end
    end

    it "overwrites an existing AGENTS.md when --force is given" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("AGENTS.md", "stale content")

          capture_agents_md_log do
            cmd = Hwaro::CLI::Commands::Tool::AgentsMdCommand.new
            cmd.run(["--write", "--force"])
          end

          File.read(File.join(dir, "AGENTS.md")).should eq(Hwaro::Services::Defaults::AgentsMd.content)
        end
      end
    end
  end
end
