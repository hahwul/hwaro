require "../spec_helper"
require "../../src/services/server/server"
require "../../src/services/server/dev_path"
require "../../src/config/options/serve_options"

# Regression coverage for the `hwaro serve` defect sweep.
#
# Handler-level tests live here; the ones that only reproduce over a real
# socket (HEAD framing, response sizes past the output buffer, subpath
# mounting) live in spec/functional/serve_http_regression_spec.cr.

# Reopened to reach the protected ready-signal builders. Names are prefixed so
# they can't collide with the shims spec/unit/server_spec.cr installs.
module Hwaro
  module Services
    class Server
      def dev_fixes_ready_signal_line(host : String, port : Int32) : String
        ready_signal_line(host, port)
      end

      def dev_fixes_ready_signal_json(host : String, port : Int32) : String
        ready_signal_json(host, port)
      end

      def dev_fixes_push_build_error(message : String, overlay : Bool, handler : LiveReloadHandler)
        @error_overlay = overlay
        @live_reload_handler = handler
        push_build_error(message)
      end

      def dev_fixes_effective_strategy(changeset : ChangeSet, output_dir : String, failed : Bool = false) : Symbol
        @rebuild_failed = failed
        effective_strategy(changeset, output_dir)
      end
    end
  end
end

# Records the pushes the server makes instead of touching a socket.
private class RecordingLiveReloadHandler < Hwaro::Services::LiveReloadHandler
  getter errors = [] of String

  def notify_build_error(message : String)
    @errors << message
  end
end

private def content_changeset : Hwaro::Services::ChangeSet
  Hwaro::Services::ChangeSet.new(
    modified_content: ["content/about.md"],
    modified_templates: [] of String,
    modified_static: [] of String,
    added_files: [] of String,
    removed_files: [] of String,
    config_changed: false,
  )
end

private def build_context(method : String, path : String, headers = HTTP::Headers.new)
  request = HTTP::Request.new(method, path, headers)
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  {HTTP::Server::Context.new(request, response), response, io}
end

private class ServeFixesSpy
  include HTTP::Handler

  property called : Bool = false
  property seen_path : String? = nil

  def call(context)
    @called = true
    @seen_path = context.request.path
  end
end

private class ServeFixesRedirector
  include HTTP::Handler

  def initialize(@location : String)
  end

  def call(context)
    context.response.status_code = 302
    context.response.headers["Location"] = @location
  end
end

