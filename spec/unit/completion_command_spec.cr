require "../spec_helper"

# Ensure commands are registered for completion generation
private def ensure_commands_registered
  return if Hwaro::CLI::CommandRegistry.all_metadata.any?
  Hwaro::CLI::CommandRegistry.register(Hwaro::CLI::Commands::InitCommand.metadata) { |_| }
  Hwaro::CLI::CommandRegistry.register(Hwaro::CLI::Commands::BuildCommand.metadata) { |_| }
  Hwaro::CLI::CommandRegistry.register(Hwaro::CLI::Commands::ServeCommand.metadata) { |_| }
  Hwaro::CLI::CommandRegistry.register(Hwaro::CLI::Commands::NewCommand.metadata) { |_| }
  Hwaro::CLI::CommandRegistry.register(Hwaro::CLI::Commands::DeployCommand.metadata) { |_| }
  Hwaro::CLI::CommandRegistry.register(Hwaro::CLI::Commands::ToolCommand.metadata) { |_| }
  Hwaro::CLI::CommandRegistry.register(Hwaro::CLI::Commands::CompletionCommand.metadata) { |_| }
end

describe Hwaro::CLI::Commands::CompletionCommand do
  before_each { ensure_commands_registered }

  describe "bash completion" do
    it "generates a bash completion script" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_bash_for_test

      output.should contain("_hwaro_completions")
      output.should contain("complete -F _hwaro_completions hwaro")
    end

    it "includes command names in bash script" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_bash_for_test

      output.should contain("build")
      output.should contain("serve")
      output.should contain("init")
      output.should contain("deploy")
      output.should contain("completion")
    end

    it "includes version and help in bash commands" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_bash_for_test

      output.should contain("version")
      output.should contain("help")
    end

    it "includes positional_choices for completion command in bash" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_bash_for_test

      output.should contain("bash")
      output.should contain("zsh")
      output.should contain("fish")
    end

    it "uses compgen for bash completions" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_bash_for_test

      output.should contain("compgen")
      output.should contain("COMPREPLY")
    end
  end

  describe "zsh completion" do
    it "generates a zsh completion script with compdef header" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_zsh_for_test

      output.should contain("#compdef hwaro")
      output.should contain("_hwaro")
    end

    it "includes _hwaro function definition" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_zsh_for_test

      output.should contain("_hwaro()")
      output.should contain("_arguments")
      output.should contain("_describe")
    end

    it "includes command descriptions in zsh" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_zsh_for_test

      output.should contain("'version:Show version'")
      output.should contain("'help:Show help'")
    end

    it "includes subcommand support in zsh" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_zsh_for_test

      # completion command should have positional choices
      output.should contain("completion)")
    end
  end

  describe "fish completion" do
    it "generates a fish completion script" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_fish_for_test

      output.should contain("complete -c hwaro -f")
    end

    it "includes main commands in fish" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_fish_for_test

      output.should contain("__fish_use_subcommand")
      output.should contain("build")
      output.should contain("serve")
      output.should contain("deploy")
      output.should contain("version")
      output.should contain("help")
    end

    it "includes subcommand conditions with __fish_seen_subcommand_from" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_fish_for_test

      output.should contain("__fish_seen_subcommand_from")
    end

    it "includes positional choices for completion in fish" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_fish_for_test

      # The completion command's positional choices (bash, zsh, fish) should appear
      output.should contain("bash")
      output.should contain("zsh")
      output.should contain("fish")
    end

    it "registers flags with descriptions in fish" do
      cmd = Hwaro::CLI::Commands::CompletionCommand.new
      output = cmd.generate_fish_for_test

      # Should have -d for description syntax
      output.should contain("-d")
    end
  end
end

# Test helper to expose private generate_ methods
class Hwaro::CLI::Commands::CompletionCommand
  def generate_bash_for_test : String
    generate_bash
  end

  def generate_zsh_for_test : String
    generate_zsh
  end

  def generate_fish_for_test : String
    generate_fish
  end
end
