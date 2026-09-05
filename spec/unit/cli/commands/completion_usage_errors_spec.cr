require "../../../spec_helper"
require "../../../../src/cli/commands/completion_command"

# `hwaro completion` bailed out with a bare `exit(1)` on both usage errors,
# so scripts saw the generic exit code and no `HWARO_E_*` prefix — unlike
# every other classified usage error (docs/content/start/cli.md).
describe "hwaro completion classified usage errors" do
  it "raises HwaroError(HWARO_E_USAGE) when <shell> is missing" do
    err = expect_raises(Hwaro::HwaroError) do
      with_captured_log { Hwaro::CLI::Commands::CompletionCommand.new.run([] of String) }
    end
    err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
    err.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
    (err.message || "").should contain("missing <shell> argument")
  end

  it "still prints the usage help before failing" do
    log = with_captured_log do
      Hwaro::CLI::Commands::CompletionCommand.new.run([] of String)
    rescue Hwaro::HwaroError
      # expected — we only care about what was printed first
    end
    log.should contain("Usage: hwaro completion")
  end

  it "raises HwaroError(HWARO_E_USAGE) for an unsupported shell" do
    err = expect_raises(Hwaro::HwaroError) do
      with_captured_log { Hwaro::CLI::Commands::CompletionCommand.new.run(["tcsh"]) }
    end
    err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
    err.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
    (err.message || "").should contain("unknown shell 'tcsh'")
    (err.hint || "").should contain("bash, zsh, fish")
  end

  it "leaves the supported-shell list intact" do
    Hwaro::CLI::Commands::CompletionCommand::SHELLS.should eq(["bash", "zsh", "fish"])
  end
end
