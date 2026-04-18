require "../spec_helper"

# Initialize the runner so CommandRegistry is populated. cli_spec.cr does
# the same — calling Runner.new is idempotent because @@commands and
# @@metadata are Hashes keyed by command name.
Hwaro::CLI::Runner.new

# =============================================================================
# Unit specs for Hwaro::CLI::Runner. Existing cli_spec.cr (291 lines) covers
# CommandRegistry storage methods, FlagInfo, CommandInfo, and per-command
# metadata. This file targets the Runner class itself:
#   - Runner.new wires every default command into the registry
#   - Runner.print_help renders the expected sections to Logger.io
# =============================================================================

private EXPECTED_DEFAULT_COMMANDS = [
  "init", "build", "serve", "new", "deploy", "tool",
  "doctor", "completion", "version", "help",
]

describe Hwaro::CLI::Runner do
  describe ".new" do
    it "registers every expected default command" do
      EXPECTED_DEFAULT_COMMANDS.each do |name|
        Hwaro::CLI::CommandRegistry.has?(name).should(
          be_true, "expected default command '#{name}' to be registered"
        )
      end
    end

    it "registers handlers that are callable" do
      EXPECTED_DEFAULT_COMMANDS.each do |name|
        Hwaro::CLI::CommandRegistry.get(name).should_not be_nil
      end
    end

    it "is idempotent — calling .new again does not duplicate entries" do
      before = Hwaro::CLI::CommandRegistry.names.size
      Hwaro::CLI::Runner.new
      after = Hwaro::CLI::CommandRegistry.names.size
      after.should eq(before)
    end

    it "registers metadata for every command" do
      EXPECTED_DEFAULT_COMMANDS.each do |name|
        Hwaro::CLI::CommandRegistry.get_metadata(name).should_not(
          be_nil, "expected metadata for command '#{name}'"
        )
      end
    end
  end

  describe ".apply_global_quiet!" do
    it "strips --quiet and sets Logger.quiet = true" do
      argv = ["--quiet", "build", "--verbose"]
      Hwaro::Logger.quiet = false
      Hwaro::CLI::Runner.apply_global_quiet!(argv)
      argv.should eq(["build", "--verbose"])
      Hwaro::Logger.quiet?.should be_true
      Hwaro::Logger.quiet = false
    end

    it "strips -q short form" do
      argv = ["build", "-q", "--verbose"]
      Hwaro::Logger.quiet = false
      Hwaro::CLI::Runner.apply_global_quiet!(argv)
      argv.should eq(["build", "--verbose"])
      Hwaro::Logger.quiet?.should be_true
      Hwaro::Logger.quiet = false
    end

    it "is a no-op when neither flag is present" do
      argv = ["build", "--verbose"]
      Hwaro::Logger.quiet = false
      Hwaro::CLI::Runner.apply_global_quiet!(argv)
      argv.should eq(["build", "--verbose"])
      Hwaro::Logger.quiet?.should be_false
    end
  end

  describe ".print_help" do
    it "writes a Commands header followed by command names to Logger.io" do
      previous_io = Hwaro::Logger.io
      previous_level = Hwaro::Logger.level
      sink = IO::Memory.new
      Hwaro::Logger.io = sink
      Hwaro::Logger.level = Hwaro::Logger::Level::Info

      begin
        Hwaro::CLI::Runner.print_help
        output = sink.to_s
        output.should contain("Commands:")
        # Every default command should appear in the help output
        EXPECTED_DEFAULT_COMMANDS.each do |name|
          output.should(
            contain(name),
            "expected '#{name}' in help output"
          )
        end
        output.should contain("hwaro <command> --help")
      ensure
        Hwaro::Logger.io = previous_io
        Hwaro::Logger.level = previous_level
      end
    end

    it "includes the version banner" do
      previous_io = Hwaro::Logger.io
      previous_level = Hwaro::Logger.level
      sink = IO::Memory.new
      Hwaro::Logger.io = sink
      Hwaro::Logger.level = Hwaro::Logger::Level::Info

      begin
        Hwaro::CLI::Runner.print_help
        sink.to_s.should contain("v#{Hwaro::VERSION}")
      ensure
        Hwaro::Logger.io = previous_io
        Hwaro::Logger.level = previous_level
      end
    end

    it "is silent when Logger.quiet? is true" do
      previous_io = Hwaro::Logger.io
      previous_level = Hwaro::Logger.level
      sink = IO::Memory.new
      Hwaro::Logger.io = sink
      Hwaro::Logger.level = Hwaro::Logger::Level::Info
      Hwaro::Logger.quiet = true

      begin
        Hwaro::CLI::Runner.print_help
        sink.to_s.should eq("")
      ensure
        Hwaro::Logger.quiet = false
        Hwaro::Logger.io = previous_io
        Hwaro::Logger.level = previous_level
      end
    end

    it "lists priority commands before unranked ones" do
      previous_io = Hwaro::Logger.io
      previous_level = Hwaro::Logger.level
      sink = IO::Memory.new
      Hwaro::Logger.io = sink
      Hwaro::Logger.level = Hwaro::Logger::Level::Info

      begin
        Hwaro::CLI::Runner.print_help
        output = sink.to_s
        # Anchor to the start-of-line "  <name>" pattern (runner uses
        # ljust(12)) so a stray "init"/"help" substring elsewhere in the
        # banner can't shift the indices.
        init_idx = output.index(/^  init\s/m)
        help_idx = output.index(/^  help\s/m)
        init_idx.should_not be_nil
        help_idx.should_not be_nil
        init_idx.not_nil!.should be < help_idx.not_nil!
      ensure
        Hwaro::Logger.io = previous_io
        Hwaro::Logger.level = previous_level
      end
    end
  end
end
