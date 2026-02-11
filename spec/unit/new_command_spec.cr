require "../spec_helper"
require "../../src/cli/commands/new_command"

describe Hwaro::CLI::Commands::NewCommand do
  describe "#parse_options" do
    it "parses path argument" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options = cmd.parse_options(["posts/hello.md"])
      options.path.should eq("posts/hello.md")
    end

    it "parses title flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options = cmd.parse_options(["--title", "Hello World"])
      options.title.should eq("Hello World")

      options = cmd.parse_options(["-t", "My Title"])
      options.title.should eq("My Title")
    end

    it "parses archetype flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options = cmd.parse_options(["--archetype", "blog"])
      options.archetype.should eq("blog")

      options = cmd.parse_options(["-a", "news"])
      options.archetype.should eq("news")
    end

    it "parses combinations of flags and arguments" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options = cmd.parse_options(["posts/new.md", "--title", "New Post", "-a", "blog"])

      options.path.should eq("posts/new.md")
      options.title.should eq("New Post")
      options.archetype.should eq("blog")
    end

    it "handles empty arguments" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options = cmd.parse_options([] of String)

      options.path.should be_nil
      options.title.should be_nil
      options.archetype.should be_nil
    end

    it "raises on unknown flags" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      expect_raises(OptionParser::InvalidOption) do
        cmd.parse_options(["--unknown"])
      end
    end
  end
end
