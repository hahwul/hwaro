require "../spec_helper"
require "../../src/models/config"
require "../../src/cli/commands/new_command"
require "../../src/services/creator"

# Every built-in scaffold ships `archetypes/default.md`, and archetype
# lookup always falls back to it, so a configured
# `[content.new].front_matter_format = "yaml"` silently never applied in a
# scaffolded project. The precedence (CLI > archetype > config) is
# intentional; the silence was not.
private def config_with_content_new(format : String, fields : Array(String)? = nil) : Hwaro::Models::Config
  config = Hwaro::Models::Config.new
  config.content_new.front_matter_format = format
  config.content_new.default_fields = fields if fields
  config
end

describe "hwaro new archetype vs [content.new]" do
  it "warns when an archetype overrides a configured front_matter_format" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("archetypes")
        File.write("archetypes/default.md", "+++\ntitle = \"{{ title }}\"\n+++\n")

        log = with_captured_log do
          Hwaro::Services::Creator.new.run(
            Hwaro::Config::Options::NewOptions.new(path: "a.md", title: "A"),
            config_with_content_new("yaml")
          )
        end

        log.should contain("archetype front matter is used as-is")
        # The archetype still wins — this is a diagnostic, not a behaviour change.
        File.read("content/a.md").should start_with("+++")
      end
    end
  end

  it "warns when default_fields were customized" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("archetypes")
        File.write("archetypes/default.md", "+++\ntitle = \"{{ title }}\"\n+++\n")

        log = with_captured_log do
          Hwaro::Services::Creator.new.run(
            Hwaro::Config::Options::NewOptions.new(path: "b.md", title: "B"),
            config_with_content_new("toml", ["description", "summary"])
          )
        end

        log.should contain("archetype front matter is used as-is")
      end
    end
  end

  it "stays silent for a project that never configured [content.new]" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("archetypes")
        File.write("archetypes/default.md", "+++\ntitle = \"{{ title }}\"\n+++\n")

        log = with_captured_log do
          Hwaro::Services::Creator.new.run(
            Hwaro::Config::Options::NewOptions.new(path: "c.md", title: "C"),
            Hwaro::Models::Config.new
          )
        end

        log.should_not contain("archetype front matter is used as-is")
      end
    end
  end

  it "stays silent when there is no archetype (the config actually applies)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("content")

        log = with_captured_log do
          Hwaro::Services::Creator.new.run(
            Hwaro::Config::Options::NewOptions.new(path: "d.md", title: "D"),
            config_with_content_new("yaml")
          )
        end

        log.should_not contain("archetype front matter is used as-is")
        File.read("content/d.md").should start_with("---")
      end
    end
  end
end

describe "hwaro new introspection flags" do
  it "does not swallow unknown flags passed alongside --list-archetypes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        expect_raises(OptionParser::InvalidOption) do
          with_captured_log { Hwaro::CLI::Commands::NewCommand.new.run(["--list-archetypes", "--totally-bogus"]) }
        end
      end
    end
  end

  it "still lists archetypes for a clean invocation" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("archetypes")
        File.write("archetypes/default.md", "+++\n+++\n")

        log = with_captured_log { Hwaro::CLI::Commands::NewCommand.new.run(["--list-archetypes"]) }
        log.should contain("default")
      end
    end
  end

  it "exposes -j as the short form of --json" do
    Hwaro::CLI::Commands::NewCommand::FLAGS
      .find! { |f| f.long == "--json" }
      .short.should eq("-j")
  end

  it "parses -j the same as --json" do
    cmd = Hwaro::CLI::Commands::NewCommand.new
    _, json_output = cmd.parse_options(["post.md", "-j"])
    json_output.should be_true
  end
end
