require "../spec_helper"
require "../../src/cli/commands/init_command"
require "../../src/services/initializer"

# `hwaro init`'s failure paths used to call `Logger.error` + `exit(1)`, so
# every one of them was indistinguishable from a generic crash: no
# `HWARO_E_*` code, no `--json` payload, and exit 1 instead of the
# documented 2 (usage) / 6 (io). See docs/content/start/cli.md.
describe "hwaro init classified usage errors" do
  describe "--scaffold" do
    it "raises HwaroError(HWARO_E_USAGE) for an unknown scaffold type" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      err = expect_raises(Hwaro::HwaroError) do
        with_captured_log { cmd.parse_options(["--scaffold", "bogus"]) }
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      err.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      (err.message || "").should contain("Unknown scaffold type: bogus")
      (err.hint || "").should contain("--list-scaffolds")
    end

    it "still prints the available scaffolds alongside the error" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      log = with_captured_log do
        cmd.parse_options(["--scaffold", "bogus"])
      rescue Hwaro::HwaroError
        # expected — we only care about what was printed
      end
      log.should contain("Available scaffolds:")
      log.should contain("Remote scaffolds:")
    end
  end

  describe "--scaffold with a remote source" do
    it "raises HwaroError(HWARO_E_USAGE) for a malformed github: shorthand" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      err = expect_raises(Hwaro::HwaroError) { cmd.parse_options(["--scaffold", "github:onlyowner"]) }
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      err.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      (err.message || "").should contain("Invalid GitHub shorthand")
    end

    it "raises HwaroError(HWARO_E_USAGE) for a non-GitHub URL" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      err = expect_raises(Hwaro::HwaroError) { cmd.parse_options(["--scaffold", "https://example.com/foo"]) }
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      (err.message || "").should contain("Only GitHub URLs are supported")
    end

    it "still accepts a well-formed remote source" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      options = cmd.parse_options(["--scaffold", "github:hahwul/hwaro-starter-blog"])
      options.scaffold_remote.should eq("github:hahwul/hwaro-starter-blog")
    end
  end

  describe "--agents" do
    it "raises HwaroError(HWARO_E_USAGE) for an unknown agents mode" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      err = expect_raises(Hwaro::HwaroError) { cmd.parse_options(["--agents", "bogus"]) }
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      err.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      (err.message || "").should contain("Unknown agents mode: bogus")
      (err.hint || "").should contain("remote")
    end
  end

  describe "extra positionals" do
    it "rejects a second positional instead of silently dropping it" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      err = expect_raises(Hwaro::HwaroError) { cmd.parse_options(["My", "Blog", "Site"]) }
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      (err.message || "").should contain("unexpected extra argument(s): 'Blog', 'Site'")
      (err.hint || "").should contain("single [path]")
    end

    it "accepts a single positional unchanged" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      cmd.parse_options(["my-site"]).path.should eq("my-site")
    end

    it "honours `--` so a leading-dash directory name is reachable" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      cmd.parse_options(["--", "-dash"]).path.should eq("-dash")
    end

    it "leaves flag-looking leftovers to OptionParser's invalid-option error" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      expect_raises(OptionParser::InvalidOption) { cmd.parse_options(["--bogus", "site"]) }
    end
  end

  describe "introspection flags" do
    it "does not swallow unknown flags passed alongside --list-scaffolds" do
      cmd = Hwaro::CLI::Commands::InitCommand.new
      expect_raises(OptionParser::InvalidOption) do
        with_captured_log { cmd.run(["--list-scaffolds", "--totally-bogus"]) }
      end
    end

    it "still lists scaffolds for a clean invocation" do
      log = with_captured_log { Hwaro::CLI::Commands::InitCommand.new.run(["--list-scaffolds"]) }
      log.should contain("Available scaffolds:")
    end

    it "exposes -j as the short form of --json" do
      Hwaro::CLI::Commands::InitCommand::FLAGS
        .find! { |f| f.long == "--json" }
        .short.should eq("-j")
    end
  end

  describe "Initializer target directory" do
    it "raises HwaroError(HWARO_E_USAGE) when the target is not empty" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "README.md"), "hello")

        err = expect_raises(Hwaro::HwaroError) do
          with_captured_log do
            Hwaro::Services::Initializer.new.run(
              Hwaro::Config::Options::InitOptions.new(path: dir)
            )
          end
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
        err.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
        (err.message || "").should contain("is not empty")
        (err.hint || "").should contain("--force")
      end
    end

    it "raises HwaroError(HWARO_E_IO) when the target path is an existing file" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "afile")
        File.write(target, "not a directory")

        err = expect_raises(Hwaro::HwaroError) do
          with_captured_log do
            Hwaro::Services::Initializer.new.run(
              Hwaro::Config::Options::InitOptions.new(path: target)
            )
          end
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_IO)
        err.exit_code.should eq(Hwaro::Errors::EXIT_IO)
        (err.message || "").should contain("Cannot create project directory")
      end
    end
  end

  describe "ignorable dotfiles" do
    it "treats a directory holding only VCS/OS metadata as empty" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, ".git"))
        File.write(File.join(dir, ".DS_Store"), "")
        File.write(File.join(dir, ".gitignore"), "public/\n")

        with_captured_log do
          Hwaro::Services::Initializer.new.run(
            Hwaro::Config::Options::InitOptions.new(path: dir)
          )
        end

        File.exists?(File.join(dir, "config.toml")).should be_true
        # The pre-existing metadata is left untouched.
        File.exists?(File.join(dir, ".gitignore")).should be_true
      end
    end

    it "still refuses a directory holding real user content" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, ".git"))
        File.write(File.join(dir, "notes.txt"), "mine")

        err = expect_raises(Hwaro::HwaroError) do
          with_captured_log do
            Hwaro::Services::Initializer.new.run(
              Hwaro::Config::Options::InitOptions.new(path: dir)
            )
          end
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
        File.exists?(File.join(dir, "config.toml")).should be_false
      end
    end
  end

  describe "--minimal-config with --include-multilingual" do
    it "does not claim to ignore the languages it actually emits" do
      Dir.mktmpdir do |dir|
        log = with_captured_log do
          Hwaro::Services::Initializer.new.run(
            Hwaro::Config::Options::InitOptions.new(
              path: dir,
              minimal_config: true,
              multilingual_languages: ["en", "ko"],
            )
          )
        end

        log.should_not contain("ignoring --include-multilingual")

        config = File.read(File.join(dir, "config.toml"))
        config.should contain("[languages]")
        config.should contain("[languages.ko]")
        config.should contain("default_language = \"en\"")
      end
    end
  end
end
