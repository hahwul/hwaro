require "../spec_helper"
require "../../src/cli/commands/init_command"
require "../../src/cli/commands/init_wizard"

# Regressions for the two `--wizard` defects found by dogfooding:
#
#   1. `hwaro init --wizard --scaffold blog` used the *value* of the
#      value-taking flag as the target directory, creating a stray `blog/`
#      with the (wrong) simple scaffold.
#   2. `--wizard` discarded every other init flag, so `--force` was
#      unreachable and the run died after the user answered every prompt.
#
# Both come down to the same root cause — the wizard branch never consulted
# the parsed options — so they are covered together here.

private def with_wizard_input(data : String, &)
  previous = Hwaro::CLI::Prompt.input
  Hwaro::CLI::Prompt.input = IO::Memory.new(data)
  begin
    yield
  ensure
    Hwaro::CLI::Prompt.input = previous
  end
end

private def run_wizard(
  answers : String,
  seed_path : String? = nil,
  base : Hwaro::Config::Options::InitOptions? = nil,
  seed_scaffold : Hwaro::Config::Options::ScaffoldType? = nil,
) : {Hwaro::Config::Options::InitOptions?, String}
  result = nil
  log = with_captured_log do
    with_wizard_input(answers) do
      result = Hwaro::CLI::Commands::InitWizard.new.run(seed_path, base, seed_scaffold)
    end
  end
  {result, log}
end

describe "hwaro init --wizard flag handling" do
  describe "positional detection (gh: flag value used as <path>)" do
    it "does not treat a value-taking flag's value as the <path> positional" do
      cmd = Hwaro::CLI::Commands::InitCommand.new

      # `--scaffold blog` must select the blog scaffold, not name a directory.
      options = cmd.parse_options(["--wizard", "--scaffold", "blog"])
      options.path.should eq(".")
      options.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Blog)
    end

    it "does not treat --include-multilingual's value as the <path> positional" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options(["--wizard", "--include-multilingual", "en,ko"])
      options.path.should eq(".")
      options.multilingual_languages.should eq(["en", "ko"])
    end

    it "does not treat --agents' value as the <path> positional" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options(["--wizard", "--agents", "local"])
      options.path.should eq(".")
      options.agents_mode.should eq(Hwaro::Config::Options::AgentsMode::Local)
    end

    it "still picks up a real positional on either side of the flags" do
      cmd = Hwaro::CLI::Commands::InitCommand.new

      cmd.parse_options(["my-site", "--wizard", "--scaffold", "blog"]).path.should eq("my-site")
      cmd.parse_options(["--wizard", "--scaffold", "blog", "my-site"]).path.should eq("my-site")
    end
  end

  describe "flag pass-through" do
    it "keeps every non-wizard flag the user supplied" do
      base = Hwaro::Config::Options::InitOptions.new(
        force: true,
        skip_agents_md: true,
        skip_sample_content: true,
        minimal_config: true,
        agents_mode: Hwaro::Config::Options::AgentsMode::Local,
        multilingual_languages: ["en", "ko"],
      )

      # directory(Enter), scaffold(1 = simple), title, confirm(Enter = yes)
      options, _ = run_wizard("\n1\nMy Site\n\n", base: base)
      options.should_not be_nil
      options = options.not_nil!

      options.force.should be_true
      options.skip_agents_md.should be_true
      options.skip_sample_content.should be_true
      options.minimal_config.should be_true
      options.agents_mode.should eq(Hwaro::Config::Options::AgentsMode::Local)
      options.multilingual_languages.should eq(["en", "ko"])

      # …while still applying what the wizard collected.
      options.path.should eq(".")
      options.site_title.should eq("My Site")
      options.from_wizard.should be_true
    end

    it "skips the scaffold picker when --scaffold was supplied" do
      base = Hwaro::Config::Options::InitOptions.new(scaffold: Hwaro::Config::Options::ScaffoldType::Blog)

      # Only directory, title and confirm are asked now.
      options, log = run_wizard(
        "\nMy Blog\n\n",
        base: base,
        seed_scaffold: Hwaro::Config::Options::ScaffoldType::Blog,
      )

      options.should_not be_nil
      options.not_nil!.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Blog)
      log.should_not contain("Enter for simple")
      log.should contain("blog")
    end

    it "skips the scaffold picker for a remote scaffold and shows it in the receipt" do
      base = Hwaro::Config::Options::InitOptions.new(scaffold_remote: "github:owner/repo")

      options, log = run_wizard("\nRemote Site\n\n", base: base)

      options.should_not be_nil
      options.not_nil!.scaffold_remote.should eq("github:owner/repo")
      log.should_not contain("Enter for simple")
      log.should contain("github:owner/repo")
    end

    it "still asks for the scaffold when --scaffold was not supplied" do
      options, log = run_wizard("\n2\nMy Blog\n\n")

      log.should contain("Enter for simple")
      options.should_not be_nil
      options.not_nil!.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Blog)
    end

    it "does not mutate the caller's parsed options on cancellation" do
      base = Hwaro::Config::Options::InitOptions.new(path: ".", force: true)

      # Decline the confirmation.
      options, _ = run_wizard("site\n1\nTitle\nn\n", base: base)
      options.should be_nil

      # `InitOptions` is a struct, so the wizard worked on a copy.
      base.path.should eq(".")
      base.from_wizard.should be_false
      base.site_title.should be_nil
    end
  end

  describe "backwards-compatible entry points" do
    it "runs with no base options at all" do
      options, _ = run_wizard("site\n1\nTitle\n\n")
      options.should_not be_nil
      options.not_nil!.path.should eq("site")
      options.not_nil!.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Simple)
    end
  end
end