describe Hwaro::Services::DevPath do
  describe ".safe_relative" do
    it "resolves ordinary paths" do
      Hwaro::Services::DevPath.safe_relative("/posts/hello/index.html").should eq("posts/hello/index.html")
    end

    it "returns an empty string for the output root" do
      Hwaro::Services::DevPath.safe_relative("/").should eq("")
    end

    # Finding 10: encoded separators must not smuggle a path past the router.
    it "refuses backslashes and encoded separators" do
      Hwaro::Services::DevPath.safe_relative("/posts%5Chello.html").should be_nil
      Hwaro::Services::DevPath.safe_relative("/posts\\hello.html").should be_nil
      Hwaro::Services::DevPath.safe_relative("/%2Fposts%2Fhello.html").should be_nil
      Hwaro::Services::DevPath.safe_relative("/%2fposts%2fhello.html").should be_nil
    end

    # Finding 10: a single decode pass means double-encoded separators stay
    # literal inside one segment instead of becoming separators.
    it "decodes exactly once" do
      Hwaro::Services::DevPath.safe_relative("/%252Fposts%252Fhello.html")
        .should eq("%2Fposts%2Fhello.html")
    end

    # Finding 10: legitimate percent-encoded unicode must keep working.
    it "resolves unicode paths in raw and percent-encoded form" do
      Hwaro::Services::DevPath.safe_relative("/%ED%95%9C%EA%B8%80/index.html")
        .should eq("한글/index.html")
      Hwaro::Services::DevPath.safe_relative("/한글/index.html")
        .should eq("한글/index.html")
      Hwaro::Services::DevPath.safe_relative("/my%20page/index.html")
        .should eq("my page/index.html")
    end

    it "rejects traversal in every encoding" do
      Hwaro::Services::DevPath.safe_relative("/../../etc/passwd").should be_nil
      Hwaro::Services::DevPath.safe_relative("/%2e%2e/%2e%2e/etc/passwd").should be_nil
      Hwaro::Services::DevPath.safe_relative("/%2E%2E/etc/passwd").should be_nil
      Hwaro::Services::DevPath.safe_relative("/a/../../etc/passwd").should be_nil
      # Encoded separators are refused outright, so the classic
      # `%2e%2e%2f` chain never even reaches the segment check.
      Hwaro::Services::DevPath.safe_relative("/%2e%2e%2f%2e%2e%2fetc%2fpasswd").should be_nil
      # Windows strips trailing dots from a component, so `...`/`....` are
      # refused alongside `..`.
      Hwaro::Services::DevPath.safe_relative("/....//....//etc/passwd").should be_nil
      Hwaro::Services::DevPath.safe_relative("/.../x").should be_nil
      # Backslash separators are refused before any of the above applies.
      Hwaro::Services::DevPath.safe_relative("/..\\..\\etc\\passwd").should be_nil
      Hwaro::Services::DevPath.safe_relative("/%5c..%5c..%5cetc").should be_nil
    end

    # A segment that merely CONTAINS ".." is an ordinary filename; 404ing it
    # would be the same dev/prod divergence in the other direction.
    it "resolves filenames that contain dots without being all dots" do
      Hwaro::Services::DevPath.safe_relative("/js/lib.v1..2.js").should eq("js/lib.v1..2.js")
      Hwaro::Services::DevPath.safe_relative("/a..b/index.html").should eq("a..b/index.html")
      Hwaro::Services::DevPath.safe_relative("/..leading/index.html").should eq("..leading/index.html")
      Hwaro::Services::DevPath.safe_relative("/trailing../index.html").should eq("trailing../index.html")
    end

    it "strips NUL bytes" do
      Hwaro::Services::DevPath.safe_relative("/a#{Char::ZERO}b.html").should eq("ab.html")
    end
  end

  describe ".encode_relative" do
    # Finding 8: a Location built from decoded bytes is not a valid URI.
    it "percent-encodes spaces and non-ASCII per segment" do
      Hwaro::Services::DevPath.encode_relative("my page").should eq("my%20page")
      Hwaro::Services::DevPath.encode_relative("한글").should eq("%ED%95%9C%EA%B8%80")
      Hwaro::Services::DevPath.encode_relative("a/b c").should eq("a/b%20c")
    end

    it "leaves plain segments untouched" do
      Hwaro::Services::DevPath.encode_relative("posts/hello").should eq("posts/hello")
    end
  end
end

describe Hwaro::Services::IndexRewriteHandler do
  # Finding 8
  it "percent-encodes the directory redirect Location" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "my page"))
      handler = Hwaro::Services::IndexRewriteHandler.new(dir)
      handler.next = ServeFixesSpy.new

      context, response, _ = build_context("GET", "/my%20page")
      handler.call(context)
      response.close

      context.response.status_code.should eq(302)
      context.response.headers["Location"].should eq("/my%20page/")
    end
  end

  it "percent-encodes a unicode directory redirect Location" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "한글"))
      handler = Hwaro::Services::IndexRewriteHandler.new(dir)
      handler.next = ServeFixesSpy.new

      context, response, _ = build_context("GET", "/%ED%95%9C%EA%B8%80")
      handler.call(context)
      response.close

      context.response.status_code.should eq(302)
      context.response.headers["Location"].should eq("/%ED%95%9C%EA%B8%80/")
    end
  end

  # Finding 9: a path that resolves to nothing must not become `Location: //`.
  it "does not redirect when the resolved path is empty" do
    Dir.mktmpdir do |dir|
      handler = Hwaro::Services::IndexRewriteHandler.new(dir)
      spy = ServeFixesSpy.new
      handler.next = spy

      context, response, _ = build_context("GET", "/#{Char::ZERO}")
      handler.call(context)
      response.close

      spy.called.should be_true
      context.response.headers["Location"]?.should be_nil
    end
  end

  # Finding 10
  it "passes encoded-separator paths through untouched" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "guide"))
      handler = Hwaro::Services::IndexRewriteHandler.new(dir)
      spy = ServeFixesSpy.new
      handler.next = spy

      context, response, _ = build_context("GET", "/%2Fguide")
      handler.call(context)
      response.close

      spy.called.should be_true
      context.response.headers["Location"]?.should be_nil
    end
  end

  it "still preserves the query string on a directory redirect" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "search"))
      handler = Hwaro::Services::IndexRewriteHandler.new(dir)
      handler.next = ServeFixesSpy.new

      context, response, _ = build_context("GET", "/search?q=term")
      handler.call(context)
      response.close

      context.response.headers["Location"].should eq("/search/?q=term")
    end
  end
