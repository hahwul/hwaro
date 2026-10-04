require "../spec_helper"
require "json"

# `hwaro build --json` promises exactly one JSON document on stdout. The
# human-readable `--profile` tables and the `--debug` site tree printed to
# stdout ahead of the envelope and made it unparseable.
describe "hwaro build --json contract" do
  binary = hwaro_binary

  it "keeps --profile and --debug reports off stdout" do
    unless File.exists?(binary)
      pending! "bin/hwaro not built"
    end

    Dir.mktmpdir do |dir|
      site = File.join(dir, "site")
      Process.run(binary, ["init", site, "--scaffold", "blog", "-q"], output: Process::Redirect::Close, error: Process::Redirect::Close)

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(binary, ["build", "--json", "--profile", "--debug"], chdir: site, output: stdout, error: stderr)

      status.success?.should be_true
      payload = JSON.parse(stdout.to_s)
      payload["status"].as_s.should eq("ok")
      # The reports still reach the user, on stderr.
      stderr.to_s.should contain("Site Structure")
    end
  end
end
