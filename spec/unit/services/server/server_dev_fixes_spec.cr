require "../../../spec_helper"
require "../../../../src/services/server/server"
require "../../../../src/services/server/dev_path"
require "../../../../src/config/options/serve_options"

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
      def dev_fixes_ready_signal_line(host : String, port : Int32, base_path : String = "") : String
        ready_signal_line(host, port, base_path)
      end

      def dev_fixes_ready_signal_json(host : String, port : Int32, base_path : String = "") : String
        ready_signal_json(host, port, base_path)
      end

      def dev_fixes_serve_url(host : String, port : Int32, base_path : String = "") : String
        serve_url(host, port, base_path)
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

      def dev_fixes_base_path_for(base_url : String?) : String
        base_path_for(base_url)
      end

      def dev_fixes_build_handlers(output_dir : String, base_path : String) : Array(HTTP::Handler)
        build_handlers(output_dir, "127.0.0.1", false, true, {} of String => String, base_path)
      end

      def dev_fixes_config_loaded? : Bool
        !@builder.config.nil?
      end

      def dev_fixes_url_openable?(url : String) : Bool
        url_openable?(url)
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

# `register_utf8_mime_types` mutates the process-global MIME table and there
# is no unregister, so without this every later spec in the process would see
# `.txt`/`.json`/… carrying a charset and any future MIME assertion would be
# order-dependent. `MIME.register` overwrites, so anything that already had a
# mapping can be put back exactly.
#
# Whichever extensions the platform's database does NOT already map cannot be
# restored — there is no API to remove a registration — so a little residue is
# unavoidable. Which extensions those are is itself platform-dependent (macOS
# has no `.md`, Linux does), which is precisely why the production rule must
# not branch on it.
private def with_utf8_mime_types(&)
  snapshot = {} of String => String
  Hwaro::Services::Server::UTF8_MIME_TYPES.each_key do |ext|
    if existing = MIME.from_extension?(ext)
      snapshot[ext] = existing
    end
  end

  Hwaro::Services::Server.register_utf8_mime_types
  begin
    yield
  ensure
    snapshot.each { |ext, type| MIME.register(ext, type) }
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

# Models IndexRewriteHandler: sets the header by hand and leaves the response
# open, so BasePathHandler's post-call_next re-prefix can still reach it.
private class ServeFixesRedirector
  include HTTP::Handler

  def initialize(@location : String)
  end

  def call(context)
    context.response.status_code = 302
    context.response.headers["Location"] = @location
  end
end

