require "../spec_helper"
require "../../src/cli/commands/tool_command"

describe Hwaro::CLI::Commands::ToolCommand do
  describe ".metadata" do
    it "returns correct command name" do
      meta = Hwaro::CLI::Commands::ToolCommand.metadata
      meta.name.should eq("tool")
    end

    it "returns a description" do
      meta = Hwaro::CLI::Commands::ToolCommand.metadata
      meta.description.should_not be_empty
    end

    it "includes help flag" do
      meta = Hwaro::CLI::Commands::ToolCommand.metadata
      meta.flags.any? { |f| f.long == "--help" }.should be_true
    end
  end

  describe ".subcommands" do
    it "returns 4 subcommands" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.size.should eq(4)
    end

    it "includes convert subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "convert" }.should be_true
    end

    it "includes list subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "list" }.should be_true
    end

    it "includes deadlink subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "deadlink" }.should be_true
    end

    it "includes doctor subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "doctor" }.should be_true
    end
  end
end

describe Hwaro::CLI::Commands::Tool::ConvertCommand do
  describe ".metadata" do
    it "returns correct command name" do
      meta = Hwaro::CLI::Commands::Tool::ConvertCommand.metadata
      meta.name.should eq("convert")
    end

    it "returns a description" do
      meta = Hwaro::CLI::Commands::Tool::ConvertCommand.metadata
      meta.description.should_not be_empty
    end

    it "includes content-dir flag" do
      meta = Hwaro::CLI::Commands::Tool::ConvertCommand.metadata
      meta.flags.any? { |f| f.long == "--content-dir" }.should be_true
    end

    it "includes json flag" do
      meta = Hwaro::CLI::Commands::Tool::ConvertCommand.metadata
      meta.flags.any? { |f| f.long == "--json" }.should be_true
    end

    it "includes help flag" do
      meta = Hwaro::CLI::Commands::Tool::ConvertCommand.metadata
      meta.flags.any? { |f| f.long == "--help" }.should be_true
    end

    it "has format as positional arg" do
      meta = Hwaro::CLI::Commands::Tool::ConvertCommand.metadata
      meta.positional_args.should eq(["format"])
    end

    it "has toYAML and toTOML as positional choices" do
      meta = Hwaro::CLI::Commands::Tool::ConvertCommand.metadata
      meta.positional_choices.should eq(["toYAML", "toTOML"])
    end

    it "content-dir flag takes a value" do
      meta = Hwaro::CLI::Commands::Tool::ConvertCommand.metadata
      flag = meta.flags.find { |f| f.long == "--content-dir" }
      flag.should_not be_nil
      flag.not_nil!.takes_value.should be_true
      flag.not_nil!.value_hint.should eq("DIR")
    end
  end
end

describe Hwaro::CLI::Commands::Tool::ListCommand do
  describe ".metadata" do
    it "returns correct command name" do
      meta = Hwaro::CLI::Commands::Tool::ListCommand.metadata
      meta.name.should eq("list")
    end

    it "returns a description" do
      meta = Hwaro::CLI::Commands::Tool::ListCommand.metadata
      meta.description.should_not be_empty
    end

    it "includes content-dir flag" do
      meta = Hwaro::CLI::Commands::Tool::ListCommand.metadata
      meta.flags.any? { |f| f.long == "--content-dir" }.should be_true
    end

    it "includes json flag" do
      meta = Hwaro::CLI::Commands::Tool::ListCommand.metadata
      meta.flags.any? { |f| f.long == "--json" }.should be_true
    end

    it "includes help flag" do
      meta = Hwaro::CLI::Commands::Tool::ListCommand.metadata
      meta.flags.any? { |f| f.long == "--help" }.should be_true
    end

    it "has filter as positional arg" do
      meta = Hwaro::CLI::Commands::Tool::ListCommand.metadata
      meta.positional_args.should eq(["filter"])
    end

    it "has all, drafts, published as positional choices" do
      meta = Hwaro::CLI::Commands::Tool::ListCommand.metadata
      meta.positional_choices.should eq(["all", "drafts", "published"])
    end

    it "content-dir flag takes a value" do
      meta = Hwaro::CLI::Commands::Tool::ListCommand.metadata
      flag = meta.flags.find { |f| f.long == "--content-dir" }
      flag.should_not be_nil
      flag.not_nil!.takes_value.should be_true
      flag.not_nil!.value_hint.should eq("DIR")
    end
  end
end

describe Hwaro::CLI::Commands::Tool::DoctorCommand do
  describe ".metadata" do
    it "returns correct command name" do
      meta = Hwaro::CLI::Commands::Tool::DoctorCommand.metadata
      meta.name.should eq("doctor")
    end

    it "returns a description" do
      meta = Hwaro::CLI::Commands::Tool::DoctorCommand.metadata
      meta.description.should_not be_empty
    end

    it "includes content-dir flag" do
      meta = Hwaro::CLI::Commands::Tool::DoctorCommand.metadata
      meta.flags.any? { |f| f.long == "--content-dir" }.should be_true
    end

    it "includes json flag" do
      meta = Hwaro::CLI::Commands::Tool::DoctorCommand.metadata
      meta.flags.any? { |f| f.long == "--json" }.should be_true
    end

    it "includes help flag" do
      meta = Hwaro::CLI::Commands::Tool::DoctorCommand.metadata
      meta.flags.any? { |f| f.long == "--help" }.should be_true
    end

    it "has no positional args" do
      meta = Hwaro::CLI::Commands::Tool::DoctorCommand.metadata
      meta.positional_args.should be_empty
    end

    it "has no positional choices" do
      meta = Hwaro::CLI::Commands::Tool::DoctorCommand.metadata
      meta.positional_choices.should be_empty
    end

    it "content-dir flag takes a value" do
      meta = Hwaro::CLI::Commands::Tool::DoctorCommand.metadata
      flag = meta.flags.find { |f| f.long == "--content-dir" }
      flag.should_not be_nil
      flag.not_nil!.takes_value.should be_true
      flag.not_nil!.value_hint.should eq("DIR")
    end
  end
end

describe Hwaro::CLI::Commands::Tool::DeadlinkCommand do
  describe ".metadata" do
    it "returns correct command name" do
      meta = Hwaro::CLI::Commands::Tool::DeadlinkCommand.metadata
      meta.name.should eq("deadlink")
    end

    it "returns a description" do
      meta = Hwaro::CLI::Commands::Tool::DeadlinkCommand.metadata
      meta.description.should_not be_empty
    end

    it "includes json flag" do
      meta = Hwaro::CLI::Commands::Tool::DeadlinkCommand.metadata
      meta.flags.any? { |f| f.long == "--json" }.should be_true
    end

    it "includes help flag" do
      meta = Hwaro::CLI::Commands::Tool::DeadlinkCommand.metadata
      meta.flags.any? { |f| f.long == "--help" }.should be_true
    end
  end
end
