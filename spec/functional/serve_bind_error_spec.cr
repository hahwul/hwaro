require "../spec_helper"
require "../../src/services/server/server"
require "socket"

# Regression coverage for an unclassified `hwaro serve` failure.
#
# `HTTP::Server#bind_tcp` does two things: it resolves `host`, then binds.
# Only the bind half raises `Socket::BindError`, and that was the only
# exception serve rescued — so a `-b/--bind` value the resolver cannot answer
# for (`-b 300.1.1.1`, a typo'd hostname) raised `Socket::Addrinfo::Error`
# straight out of `run_with_options` and reached the user as a bare
# `Error: Hostname lookup for 300.1.1.1 failed: No address found`: no error
# code, no hint, and nothing naming the flag that produced it.
#
# The CLI-level example is the one that matters — it compiles and fails
# against pre-fix sources, where the seam below did not exist yet.
private HWARO_BIND_BIN = File.expand_path("../../bin/hwaro", __DIR__)

Spec.before_suite do
  unless File.exists?(HWARO_BIND_BIN) && File::Info.executable?(HWARO_BIND_BIN)
    raise "Binary #{HWARO_BIND_BIN} is missing or not executable. Run `shards build` first."
  end
end

module Hwaro
  module Services
    class Server
      def bind_error_bind(server : HTTP::Server, host : String, port : Int32)
        bind_dev_server(server, host, port)
      end
    end
  end
end

# A server that never listens — these examples only drive the bind step. It
# still needs a handler: `HTTP::Server.new` refuses an empty chain.
private def bind_error_probe_server : HTTP::Server
  HTTP::Server.new(&.response.status_code=(204))
end

private def bind_error_site(dir : String)
  %w[content templates].each { |d| FileUtils.mkdir_p(File.join(dir, d)) }
  File.write(File.join(dir, "config.toml"), %(title = "Bind"\nbase_url = "https://example.com"\n))
  File.write(File.join(dir, "content", "_index.md"), "---\ntitle: Home\n---\nBody")
  File.write(File.join(dir, "templates", "index.html"), "{{ page.title }}")
  File.write(File.join(dir, "templates", "page.html"), "{{ page.title }}")
end

describe "hwaro serve bind failures" do
  it "reports an unresolvable --bind host as a classified error" do
    Dir.mktmpdir do |dir|
      bind_error_site(dir)
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      # Port 0 would bind fine; the resolver refuses the host first. Pre-fix
      # this printed an unprefixed `Error: Hostname lookup …` line.
      status = Process.run(
        HWARO_BIND_BIN,
        ["serve", "-b", "300.1.1.1", "-p", "4399", "--no-open"],
        chdir: dir, output: stdout, error: stderr
      )

      combined = stdout.to_s + stderr.to_s
      status.success?.should be_false
      combined.should contain("Error [#{Hwaro::Errors::HWARO_E_USAGE}]")
      combined.should contain("300.1.1.1")
      combined.should contain("-b/--bind")
    end
  end

  it "classifies an unresolvable host at the bind seam" do
    error = expect_raises(Hwaro::HwaroError) do
      Hwaro::Services::Server.new.bind_error_bind(bind_error_probe_server, "300.1.1.1", 0)
    end
    error.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
    error.hint.to_s.should contain("-b/--bind")
  end

  # An address that resolves but this machine does not hold fails INSIDE
  # bind (EADDRNOTAVAIL) — a `Socket::BindError` like port-in-use, which used
  # to get the "another process is listening" hint. 192.0.2.1 is TEST-NET-1,
  # never assigned to a real interface.
  it "classifies an address this machine does not hold as a --bind usage error" do
    error = expect_raises(Hwaro::HwaroError) do
      Hwaro::Services::Server.new.bind_error_bind(bind_error_probe_server, "192.0.2.1", 0)
    end
    error.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
    error.hint.to_s.should contain("-b/--bind")
    error.hint.to_s.should_not contain("--port")
  end

  it "still classifies a port already in use as an IO error" do
    taken = TCPServer.new("127.0.0.1", 0)
    port = taken.local_address.port
    begin
      error = expect_raises(Hwaro::HwaroError) do
        Hwaro::Services::Server.new.bind_error_bind(bind_error_probe_server, "127.0.0.1", port)
      end
      error.code.should eq(Hwaro::Errors::HWARO_E_IO)
      error.hint.to_s.should contain("--port")
    ensure
      taken.close
    end
  end
end
