require "../../../spec_helper"

# RemoteFetch's per-hop guard. Local servers only: a host that does not
# resolve (`.invalid`) proves the connection went to the pinned address.

private def with_echo_server(& : Int32, Array(String) ->)
  hosts = [] of String
  server = HTTP::Server.new do |ctx|
    hosts << (ctx.request.headers["Host"]? || "")
    if ctx.request.path == "/hop"
      ctx.response.status = HTTP::Status::FOUND
      ctx.response.headers["Location"] = "/final"
    else
      ctx.response.content_type = "text/plain"
      ctx.response.print("ok")
    end
  end
  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  Fiber.yield
  begin
    yield address.port, hosts
  ensure
    server.close
  end
end

describe Hwaro::Core::Build::RemoteFetch do
  it "pins every hop to the address the guard vetted, keeping the URL's Host" do
    with_echo_server do |port, hosts|
      vetted = [] of String
      guard = ->(uri : URI) { vetted << uri.path; ["127.0.0.1"].as(Array(String)?) }
      body, _type, final = Hwaro::Core::Build::RemoteFetch.fetch("http://pinned.invalid:#{port}/hop", {} of String => String,
        1024_i64, 10.seconds, guard: guard)
      body.should eq("ok")
      final.should eq("http://pinned.invalid:#{port}/final")
      vetted.should eq(["/hop", "/final"])
      hosts.should eq(["pinned.invalid:#{port}", "pinned.invalid:#{port}"])
    end
  end

  it "stops at a hop the guard refuses" do
    with_echo_server do |port, hosts|
      guard = ->(uri : URI) : Array(String)? { raise Hwaro::Core::Build::RemoteFetch::FetchError.new("no") if uri.path == "/final"; nil }
      expect_raises(Hwaro::Core::Build::RemoteFetch::FetchError, "no") do
        Hwaro::Core::Build::RemoteFetch.fetch("http://127.0.0.1:#{port}/hop", {} of String => String, 1024_i64, 10.seconds, guard: guard)
      end
      hosts.size.should eq(1)
    end
  end

  it "tries each vetted address in turn" do
    with_echo_server do |port, hosts|
      # Nothing listens on ::1 at this port; the next address answers.
      guard = ->(_uri : URI) { ["::1", "127.0.0.1"].as(Array(String)?) }
      body, _type, _final = Hwaro::Core::Build::RemoteFetch.fetch("http://pinned.invalid:#{port}/x", {} of String => String,
        1024_i64, 10.seconds, guard: guard)
      body.should eq("ok")
      hosts.should eq(["pinned.invalid:#{port}"])
    end
  end

  it "reports a connection closed without a response the same way pinned or not" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.local_address.port
    spawn do
      while client = server.accept?
        spawn do
          while (line = client.gets) && !line.empty?
          end
          client.close
        rescue IO::Error
        end
      end
    end
    Fiber.yield
    begin
      url = "http://127.0.0.1:#{port}/x"
      pinned = ->(_uri : URI) { ["127.0.0.1"].as(Array(String)?) }
      {nil, pinned}.each do |guard|
        expect_raises(Hwaro::Core::Build::RemoteFetch::FetchError, "Unexpected end of http response") do
          Hwaro::Core::Build::RemoteFetch.fetch(url, {} of String => String, 1024_i64, 10.seconds, guard: guard)
        end
      end
    ensure
      server.close
    end
  end
end
