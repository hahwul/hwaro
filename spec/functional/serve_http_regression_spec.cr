require "../spec_helper"
require "../../src/services/server/server"
require "http/client"
require "socket"

# Request-level regression coverage for the `hwaro serve` defect sweep.
#
# These bind the *real* handler chain (`Server#build_handlers`) to a loopback
# port and drive it with a real client, because the defects they guard only
# reproduce on the wire: HEAD framing on a keep-alive connection, responses
# past the response output buffer (`IO::DEFAULT_BUFFER_SIZE`, 32 KiB), and
# subpath mounting across several handlers.
#
# Reopened with a prefixed name so it can't collide with the shims other
# server specs install.
module Hwaro
  module Services
    class Server
      def serve_http_build_handlers(
        output_dir : String,
        base_path : String = "",
        headers : Hash(String, String) = {} of String => String,
        live_reload : Bool = true,
      ) : Array(HTTP::Handler)
        build_handlers(output_dir, "127.0.0.1", false, live_reload, headers, base_path)
      end
    end
  end
end

private def with_dev_server(
  base_path : String = "",
  headers : Hash(String, String) = {} of String => String,
  live_reload : Bool = true,
  &
)
  Dir.mktmpdir do |dir|
    FileUtils.mkdir_p(File.join(dir, "guide"))
    FileUtils.mkdir_p(File.join(dir, "한글"))
    File.write(File.join(dir, "index.html"), "<html><body>HOME</body></html>")
    File.write(File.join(dir, "404.html"), "<html><body>NOT FOUND PAGE</body></html>")
    File.write(File.join(dir, "guide", "index.html"), "<html><body>GUIDE</body></html>")
    File.write(File.join(dir, "한글", "index.html"), "<html><body>HANGUL</body></html>")
    # Straddle the 32 KiB response output buffer: the small file was always
    # fine, the large one used to lose its charset.
    File.write(File.join(dir, "small.txt"), "a" * 32_767)
    File.write(File.join(dir, "large.txt"), "a" * 40_000)
    File.write(File.join(dir, "large.json"), %({"k":"#{"x" * 40_000}"}))
    # HTML past the buffer, for the charset check that matters most.
    File.write(File.join(dir, "large.html"), "<html><body>#{"한" * 20_000}</body></html>")

    Hwaro::Services::Server.register_utf8_mime_types
    # DevHTTPServer, exactly as `Server#run_with_options` builds it — the
    # malformed-request rescue lives there, not in the handler chain.
    server = Hwaro::Services::DevHTTPServer.new(
      Hwaro::Services::Server.new.serve_http_build_handlers(dir, base_path, headers, live_reload)
    )
    address = server.bind_unused_port("127.0.0.1")
    spawn { server.listen }
    # `listening?` flips synchronously inside `#listen`, so once it is true the
    # accept path is live.
    until server.listening?
      Fiber.yield
    end

    begin
      yield address.port, dir
    ensure
      server.close
    end
  end
end

private def dev_client(port : Int32, &)
  client = HTTP::Client.new("127.0.0.1", port)
  client.read_timeout = 5.seconds
  client.connect_timeout = 2.seconds
  begin
    yield client
  ensure
    client.close
  end
end

