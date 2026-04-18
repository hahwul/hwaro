require "../spec_helper"
require "../../src/cli/commands/deploy_command"

describe Hwaro::CLI::Commands::DeployCommand do
  describe "#parse_options" do
    it "returns default options" do
      cmd = Hwaro::CLI::Commands::DeployCommand.new
      options, list_targets = cmd.parse_options([] of String)

      options.source_dir.should be_nil
      options.dry_run.should be_nil
      options.confirm.should be_nil
      options.force.should be_nil
      options.max_deletes.should be_nil
      options.targets.should be_empty
      list_targets.should be_false
    end

    it "parses source directory" do
      cmd = Hwaro::CLI::Commands::DeployCommand.new
      options, _ = cmd.parse_options(["--source", "dist"])
      options.source_dir.should eq("dist")

      options, _ = cmd.parse_options(["-s", "public"])
      options.source_dir.should eq("public")
    end

    it "parses boolean flags" do
      cmd = Hwaro::CLI::Commands::DeployCommand.new
      options, _ = cmd.parse_options(["--dry-run", "--confirm", "--force"])

      options.dry_run.should be_true
      options.confirm.should be_true
      options.force.should be_true
    end

    it "parses max deletes" do
      cmd = Hwaro::CLI::Commands::DeployCommand.new
      options, _ = cmd.parse_options(["--max-deletes", "10"])
      options.max_deletes.should eq(10)

      options, _ = cmd.parse_options(["--max-deletes", "-1"])
      options.max_deletes.should eq(-1)
    end

    it "parses list targets" do
      cmd = Hwaro::CLI::Commands::DeployCommand.new
      _, list_targets = cmd.parse_options(["--list-targets"])
      list_targets.should be_true
    end

    it "parses positional arguments as targets" do
      cmd = Hwaro::CLI::Commands::DeployCommand.new
      options, _ = cmd.parse_options(["production", "staging"])
      options.targets.should eq(["production", "staging"])
    end

    it "parses mixed flags and arguments" do
      cmd = Hwaro::CLI::Commands::DeployCommand.new
      options, _ = cmd.parse_options(["--dry-run", "production", "-s", "dist"])

      options.dry_run.should be_true
      options.source_dir.should eq("dist")
      options.targets.should eq(["production"])
    end
  end

  describe "#configured_targets_hint" do
    it "returns empty string when config.toml is missing" do
      cmd = Hwaro::CLI::Commands::DeployCommand.new
      Dir.mktmpdir do |dir|
        missing = File.join(dir, "missing.toml")
        cmd.configured_targets_hint(nil, missing).should eq("")
      end
    end

    it "reports no targets when config has none" do
      cmd = Hwaro::CLI::Commands::DeployCommand.new
      Dir.mktmpdir do |dir|
        path = File.join(dir, "config.toml")
        File.write(path, "title = \"Empty\"\n")
        hint = cmd.configured_targets_hint(nil, path)
        hint.should contain("Configured targets")
        hint.should contain("(none defined in")
      end
    end

    it "lists configured deployment targets" do
      cmd = Hwaro::CLI::Commands::DeployCommand.new
      Dir.mktmpdir do |dir|
        path = File.join(dir, "config.toml")
        File.write(path, <<-TOML)
        title = "Demo"

        [[deployment.targets]]
        name = "production"
        url = "s3://my-bucket"

        [[deployment.targets]]
        name = "staging"
        url = "netlify:site-id"
        TOML

        hint = cmd.configured_targets_hint(nil, path)
        hint.should contain("Configured targets (from")
        hint.should contain("production")
        hint.should contain("s3://my-bucket")
        hint.should contain("staging")
        hint.should contain("netlify:site-id")
      end
    end

    it "returns a friendly note when config.toml cannot be parsed" do
      cmd = Hwaro::CLI::Commands::DeployCommand.new
      Dir.mktmpdir do |dir|
        path = File.join(dir, "config.toml")
        File.write(path, "this is = = invalid toml [[\n")
        hint = cmd.configured_targets_hint(nil, path)
        hint.should contain("could not read")
      end
    end
  end
end
