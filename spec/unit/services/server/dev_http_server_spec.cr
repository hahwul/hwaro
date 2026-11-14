require "../../../spec_helper"
require "../../../../src/services/server/server"

class Hwaro::Services::DevHTTPServer
  def network_handle_client_for_test(io : IO)
    handle_client(io)
  end
end

describe Hwaro::Services::DevHTTPServer do
  # The stdlib raises HTTP::Server::ClientError from `Response#close` (outside
  # its own rescue) when the peer resets after the request was read; it used to
  # escape into the fiber serving the connection as an "Unhandled exception in
  # spawn" backtrace.
  it "does not raise when the client resets before the response is flushed" do
    server = Hwaro::Services::DevHTTPServer.new do |ctx|
      sleep 100.milliseconds # the client resets while the handler is still working
      ctx.response.print("x" * 10_000)
    end
    listener = TCPServer.new("127.0.0.1", 0)
    begin
      spawn do
        client = TCPSocket.new("127.0.0.1", listener.local_address.port)
        client << "GET / HTTP/1.1\r\nHost: x\r\n\r\n"
        client.flush
        sleep 30.milliseconds
        client.linger = 0
        client.close
      end
      server.network_handle_client_for_test(listener.accept)
    ensure
      listener.close
    end
  end
end
