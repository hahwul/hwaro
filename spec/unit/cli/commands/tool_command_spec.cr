require "../../../spec_helper"

# `hwaro tool` with no subcommand printed the help and bailed out with a bare
# `exit(1)` — the generic exit code and no `HWARO_E_USAGE` line, unlike every
# other missing-argument usage error (docs/content/start/cli.md).
describe "hwaro tool classified usage errors" do
  it "raises HwaroError(HWARO_E_USAGE) when <subcommand> is missing" do
    err = expect_raises(Hwaro::HwaroError) do
      with_captured_log { Hwaro::CLI::Commands::ToolCommand.new.run([] of String) }
    end
    err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
    err.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
    (err.message || "").should contain("missing <subcommand> argument")
  end

  it "still prints the usage help before failing" do
    log = with_captured_log do
      Hwaro::CLI::Commands::ToolCommand.new.run([] of String)
    rescue Hwaro::HwaroError
    end
    log.should contain("Usage: hwaro tool <subcommand>")
  end
end
