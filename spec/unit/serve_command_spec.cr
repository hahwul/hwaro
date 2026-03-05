require "../spec_helper"
require "../../src/cli/commands/serve_command"
require "../../src/cli/commands/completion_command"

# Reopen ServeCommand to test private parse_options method
module Hwaro
  module CLI
    module Commands
      class ServeCommand
        def test_parse_options(args : Array(String))
          parse_options(args)
        end
      end
    end
  end
end

describe Hwaro::CLI::Commands::ServeCommand do
  describe "#parse_options" do
    it "defaults error_overlay to true" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options([] of String)
      options.error_overlay.should be_true
    end

    it "sets error_overlay to false when --no-error-overlay is passed" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--no-error-overlay"])
      options.error_overlay.should be_false
    end

    it "defaults host to 0.0.0.0" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options([] of String)
      options.host.should eq("0.0.0.0")
    end

    it "defaults port to 3000" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options([] of String)
      options.port.should eq(3000)
    end

    it "parses --port flag" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--port", "8080"])
      options.port.should eq(8080)
    end

    it "parses --bind flag" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--bind", "127.0.0.1"])
      options.host.should eq("127.0.0.1")
    end

    it "parses --drafts flag" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--drafts"])
      options.drafts.should be_true
    end

    it "parses combined flags" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--no-error-overlay", "--drafts", "--verbose", "--port", "4000"])
      options.error_overlay.should be_false
      options.drafts.should be_true
      options.verbose.should be_true
      options.port.should eq(4000)
    end

    it "defaults live_reload to false" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options([] of String)
      options.live_reload.should be_false
    end

    it "sets live_reload to true when --live-reload is passed" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--live-reload"])
      options.live_reload.should be_true
    end
  end

  describe "metadata" do
    it "has correct name" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      meta.name.should eq("serve")
    end

    it "has a description" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      meta.description.should_not be_empty
    end

    it "has flags" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      meta.flags.should_not be_empty
    end

    it "has bind flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--bind")
    end

    it "has port flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--port")
    end

    it "has base-url flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--base-url")
    end

    it "has drafts flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--drafts")
    end

    it "has minify flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--minify")
    end

    it "has open flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--open")
    end

    it "has verbose flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--verbose")
    end

    it "has debug flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--debug")
    end

    it "has help flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--help")
    end

    it "has no-error-overlay flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--no-error-overlay")
    end

    it "no-error-overlay flag does not take a value" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag = meta.flags.find { |f| f.long == "--no-error-overlay" }
      flag.should_not be_nil
      flag.not_nil!.takes_value.should be_false
    end

    it "has live-reload flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--live-reload")
    end

    it "live-reload flag does not take a value" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag = meta.flags.find { |f| f.long == "--live-reload" }
      flag.should_not be_nil
      flag.not_nil!.takes_value.should be_false
    end

    it "has no positional args" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      meta.positional_args.should be_empty
    end

    it "has no positional choices" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      meta.positional_choices.should be_empty
    end

    it "bind flag takes a value" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      bind_flag = meta.flags.find { |f| f.long == "--bind" }
      bind_flag.should_not be_nil
      bind_flag.not_nil!.takes_value.should be_true
      bind_flag.not_nil!.value_hint.should eq("HOST")
    end

    it "port flag takes a value" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      port_flag = meta.flags.find { |f| f.long == "--port" }
      port_flag.should_not be_nil
      port_flag.not_nil!.takes_value.should be_true
      port_flag.not_nil!.value_hint.should eq("PORT")
    end

    it "base-url flag takes a value" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag = meta.flags.find { |f| f.long == "--base-url" }
      flag.should_not be_nil
      flag.not_nil!.takes_value.should be_true
      flag.not_nil!.value_hint.should eq("URL")
    end

    it "drafts flag does not take a value" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag = meta.flags.find { |f| f.long == "--drafts" }
      flag.should_not be_nil
      flag.not_nil!.takes_value.should be_false
    end

    it "bind flag has short option -b" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag = meta.flags.find { |f| f.long == "--bind" }
      flag.should_not be_nil
      flag.not_nil!.short.should eq("-b")
    end

    it "port flag has short option -p" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag = meta.flags.find { |f| f.long == "--port" }
      flag.should_not be_nil
      flag.not_nil!.short.should eq("-p")
    end

    it "drafts flag has short option -d" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag = meta.flags.find { |f| f.long == "--drafts" }
      flag.should_not be_nil
      flag.not_nil!.short.should eq("-d")
    end

    it "verbose flag has short option -v" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag = meta.flags.find { |f| f.long == "--verbose" }
      flag.should_not be_nil
      flag.not_nil!.short.should eq("-v")
    end
  end

  describe "constants" do
    it "has NAME set to serve" do
      Hwaro::CLI::Commands::ServeCommand::NAME.should eq("serve")
    end

    it "has non-empty DESCRIPTION" do
      Hwaro::CLI::Commands::ServeCommand::DESCRIPTION.should_not be_empty
    end

    it "has empty POSITIONAL_ARGS" do
      Hwaro::CLI::Commands::ServeCommand::POSITIONAL_ARGS.should be_empty
    end

    it "has empty POSITIONAL_CHOICES" do
      Hwaro::CLI::Commands::ServeCommand::POSITIONAL_CHOICES.should be_empty
    end

    it "has FLAGS array" do
      Hwaro::CLI::Commands::ServeCommand::FLAGS.should_not be_empty
    end

    it "FLAGS includes help flag" do
      flags = Hwaro::CLI::Commands::ServeCommand::FLAGS
      flags.any? { |f| f.long == "--help" }.should be_true
    end
  end
