require "../spec_helper"
require "../../src/cli/commands/init_command"

describe Hwaro::CLI::Commands::InitCommand do
  describe "#parse_options" do
    it "parses default options" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options([] of String)

      options.path.should eq(".")
      options.force.should be_false
      options.skip_agents_md.should be_false
      options.skip_sample_content.should be_false
      options.skip_taxonomies.should be_false
      options.multilingual_languages.should be_empty
      options.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Simple)
    end

    it "parses path argument" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options(["my-site"])
      options.path.should eq("my-site")
    end

    it "parses force flag" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options(["--force"])
      options.force.should be_true

      options = cmd.parse_options(["-f"])
      options.force.should be_true
    end

    it "parses scaffold flag" do
      cmd = Hwaro::CLI::Commands::InitCommand.new

      options = cmd.parse_options(["--scaffold", "simple"])
      options.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Simple)

      options = cmd.parse_options(["--scaffold", "blog"])
      options.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Blog)

      options = cmd.parse_options(["--scaffold", "docs"])
      options.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Docs)
    end

    it "parses skip flags" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options([
        "--skip-agents-md",
        "--skip-sample-content",
        "--skip-taxonomies",
      ])

      options.skip_agents_md.should be_true
      options.skip_sample_content.should be_true
      options.skip_taxonomies.should be_true
    end

    it "parses multilingual flag" do
      cmd = Hwaro::CLI::Commands::InitCommand.new

      # Single language
      options = cmd.parse_options(["--include-multilingual", "en"])
      options.multilingual_languages.should eq(["en"])

      # Multiple languages
      options = cmd.parse_options(["--include-multilingual", "en,ko"])
      options.multilingual_languages.should eq(["en", "ko"])

      # With spaces
      options = cmd.parse_options(["--include-multilingual", "en, ko, fr"])
      options.multilingual_languages.should eq(["en", "ko", "fr"])
    end

    it "parses mixed flags and arguments" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options([
        "new-site",
        "--force",
        "--scaffold", "blog",
        "--include-multilingual", "en,es",
      ])

      options.path.should eq("new-site")
      options.force.should be_true
      options.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Blog)
      options.multilingual_languages.should eq(["en", "es"])
    end

    it "raises on unknown flags" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      expect_raises(OptionParser::InvalidOption) do
        cmd.parse_options(["--unknown-flag"])
      end
    end
  end
end
