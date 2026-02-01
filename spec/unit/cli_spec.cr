require "../spec_helper"
require "../../src/cli/metadata"
require "../../src/cli/commands/completion_command"

describe Hwaro::CLI::Metadata do
  describe ".commands" do
    it "returns all registered commands" do
      commands = Hwaro::CLI::Metadata.commands
      commands.should_not be_empty
      command_names = commands.map(&.name)
      command_names.should contain("init")
      command_names.should contain("build")
      command_names.should contain("serve")
      command_names.should contain("new")
      command_names.should contain("deploy")
      command_names.should contain("tool")
      command_names.should contain("completion")
    end
  end

  describe ".get" do
    it "returns command by name" do
      cmd = Hwaro::CLI::Metadata.get("build")
      cmd.should_not be_nil
      cmd.not_nil!.name.should eq("build")
      cmd.not_nil!.description.should eq("Build the project")
    end

    it "returns nil for unknown command" do
      cmd = Hwaro::CLI::Metadata.get("unknown")
      cmd.should be_nil
    end
  end

  describe ".command_names" do
    it "includes all command names plus version and help" do
      names = Hwaro::CLI::Metadata.command_names
      names.should contain("init")
      names.should contain("build")
      names.should contain("serve")
      names.should contain("version")
      names.should contain("help")
    end
  end

  describe "init_command" do
    it "has correct metadata" do
      cmd = Hwaro::CLI::Metadata.init_command
      cmd.name.should eq("init")
      cmd.positional_args.should contain("path")
      cmd.flags.size.should be > 0

      # Check for specific flags
      flag_names = cmd.flags.map(&.long)
      flag_names.should contain("--force")
      flag_names.should contain("--scaffold")
      flag_names.should contain("--skip-agents-md")
    end
  end

  describe "build_command" do
    it "has correct metadata" do
      cmd = Hwaro::CLI::Metadata.build_command
      cmd.name.should eq("build")

      flag_names = cmd.flags.map(&.long)
      flag_names.should contain("--output-dir")
      flag_names.should contain("--drafts")
      flag_names.should contain("--minify")
      flag_names.should contain("--verbose")
      flag_names.should contain("--cache")
    end
  end

  describe "serve_command" do
    it "has correct metadata" do
      cmd = Hwaro::CLI::Metadata.serve_command
      cmd.name.should eq("serve")

      flag_names = cmd.flags.map(&.long)
      flag_names.should contain("--bind")
      flag_names.should contain("--port")
      flag_names.should contain("--open")
    end
  end

  describe "tool_command" do
    it "has subcommands" do
      cmd = Hwaro::CLI::Metadata.tool_command
      cmd.name.should eq("tool")
      cmd.subcommands.should_not be_empty

      subcommand_names = cmd.subcommands.map(&.name)
      subcommand_names.should contain("convert")
      subcommand_names.should contain("list")
      subcommand_names.should contain("check")
    end

    it "convert subcommand has positional choices" do
      sub = Hwaro::CLI::Metadata.tool_convert_subcommand
      sub.positional_choices.should contain("toYAML")
      sub.positional_choices.should contain("toTOML")
    end

    it "list subcommand has positional choices" do
      sub = Hwaro::CLI::Metadata.tool_list_subcommand
      sub.positional_choices.should contain("all")
      sub.positional_choices.should contain("drafts")
      sub.positional_choices.should contain("published")
    end
  end

  describe "completion_command" do
    it "has shell choices" do
      cmd = Hwaro::CLI::Metadata.completion_command
      cmd.name.should eq("completion")
      cmd.positional_args.should contain("shell")
      cmd.positional_choices.should contain("bash")
      cmd.positional_choices.should contain("zsh")
      cmd.positional_choices.should contain("fish")
    end
  end
end

describe Hwaro::CLI::FlagInfo do
  it "stores flag information" do
    flag = Hwaro::CLI::FlagInfo.new(
      short: "-v",
      long: "--verbose",
      description: "Verbose output",
      takes_value: false
    )
    flag.short.should eq("-v")
    flag.long.should eq("--verbose")
    flag.description.should eq("Verbose output")
    flag.takes_value.should be_false
  end

  it "handles flags with values" do
    flag = Hwaro::CLI::FlagInfo.new(
      short: "-o",
      long: "--output",
      description: "Output directory",
      takes_value: true,
      value_hint: "DIR"
    )
    flag.takes_value.should be_true
    flag.value_hint.should eq("DIR")
  end

  it "handles flags without short option" do
    flag = Hwaro::CLI::FlagInfo.new(
      short: nil,
      long: "--minify",
      description: "Minify output"
    )
    flag.short.should be_nil
    flag.long.should eq("--minify")
  end
end

describe Hwaro::CLI::CommandInfo do
  it "stores command information" do
    cmd = Hwaro::CLI::CommandInfo.new(
      name: "test",
      description: "Test command",
      flags: [Hwaro::CLI::FlagInfo.new(short: "-h", long: "--help", description: "Help")],
      positional_args: ["path"]
    )
    cmd.name.should eq("test")
    cmd.description.should eq("Test command")
    cmd.flags.size.should eq(1)
    cmd.positional_args.should contain("path")
  end

  it "supports subcommands" do
    sub = Hwaro::CLI::CommandInfo.new(name: "sub", description: "Subcommand")
    cmd = Hwaro::CLI::CommandInfo.new(
      name: "parent",
      description: "Parent command",
      subcommands: [sub]
    )
    cmd.subcommands.size.should eq(1)
    cmd.subcommands.first.name.should eq("sub")
  end

  it "supports positional choices" do
    cmd = Hwaro::CLI::CommandInfo.new(
      name: "completion",
      description: "Generate completions",
      positional_args: ["shell"],
      positional_choices: ["bash", "zsh", "fish"]
    )
    cmd.positional_choices.should eq(["bash", "zsh", "fish"])
  end
end

describe Hwaro::CLI::Commands::CompletionCommand do
  describe "shell completion generation" do
    it "supports bash shell" do
      Hwaro::CLI::Commands::CompletionCommand::SHELLS.should contain("bash")
    end

    it "supports zsh shell" do
      Hwaro::CLI::Commands::CompletionCommand::SHELLS.should contain("zsh")
    end

    it "supports fish shell" do
      Hwaro::CLI::Commands::CompletionCommand::SHELLS.should contain("fish")
    end

    it "has exactly three supported shells" do
      Hwaro::CLI::Commands::CompletionCommand::SHELLS.size.should eq(3)
    end
  end
end