end

describe Hwaro::Services::NotFoundHandler do
  # Finding 1
  it "sends no body on HEAD but keeps the GET Content-Length" do
    Dir.mktmpdir do |dir|
      body = "<html><body>not found</body></html>"
      File.write(File.join(dir, "404.html"), body)
      handler = Hwaro::Services::NotFoundHandler.new(dir)

      head_context, head_response, head_io = build_context("HEAD", "/missing")
      handler.call(head_context)
      head_response.close

      get_context, get_response, get_io = build_context("GET", "/missing")
      handler.call(get_context)
      get_response.close

      head_context.response.status_code.should eq(404)
      head_io.to_s.includes?(body).should be_false
      get_io.to_s.includes?(body).should be_true
      head_io.to_s.should contain("Content-Length: #{body.bytesize}")
      get_io.to_s.should contain("Content-Length: #{body.bytesize}")
    end
  end

  # Finding 11
  it "answers 405 with an Allow header for unsupported methods" do
    Dir.mktmpdir do |dir|
      handler = Hwaro::Services::NotFoundHandler.new(dir)

      context, response, io = build_context("POST", "/")
      handler.call(context)
      response.close

      context.response.status_code.should eq(405)
      context.response.headers["Allow"].should eq("GET, HEAD, OPTIONS")
      io.to_s.should contain("405 Method Not Allowed")
    end
  end

  it "still answers 404 for GET" do
    Dir.mktmpdir do |dir|
      handler = Hwaro::Services::NotFoundHandler.new(dir)

      context, response, _ = build_context("GET", "/missing")
      handler.call(context)
      response.close

      context.response.status_code.should eq(404)
    end
  end
end

describe Hwaro::Services::LiveReloadInjectHandler do
  # Finding 6
  it "answers HEAD with the injected length and no body" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "index.html"), "<html><body>hi</body></html>")
      handler = Hwaro::Services::LiveReloadInjectHandler.new(dir)
      handler.next = ServeFixesSpy.new

      head_context, head_response, head_io = build_context("HEAD", "/index.html")
      handler.call(head_context)
      head_response.close

      get_context, get_response, get_io = build_context("GET", "/index.html")
      handler.call(get_context)
      get_response.close

      injected_size = handler.inject_script(File.read(File.join(dir, "index.html"))).bytesize
      head_io.to_s.should contain("Content-Length: #{injected_size}")
      get_io.to_s.should contain("Content-Length: #{injected_size}")
      head_io.to_s.includes?("__hwaro_livereload").should be_false
      get_io.to_s.includes?("__hwaro_livereload").should be_true
    end
  end

  # Finding 10
  it "refuses encoded-separator and backslash aliases" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "guide"))
      File.write(File.join(dir, "guide", "index.html"), "<html><body>g</body></html>")
      handler = Hwaro::Services::LiveReloadInjectHandler.new(dir)

      ["/guide%5Cindex.html", "/%2Fguide%2Findex.html", "/%252Fguide%252Findex.html"].each do |path|
        spy = ServeFixesSpy.new
        handler.next = spy
        context, response, io = build_context("GET", path)
        handler.call(context)
        response.close

        spy.called.should be_true
        io.to_s.includes?("__hwaro_livereload").should be_false
      end
    end
  end

  # Finding 10: the strictness must not cost unicode routes.
  it "still serves percent-encoded and raw unicode paths" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "한글"))
      File.write(File.join(dir, "한글", "index.html"), "<html><body>HANGUL</body></html>")
      handler = Hwaro::Services::LiveReloadInjectHandler.new(dir)
      handler.next = ServeFixesSpy.new

      ["/%ED%95%9C%EA%B8%80/index.html", "/한글/index.html"].each do |path|
        context, response, io = build_context("GET", path)
        handler.call(context)
        response.close
        io.to_s.should contain("HANGUL")
        io.to_s.should contain("__hwaro_livereload")
      end
    end
  end
