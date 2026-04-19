require "../spec_helper"
require "../../src/cli/commands/new_command"

describe Hwaro::CLI::Commands::NewCommand do
  describe "#parse_options" do
    it "parses path argument" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["posts/hello.md"])
      options.path.should eq("posts/hello.md")
    end

    it "parses title flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["--title", "Hello World"])
      options.title.should eq("Hello World")

      options, _json = cmd.parse_options(["-t", "My Title"])
      options.title.should eq("My Title")
    end

    it "parses archetype flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["--archetype", "blog"])
      options.archetype.should eq("blog")

      options, _json = cmd.parse_options(["-a", "news"])
      options.archetype.should eq("news")
    end

    it "parses combinations of flags and arguments" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["posts/new.md", "--title", "New Post", "-a", "blog"])

      options.path.should eq("posts/new.md")
      options.title.should eq("New Post")
      options.archetype.should eq("blog")
    end

    it "parses --date flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md", "--date", "2026-03-22"])
      options.date.should eq("2026-03-22")
    end

    it "parses --draft flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md", "--draft"])
      options.draft.should be_true
    end

    it "defaults draft to nil (auto-detect)" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md"])
      options.draft.should be_nil
    end

    it "parses --tags flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md", "--tags", "go,web,api"])
      options.tags.should eq(["go", "web", "api"])
    end

    it "parses --tags with spaces" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md", "--tags", "go, web, api"])
      options.tags.should eq(["go", "web", "api"])
    end

    it "defaults tags to empty" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md"])
      options.tags.should be_empty
    end

    it "parses --section flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md", "--section", "blog"])
      options.section.should eq("blog")

      options, _json = cmd.parse_options(["post.md", "-s", "docs"])
      options.section.should eq("docs")
    end

    it "handles empty arguments" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options([] of String)

      options.path.should be_nil
      options.title.should be_nil
      options.archetype.should be_nil
      options.date.should be_nil
      options.draft.should be_nil
      options.tags.should be_empty
      options.section.should be_nil
    end

    it "raises on unknown flags" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      expect_raises(OptionParser::InvalidOption) do
        cmd.parse_options(["--unknown"])
      end
    end
  end

  # A malformed `config.toml` must surface as the same classified
  # HWARO_E_CONFIG error that every other command raises. Silently falling
  # back to defaults would hide user typos from `hwaro new`.
  describe "#run with malformed config" do
    it "raises HwaroError(HWARO_E_CONFIG) when config.toml is broken" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", "this = = broken\n")
          FileUtils.mkdir_p("content/drafts")

          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::NewCommand.new.run(["post.md", "-t", "Hello"])
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        end
      end
    end
  end
end
