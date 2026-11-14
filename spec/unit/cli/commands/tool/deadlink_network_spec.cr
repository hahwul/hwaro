require "../../../../spec_helper"

# check-links against a misbehaving peer. The loopback host is whitelisted in
# the SSRF cache so the in-process server can be reached.
class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def network_check_for_test(url : String, timeout_seconds : Int32) : {Int32, String?}
    @private_host_cache["127.0.0.1"] = false
    check_external_url(url, timeout_seconds)
  end
end

private def serve_peer(client : TCPSocket, script : TCPSocket, String ->) : Nil
  script.call(client, client.gets("\r\n\r\n") || "")
rescue IO::Error
ensure
  client.close
end

# `script` runs once per accepted connection after the request was read.
private def with_raw_peer(script : TCPSocket, String ->, & : Int32 ->)
  server = TCPServer.new("127.0.0.1", 0)
  spawn do
    while accepted = server.accept?
      spawn serve_peer(accepted, script)
    end
  end
  begin
    yield server.local_address.port
  ensure
    server.close
  end
end

describe "check-links external peers" do
  it "bounds a peer that trickles response headers inside the read timeout" do
    peer = ->(client : TCPSocket, _request : String) do
      client << "HTTP/1.1 200 OK\r\n"
      loop do
        client << "X"
        client.flush
        sleep 20.milliseconds
      end
    end
    with_raw_peer(peer) do |port|
      started = Time.instant
      status, error = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.network_check_for_test("http://127.0.0.1:#{port}/", 1)
      status.should eq(-1)
      error.to_s.should contain("timed out")
      (Time.instant - started).should be < 5.seconds
    end
  end

  it "does not buffer the body of the GET fallback" do
    peer = ->(client : TCPSocket, request : String) do
      if request.starts_with?("HEAD")
        client << "HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n"
      else
        client << "HTTP/1.1 200 OK\r\nContent-Length: 100000000000\r\n\r\n"
        chunk = Bytes.new(64 * 1024, 65_u8)
        loop { client.write(chunk) }
      end
    end
    with_raw_peer(peer) do |port|
      started = Time.instant
      status, _error = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.network_check_for_test("http://127.0.0.1:#{port}/", 1)
      status.should eq(200)
      (Time.instant - started).should be < 5.seconds
    end
  end
end
