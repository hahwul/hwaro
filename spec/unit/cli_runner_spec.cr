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

  describe ".emit_hwaro_error" do
    it "emits classified text to stderr when json_mode? is false" do
      previous_json = Hwaro::CLI::Runner.json_mode?
      previous_err_io = Hwaro::Logger.err_io
      previous_color = Hwaro::Logger.color_enabled?
      Hwaro::Logger.color_enabled = false
      err_sink = IO::Memory.new
      Hwaro::Logger.err_io = err_sink
      Hwaro::CLI::Runner.json_mode = false

      begin
        err = Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_USAGE,
          message: "missing <path> argument",
          hint: "run hwaro new --help",
        )
        Hwaro::CLI::Runner.emit_hwaro_error(err, io: err_sink)
        output = err_sink.to_s
        output.should contain("Error [HWARO_E_USAGE]: missing <path> argument")
        output.should contain("run hwaro new --help")
      ensure
        Hwaro::Logger.err_io = previous_err_io
        Hwaro::Logger.color_enabled = previous_color
        Hwaro::CLI::Runner.json_mode = previous_json
      end
    end

    # The JSON branch of emit_hwaro_error writes to the hardcoded STDOUT
    # constant (not the io: parameter), so it cannot be captured via an
    # IO::Memory sink in-process. Drive the built binary instead: an unknown
    # command plus --json triggers the ARGV.includes?("--json") branch (no
    # parser has run yet), so this also covers the ARGV-detection path.
    it "emits the structured JSON payload to stdout under --json (ARGV detection)" do
      bin = File.expand_path("../../bin/hwaro", __DIR__)
      next unless File.exists?(bin) && File::Info.executable?(bin)

      stdout_sink = IO::Memory.new
      stderr_sink = IO::Memory.new
      status = Process.run(bin, ["boguscmd", "--json"], output: stdout_sink, error: stderr_sink)

      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      stdout = stdout_sink.to_s
      # No human-form "Error [CODE]" line leaks to stdout under --json.
      stdout.should_not contain("Error [")
      parsed = JSON.parse(stdout)
      parsed["status"].as_s.should eq("error")
      parsed["error"]["code"].as_s.should eq(Hwaro::Errors::HWARO_E_USAGE)
      parsed["error"]["message"].as_s.should contain("unknown command")
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

  describe "#run" do
    it "prints version with -v, -V, and --version flags" do
      ["-v", "-V", "--version"].each do |flag|
        previous_io = Hwaro::Logger.io
        previous_level = Hwaro::Logger.level
        sink = IO::Memory.new
        Hwaro::Logger.io = sink
        Hwaro::Logger.level = Hwaro::Logger::Level::Info

        old_argv = ARGV.dup
        ARGV.clear
        ARGV.push(flag)

        begin
          Hwaro::CLI::Runner.new.run
          sink.to_s.should contain(Hwaro::VERSION)
        ensure
          ARGV.clear
          ARGV.concat(old_argv)
          Hwaro::Logger.io = previous_io
          Hwaro::Logger.level = previous_level
        end
      end
    end
  end
end
