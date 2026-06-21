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

    it "defaults host to 127.0.0.1" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options([] of String)
      options.host.should eq("127.0.0.1")
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

    it "raises HwaroError(HWARO_E_USAGE) when --port is out of range or non-numeric" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new

      ["0", "-1", "99999", "abc", ""].each do |bad|
        err = expect_raises(Hwaro::HwaroError) do
          cmd.test_parse_options(["--port", bad])
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      end
    end

    it "accepts the inclusive --port boundary values 1 and 65535" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new

      _, options = cmd.test_parse_options(["--port", "1"])
      options.port.should eq(1)

      _, options = cmd.test_parse_options(["--port", "65535"])
      options.port.should eq(65535)
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

    it "defaults live_reload to true" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options([] of String)
      options.live_reload.should be_true
    end

    it "keeps live_reload true when --live-reload is passed (backwards compat no-op)" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--live-reload"])
      options.live_reload.should be_true
    end

    it "sets live_reload to false when --no-live-reload is passed" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--no-live-reload"])
      options.live_reload.should be_false
    end

    it "defaults skip_og_image to false" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options([] of String)
      options.skip_og_image.should be_false
    end

    it "sets skip_og_image to true when --skip-og-image is passed" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--skip-og-image"])
      options.skip_og_image.should be_true
    end

    it "defaults skip_image_processing to false" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options([] of String)
      options.skip_image_processing.should be_false
    end

    it "sets skip_image_processing to true when --skip-image-processing is passed" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--skip-image-processing"])
      options.skip_image_processing.should be_true
    end

    it "propagates skip flags to build options" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--skip-og-image", "--skip-image-processing"])
      build_options = options.to_build_options
      build_options.skip_og_image.should be_true
      build_options.skip_image_processing.should be_true
    end

    it "defaults cache to false" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options([] of String)
      options.cache.should be_false
    end

    it "parses --cache flag" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--cache"])
      options.cache.should be_true
    end

    it "defaults stream to false" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options([] of String)
      options.stream.should be_false
    end

    it "parses --stream flag" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--stream"])
      options.stream.should be_true
    end

    it "defaults memory_limit to nil" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options([] of String)
      options.memory_limit.should be_nil
    end

    it "parses --memory-limit flag" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--memory-limit", "512M"])
      options.memory_limit.should eq("512M")
    end

    it "propagates cache/stream/memory-limit to build options" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--cache", "--stream", "--memory-limit", "2G"])
      build_options = options.to_build_options
      build_options.cache.should be_true
      build_options.stream.should be_true
      build_options.memory_limit.should eq("2G")
      build_options.streaming?.should be_true
    end

    it "defaults fast_start to false" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options([] of String)
      options.fast_start.should be_false
      options.fast_start_count.should eq(20)
    end

    it "enables fast_start when --fast-start is passed" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--fast-start"])
      options.fast_start.should be_true
      options.fast_start_count.should eq(20)
    end

    it "parses --fast-start-count and implies --fast-start" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--fast-start-count", "50"])
      options.fast_start.should be_true
      options.fast_start_count.should eq(50)
    end

    it "raises HwaroError(HWARO_E_USAGE) when --fast-start-count is not a positive integer" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new

      ["0", "-1", "abc", ""].each do |bad|
        err = expect_raises(Hwaro::HwaroError) do
          cmd.test_parse_options(["--fast-start-count", bad])
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      end
    end

    it "propagates fast_start fields to build options" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--fast-start", "--fast-start-count", "5"])
      build_options = options.to_build_options
      build_options.fast_start.should be_true
      build_options.fast_start_count.should eq(5)
    end

    it "parses --header and stores in options.headers (CLI only at parse time)" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--header", "X-Test: hello", "--header", "Cache-Control=no-store"])
      options.headers["X-Test"].should eq("hello")
      options.headers["Cache-Control"].should eq("no-store")
      options.headers.size.should eq(2)
    end

    it "supports --header with = separator and whitespace" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options(["--header", "X-Foo = bar baz"])
      options.headers["X-Foo"].should eq("bar baz")
    end

    it "preserves a colon inside the --header value (split on first colon only)" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      _, options = cmd.test_parse_options([
        "--header", "Refresh: 5; url=https://example.com",
        "--header", "CSP: default-src https://a.com",
      ])
      # Value is .strip-ped, but the colon(s) after the first are kept intact.
      options.headers["Refresh"].should eq("5; url=https://example.com")
      options.headers["CSP"].should eq("default-src https://a.com")
    end

    it "raises on invalid --header (empty key)" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      err = expect_raises(Hwaro::HwaroError) do
        cmd.test_parse_options(["--header", ": value"])
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
    end

    it "handles bare --header token (no separator) gracefully instead of IndexError" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      err = expect_raises(Hwaro::HwaroError) do
        cmd.test_parse_options(["--header", "JustKeyNoValue"])
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      # Use to_s because Exception#message is String? in the base class
      err.message.to_s.should contain("Invalid --header value")
    end

    it "raises on --header containing control characters (CRLF injection guard)" do
      cmd = Hwaro::CLI::Commands::ServeCommand.new
      # Pass the flag and the bad value as two separate argv elements (the value itself contains \n)
      err = expect_raises(Hwaro::HwaroError) do
        cmd.test_parse_options(["--header", "X-Bad: foo\nbar"])
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)

      err2 = expect_raises(Hwaro::HwaroError) do
        cmd.test_parse_options(["--header", "X-Bad2: foo\r\nX-Inject: evil"])
      end
      err2.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
    end
  end

  describe "#run" do
    it "raises HwaroError(HWARO_E_IO) when the input directory is missing" do
      missing = File.join(Dir.tempdir, "hwaro-does-not-exist-#{Random.rand(1_000_000)}")
      cmd = Hwaro::CLI::Commands::ServeCommand.new

      err = expect_raises(Hwaro::HwaroError) do
        cmd.run(["-i", missing])
      end

      err.code.should eq(Hwaro::Errors::HWARO_E_IO)
      err.exit_code.should eq(6)
      err.category.should eq(:io)
      err.message.not_nil!.should contain(missing)
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

    it "has skip-og-image flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--skip-og-image")
    end

    it "has skip-image-processing flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--skip-image-processing")
    end

    it "has live-reload flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--live-reload")
    end

    it "has no-live-reload flag" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag_longs = meta.flags.map(&.long)
      flag_longs.should contain("--no-live-reload")
    end

    it "live-reload flag does not take a value" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag = meta.flags.find { |f| f.long == "--live-reload" }
      flag.should_not be_nil
      flag.not_nil!.takes_value.should be_false
    end

    it "no-live-reload flag does not take a value" do
      meta = Hwaro::CLI::Commands::ServeCommand.metadata
      flag = meta.flags.find { |f| f.long == "--no-live-reload" }
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
      Hwaro::Logger.io = IO::Memory.new

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

    it "tool command has check-links subcommand" do
      commands = Hwaro::CLI::Commands::CompletionCommand.all_commands
      tool_cmd = commands.find { |c| c.name == "tool" }
      tool_cmd.should_not be_nil
      sub_names = tool_cmd.not_nil!.subcommands.map(&.name)
      sub_names.should contain("check-links")
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
