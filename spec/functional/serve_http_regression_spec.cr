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

    Hwaro::Services::Server.register_utf8_mime_types
    server = HTTP::Server.new(
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

describe "hwaro serve HTTP behaviour" do
  # Finding 1: a HEAD that carries a body desyncs the connection, so the
  # second pipelined request never gets an answer.
  it "answers two pipelined HEAD requests on one keep-alive connection" do
    with_dev_server do |port, _|
      socket = TCPSocket.new("127.0.0.1", port)
      socket.read_timeout = 5.seconds
      begin
        socket << "HEAD /missing HTTP/1.1\r\nHost: h\r\n\r\n"
        socket << "HEAD /missing HTTP/1.1\r\nHost: h\r\nConnection: close\r\n\r\n"
        socket.flush
        raw = socket.gets_to_end
      ensure
        socket.close
      end

      raw.scan(/^HTTP\/1\.1 /m).size.should eq(2)
      raw.includes?("NOT FOUND PAGE").should be_false
    end
  end

  it "answers two pipelined HEAD requests for a page on one connection" do
    with_dev_server do |port, _|
      socket = TCPSocket.new("127.0.0.1", port)
      socket.read_timeout = 5.seconds
      begin
        socket << "HEAD / HTTP/1.1\r\nHost: h\r\n\r\n"
        socket << "HEAD / HTTP/1.1\r\nHost: h\r\nConnection: close\r\n\r\n"
        socket.flush
        raw = socket.gets_to_end
      ensure
        socket.close
      end

      raw.scan(/^HTTP\/1\.1 /m).size.should eq(2)
      raw.includes?("HOME").should be_false
    end
  end

  # Finding 6
  it "reports the same Content-Length for HEAD and GET on an injected page" do
    with_dev_server do |port, _|
      head_length = dev_client(port, &.head("/")).headers["Content-Length"]
      get_response = dev_client(port, &.get("/"))

      head_length.should eq(get_response.headers["Content-Length"])
      head_length.to_i.should eq(get_response.body.bytesize)
      get_response.body.should contain("__hwaro_livereload")
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

  # Finding 11
  it "answers 405 with Allow for unsupported methods" do
    with_dev_server do |port, _|
      response = dev_client(port, &.post("/"))
      response.status_code.should eq(405)
      response.headers["Allow"].should eq("GET, HEAD, OPTIONS")
    end
  end

  # Finding 10
  it "refuses backslash aliases that a static host would 404" do
    with_dev_server do |port, _|
      response = dev_client(port, &.get("/guide%5Cindex.html"))
      response.status_code.should eq(404)
    end
  end

  # Finding 10: strictness must not cost legitimate unicode routes.
  it "serves unicode routes percent-encoded and raw" do
    with_dev_server do |port, _|
      dev_client(port, &.get("/%ED%95%9C%EA%B8%80/")).body.should contain("HANGUL")
      dev_client(port, &.get("/한글/")).body.should contain("HANGUL")
    end
  end

  # Finding 8
  it "percent-encodes the trailing-slash redirect Location" do
    with_dev_server do |port, _|
      response = dev_client(port, &.get("/%ED%95%9C%EA%B8%80"))
      response.status_code.should eq(302)
      response.headers["Location"].should eq("/%ED%95%9C%EA%B8%80/")
      response.headers["Location"].each_char.all?(&.ascii?).should be_true
    end
  end

  # Finding 7
  it "applies custom headers and no-store to the CORS preflight" do
    headers = {"X-Guard" => "on"}
    with_dev_server(headers: headers) do |port, _|
      response = dev_client(port) do |client|
        client.options("/", HTTP::Headers{"Origin" => "http://localhost"})
      end

      response.status_code.should eq(204)
      response.headers["X-Guard"].should eq("on")
      response.headers["Cache-Control"].should eq("no-store")
      # The preflight itself must still be a valid one.
      response.headers["Access-Control-Allow-Origin"].should eq("http://localhost")
      response.headers["Access-Control-Allow-Methods"].should eq("GET, HEAD, OPTIONS")
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

  # Finding 5
  describe "with a base_url subpath" do
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

    it "re-prefixes the trailing-slash redirect" do
      with_dev_server(base_path: "/myblog") do |port, _|
        response = dev_client(port, &.get("/myblog/guide"))
        response.status_code.should eq(302)
        response.headers["Location"].should eq("/myblog/guide/")
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
  end

  # Regression guards for behaviour the fixes had to preserve.
  it "still redirects a directory without a trailing slash" do
    with_dev_server do |port, _|
      response = dev_client(port, &.get("/guide"))
      response.status_code.should eq(302)
      response.headers["Location"].should eq("/guide/")
    end
  end

  it "still rejects path traversal" do
    with_dev_server do |port, _|
      ["/../../etc/passwd", "/%2e%2e%2f%2e%2e%2fetc%2fpasswd", "/%2e%2e/%2e%2e/etc/passwd",
       "/....//....//etc/passwd"].each do |path|
        response = dev_client(port, &.get(path))
        response.status_code.should_not eq(200)
        response.body.includes?("root:").should be_false
      end
    end
  end

  # The traversal rule must not swallow ordinary filenames that contain dots.
  it "serves a file whose name contains .. without being all dots" do
    with_dev_server do |port, dir|
      File.write(File.join(dir, "lib.v1..2.js"), "DOTTED_ASSET")
      FileUtils.mkdir_p(File.join(dir, "a..b"))
      File.write(File.join(dir, "a..b", "index.html"), "<html><body>DOTTED_PAGE</body></html>")

      dev_client(port, &.get("/lib.v1..2.js")).body.should contain("DOTTED_ASSET")
      dev_client(port, &.get("/a..b/")).body.should contain("DOTTED_PAGE")
    end
  end

  it "still injects the live-reload script into the 404 page" do
    with_dev_server do |port, _|
      response = dev_client(port, &.get("/missing"))
      response.status_code.should eq(404)
      response.body.should contain("NOT FOUND PAGE")
      response.body.should contain("__hwaro_livereload")
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