# Every routing rule has to hold identically with and without a mount point.
# The unservable rules and the subpath mount were specced independently, and
# the moment they met they regressed: BasePathHandler's canonicalising
# pre-empt reached an unservable path before the hard refusal could 404 it, so
# `/myblog/%2Fguide%2Findex.html` answered 302 and `/myblog/index%00.html`
# raised out of the handler as a 500 — both correct at the domain root. These
# are parameterised rather than duplicated so a future routing rule cannot be
# added to only one shape.
[nil, "/myblog"].each do |mount|
  shape = mount ? "under a #{mount} mount" : "at the domain root"

  describe "hwaro serve routing #{shape}" do
    # A site-relative path as the client must ask for it in this shape.
    at = ->(path : String) { mount ? "#{mount}#{path}" : path }

    it "404s every alias a static host would refuse" do
      with_dev_server(base_path: mount || "") do |port, _|
        {
          "/guide%5Cindex.html"    => "encoded backslash",
          "/%2Fguide%2Findex.html" => "encoded slash",
          "/%2fguide%2f"           => "encoded slash, lowercase",
          "/%2e%2e%2findex.html"   => "encoded slash with dot segments",
          "/index%00.html"         => "encoded NUL",
        }.each do |path, label|
          response = dev_client(port, &.get(at.call(path)))
          unless response.status_code == 404
            fail "#{label} (#{at.call(path)}) should 404, got #{response.status_code}"
          end
        end
      end
    end

    it "answers 404, not 500, for invalid UTF-8 in the request path" do
      with_dev_server(base_path: mount || "") do |port, _|
        ["/\xc0\xae\xc0\xae/x.html", "/\xff\xfe.html"].each do |path|
          socket = TCPSocket.new("127.0.0.1", port)
          socket.read_timeout = 5.seconds
          begin
            socket << "GET #{at.call(path)} HTTP/1.1\r\nHost: h\r\nConnection: close\r\n\r\n"
            socket.flush
            status = socket.gets || ""
          ensure
            socket.close
          end
          status.should contain("404")
          status.should_not contain("500")
        end
      end
    end

    it "rejects path traversal" do
      with_dev_server(base_path: mount || "") do |port, _|
        ["/../../etc/passwd", "/%2e%2e%2f%2e%2e%2fetc%2fpasswd",
         "/%2e%2e/%2e%2e/etc/passwd", "/....//....//etc/passwd"].each do |path|
          response = dev_client(port, &.get(at.call(path)))
          response.status_code.should_not eq(200)
          response.body.includes?("root:").should be_false
        end
      end
    end

    it "serves unicode routes percent-encoded and raw" do
      with_dev_server(base_path: mount || "") do |port, _|
        dev_client(port, &.get(at.call("/%ED%95%9C%EA%B8%80/"))).body.should contain("HANGUL")
        dev_client(port, &.get(at.call("/한글/"))).body.should contain("HANGUL")
      end
    end

    it "redirects a directory without a trailing slash, keeping the mount point" do
      with_dev_server(base_path: mount || "") do |port, _|
        response = dev_client(port, &.get(at.call("/guide")))
        response.status_code.should eq(302)
        response.headers["Location"].should eq(at.call("/guide/"))
      end
    end

    it "percent-encodes the trailing-slash redirect Location" do
      with_dev_server(base_path: mount || "") do |port, _|
        response = dev_client(port, &.get(at.call("/%ED%95%9C%EA%B8%80")))
        response.status_code.should eq(302)
        response.headers["Location"].should eq(at.call("/%ED%95%9C%EA%B8%80/"))
        response.headers["Location"].each_char.all?(&.ascii?).should be_true
      end
    end

    it "serves a file whose name contains .. without being all dots" do
      with_dev_server(base_path: mount || "") do |port, dir|
        File.write(File.join(dir, "lib.v1..2.js"), "DOTTED_ASSET")
        FileUtils.mkdir_p(File.join(dir, "a..b"))
        File.write(File.join(dir, "a..b", "index.html"), "<html><body>DOTTED_PAGE</body></html>")

        dev_client(port, &.get(at.call("/lib.v1..2.js"))).body.should contain("DOTTED_ASSET")
        dev_client(port, &.get(at.call("/a..b/"))).body.should contain("DOTTED_PAGE")
      end
    end

    it "lets a dot segment canonicalise instead of 404ing it" do
      with_dev_server(base_path: mount || "") do |port, _|
        dev_client(port, &.get(at.call("/guide/../small.txt"))).status_code.should_not eq(404)
      end
    end

    it "does not 404 an encoded slash in the query string" do
      with_dev_server(base_path: mount || "") do |port, _|
        dev_client(port, &.get(at.call("/small.txt?next=%2Fguide%2F"))).status_code.should eq(200)
      end
    end

    it "answers two pipelined HEAD requests on one keep-alive connection" do
      with_dev_server(base_path: mount || "") do |port, _|
        socket = TCPSocket.new("127.0.0.1", port)
        socket.read_timeout = 5.seconds
        begin
          2.times { socket << "HEAD #{at.call("/missing")} HTTP/1.1\r\nHost: h\r\n\r\n" }
          socket << "GET #{at.call("/missing")} HTTP/1.1\r\nHost: h\r\nConnection: close\r\n\r\n"
          socket.flush
          raw = socket.gets_to_end
        ensure
          socket.close
        end

        raw.scan(/^HTTP\/1\.1 /m).size.should eq(3)
        raw.scan(/NOT FOUND PAGE/).size.should eq(1)
      end
    end

    it "reports the same Content-Length for HEAD and GET" do
      with_dev_server(base_path: mount || "") do |port, _|
        head_length = dev_client(port, &.head(at.call("/"))).headers["Content-Length"]
        get_response = dev_client(port, &.get(at.call("/")))

        head_length.should eq(get_response.headers["Content-Length"])
        head_length.to_i.should eq(get_response.body.bytesize)
      end
    end

    it "answers 405 with Allow for unsupported methods" do
      with_dev_server(base_path: mount || "") do |port, _|
        response = dev_client(port, &.post(at.call("/")))
        response.status_code.should eq(405)
        response.headers["Allow"].should eq("GET, HEAD, OPTIONS")
      end
    end

    it "applies custom headers and no-store to the CORS preflight" do
      with_dev_server(base_path: mount || "", headers: {"X-Guard" => "on"}) do |port, _|
        response = dev_client(port) do |client|
          client.options(at.call("/"), HTTP::Headers{"Origin" => "http://localhost"})
        end

        response.status_code.should eq(204)
        response.headers["X-Guard"].should eq("on")
        response.headers["Cache-Control"].should eq("no-store")
        response.headers["Access-Control-Allow-Origin"].should eq("http://localhost")
        response.headers["Access-Control-Allow-Methods"].should eq("GET, HEAD, OPTIONS")
      end
    end

    it "injects the live-reload script into the 404 page" do
      with_dev_server(base_path: mount || "") do |port, _|
        response = dev_client(port, &.get(at.call("/missing")))
        response.status_code.should eq(404)
        response.body.should contain("NOT FOUND PAGE")
        response.body.should contain("__hwaro_livereload")
      end
    end
  end