end

describe Hwaro::Services::BasePathHandler do
  # Finding 5
  it "is a no-op when the base path is empty" do
    handler = Hwaro::Services::BasePathHandler.new("")
    spy = ServeFixesSpy.new
    handler.next = spy

    context, response, _ = build_context("GET", "/posts/")
    handler.call(context)
    response.close

    spy.seen_path.should eq("/posts/")
    context.response.headers["Location"]?.should be_nil
  end

  it "strips the prefix from a prefixed request" do
    handler = Hwaro::Services::BasePathHandler.new("/myblog")
    spy = ServeFixesSpy.new
    handler.next = spy

    context, response, _ = build_context("GET", "/myblog/posts/")
    handler.call(context)
    response.close

    spy.seen_path.should eq("/posts/")
  end

  it "redirects the bare root to the mount point" do
    handler = Hwaro::Services::BasePathHandler.new("/myblog")
    handler.next = ServeFixesSpy.new

    context, response, _ = build_context("GET", "/")
    handler.call(context)
    response.close

    context.response.status_code.should eq(302)
    context.response.headers["Location"].should eq("/myblog/")
  end

  it "redirects the unslashed mount point and keeps the query" do
    handler = Hwaro::Services::BasePathHandler.new("/myblog")
    handler.next = ServeFixesSpy.new

    context, response, _ = build_context("GET", "/myblog?q=1")
    handler.call(context)
    response.close

    context.response.status_code.should eq(302)
    context.response.headers["Location"].should eq("/myblog/?q=1")
  end

  it "re-prefixes a downstream redirect whenever the prefix was stripped" do
    handler = Hwaro::Services::BasePathHandler.new("/myblog")
    handler.next = ServeFixesRedirector.new("/posts/")

    context, response, _ = build_context("GET", "/myblog/posts")
    handler.call(context)
    response.close

    context.response.headers["Location"].should eq("/myblog/posts/")
  end

  # A site with a top-level section named after the mount point produces a
  # downstream Location that *looks* already-prefixed but is in stripped
  # space. Deciding from the request we rewrote, not from the string, keeps
  # the mount point on it.
  it "re-prefixes a redirect that collides with the mount point name" do
    handler = Hwaro::Services::BasePathHandler.new("/myblog")
    handler.next = ServeFixesRedirector.new("/myblog/")

    context, response, _ = build_context("GET", "/myblog/myblog")
    handler.call(context)
    response.close

    context.response.headers["Location"].should eq("/myblog/myblog/")
  end

  it "leaves a redirect from an unprefixed pass-through request unprefixed" do
    handler = Hwaro::Services::BasePathHandler.new("/myblog")
    handler.next = ServeFixesRedirector.new("/guide/")

    context, response, _ = build_context("GET", "/guide")
    handler.call(context)
    response.close

    context.response.headers["Location"].should eq("/guide/")
  end

  it "leaves a protocol-relative redirect alone" do
    handler = Hwaro::Services::BasePathHandler.new("/myblog")
    handler.next = ServeFixesRedirector.new("//cdn.example.com/x")

    context, response, _ = build_context("GET", "/myblog/posts")
    handler.call(context)
    response.close

    context.response.headers["Location"].should eq("//cdn.example.com/x")
  end

  it "passes an unprefixed asset request through instead of 404ing it" do
    handler = Hwaro::Services::BasePathHandler.new("/myblog")
    spy = ServeFixesSpy.new
    handler.next = spy

    context, response, _ = build_context("GET", "/css/style.css")
    handler.call(context)
    response.close

    spy.seen_path.should eq("/css/style.css")
    context.response.headers["Location"]?.should be_nil
  end

  it "leaves the live-reload endpoint unprefixed" do
    handler = Hwaro::Services::BasePathHandler.new("/myblog")
    spy = ServeFixesSpy.new
    handler.next = spy

    context, response, _ = build_context("GET", "/__hwaro_livereload")
    handler.call(context)
    response.close

    spy.seen_path.should eq("/__hwaro_livereload")
  end
end

