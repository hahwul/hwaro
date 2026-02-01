require "../spec_helper"
require "../../src/cli/metadata"
require "../../src/cli/runner"

# Initialize Runner to register commands before tests
Hwaro::CLI::Runner.new

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

describe Hwaro::CLI::HELP_FLAG do
  it "is a standard help flag" do
    Hwaro::CLI::HELP_FLAG.short.should eq("-h")
    Hwaro::CLI::HELP_FLAG.long.should eq("--help")
    Hwaro::CLI::HELP_FLAG.description.should eq("Show this help")
  end
end

describe Hwaro::CLI::Commands::InitCommand do
  it "has correct metadata" do
    meta = Hwaro::CLI::Commands::InitCommand.metadata
    meta.name.should eq("init")
    meta.description.should eq("Initialize a new project")
    meta.positional_args.should contain("path")

    flag_names = meta.flags.map(&.long)
    flag_names.should contain("--force")
    flag_names.should contain("--scaffold")
    flag_names.should contain("--skip-agents-md")
  end

  it "FLAGS constant is used for metadata" do
    Hwaro::CLI::Commands::InitCommand::FLAGS.size.should be > 0
    Hwaro::CLI::Commands::InitCommand.metadata.flags.should eq(Hwaro::CLI::Commands::InitCommand::FLAGS)
  end
end

describe Hwaro::CLI::Commands::BuildCommand do
  it "has correct metadata" do
    meta = Hwaro::CLI::Commands::BuildCommand.metadata
    meta.name.should eq("build")

    flag_names = meta.flags.map(&.long)
    flag_names.should contain("--output-dir")
    flag_names.should contain("--drafts")
    flag_names.should contain("--minify")
    flag_names.should contain("--verbose")
    flag_names.should contain("--cache")
  end

  it "FLAGS constant is used for metadata" do
    Hwaro::CLI::Commands::BuildCommand::FLAGS.size.should be > 0
    Hwaro::CLI::Commands::BuildCommand.metadata.flags.should eq(Hwaro::CLI::Commands::BuildCommand::FLAGS)
  end
end

describe Hwaro::CLI::Commands::ServeCommand do
  it "has correct metadata" do
    meta = Hwaro::CLI::Commands::ServeCommand.metadata
    meta.name.should eq("serve")

    flag_names = meta.flags.map(&.long)
    flag_names.should contain("--bind")
    flag_names.should contain("--port")
    flag_names.should contain("--open")
  end
end

describe Hwaro::CLI::Commands::NewCommand do
  it "has correct metadata" do
    meta = Hwaro::CLI::Commands::NewCommand.metadata
    meta.name.should eq("new")
    meta.positional_args.should contain("path")

    flag_names = meta.flags.map(&.long)
    flag_names.should contain("--title")
  end

  it "FLAGS constant is used for metadata" do
    Hwaro::CLI::Commands::NewCommand::FLAGS.size.should be > 0
    Hwaro::CLI::Commands::NewCommand.metadata.flags.should eq(Hwaro::CLI::Commands::NewCommand::FLAGS)
  end
end

describe Hwaro::CLI::Commands::DeployCommand do
  it "has correct metadata" do
    meta = Hwaro::CLI::Commands::DeployCommand.metadata
    meta.name.should eq("deploy")

    flag_names = meta.flags.map(&.long)
    flag_names.should contain("--source")
    flag_names.should contain("--dry-run")
    flag_names.should contain("--force")
  end
end

describe Hwaro::CLI::Commands::ToolCommand do
  it "has subcommands" do
    meta = Hwaro::CLI::Commands::ToolCommand.metadata
    meta.name.should eq("tool")
    meta.subcommands.should_not be_empty

    subcommand_names = meta.subcommands.map(&.name)
    subcommand_names.should contain("convert")
    subcommand_names.should contain("list")
    subcommand_names.should contain("check")
  end

  it "subcommands are loaded from subcommand classes" do
    subs = Hwaro::CLI::Commands::ToolCommand.subcommands
    subs.size.should eq(3)
  end
end

describe Hwaro::CLI::Commands::Tool::ConvertCommand do
  it "has correct metadata with positional choices" do
    meta = Hwaro::CLI::Commands::Tool::ConvertCommand.metadata
    meta.positional_choices.should contain("toYAML")
    meta.positional_choices.should contain("toTOML")
  end
end

describe Hwaro::CLI::Commands::Tool::ListCommand do
  it "has correct metadata with positional choices" do
    meta = Hwaro::CLI::Commands::Tool::ListCommand.metadata
    meta.positional_choices.should contain("all")
    meta.positional_choices.should contain("drafts")
    meta.positional_choices.should contain("published")
  end
end

describe Hwaro::CLI::Commands::CompletionCommand do
  it "has shell choices" do
    meta = Hwaro::CLI::Commands::CompletionCommand.metadata
    meta.name.should eq("completion")
    meta.positional_args.should contain("shell")
    meta.positional_choices.should contain("bash")
    meta.positional_choices.should contain("zsh")
    meta.positional_choices.should contain("fish")
  end

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

describe Hwaro::CLI::CommandRegistry do
  # Note: Tests run after Runner.new is called during spec loading,
  # so commands are already registered

  it "has registered commands" do
    Hwaro::CLI::CommandRegistry.names.should_not be_empty
  end

  it "can get command by name" do
    handler = Hwaro::CLI::CommandRegistry.get("build")
    handler.should_not be_nil
  end

  it "can check if command exists" do
    Hwaro::CLI::CommandRegistry.has?("build").should be_true
    Hwaro::CLI::CommandRegistry.has?("nonexistent").should be_false
  end

  it "returns nil for unknown command" do
    Hwaro::CLI::CommandRegistry.get("nonexistent").should be_nil
  end

  it "can get command metadata" do
    meta = Hwaro::CLI::CommandRegistry.get_metadata("build")
    meta.should_not be_nil
    meta.not_nil!.name.should eq("build")
  end

  it "all_metadata returns all command metadata" do
    all = Hwaro::CLI::CommandRegistry.all_metadata
    all.should_not be_empty
    names = all.map(&.name)
    names.should contain("init")
    names.should contain("build")
    names.should contain("completion")
  end
end