end

describe "hwaro serve HTTP behaviour" do
  # Finding 6
  it "includes the injected script in the Content-Length reported to HEAD" do
    with_dev_server do |port, _|
      get_response = dev_client(port, &.get("/"))
      get_response.body.should contain("__hwaro_livereload")
      dev_client(port, &.head("/")).headers["Content-Length"]
        .should eq(get_response.headers["Content-Length"])
    end
  end

  # Finding 2
  it "keeps the UTF-8 charset on text responses past the output buffer" do
    with_dev_server do |port, _|
      {"/small.txt" => "text/plain", "/large.txt" => "text/plain", "/large.json" => "application/json"}.each do |path, base|
        response = dev_client(port, &.get(path))
        response.status_code.should eq(200)
        response.headers["Content-Type"].should eq("#{base}; charset=utf-8")
      end
    end
  end

  # Review finding 3: HTML was missing from the registration list, so a large
  # page went out as bare `text/html` and a CJK page rendered as mojibake.
  # Served through StaticFileHandler (live reload off) — the path the injector,
  # which sets its own charset, does not cover.
  it "keeps the UTF-8 charset on a large HTML page served statically" do
    with_dev_server(live_reload: false) do |port, _|
      response = dev_client(port, &.get("/large.html"))
      response.status_code.should eq(200)
      response.body.bytesize.should be > 32_768
      response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    end
  end

  it "still refuses CORS for a non-loopback origin" do
    with_dev_server do |port, _|
      response = dev_client(port) do |client|
        client.get("/", HTTP::Headers{"Origin" => "http://evil.example"})
      end
      response.headers["Access-Control-Allow-Origin"]?.should be_nil
    end
  end

  it "serves plain static files without the injector when live reload is off" do
    with_dev_server(live_reload: false) do |port, _|
      response = dev_client(port, &.get("/"))
      response.status_code.should eq(200)
      response.body.should contain("HOME")
      response.body.includes?("__hwaro_livereload").should be_false
    end
  end
end

