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
    it "returns 12 subcommands" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.size.should eq(12)
    end

    it "includes convert subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "convert" }.should be_true
    end

    it "includes list subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "list" }.should be_true
    end

    it "includes check-links subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "check-links" }.should be_true
    end

    it "includes doctor subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "doctor" }.should be_true
    end

    it "includes platform subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "platform" }.should be_true
    end

    it "includes ci subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "ci" }.should be_true
    end

    it "includes agents-md subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "agents-md" }.should be_true
    end

    it "includes stats subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "stats" }.should be_true
    end

    it "includes validate subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "validate" }.should be_true
    end

    it "includes unused-assets subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "unused-assets" }.should be_true
    end

    it "includes export subcommand" do
      subs = Hwaro::CLI::Commands::ToolCommand.subcommands
      subs.any? { |s| s.name == "export" }.should be_true
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

    it "has to-yaml and to-toml as positional choices" do
      meta = Hwaro::CLI::Commands::Tool::ConvertCommand.metadata
      meta.positional_choices.should eq(["to-yaml", "to-toml"])
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

describe Hwaro::CLI::Commands::Tool::PlatformCommand do
  describe ".metadata" do
    it "returns correct command name" do
      meta = Hwaro::CLI::Commands::Tool::PlatformCommand.metadata
      meta.name.should eq("platform")
    end

    it "returns a description" do
      meta = Hwaro::CLI::Commands::Tool::PlatformCommand.metadata
      meta.description.should_not be_empty
    end

    it "includes output flag" do
      meta = Hwaro::CLI::Commands::Tool::PlatformCommand.metadata
      meta.flags.any? { |f| f.long == "--output" }.should be_true
    end

    it "includes stdout flag" do
      meta = Hwaro::CLI::Commands::Tool::PlatformCommand.metadata
      meta.flags.any? { |f| f.long == "--stdout" }.should be_true
    end

    it "includes force flag" do
      meta = Hwaro::CLI::Commands::Tool::PlatformCommand.metadata
      meta.flags.any? { |f| f.long == "--force" }.should be_true
    end

    it "includes help flag" do
      meta = Hwaro::CLI::Commands::Tool::PlatformCommand.metadata
      meta.flags.any? { |f| f.long == "--help" }.should be_true
    end

    it "has platform as positional arg" do
      meta = Hwaro::CLI::Commands::Tool::PlatformCommand.metadata
      meta.positional_args.should eq(["platform"])
    end

    it "has all supported platforms as positional choices" do
      meta = Hwaro::CLI::Commands::Tool::PlatformCommand.metadata
      meta.positional_choices.should eq(["netlify", "vercel", "cloudflare", "github-pages", "gitlab-ci"])
    end

    it "output flag takes a value" do
      meta = Hwaro::CLI::Commands::Tool::PlatformCommand.metadata
      flag = meta.flags.find { |f| f.long == "--output" }
      flag.should_not be_nil
      flag.not_nil!.takes_value.should be_true
      flag.not_nil!.value_hint.should eq("PATH")
    end
  end
end

describe Hwaro::CLI::Commands::Tool::CICommand do
  describe ".metadata" do
    it "returns correct command name" do
      meta = Hwaro::CLI::Commands::Tool::CICommand.metadata
      meta.name.should eq("ci")
    end

    it "returns a description" do
      meta = Hwaro::CLI::Commands::Tool::CICommand.metadata
      meta.description.should_not be_empty
    end

    it "includes output flag" do
      meta = Hwaro::CLI::Commands::Tool::CICommand.metadata
      meta.flags.any? { |f| f.long == "--output" }.should be_true
    end

    it "includes stdout flag" do
      meta = Hwaro::CLI::Commands::Tool::CICommand.metadata
      meta.flags.any? { |f| f.long == "--stdout" }.should be_true
    end

    it "includes force flag" do
      meta = Hwaro::CLI::Commands::Tool::CICommand.metadata
      meta.flags.any? { |f| f.long == "--force" }.should be_true
    end

    it "includes help flag" do
      meta = Hwaro::CLI::Commands::Tool::CICommand.metadata
      meta.flags.any? { |f| f.long == "--help" }.should be_true
    end

    it "has provider as positional arg" do
      meta = Hwaro::CLI::Commands::Tool::CICommand.metadata
      meta.positional_args.should eq(["provider"])
    end

    it "has github-actions as positional choice" do
      meta = Hwaro::CLI::Commands::Tool::CICommand.metadata
      meta.positional_choices.should eq(["github-actions"])
    end
  end
end

describe Hwaro::CLI::Commands::Tool::DeadlinkCommand do
  describe ".metadata" do
    it "returns correct command name" do
      meta = Hwaro::CLI::Commands::Tool::DeadlinkCommand.metadata
      meta.name.should eq("check-links")
    end

    it "returns a description" do
      meta = Hwaro::CLI::Commands::Tool::DeadlinkCommand.metadata
      meta.description.should_not be_empty
    end

    it "includes content-dir flag" do
      meta = Hwaro::CLI::Commands::Tool::DeadlinkCommand.metadata
      meta.flags.any? { |f| f.long == "--content-dir" }.should be_true
    end

    it "content-dir flag takes a value" do
      meta = Hwaro::CLI::Commands::Tool::DeadlinkCommand.metadata
      flag = meta.flags.find { |f| f.long == "--content-dir" }
      flag.should_not be_nil
      flag.not_nil!.takes_value.should be_true
      flag.not_nil!.value_hint.should eq("DIR")
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

describe Hwaro::CLI::Commands::Tool::AgentsMdCommand do
  describe ".metadata" do
    it "returns correct command name" do
      meta = Hwaro::CLI::Commands::Tool::AgentsMdCommand.metadata
      meta.name.should eq("agents-md")
    end

    it "returns a description" do
      meta = Hwaro::CLI::Commands::Tool::AgentsMdCommand.metadata
      meta.description.should_not be_empty
    end

    it "includes remote flag" do
      meta = Hwaro::CLI::Commands::Tool::AgentsMdCommand.metadata
      meta.flags.any? { |f| f.long == "--remote" }.should be_true
    end

    it "includes local flag" do
      meta = Hwaro::CLI::Commands::Tool::AgentsMdCommand.metadata
      meta.flags.any? { |f| f.long == "--local" }.should be_true
    end

    it "includes write flag" do
      meta = Hwaro::CLI::Commands::Tool::AgentsMdCommand.metadata
      meta.flags.any? { |f| f.long == "--write" }.should be_true
    end

    it "includes force flag" do
      meta = Hwaro::CLI::Commands::Tool::AgentsMdCommand.metadata
      meta.flags.any? { |f| f.long == "--force" }.should be_true
    end

    it "includes help flag" do
      meta = Hwaro::CLI::Commands::Tool::AgentsMdCommand.metadata
      meta.flags.any? { |f| f.long == "--help" }.should be_true
    end

    it "has no positional args" do
      meta = Hwaro::CLI::Commands::Tool::AgentsMdCommand.metadata
      meta.positional_args.should be_empty
    end

    it "has no positional choices" do
      meta = Hwaro::CLI::Commands::Tool::AgentsMdCommand.metadata
      meta.positional_choices.should be_empty
    end
  end
end
