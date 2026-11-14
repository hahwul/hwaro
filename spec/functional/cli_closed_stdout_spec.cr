require "../spec_helper"

# A closed stdout (`>&-`) must not turn a classified failure into an uncaught
# `IO::Error` backtrace or the unclassified exit 1: the exit code still says
# what happened even though the result cannot be printed.

private HWARO_BIN = hwaro_binary

Spec.before_suite do
  unless File.exists?(HWARO_BIN) && File::Info.executable?(HWARO_BIN)
    raise "Binary #{HWARO_BIN} is missing or not executable. Run `shards build` first."
  end
end

private def run_closed_stdout(args : String)
  error = IO::Memory.new
  status = Process.run("/bin/sh", ["-c", "exec \"$0\" #{args} >&-", HWARO_BIN], output: Process::Redirect::Close, error: error)
  {status.exit_code, error.to_s}
end

describe "hwaro with stdout closed" do
  it "keeps the usage exit code for a --json failure" do
    posix_only!("sh redirection")
    code, err = run_closed_stdout("build --json --bogus")
    err.should_not contain("Unhandled exception")
    code.should eq(2)
  end

  it "classifies the write failure of a result as an I/O error" do
    posix_only!("sh redirection")
    code, err = run_closed_stdout("completion zsh")
    err.should_not contain("Unhandled exception")
    code.should eq(6)
  end
end