# Finding 5: behaviour that only exists when a mount point is configured.
describe "hwaro serve with a base_url subpath" do
  it "serves the site under the mount point" do
    with_dev_server(base_path: "/myblog") do |port, _|
      dev_client(port, &.get("/myblog/")).body.should contain("HOME")
      dev_client(port, &.get("/myblog/guide/")).body.should contain("GUIDE")
      dev_client(port, &.get("/myblog/small.txt")).status_code.should eq(200)
    end
  end

  it "redirects the bare root to the mount point" do
    with_dev_server(base_path: "/myblog") do |port, _|
      response = dev_client(port, &.get("/"))
      response.status_code.should eq(302)
      response.headers["Location"].should eq("/myblog/")
    end
  end

  it "keeps the live-reload script and its unprefixed endpoint" do
    with_dev_server(base_path: "/myblog") do |port, _|
      body = dev_client(port, &.get("/myblog/")).body
      body.should contain("/__hwaro_livereload")
      # The endpoint answers (403 without an Origin, never 404).
      dev_client(port, &.get("/__hwaro_livereload")).status_code.should eq(403)
    end
  end

  it "still resolves an unprefixed asset instead of 404ing it" do
    with_dev_server(base_path: "/myblog") do |port, _|
      dev_client(port, &.get("/small.txt")).status_code.should eq(200)
    end
  end

  # Review finding 2: these redirects come from HTTP::StaticFileHandler, which
  # emits them via Response#redirect — that CLOSES the response, so the
  # post-call_next header edit BasePathHandler used could never reach the wire
  # and the mount point was silently dropped. `//` is a routine artifact of
  # `{{ base_url }}/…` concatenation, so this is ordinary-use reachable.
  # Driven through a real StaticFileHandler on purpose: a spec double that sets
  # the header without closing cannot reproduce it.
  it "keeps the mount point on a canonicalising redirect" do
    with_dev_server(base_path: "/myblog") do |port, _|
      {
        "/myblog//small.txt"         => "/myblog/small.txt",
        "/myblog/./small.txt"        => "/myblog/small.txt",
        "/myblog/guide/../small.txt" => "/myblog/small.txt",
      }.each do |path, expected|
        response = dev_client(port, &.get(path))
        response.status_code.should eq(302)
        response.headers["Location"].should eq(expected)
      end
    end
  end

  it "keeps the query string on a canonicalising redirect" do
    with_dev_server(base_path: "/myblog") do |port, _|
      response = dev_client(port, &.get("/myblog//small.txt?a=1"))
      response.headers["Location"].should eq("/myblog/small.txt?a=1")
    end
  end

  it "follows a canonicalising redirect back to the real file" do
    with_dev_server(base_path: "/myblog") do |port, _|
      location = dev_client(port, &.get("/myblog//small.txt")).headers["Location"]
      dev_client(port, &.get(location)).status_code.should eq(200)
    end
  end
end

# `HTTP::Request.from_io` parses Content-Length eagerly and strictly, and it
# runs above every rescue in `HTTP::Server::RequestProcessor#process` — so a
# malformed value used to raise ArgumentError straight out of the connection
# fiber: the client got zero bytes (not even a status line) and the developer's
# terminal was repainted with a Crystal backtrace for every such request.
describe "hwaro serve malformed request handling" do
  # Sends a raw request and returns its status line ("" when the server closed
  # the connection without answering, which is the pre-fix behaviour).
  status_line = ->(port : Int32, request : String) do
    socket = TCPSocket.new("127.0.0.1", port)
    socket.read_timeout = 5.seconds
    begin
      socket << request
      socket.flush
      socket.gets || ""
    ensure
      socket.close
    end
  end

  it "answers 400 to a Content-Length the parser refuses" do
    with_dev_server do |port, _|
      ["abc", "0x5", "99999999999999999999999"].each do |value|
        line = status_line.call(port, "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: #{value}\r\nConnection: close\r\n\r\n")
        unless line.includes?("400")
          fail "Content-Length: #{value} should answer 400, got #{line.inspect}"
        end
      end
    end
  end

  it "answers 400 to duplicated, disagreeing Content-Length headers" do
    with_dev_server do |port, _|
      line = status_line.call(port, "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 0\r\nContent-Length: 5\r\nConnection: close\r\n\r\n")
      line.should contain("400")
    end
  end

  # The rescue must not swallow ordinary traffic: a well-formed request on the
  # same server still gets its real response.
  it "still answers a well-formed request normally" do
    with_dev_server do |port, _|
      dev_client(port, &.get("/")).body.should contain("HOME")
    end
  end
end
