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

  it "reports a connection closed without a response, pinned or not" do
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
      expect_raises(Hwaro::Core::Build::RemoteFetch::FetchError, "Unexpected end of http response") do
        Hwaro::Core::Build::RemoteFetch.fetch(url, {} of String => String, 1024_i64, 10.seconds)
      end
      # Pinned, the client cannot tell an EOF from a reset; never the
      # misleading "cannot be reconnected".
      expect_raises(Hwaro::Core::Build::RemoteFetch::FetchError, "connection closed or reset before a response") do
        Hwaro::Core::Build::RemoteFetch.fetch(url, {} of String => String, 1024_i64, 10.seconds, guard: pinned)
      end
    ensure
      server.close
    end
  end

  it "turns a redirect Location with a port above Int32 into a FetchError" do
    server = HTTP::Server.new do |ctx|
      ctx.response.status = HTTP::Status::FOUND
      ctx.response.headers["Location"] = "http://example.com:99999999999999999999/x.js"
    end
    port = server.bind_tcp("127.0.0.1", 0).port
    spawn { server.listen }
    Fiber.yield
    begin
      expect_raises(Hwaro::Core::Build::RemoteFetch::FetchError, "port out of range") do
        Hwaro::Core::Build::RemoteFetch.fetch("http://127.0.0.1:#{port}/r", {} of String => String, 1024_i64, 10.seconds)
      end
    ensure
      server.close
    end
    expect_raises(Hwaro::Core::Build::RemoteFetch::FetchError, "port out of range") do
      Hwaro::Core::Build::RemoteFetch.fetch("http://example.com:99999999999999999999/x", {} of String => String, 1024_i64, 10.seconds)
    end
    Hwaro::Core::Build::RemoteFetch.sanitized_url("http://example.com:99999999999999999999/x").should eq("<unparseable url>")
  end

  it "percent-encodes non-ASCII and spaces in the request line, leaving existing escapes alone" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.local_address.port
    lines = Channel(String).new(1)
    spawn do
      if client = server.accept?
        lines.send(client.gets(chomp: true) || "")
        client << "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
        client.close
      end
    end
    Fiber.yield
    begin
      Hwaro::Core::Build::RemoteFetch.fetch("http://127.0.0.1:#{port}/한글/a b%20c.png?q=가&r=%E3%81%82", {} of String => String, 1024_i64, 10.seconds)
      lines.receive.should eq("GET /%ED%95%9C%EA%B8%80/a%20b%20c.png?q=%EA%B0%80&r=%E3%81%82 HTTP/1.1")
    ensure
      server.close
    end
  end
end