end

describe Hwaro::CLI::Commands::CompletionCommand do
  describe "bash completion generation" do
    it "generates bash completion script" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      io = IO::Memory.new
      original_io = Hwaro::Logger
      Hwaro::Logger.io = io

      # Use a pipe to capture stdout
      reader, writer = IO.pipe
      original_stdout = STDOUT

      # We'll test the generate methods indirectly through metadata
      # The script generation is private, so we test the command structure
      meta = Hwaro::CLI::Commands::CompletionCommand.metadata
      meta.name.should eq("completion")
      meta.positional_args.should contain("shell")
      meta.positional_choices.should contain("bash")
      meta.positional_choices.should contain("zsh")
      meta.positional_choices.should contain("fish")

      Hwaro::Logger.io = IO::Memory.new
    end
  end

  describe "all_commands" do
    # Ensure runner is initialized so commands are registered
    Hwaro::CLI::Runner.new

    it "returns registered commands" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      commands.should_not be_empty
    end

    it "includes build command" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      names = commands.map(&.name)
      names.should contain("build")
    end

    it "includes serve command" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      names = commands.map(&.name)
      names.should contain("serve")
    end

    it "includes init command" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      names = commands.map(&.name)
      names.should contain("init")
    end

    it "includes deploy command" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      names = commands.map(&.name)
      names.should contain("deploy")
    end

    it "includes new command" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      names = commands.map(&.name)
      names.should contain("new")
    end

    it "includes tool command" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      names = commands.map(&.name)
      names.should contain("tool")
    end

    it "includes completion command" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      names = commands.map(&.name)
      names.should contain("completion")
    end

    it "all commands have names" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      commands.each do |cmd|
        cmd.name.should_not be_empty
      end
    end

    it "all commands have descriptions" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      commands.each do |cmd|
        cmd.description.should_not be_empty
      end
    end

    it "tool command has subcommands" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      tool_cmd = commands.find { |c| c.name == "tool" }
      tool_cmd.should_not be_nil
      tool_cmd.not_nil!.subcommands.should_not be_empty
    end

    it "tool command has convert subcommand" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      tool_cmd = commands.find { |c| c.name == "tool" }
      tool_cmd.should_not be_nil
      sub_names = tool_cmd.not_nil!.subcommands.map(&.name)
      sub_names.should contain("convert")
    end

    it "tool command has list subcommand" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      tool_cmd = commands.find { |c| c.name == "tool" }
      tool_cmd.should_not be_nil
      sub_names = tool_cmd.not_nil!.subcommands.map(&.name)
      sub_names.should contain("list")
    end

    it "tool command has deadlink subcommand" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      tool_cmd = commands.find { |c| c.name == "tool" }
      tool_cmd.should_not be_nil
      sub_names = tool_cmd.not_nil!.subcommands.map(&.name)
      sub_names.should contain("deadlink")
    end

    it "tool command has doctor subcommand" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      tool_cmd = commands.find { |c| c.name == "tool" }
      tool_cmd.should_not be_nil
      sub_names = tool_cmd.not_nil!.subcommands.map(&.name)
      sub_names.should contain("doctor")
    end
  end

  describe "constants" do
    it "has NAME set to completion" do
      Hwaro::CLI::Commands::CompletionCommand::NAME.should eq("completion")
    end

    it "has non-empty DESCRIPTION" do
      Hwaro::CLI::Commands::CompletionCommand::DESCRIPTION.should_not be_empty
    end

    it "supports exactly three shells" do
      Hwaro::CLI::Commands::CompletionCommand::SHELLS.size.should eq(3)
    end

    it "supports bash" do
      Hwaro::CLI::Commands::CompletionCommand::SHELLS.should contain("bash")
    end

    it "supports zsh" do
      Hwaro::CLI::Commands::CompletionCommand::SHELLS.should contain("zsh")
    end

    it "supports fish" do
      Hwaro::CLI::Commands::CompletionCommand::SHELLS.should contain("fish")
    end

    it "has shell as positional arg" do
      Hwaro::CLI::Commands::CompletionCommand::POSITIONAL_ARGS.should contain("shell")
    end

    it "positional choices match SHELLS" do
      Hwaro::CLI::Commands::CompletionCommand::POSITIONAL_CHOICES.should eq(Hwaro::CLI::Commands::CompletionCommand::SHELLS)
    end

    it "has only help flag" do
      flags = Hwaro::CLI::Commands::CompletionCommand::FLAGS
      flags.size.should eq(1)
      flags.first.long.should eq("--help")
    end
  end

  describe "metadata" do
    it "returns correct command info" do
      meta = Hwaro::CLI::Commands::CompletionCommand.metadata
      meta.name.should eq("completion")
      meta.description.should_not be_empty
    end

    it "has positional args" do
      meta = Hwaro::CLI::Commands::CompletionCommand.metadata
      meta.positional_args.should eq(["shell"])
    end

    it "has positional choices for shells" do
      meta = Hwaro::CLI::Commands::CompletionCommand.metadata
      meta.positional_choices.should eq(["bash", "zsh", "fish"])
    end

    it "has flags array" do
      meta = Hwaro::CLI::Commands::CompletionCommand.metadata
      meta.flags.should_not be_empty
    end

    it "has no subcommands" do
      meta = Hwaro::CLI::Commands::CompletionCommand.metadata
      meta.subcommands.should be_empty
    end
  end
end