# Models HTTP::StaticFileHandler: redirects through `Response#redirect`, which
# CLOSES the response and flushes the headers. The suite previously had no
# double of this shape, which is why the whole stdlib-redirect class of bugs
# was structurally invisible to it.
private class ServeFixesClosingRedirector
  include HTTP::Handler

  def initialize(@location : String)
  end

  def call(context)
    context.response.redirect(@location)
    context.response.close
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

    # Review finding 6: the predicates run PCRE2 over raw request bytes, so
    # invalid UTF-8 used to raise ArgumentError straight out of the handler and
    # surface as 500 — for a request a static host answers with 404.
    it "refuses invalid UTF-8 instead of raising" do
      raw = String.new(Bytes[0x2f, 0xc0, 0xae, 0xc0, 0xae, 0x2f, 0x78])
      raw.valid_encoding?.should be_false
      Hwaro::Services::DevPath.safe_relative(raw).should be_nil
      Hwaro::Services::DevPath.unservable?(raw).should be_true

      lone = String.new(Bytes[0x2f, 0xff, 0xfe, 0x2e, 0x68, 0x74, 0x6d, 0x6c])
      Hwaro::Services::DevPath.safe_relative(lone).should be_nil
      Hwaro::Services::DevPath.unservable?(lone).should be_true
    end

    # …including bytes that only become invalid once decoded.
    it "refuses percent-encoded invalid UTF-8" do
      Hwaro::Services::DevPath.safe_relative("/%c0%ae%c0%ae/x.html").should be_nil
      Hwaro::Services::DevPath.safe_relative("/%ff%fe.html").should be_nil
    end

    # Review finding 7: the shared sanitizer rejects dots AND spaces because
    # Windows strips both from a trailing component; the dots-only rule let
    # `".. "` through while claiming parity.
    it "refuses segments of dots and spaces, not just dots" do
      Hwaro::Services::DevPath.safe_relative("/.. /x").should be_nil
      Hwaro::Services::DevPath.safe_relative("/. /x").should be_nil
      Hwaro::Services::DevPath.safe_relative("/x/.. ").should be_nil
      Hwaro::Services::DevPath.safe_relative("/ .. / x").should be_nil
    end

    # …without swallowing ordinary names that merely contain a dot or space.
    it "still resolves names containing dots and spaces" do
      Hwaro::Services::DevPath.safe_relative("/my page/a. b.html").should eq("my page/a. b.html")
      Hwaro::Services::DevPath.safe_relative("/js/lib.v1..2.js").should eq("js/lib.v1..2.js")
    end

    # Finding 5: deleting the NUL made `/index%00.html` resolve to the real
    # homepage while the StaticFileHandler in the same chain 400s a decoded
    # NUL. Fail closed instead of papering over it.
    it "refuses NUL in any form" do
      Hwaro::Services::DevPath.safe_relative("/a#{Char::ZERO}b.html").should be_nil
      Hwaro::Services::DevPath.safe_relative("/index%00.html").should be_nil
      Hwaro::Services::DevPath.safe_relative("/index%00").should be_nil
    end
  end

  # Finding 4: our handlers declining is not enough — StaticFileHandler
  # decodes once too, so these need an explicit 404 upstream of it.
  describe ".unservable?" do
    it "flags encoded separators, backslashes and NUL" do
      %w[/%2Fguide%2Findex.html /%2fguide%2f /guide%5Cindex.html /index%00.html].each do |path|
        Hwaro::Services::DevPath.unservable?(path).should be_true
      end
      Hwaro::Services::DevPath.unservable?("/a\\b").should be_true
      Hwaro::Services::DevPath.unservable?("/a#{Char::ZERO}b").should be_true
    end

    it "leaves ordinary and percent-encoded unicode paths alone" do
      %w[/ /guide/index.html /%ED%95%9C%EA%B8%80/ /my%20page/ /js/lib.v1..2.js].each do |path|
        Hwaro::Services::DevPath.unservable?(path).should be_false
      end
      # `..` is normalisation, not smuggling — stdlib canonicalises it and so
      # does production; it must not be turned into a 404 here.
      Hwaro::Services::DevPath.unservable?("/guide/../index.html").should be_false
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

  # S7: a non-canonical path (`//`, `/./` segments) must not be served with
  # a 200 — StaticFileHandler (and the base-path mount) answer it with a
  # canonicalising 302, so the injector defers instead of short-circuiting.
  it "defers non-canonical paths to the next handler" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "guide"))
      File.write(File.join(dir, "guide", "index.html"), "<html><body>g</body></html>")
      handler = Hwaro::Services::LiveReloadInjectHandler.new(dir)

      ["/guide//index.html", "/./guide/index.html", "/guide/./index.html"].each do |path|
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

  # S7: chained with the real static handler, the deferral becomes the same
  # canonicalising redirect production hosts issue — while the canonical
  # path keeps its 200 + injection.
  it "redirects non-canonical paths when chained with the static handler" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "guide"))
      File.write(File.join(dir, "guide", "index.html"), "<html><body>g</body></html>")
      handler = Hwaro::Services::LiveReloadInjectHandler.new(dir)
      handler.next = HTTP::StaticFileHandler.new(dir, directory_listing: false, fallthrough: true)

      context, response, _ = build_context("GET", "/guide//index.html")
      handler.call(context)
      response.close
      context.response.status_code.should eq(302)
      context.response.headers["Location"].should eq("/guide/index.html")

      ok_context, ok_response, ok_io = build_context("GET", "/guide/index.html")
      handler.call(ok_context)
      ok_response.close
      ok_context.response.status_code.should eq(200)
      ok_io.to_s.should contain("__hwaro_livereload")
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

  # Review finding 2 / test-shape: a closed response cannot be re-prefixed
  # after the fact, which is precisely why BasePathHandler pre-empts stdlib's
  # canonicalising redirect instead of trying to patch it up afterwards. This
  # pins the constraint so nobody "simplifies" the pre-empt away.
  it "cannot re-prefix a redirect from a handler that closed the response" do
    handler = Hwaro::Services::BasePathHandler.new("/myblog")
    handler.next = ServeFixesClosingRedirector.new("/posts/")

    context, response, io = build_context("GET", "/myblog/posts")
    handler.call(context)
    response.close

    # The header on the wire is the un-prefixed one the double wrote.
    io.to_s.should contain("Location: /posts/")
    io.to_s.should_not contain("Location: /myblog/posts/")
  end

  # Finding 12: the documented "no trailing slash" contract is now enforced,
  # so a caller passing "/myblog/" behaves identically to "/myblog".
  it "normalises a base path given with a trailing slash" do
    handler = Hwaro::Services::BasePathHandler.new("/myblog/")
    spy = ServeFixesSpy.new
    handler.next = spy

    context, response, _ = build_context("GET", "/myblog/posts/")
    handler.call(context)
    response.close

    spy.seen_path.should eq("/posts/")

    redirect_context, redirect_response, _ = build_context("GET", "/")
    handler.call(redirect_context)
    redirect_response.close
    redirect_context.response.headers["Location"].should eq("/myblog/")
  end

  # Finding 9: LogHandler is outermost and reads request.resource AFTER
  # call_next, so a stripped path made --access-log report the wrong URL.
  it "restores the original request path after the chain runs" do
    handler = Hwaro::Services::BasePathHandler.new("/myblog")
    spy = ServeFixesSpy.new
    handler.next = spy

    context, response, _ = build_context("GET", "/myblog/posts/")
    handler.call(context)
    response.close

    spy.seen_path.should eq("/posts/")
    context.request.path.should eq("/myblog/posts/")
    context.request.resource.should eq("/myblog/posts/")
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

    # Review finding 10: RFC 6874 requires the zone-id separator to be
    # percent-encoded inside a URI.
    it "percent-encodes an IPv6 zone id" do
      Hwaro::Config::Options::ServeOptions.url_host("fe80::1%en0").should eq("[fe80::1%25en0]")
    end

    it "does not double-encode an already-encoded zone id" do
      Hwaro::Config::Options::ServeOptions.url_host("fe80::1%25en0").should eq("[fe80::1%25en0]")
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

  # Review finding 8: the receipt included the mount point and the machine
  # line did not, so a script blocking on the ready line fetched the bare
  # origin and got a 302 it may not follow.
  describe "#serve_url" do
    it "is the single source of truth for the receipt and both ready signals" do
      server = Hwaro::Services::Server.new
      url = server.dev_fixes_serve_url("127.0.0.1", 3000, "/myblog")
      url.should eq("http://127.0.0.1:3000/myblog/")

      server.dev_fixes_ready_signal_line("127.0.0.1", 3000, "/myblog")
        .should eq("hwaro serve: ready url=#{url} pid=#{Process.pid}")
      JSON.parse(server.dev_fixes_ready_signal_json("127.0.0.1", 3000, "/myblog"))["url"]
        .as_s.should eq(url)
    end

    it "leaves the bare origin untouched without a mount point" do
      server = Hwaro::Services::Server.new
      server.dev_fixes_serve_url("127.0.0.1", 3000).should eq("http://127.0.0.1:3000")
      server.dev_fixes_ready_signal_line("127.0.0.1", 3000)
        .should eq("hwaro serve: ready url=http://127.0.0.1:3000 pid=#{Process.pid}")
    end
  end

  # Finding 1: the mount point must not depend on a config load that can fail.
  describe "#base_path_for" do
    it "derives the mount point from the effective base_url" do
      server = Hwaro::Services::Server.new
      server.dev_fixes_base_path_for("http://127.0.0.1:3000/myblog/").should eq("/myblog")
      server.dev_fixes_base_path_for("http://127.0.0.1:3000/a/b/").should eq("/a/b")
    end

    it "yields an empty prefix for a domain-root or missing base_url" do
      server = Hwaro::Services::Server.new
      server.dev_fixes_base_path_for("http://127.0.0.1:3000").should eq("")
      server.dev_fixes_base_path_for("http://127.0.0.1:3000/").should eq("")
      server.dev_fixes_base_path_for(nil).should eq("")
      server.dev_fixes_base_path_for("::::").should eq("")
    end

    # The regression itself: a server whose startup build never loaded a
    # config (broken config.toml) still has to mount the subpath, and the
    # chain is assembled exactly once so a later good rebuild cannot fix it.
    it "still installs BasePathHandler when no config was ever loaded" do
      Dir.mktmpdir do |dir|
        server = Hwaro::Services::Server.new
        server.dev_fixes_config_loaded?.should be_false

        base_path = server.dev_fixes_base_path_for("http://127.0.0.1:3000/myblog/")
        base_path.should eq("/myblog")
        handlers = server.dev_fixes_build_handlers(dir, base_path)
        handlers.any?(Hwaro::Services::BasePathHandler).should be_true
      end
    end

    it "installs no BasePathHandler for a domain-root base_url" do
      Dir.mktmpdir do |dir|
        server = Hwaro::Services::Server.new
        handlers = server.dev_fixes_build_handlers(dir, server.dev_fixes_base_path_for("http://127.0.0.1:3000"))
        handlers.any?(Hwaro::Services::BasePathHandler).should be_false
      end
    end
  end

  # S4: the --open allowlist must accept serve's own URL shapes — a
  # bracketed IPv6 bind (`-b ::1`) and percent-encoded base paths — while
  # still refusing shell metacharacters and non-http schemes.
  describe "#url_openable?" do
    it "accepts bracketed IPv6 hosts and percent-encoded paths" do
      server = Hwaro::Services::Server.new
      server.dev_fixes_url_openable?("http://[::1]:3000").should be_true
      server.dev_fixes_url_openable?("http://[fe80::1]:8080/blog/").should be_true
      server.dev_fixes_url_openable?("http://127.0.0.1:3000/my%20blog/").should be_true
      server.dev_fixes_url_openable?("http://127.0.0.1:3000").should be_true
    end

    it "still refuses shell metacharacters and non-http schemes" do
      server = Hwaro::Services::Server.new
      server.dev_fixes_url_openable?("http://localhost:3000/$(touch pwned)").should be_false
      server.dev_fixes_url_openable?("http://localhost:3000/a;b").should be_false
      server.dev_fixes_url_openable?("http://localhost:3000/`id`").should be_false
      server.dev_fixes_url_openable?("file:///etc/passwd").should be_false
      server.dev_fixes_url_openable?("ftp://example.com").should be_false
    end
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

    # Crinja quotes the offending source lines, so a syntax error next to one
    # very long line produced a multi-megabyte message that was pushed over the
    # live-reload socket on every save (and printed to the terminal, which grew
    # a serve log to 12 MB with no client attached at all).
    it "caps a runaway build-error payload" do
      handler = RecordingLiveReloadHandler.new
      message = "Template error: #{"x" * 3_000_000}"
      Hwaro::Services::Server.new.dev_fixes_push_build_error(message, true, handler)

      pushed = handler.errors.first
      pushed.size.should be <= Hwaro::Services::Server::MAX_BUILD_ERROR_CHARS + 64
      # The head of the message — the part that names the error — survives.
      pushed.should start_with("Template error: ")
      pushed.should contain("truncated")
    end

    it "leaves a normal-sized message byte-identical" do
      handler = RecordingLiveReloadHandler.new
      Hwaro::Services::Server.new.dev_fixes_push_build_error("Template error: unterminated tag", true, handler)
      handler.errors.should eq(["Template error: unterminated tag"])
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
      with_utf8_mime_types do
        {".txt", ".json", ".xml", ".svg"}.each do |ext|
          MIME.from_extension(ext).should contain("charset=utf-8")
        end
      end
    end

    it "is idempotent and never double-appends a charset" do
      with_utf8_mime_types do
        first = Hwaro::Services::Server::UTF8_MIME_TYPES.keys.map { |ext| MIME.from_extension(ext) }
        Hwaro::Services::Server.register_utf8_mime_types
        Hwaro::Services::Server.register_utf8_mime_types
        second = Hwaro::Services::Server::UTF8_MIME_TYPES.keys.map { |ext| MIME.from_extension(ext) }

        second.should eq(first)
        second.each(&.scan("charset=").size.should(eq(1)))
      end
    end

    # Review finding 13: the registration is process-global and irreversible,
    # so a spec that leaves it applied makes every later MIME assertion in the
    # process order-dependent. The guard restores what it can.
    it "does not leak the charset into later specs" do
      before = MIME.from_extension(".txt")
      with_utf8_mime_types do
        MIME.from_extension(".txt").should contain("charset=utf-8")
      end
      MIME.from_extension(".txt").should eq(before)
    end

    # Finding 3: HTML is the site's primary content type and was missing, so
    # a large page — exactly the case the charset fix exists for — still lost
    # its encoding.
    # Asserted as a property, not a literal: the base type comes from the
    # platform's MIME database, so `should eq("text/html; charset=utf-8")`
    # is a spec that can pass on one OS and fail on another.
    it "covers HTML" do
      with_utf8_mime_types do
        {".html", ".htm"}.each do |ext|
          type = MIME.from_extension(ext)
          type.should contain("charset=utf-8")
          type.should contain("html")
        end
      end
    end

    # The CI regression: the old rule only registered these when stdlib had NO
    # mapping, which is true on macOS and false on Linux — so on Linux they
    # came back as a bare `text/markdown`, with no charset at all. Every
    # extension must end up with one on every platform, whatever the local
    # database happens to know.
    it "ensures a charset for every listed extension on any platform" do
      with_utf8_mime_types do
        Hwaro::Services::Server::UTF8_MIME_TYPES.each_key do |ext|
          type = MIME.from_extension(ext)
          type.should contain("charset=utf-8")
          type.should_not contain("octet-stream")
        end
      end
    end

    # The CI failure, reproduced on ANY platform by simulating the condition
    # instead of depending on it: Linux's /etc/mime.types maps `.md`, macOS's
    # /etc/apache2/mime.types does not. The old rule only registered the
    # fallback extensions when stdlib had NO mapping, so this pre-registration
    # is enough to make it emit a bare `text/markdown` with no charset.
    it "ensures a charset even when the platform database already maps the extension" do
      original = MIME.from_extension?(".md")
      MIME.register(".md", "text/markdown")
      begin
        Hwaro::Services::Server.register_utf8_mime_types
        MIME.from_extension(".md").should eq("text/markdown; charset=utf-8")
      ensure
        MIME.register(".md", original) if original
      end
    end

    # Whether the platform maps an extension must not change the outcome, only
    # which base the charset is appended to.
    it "appends to the platform base type without overriding it" do
      before = {} of String => String?
      Hwaro::Services::Server::UTF8_MIME_TYPES.each_key { |ext| before[ext] = MIME.from_extension?(ext) }

      with_utf8_mime_types do
        Hwaro::Services::Server::UTF8_MIME_TYPES.each do |ext, assumed|
          type = MIME.from_extension(ext)
          expected_base = before[ext] || assumed
          next if expected_base.includes?("charset=")
          type.should eq("#{expected_base}; charset=utf-8")
        end
      end
    end

    it "leaves binary types alone" do
      with_utf8_mime_types do
        MIME.from_extension(".png").includes?("charset=").should be_false
      end
    end
  end
end