describe Hwaro::Config::Options::ServeOptions do
  # Finding 3
  describe ".url_host" do
    it "brackets IPv6 literals" do
      Hwaro::Config::Options::ServeOptions.url_host("::1").should eq("[::1]")
      Hwaro::Config::Options::ServeOptions.url_host("fe80::1").should eq("[fe80::1]")
    end

    it "leaves IPv4 and hostnames alone" do
      Hwaro::Config::Options::ServeOptions.url_host("127.0.0.1").should eq("127.0.0.1")
      Hwaro::Config::Options::ServeOptions.url_host("0.0.0.0").should eq("0.0.0.0")
      Hwaro::Config::Options::ServeOptions.url_host("localhost").should eq("localhost")
    end

    it "does not double-bracket" do
      Hwaro::Config::Options::ServeOptions.url_host("[::1]").should eq("[::1]")
    end
  end

  it "derives a bracketed base_url for an IPv6 bind" do
    options = Hwaro::Config::Options::ServeOptions.new(host: "::1", port: 8080)
    options.to_build_options.base_url.should eq("http://[::1]:8080")
  end

  it "leaves an explicit --base-url untouched" do
    options = Hwaro::Config::Options::ServeOptions.new(host: "::1", port: 8080, base_url: "https://example.com")
    options.to_build_options.base_url.should eq("https://example.com")
  end
end

describe Hwaro::Services::Server do
  # Finding 3
  it "brackets IPv6 hosts in both ready signals" do
    server = Hwaro::Services::Server.new
    server.dev_fixes_ready_signal_line("::1", 3000).should contain("url=http://[::1]:3000")

    parsed = JSON.parse(server.dev_fixes_ready_signal_json("::1", 3000))
    parsed["url"].as_s.should eq("http://[::1]:3000")
    # The `host` field stays the literal address — it is not a URL.
    parsed["host"].as_s.should eq("::1")
  end

  # Finding 4
  describe "#push_build_error" do
    it "pushes the overlay by default" do
      handler = RecordingLiveReloadHandler.new
      Hwaro::Services::Server.new.dev_fixes_push_build_error("boom", true, handler)
      handler.errors.should eq(["boom"])
    end

    it "stays silent under --no-error-overlay" do
      handler = RecordingLiveReloadHandler.new
      Hwaro::Services::Server.new.dev_fixes_push_build_error("boom", false, handler)
      handler.errors.should be_empty
    end
  end

  # Finding 12
  describe "#effective_strategy" do
    it "keeps the cheap strategy when the output root exists" do
      Dir.mktmpdir do |dir|
        Hwaro::Services::Server.new
          .dev_fixes_effective_strategy(content_changeset, dir)
          .should eq(:incremental)
      end
    end

    it "escalates to a full rebuild when the output root vanished" do
      missing = File.join(Dir.tempdir, "hwaro-serve-missing-#{Process.pid}")
      FileUtils.rm_rf(missing)
      Hwaro::Services::Server.new
        .dev_fixes_effective_strategy(content_changeset, missing)
        .should eq(:full)
    end

    it "still escalates after a previous failure" do
      Dir.mktmpdir do |dir|
        Hwaro::Services::Server.new
          .dev_fixes_effective_strategy(content_changeset, dir, failed: true)
          .should eq(:full)
      end
    end
  end

  # Finding 2
  describe ".register_utf8_mime_types" do
    it "teaches the MIME table a UTF-8 charset for text extensions" do
      Hwaro::Services::Server.register_utf8_mime_types
      MIME.from_extension(".txt").should contain("charset=utf-8")
      MIME.from_extension(".json").should contain("charset=utf-8")
      MIME.from_extension(".xml").should contain("charset=utf-8")
      MIME.from_extension(".svg").should contain("charset=utf-8")
    end

    it "keeps the stdlib base type and is idempotent" do
      Hwaro::Services::Server.register_utf8_mime_types
      Hwaro::Services::Server.register_utf8_mime_types
      MIME.from_extension(".txt").should eq("text/plain; charset=utf-8")
      MIME.from_extension(".json").should eq("application/json; charset=utf-8")
    end

    it "leaves binary types alone" do
      Hwaro::Services::Server.register_utf8_mime_types
      MIME.from_extension(".png").includes?("charset=").should be_false
    end
  end
end
