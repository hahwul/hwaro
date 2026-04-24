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
      options.minimal_config.should be_false
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

    it "parses clean flag" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options([] of String)
      options.clean.should be_false

      options = cmd.parse_options(["--clean"])
      options.clean.should be_true
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

    it "parses agents mode flag" do
      cmd = Hwaro::CLI::Commands::InitCommand.new

      options = cmd.parse_options(["--agents", "remote"])
      options.agents_mode.should eq(Hwaro::Config::Options::AgentsMode::Remote)

      options = cmd.parse_options(["--agents", "local"])
      options.agents_mode.should eq(Hwaro::Config::Options::AgentsMode::Local)
    end

    it "defaults agents mode to remote" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options([] of String)
      options.agents_mode.should eq(Hwaro::Config::Options::AgentsMode::Remote)
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

      # Region subtags
      options = cmd.parse_options(["--include-multilingual", "en-US,pt-BR,zh-Hant"])
      options.multilingual_languages.should eq(["en-US", "pt-BR", "zh-Hant"])
    end

    it "rejects invalid language codes in --include-multilingual" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      expect_raises(Hwaro::HwaroError, /Invalid language code: '@@@'/) do
        cmd.parse_options(["--include-multilingual", "en,@@@"])
      end

      expect_raises(Hwaro::HwaroError, /Invalid language code/) do
        cmd.parse_options(["--include-multilingual", "123"])
      end
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

    it "parses github shorthand scaffold" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options(["--scaffold", "github:hahwul/hwaro-starter-blog"])
      options.scaffold_remote.should eq("github:hahwul/hwaro-starter-blog")
    end

    it "parses full github URL scaffold" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options(["--scaffold", "https://github.com/hahwul/hwaro-starter-blog"])
      options.scaffold_remote.should eq("https://github.com/hahwul/hwaro-starter-blog")
    end

    it "keeps scaffold_remote nil for built-in types" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options(["--scaffold", "blog"])
      options.scaffold_remote.should be_nil
      options.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Blog)
    end

    it "parses minimal-config flag" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options(["--minimal-config"])
      options.minimal_config.should be_true
    end

    it "raises on unknown flags" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      expect_raises(OptionParser::InvalidOption) do
        cmd.parse_options(["--unknown-flag"])
      end
    end
  end

  describe "minimal_config_content" do
    it "generates minimal config for simple scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Simple)
      config = scaffold.minimal_config_content
      config.should contain("title = \"My Hwaro Site\"")
      config.should contain("[plugins]")
      config.should contain("[sitemap]")
      config.should contain("[feeds]")
      config.should contain("[[taxonomies]]")
      config.should_not contain("# ====")
    end

    it "generates minimal config for blog scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Blog)
      config = scaffold.minimal_config_content
      config.should contain("title = \"My Blog\"")
      config.should_not contain("# ====")
    end

    it "generates minimal config for docs scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Docs)
      config = scaffold.minimal_config_content
      config.should contain("title = \"Documentation\"")
      config.should_not contain("# ====")
    end

    it "skips taxonomies when requested" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Simple)
      config = scaffold.minimal_config_content(skip_taxonomies: true)
      config.should_not contain("[[taxonomies]]")
    end

    it "uses github theme for light scaffolds" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Simple)
      config = scaffold.minimal_config_content
      config.should contain("theme = \"github\"")
    end

    it "uses github-dark theme for dark scaffolds" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::BlogDark)
      config = scaffold.minimal_config_content
      config.should contain("theme = \"github-dark\"")

      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::DocsDark)
      config = scaffold.minimal_config_content
      config.should contain("theme = \"github-dark\"")
    end
  end

  describe "--list-scaffolds" do
    it "prints every built-in scaffold registered in the Registry" do
      sink = IO::Memory.new
      previous_io = Hwaro::Logger.io
      Hwaro::Logger.io = sink
      begin
        Hwaro::CLI::Commands::InitCommand.new.run(["--list-scaffolds"])
      ensure
        Hwaro::Logger.io = previous_io
      end

      output = sink.to_s
      output.should contain("Available scaffolds:")
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        output.should contain(scaffold.type.to_s)
        output.should contain(scaffold.description)
      end
      output.should contain("(default)")
    end
  end
end
