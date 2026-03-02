require "../spec_helper"
require "../../src/cli/metadata"

describe Hwaro::CLI::FlagInfo do
  describe "#initialize" do
    it "creates a flag with short and long options" do
      flag = Hwaro::CLI::FlagInfo.new(short: "-v", long: "--verbose", description: "Enable verbose output")
      flag.short.should eq("-v")
      flag.long.should eq("--verbose")
      flag.description.should eq("Enable verbose output")
      flag.takes_value.should be_false
      flag.value_hint.should be_nil
    end

    it "creates a flag without short option" do
      flag = Hwaro::CLI::FlagInfo.new(short: nil, long: "--output", description: "Output dir")
      flag.short.should be_nil
      flag.long.should eq("--output")
    end

    it "creates a flag that takes a value" do
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
  end
end

describe Hwaro::CLI::CommandInfo do
  describe "#initialize" do
    it "creates a command with defaults" do
      cmd = Hwaro::CLI::CommandInfo.new(name: "build", description: "Build the site")
      cmd.name.should eq("build")
      cmd.description.should eq("Build the site")
      cmd.flags.should be_empty
      cmd.subcommands.should be_empty
      cmd.positional_args.should be_empty
      cmd.positional_choices.should be_empty
    end

    it "creates a command with flags" do
      flag = Hwaro::CLI::FlagInfo.new(short: "-h", long: "--help", description: "Show help")
      cmd = Hwaro::CLI::CommandInfo.new(
        name: "serve",
        description: "Serve the site",
        flags: [flag]
      )
      cmd.flags.size.should eq(1)
      cmd.flags.first.long.should eq("--help")
    end

    it "creates a command with subcommands" do
      sub = Hwaro::CLI::CommandInfo.new(name: "check", description: "Check links")
      cmd = Hwaro::CLI::CommandInfo.new(
        name: "tool",
        description: "Utility tools",
        subcommands: [sub]
      )
      cmd.subcommands.size.should eq(1)
      cmd.subcommands.first.name.should eq("check")
    end

    it "creates a command with positional args and choices" do
      cmd = Hwaro::CLI::CommandInfo.new(
        name: "convert",
        description: "Convert format",
        positional_args: ["format"],
        positional_choices: ["toYAML", "toTOML"]
      )
      cmd.positional_args.should eq(["format"])
      cmd.positional_choices.should eq(["toYAML", "toTOML"])
    end
  end

  describe "property setters" do
    it "allows modifying name" do
      cmd = Hwaro::CLI::CommandInfo.new(name: "old", description: "desc")
      cmd.name = "new"
      cmd.name.should eq("new")
    end

    it "allows modifying description" do
      cmd = Hwaro::CLI::CommandInfo.new(name: "cmd", description: "old")
      cmd.description = "new description"
      cmd.description.should eq("new description")
    end
  end
end

describe "Hwaro::CLI::HELP_FLAG" do
  it "has correct short flag" do
    Hwaro::CLI::HELP_FLAG.short.should eq("-h")
  end

  it "has correct long flag" do
    Hwaro::CLI::HELP_FLAG.long.should eq("--help")
  end

  it "has correct description" do
    Hwaro::CLI::HELP_FLAG.description.should eq("Show this help")
  end
end
