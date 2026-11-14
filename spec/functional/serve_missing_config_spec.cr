require "../spec_helper"

# `hwaro serve` in a directory without config.toml fails like `hwaro build`
# (config error, exit 3) and creates nothing, instead of serving defaults.

private HWARO_BIN = hwaro_binary

private def run_serve(args : Array(String), chdir : String)
  output = IO::Memory.new
  error = IO::Memory.new
  # The pre-fix binary never exits, so bound the wait.
  process = Process.new(HWARO_BIN, ["serve"] + args, chdir: chdir, output: output, error: error)
  done = Channel(Process::Status).new(1)
  spawn { done.send(process.wait) }
  select
  when status = done.receive
    {status.exit_code, output.to_s, error.to_s}
  when timeout(15.seconds)
    process.terminate
    {-1, output.to_s, error.to_s}
  end
end

describe "hwaro serve without config.toml" do
  it "exits 3 with build's config error and creates nothing" do
    Dir.mktmpdir do |dir|
      code, _, err = run_serve(["-p", "39417"], dir)
      code.should eq(3), err
      err.should contain("config.toml not found")
      Dir.children(dir).should be_empty
    end
  end

  it "honours -i and the --json envelope" do
    Dir.mktmpdir do |dir|
      code, stdout, _ = run_serve(["-i", dir, "--json", "-p", "39418"], Dir.tempdir)
      code.should eq(3)
      JSON.parse(stdout)["error"]["code"].as_s.should eq("HWARO_E_CONFIG")
      Dir.children(dir).should be_empty
    end
  end
end
