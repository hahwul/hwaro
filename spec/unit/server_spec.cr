require "../spec_helper"
require "../../src/services/server/server"
require "../../src/services/server/live_reload_handler"
require "../../src/core/build/builder"
require "../../src/content/hooks"

# Reopen Server to test private methods
module Hwaro
  module Services
    class Server
      def test_sanitize_output_dir(dir : String)
        sanitize_output_dir(dir)
      end

      def test_ready_signal_line(host : String, port : Int32) : String
        ready_signal_line(host, port)
      end

      def test_ready_signal_json(host : String, port : Int32) : String
        ready_signal_json(host, port)
      end

      def test_run_with_options(host, port, open_browser, access_log, live_reload, build_options, json_output)
        run_with_options(host, port, open_browser, access_log, live_reload, build_options, json_output)
      end

      def test_scan_mtimes
        scan_mtimes
      end

      def self.test_watcher_ignored?(path : String) : Bool
        watcher_ignored?(path)
      end

      def test_remove_stale_outputs(paths : Array(String), output_dir : String)
        remove_stale_outputs(paths, output_dir)
      end
    end
  end
end

# Reopen Builder to test private inject_error_overlay method, and to seed
# @site/@config/@cache for stale_outputs_for_removed's [outputs] fallbacks.
module Hwaro
  module Core
    module Build
      class Builder
        def test_inject_error_overlay(html : String, warnings : Array(String)) : String
          inject_error_overlay(html, warnings)
        end

        def test_set_site(site : Models::Site)
          @site = site
        end

        def test_set_config(config : Models::Config)
          @config = config
        end

        def test_set_cache(cache : Cache)
          @cache = cache
        end
      end
    end
  end
end

class DummyHandler
  include HTTP::Handler

  property called : Bool = false

  def call(context)
    @called = true
  end
end

# Downstream handler that writes a fixed Content-Type so post-processing
# handlers (CharsetHandler, CustomHeadersHandler) can be exercised against a
# realistic response. When @content_type is nil it sets no Content-Type at all.
class ContentTypeHandler
  include HTTP::Handler

  property called : Bool = false

  def initialize(@content_type : String?)
  end

  def call(context)
    @called = true
    if ct = @content_type
      context.response.headers["Content-Type"] = ct
    end
  end
end

describe Hwaro::Services::Server do
  describe "#sanitize_output_dir" do
    it "normalizes clean relative paths" do
      server = Hwaro::Services::Server.new
      server.test_sanitize_output_dir("foo/bar").should eq("foo/bar")
      server.test_sanitize_output_dir("./baz").should eq("baz")
    end

    it "defaults to 'public' for paths starting with .." do
      server = Hwaro::Services::Server.new
      server.test_sanitize_output_dir("../foo").should eq("public")
    end

    it "defaults to 'public' for absolute paths" do
      server = Hwaro::Services::Server.new
      server.test_sanitize_output_dir("/foo").should eq("public")
    end
  end

  describe "#ready_signal_line" do
    it "formats a single deterministic ready line with url and pid" do
      server = Hwaro::Services::Server.new
      line = server.test_ready_signal_line("127.0.0.1", 3000)
      line.should eq("hwaro serve: ready url=http://127.0.0.1:3000 pid=#{Process.pid}")
    end

    it "is a single line (no embedded newlines)" do
      server = Hwaro::Services::Server.new
      line = server.test_ready_signal_line("127.0.0.1", 4567)
      line.includes?('\n').should be_false
    end

    it "contains no ANSI color escape codes" do
      server = Hwaro::Services::Server.new
      line = server.test_ready_signal_line("0.0.0.0", 8080)
      line.includes?('\e').should be_false
    end

    it "reflects the requested host and port" do
      server = Hwaro::Services::Server.new
      line = server.test_ready_signal_line("0.0.0.0", 8080)
      line.should contain("url=http://0.0.0.0:8080")
    end
  end

  describe "#ready_signal_json" do
    it "emits the documented {event,url,host,port,pid} schema" do
      server = Hwaro::Services::Server.new
      parsed = JSON.parse(server.test_ready_signal_json("127.0.0.1", 3000))
      parsed["event"].as_s.should eq("ready")
      parsed["url"].as_s.should eq("http://127.0.0.1:3000")
      parsed["host"].as_s.should eq("127.0.0.1")
      parsed["port"].as_i.should eq(3000)
      parsed["pid"].as_i.should eq(Process.pid)
    end

    it "emits port as a JSON integer, not a string" do
      server = Hwaro::Services::Server.new
      parsed = JSON.parse(server.test_ready_signal_json("0.0.0.0", 8080))
      parsed["port"].as_i?.should eq(8080)
      parsed["port"].as_s?.should be_nil
    end

    it "is a single line with no embedded newline" do
      server = Hwaro::Services::Server.new
      json = server.test_ready_signal_json("localhost", 4567)
      json.includes?('\n').should be_false
    end
  end
end

describe Hwaro::Services::IndexRewriteHandler do
  it "rewrites path ending in / to index.html" do
    Dir.mktmpdir do |dir|
      handler = Hwaro::Services::IndexRewriteHandler.new(dir)
      dummy = DummyHandler.new
      handler.next = dummy

      request = HTTP::Request.new("GET", "/some/path/")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      request.path.should eq("/some/path/index.html")
      dummy.called.should be_true
    end
  end

  it "redirects directory without slash to slash" do
    Dir.mktmpdir do |dir|
      # Create a directory inside public dir
      FileUtils.mkdir_p(File.join(dir, "some/dir"))

      handler = Hwaro::Services::IndexRewriteHandler.new(dir)
      dummy = DummyHandler.new
      handler.next = dummy

      request = HTTP::Request.new("GET", "/some/dir")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      response.status_code.should eq(301)
      response.headers["Location"].should eq("/some/dir/")
      dummy.called.should be_false
    end
  end

  it "uses sanitized path in Location header to prevent CRLF injection" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "safe/dir"))

      handler = Hwaro::Services::IndexRewriteHandler.new(dir)
      dummy = DummyHandler.new
      handler.next = dummy

      # Path with percent-encoded CRLF that could cause header injection
      request = HTTP::Request.new("GET", "/safe/dir")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      response.status_code.should eq(301)
      location = response.headers["Location"]
      location.should eq("/safe/dir/")
      location.should_not contain("\r")
      location.should_not contain("\n")
    end
  end

  it "does not redirect traversal attempts" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "legit"))

      handler = Hwaro::Services::IndexRewriteHandler.new(dir)
      dummy = DummyHandler.new
      handler.next = dummy

      request = HTTP::Request.new("GET", "/../../etc")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      # Should not issue a redirect for traversal paths
      dummy.called.should be_true
    end
  end

  it "passes through files that don't need rewriting" do
    Dir.mktmpdir do |dir|
      handler = Hwaro::Services::IndexRewriteHandler.new(dir)
      dummy = DummyHandler.new
      handler.next = dummy

      request = HTTP::Request.new("GET", "/some/file.html")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      request.path.should eq("/some/file.html")
      dummy.called.should be_true
    end
  end
end

describe Hwaro::Services::NotFoundHandler do
  it "serves 404.html if present" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "404.html"), "Custom 404")

      handler = Hwaro::Services::NotFoundHandler.new(dir)

      request = HTTP::Request.new("GET", "/nonexistent")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)
      response.close

      response.status_code.should eq(404)
      io.rewind
      content = io.to_s
      content.should contain("Custom 404")
    end
  end

  it "serves default 404 message if 404.html missing" do
    Dir.mktmpdir do |dir|
      handler = Hwaro::Services::NotFoundHandler.new(dir)

      request = HTTP::Request.new("GET", "/nonexistent")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)
      response.close

      response.status_code.should eq(404)
      io.rewind
      content = io.to_s
      content.should contain("404 Not Found")
    end
  end
end

private def cors_request(method : String, origin : String?, extra_headers = {} of String => String)
  headers = HTTP::Headers.new
  headers["Origin"] = origin if origin
  extra_headers.each { |k, v| headers[k] = v }
  HTTP::Request.new(method, "/search_index.json", headers)
end

describe Hwaro::Services::DevCorsHandler do
  it "reflects a loopback Origin and passes through" do
    handler = Hwaro::Services::DevCorsHandler.new
    dummy = DummyHandler.new
    handler.next = dummy

    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(cors_request("GET", "http://localhost:3000"), response)

    handler.call(context)

    response.headers["Access-Control-Allow-Origin"].should eq("http://localhost:3000")
    response.headers["Vary"].should eq("Origin")
    dummy.called.should be_true
  end

  it "does NOT grant CORS to an arbitrary internet Origin" do
    handler = Hwaro::Services::DevCorsHandler.new
    dummy = DummyHandler.new
    handler.next = dummy

    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(cors_request("GET", "https://evil.example.com"), response)

    handler.call(context)

    response.headers["Access-Control-Allow-Origin"]?.should be_nil
    dummy.called.should be_true
  end

  it "reflects the explicitly bound host Origin" do
    handler = Hwaro::Services::DevCorsHandler.new(Set{"localhost", "127.0.0.1", "::1", "192.168.1.5"})
    dummy = DummyHandler.new
    handler.next = dummy

    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(cors_request("GET", "http://192.168.1.5:3000"), response)

    handler.call(context)

    response.headers["Access-Control-Allow-Origin"].should eq("http://192.168.1.5:3000")
  end

  it "short-circuits OPTIONS preflight with 204 and CORS headers for a loopback Origin" do
    handler = Hwaro::Services::DevCorsHandler.new
    dummy = DummyHandler.new
    handler.next = dummy

    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(
      cors_request("OPTIONS", "http://127.0.0.1:3000", {"Access-Control-Request-Headers" => "content-type"}),
      response,
    )

    handler.call(context)

    response.status_code.should eq(204)
    response.headers["Access-Control-Allow-Origin"].should eq("http://127.0.0.1:3000")
    response.headers["Access-Control-Allow-Methods"].should eq("GET, HEAD, OPTIONS")
    response.headers["Access-Control-Allow-Headers"].should eq("content-type")
    response.headers["Access-Control-Max-Age"].should eq("86400")
    dummy.called.should be_false
  end

  it "returns 204 for an OPTIONS preflight from a disallowed Origin without CORS headers" do
    handler = Hwaro::Services::DevCorsHandler.new
    dummy = DummyHandler.new
    handler.next = dummy

    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(cors_request("OPTIONS", "https://evil.example.com"), response)

    handler.call(context)

    response.status_code.should eq(204)
    response.headers["Access-Control-Allow-Origin"]?.should be_nil
    response.headers["Access-Control-Allow-Methods"]?.should be_nil
    dummy.called.should be_false
  end

  it "reflects a bracketed loopback IPv6 Origin (strips brackets before membership check)" do
    handler = Hwaro::Services::DevCorsHandler.new
    dummy = DummyHandler.new
    handler.next = dummy

    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(cors_request("GET", "http://[::1]:3000"), response)

    handler.call(context)

    response.headers["Access-Control-Allow-Origin"].should eq("http://[::1]:3000")
    response.headers["Vary"].should eq("Origin")
    dummy.called.should be_true
  end

  it "does NOT grant CORS to a non-loopback bracketed IPv6 Origin" do
    handler = Hwaro::Services::DevCorsHandler.new
    dummy = DummyHandler.new
    handler.next = dummy

    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(cors_request("GET", "http://[2001:db8::1]:3000"), response)

    handler.call(context)

    response.headers["Access-Control-Allow-Origin"]?.should be_nil
    dummy.called.should be_true
  end
end

private def run_charset(content_type : String?)
  handler = Hwaro::Services::CharsetHandler.new
  handler.next = ContentTypeHandler.new(content_type)

  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/"), response)

  handler.call(context)
  response
end

describe Hwaro::Services::CharsetHandler do
  it "appends charset to application/json" do
    run_charset("application/json").headers["Content-Type"].should eq("application/json; charset=utf-8")
  end

  it "appends charset to feed and SVG text-shaped types" do
    run_charset("application/rss+xml").headers["Content-Type"].should eq("application/rss+xml; charset=utf-8")
    run_charset("image/svg+xml").headers["Content-Type"].should eq("image/svg+xml; charset=utf-8")
  end

  it "appends charset to every [outputs] format's content type (json/xml/txt/csv)" do
    run_charset("application/json").headers["Content-Type"].should eq("application/json; charset=utf-8")
    run_charset("application/xml").headers["Content-Type"].should eq("application/xml; charset=utf-8")
    run_charset("text/plain").headers["Content-Type"].should eq("text/plain; charset=utf-8")
    run_charset("text/csv").headers["Content-Type"].should eq("text/csv; charset=utf-8")
  end

  it "leaves binary types untouched (no charset)" do
    run_charset("image/png").headers["Content-Type"].should eq("image/png")
    run_charset("font/woff2").headers["Content-Type"].should eq("font/woff2")
  end

  it "is idempotent when a charset already exists (no double-append)" do
    run_charset("text/html; charset=iso-8859-1").headers["Content-Type"].should eq("text/html; charset=iso-8859-1")
  end

  it "is a no-op when downstream sets no Content-Type" do
    response = run_charset(nil)
    response.headers["Content-Type"]?.should be_nil
  end
end

describe Hwaro::Services::CustomHeadersHandler do
  it "applies user headers and overrides built-ins set downstream" do
    handler = Hwaro::Services::CustomHeadersHandler.new({
      "X-Frame-Options" => "DENY",
      "Content-Type"    => "text/custom",
    })
    handler.next = ContentTypeHandler.new("text/html")

    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/"), response)

    handler.call(context)

    response.headers["X-Frame-Options"].should eq("DENY")
    # User value wins over the Content-Type the downstream handler set.
    response.headers["Content-Type"].should eq("text/custom")
  end

  it "drops a header whose value contains control characters (defense-in-depth)" do
    handler = Hwaro::Services::CustomHeadersHandler.new({
      "X-Frame-Options" => "DENY",
      "X-Evil"          => "a\r\nInjected: 1",
    })
    handler.next = ContentTypeHandler.new("text/html")

    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/"), response)

    handler.call(context)

    response.headers["X-Frame-Options"].should eq("DENY")
    response.headers["X-Evil"]?.should be_nil
  end
end

describe "stale output cleanup on file removal" do
  it "maps removed static and content-asset paths to their output files" do
    builder = Hwaro::Core::Build::Builder.new
    outputs = builder.stale_outputs_for_removed(["static/img/logo.png", "content/posts/photo.jpg"], "public")
    outputs.should eq([File.join("public", "img/logo.png"), File.join("public", "posts/photo.jpg")])
  end

  it "ignores removed markdown files when no site has been built yet" do
    builder = Hwaro::Core::Build::Builder.new
    builder.stale_outputs_for_removed(["content/posts/gone.md"], "public").should be_empty
  end

  it "includes cache-recorded sibling output-format files for a removed page" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("content/posts")
        File.write("content/posts/gone.md", "content")

        config = Hwaro::Models::Config.new
        site = Hwaro::Models::Site.new(config)
        page = Hwaro::Models::Page.new("posts/gone.md")
        page.url = "/posts/gone/"
        site.pages << page

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: File.join(dir, ".hwaro_cache.json"))
        cache.update("content/posts/gone.md", output_paths: [File.join("public", "posts/gone/index.json")])

        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_site(site)
        builder.test_set_config(config)
        builder.test_set_cache(cache)

        outputs = builder.stale_outputs_for_removed(["content/posts/gone.md"], "public")
        outputs.any?(&.ends_with?("public/posts/gone/index.html")).should be_true
        outputs.should contain(File.join("public", "posts/gone/index.json"))
      end
    end
  end

  it "falls back to recomputing effective formats when the cache has no record" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        config = Hwaro::Models::Config.new
        config.outputs.page = ["json"]
        site = Hwaro::Models::Site.new(config)
        page = Hwaro::Models::Page.new("posts/gone.md")
        page.url = "/posts/gone/"
        site.pages << page

        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_site(site)
        builder.test_set_config(config)

        outputs = builder.stale_outputs_for_removed(["content/posts/gone.md"], "public")
        outputs.any?(&.ends_with?("public/posts/gone/index.html")).should be_true
        outputs.any?(&.ends_with?("public/posts/gone/index.json")).should be_true
      end
    end
  end

  it "adds no format paths for a removed page with no effective formats" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        config = Hwaro::Models::Config.new
        site = Hwaro::Models::Site.new(config)
        page = Hwaro::Models::Page.new("posts/gone.md")
        page.url = "/posts/gone/"
        site.pages << page

        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_site(site)
        builder.test_set_config(config)

        outputs = builder.stale_outputs_for_removed(["content/posts/gone.md"], "public")
        outputs.size.should eq(1)
        outputs[0].ends_with?("public/posts/gone/index.html").should be_true
      end
    end
  end

  it "deletes stale outputs and prunes empty parent directories" do
    Dir.mktmpdir do |dir|
      stale = File.join(dir, "guide", "old-page", "index.html")
      FileUtils.mkdir_p(File.dirname(stale))
      File.write(stale, "x")
      keep = File.join(dir, "guide", "index.html")
      File.write(keep, "y")

      Hwaro::Services::Server.new.test_remove_stale_outputs([stale], dir)

      File.exists?(stale).should be_false
      Dir.exists?(File.join(dir, "guide", "old-page")).should be_false
      # Sibling content (and the shared parent) must survive the pruning.
      File.exists?(keep).should be_true
    end
  end

  it "refuses to delete files outside the output directory" do
    Dir.mktmpdir do |dir|
      outside = File.join(dir, "outside.txt")
      File.write(outside, "precious")
      output_dir = File.join(dir, "public")
      FileUtils.mkdir_p(output_dir)

      Hwaro::Services::Server.new.test_remove_stale_outputs([outside], output_dir)

      File.exists?(outside).should be_true
    end
  end
end

describe Hwaro::Services::ChangeSet do
  describe "#empty?" do
    it "returns true when nothing changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.empty?.should be_true
    end

    it "returns false when content changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.empty?.should be_false
    end

    it "returns false when config changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: true,
      )
      cs.empty?.should be_false
    end
  end

  describe "#needs_full_rebuild?" do
    it "returns true when config changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: true,
      )
      cs.needs_full_rebuild?.should be_true
    end

    it "returns true when files were added" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: ["content/posts/new-post.md"],
        removed_files: [] of String,
        config_changed: false,
      )
      cs.needs_full_rebuild?.should be_true
    end

    it "returns true when files were removed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: ["content/posts/old-post.md"],
        config_changed: false,
      )
      cs.needs_full_rebuild?.should be_true
    end

    it "returns true when data/i18n files were modified" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
        modified_data: ["data/authors.yml"],
      )
      cs.needs_full_rebuild?.should be_true
      cs.empty?.should be_false
    end

    it "returns false for content-only modification" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.needs_full_rebuild?.should be_false
    end

    it "returns false for static-only modification" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: ["static/css/style.css"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.needs_full_rebuild?.should be_false
    end
  end

  describe "#templates_only?" do
    it "returns true when only templates changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.templates_only?.should be_true
    end

    it "returns false when templates and content changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.templates_only?.should be_false
    end

    it "returns false when templates changed and files added" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: ["content/new.md"],
        removed_files: [] of String,
        config_changed: false,
      )
      cs.templates_only?.should be_false
    end

    it "returns false when no templates changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.templates_only?.should be_false
    end
  end

  describe "#static_only?" do
    it "returns true when only static files changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: ["static/css/style.css", "static/js/app.js"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.static_only?.should be_true
    end

    it "returns false when static and content changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: ["static/css/style.css"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.static_only?.should be_false
    end

    it "returns false when static changed and config changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: ["static/css/style.css"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: true,
      )
      cs.static_only?.should be_false
    end
  end

  describe "#content_incremental?" do
    it "returns true when only content files were modified" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.content_incremental?.should be_true
    end

    it "returns true when content and static were modified (no structural changes)" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: ["static/css/style.css"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.content_incremental?.should be_true
    end

    it "returns false when files were added alongside content changes" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: ["content/posts/new.md"],
        removed_files: [] of String,
        config_changed: false,
      )
      cs.content_incremental?.should be_false
    end

    it "returns false when templates also changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.content_incremental?.should be_false
    end

    it "returns false when config also changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: true,
      )
      cs.content_incremental?.should be_false
    end

    it "returns false when no content changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: ["static/css/style.css"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.content_incremental?.should be_false
    end
  end

  describe "#merge" do
    it "combines two changesets with deduplication" do
      cs1 = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/a.md"],
        modified_templates: [] of String,
        modified_static: ["static/css/style.css"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs2 = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/a.md", "content/posts/b.md"],
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: ["content/posts/new.md"],
        removed_files: [] of String,
        config_changed: false,
      )

      merged = cs1.merge(cs2)
      merged.modified_content.should eq(["content/posts/a.md", "content/posts/b.md"])
      merged.modified_templates.should eq(["templates/page.html"])
      merged.modified_static.should eq(["static/css/style.css"])
      merged.added_files.should eq(["content/posts/new.md"])
    end

    it "propagates config_changed from either side" do
      cs1 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs2 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: true,
      )

      cs1.merge(cs2).config_changed.should be_true
      cs2.merge(cs1).config_changed.should be_true
    end

    it "cancels out files that are both added and removed" do
      cs1 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: ["content/posts/temp.md"],
        removed_files: [] of String,
        config_changed: false,
      )
      cs2 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: ["content/posts/temp.md"],
        config_changed: false,
      )

      merged = cs1.merge(cs2)
      merged.added_files.should be_empty
      merged.removed_files.should be_empty
      merged.empty?.should be_true
    end

    it "treats remove→add as net add (atomic save via delete+move)" do
      cs1 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: ["content/posts/old.md"],
        config_changed: false,
      )
      cs2 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: ["content/posts/old.md"],
        removed_files: [] of String,
        config_changed: false,
      )

      merged = cs1.merge(cs2)
      merged.added_files.should eq(["content/posts/old.md"])
      merged.removed_files.should be_empty
    end

    it "only cancels overlapping entries, keeps the rest" do
      cs1 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: ["content/a.md", "content/b.md"],
        removed_files: [] of String,
        config_changed: false,
      )
      cs2 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: ["content/b.md", "content/c.md"],
        config_changed: false,
      )

      merged = cs1.merge(cs2)
      merged.added_files.should eq(["content/a.md"])
      merged.removed_files.should eq(["content/c.md"])
    end

    it "merges two empty changesets" do
      cs1 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs2 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )

      merged = cs1.merge(cs2)
      merged.empty?.should be_true
    end

    it "merges removed files with deduplication" do
      cs1 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: ["content/old.md"],
        config_changed: false,
      )
      cs2 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: ["content/old.md", "content/other.md"],
        config_changed: false,
      )

      merged = cs1.merge(cs2)
      merged.removed_files.should eq(["content/old.md", "content/other.md"])
    end

    it "merges modified_content_files with deduplication" do
      cs1 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
        modified_content_files: ["content/projects/a/cover.jpg"],
      )
      cs2 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
        modified_content_files: ["content/projects/a/cover.jpg", "content/projects/b/cover.png"],
      )

      merged = cs1.merge(cs2)
      merged.modified_content_files.should eq([
        "content/projects/a/cover.jpg",
        "content/projects/b/cover.png",
      ])
      merged.content_files_only?.should be_true
    end

    it "merges modified_data with deduplication" do
      cs1 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
        modified_data: ["data/authors.yml"],
      )
      cs2 = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
        modified_data: ["data/authors.yml", "i18n/ko.toml"],
      )

      merged = cs1.merge(cs2)
      merged.modified_data.should eq(["data/authors.yml", "i18n/ko.toml"])
      merged.rebuild_strategy.should eq(:full)
    end
  end

  describe "#rebuild_strategy" do
    it "returns :full for config changes" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: true,
      )
      cs.rebuild_strategy.should eq(:full)
    end

    it "returns :full for added files" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: ["content/new.md"],
        removed_files: [] of String,
        config_changed: false,
      )
      cs.rebuild_strategy.should eq(:full)
    end

    it "returns :templates for template-only changes" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.rebuild_strategy.should eq(:templates)
    end

    it "returns :incremental for content-only changes" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.rebuild_strategy.should eq(:incremental)
    end

    it "returns :static for static-only changes" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: ["static/css/style.css"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.rebuild_strategy.should eq(:static)
    end

    it "returns :content_and_template for mixed content+template changes" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.rebuild_strategy.should eq(:content_and_template)
    end

    it "returns :content_files when only content assets changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
        modified_content_files: ["content/projects/foo/cover.jpg"],
      )
      cs.rebuild_strategy.should eq(:content_files)
    end
  end

  describe "#content_files_only?" do
    it "returns true when only non-Markdown content assets changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
        modified_content_files: ["content/projects/foo/cover.jpg"],
      )
      cs.content_files_only?.should be_true
      cs.empty?.should be_false
    end

    it "returns false when a markdown file also changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/projects/foo/index.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
        modified_content_files: ["content/projects/foo/cover.jpg"],
      )
      cs.content_files_only?.should be_false
    end

    it "returns false when a structural change is present" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: ["content/projects/bar/new.jpg"],
        removed_files: [] of String,
        config_changed: false,
        modified_content_files: ["content/projects/foo/cover.jpg"],
      )
      cs.content_files_only?.should be_false
      cs.needs_full_rebuild?.should be_true
    end
  end

  describe "#description" do
    it "describes content changes" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/a.md", "content/b.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.description.should eq("2 content files")
    end

    it "describes mixed changes" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/a.md"],
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: ["content/new.md"],
        removed_files: [] of String,
        config_changed: true,
      )
      cs.description.should eq("1 content, 1 template, 1 added files, config")
    end

    it "describes content-asset and removed buckets" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: ["content/old.md"],
        config_changed: false,
        modified_content_files: ["content/a/cover.jpg"],
      )
      cs.description.should eq("1 content-asset, 1 removed files")
    end
  end

  describe "classification priority" do
    it "full rebuild takes precedence over content incremental" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: ["content/posts/new.md"],
        removed_files: [] of String,
        config_changed: false,
      )
      cs.needs_full_rebuild?.should be_true
      cs.content_incremental?.should be_false
    end

    it "full rebuild takes precedence over templates only" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: ["templates/old.html"],
        config_changed: false,
      )
      cs.needs_full_rebuild?.should be_true
      cs.templates_only?.should be_false
    end

    it "multiple content modifications are incremental" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/a.md", "content/posts/b.md", "content/about.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.content_incremental?.should be_true
      cs.needs_full_rebuild?.should be_false
    end

    it "multiple template modifications are templates_only" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: ["templates/page.html", "templates/base.html", "templates/header.html"],
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.templates_only?.should be_true
    end
  end
end

# Expose private detect_changes and classify_modified for testing
module Hwaro
  module Services
    class Server
      def test_detect_changes(old_mtimes : Hash(String, Time), new_mtimes : Hash(String, Time)) : ChangeSet
        detect_changes(old_mtimes, new_mtimes)
      end
    end
  end
end

describe "Builder#inject_error_overlay" do
  it "injects overlay before </body>" do
    builder = Hwaro::Core::Build::Builder.new
    html = "<html><body><p>Hello</p></body></html>"
    warnings = ["No template found for test.md. Using raw content."]

    result = builder.test_inject_error_overlay(html, warnings)
    result.should contain("hwaro-error-overlay")
    result.should contain("Build Warning")
    result.should contain("No template found for test.md")
    # Overlay should be before </body>
    overlay_pos = result.index!("hwaro-error-overlay")
    body_pos = result.rindex!("</body>")
    overlay_pos.should be < body_pos
  end

  it "appends overlay when no </body> tag exists" do
    builder = Hwaro::Core::Build::Builder.new
    html = "<p>Simple content</p>"
    warnings = ["Template error for page.md: undefined variable"]

    result = builder.test_inject_error_overlay(html, warnings)
    result.should contain("hwaro-error-overlay")
    result.should start_with("<p>Simple content</p>")
  end

  it "returns html unchanged when warnings are empty" do
    builder = Hwaro::Core::Build::Builder.new
    html = "<html><body><p>Hello</p></body></html>"

    result = builder.test_inject_error_overlay(html, [] of String)
    result.should eq(html)
  end

  it "escapes HTML in warning messages" do
    builder = Hwaro::Core::Build::Builder.new
    html = "<html><body></body></html>"
    warnings = ["Error with <script>alert('xss')</script>"]

    result = builder.test_inject_error_overlay(html, warnings)
    result.should_not contain("<script>alert")
    result.should contain("&lt;script&gt;")
  end

  it "shows multiple warnings as list items" do
    builder = Hwaro::Core::Build::Builder.new
    html = "<html><body></body></html>"
    warnings = ["Warning one", "Warning two"]

    result = builder.test_inject_error_overlay(html, warnings)
    result.should contain("Warning one")
    result.should contain("Warning two")
    # Should have two <li> items
    result.scan(/<li /).size.should eq(2)
  end
end

describe "Server#detect_changes" do
  it "detects modified content files" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)
    t2 = Time.utc(2025, 1, 1, 0, 0, 5)

    old = {"content/posts/hello.md" => t1, "content/about.md" => t1}
    new_m = {"content/posts/hello.md" => t2, "content/about.md" => t1}

    cs = server.test_detect_changes(old, new_m)
    cs.modified_content.should eq(["content/posts/hello.md"])
    cs.modified_templates.should be_empty
    cs.modified_static.should be_empty
    cs.added_files.should be_empty
    cs.removed_files.should be_empty
    cs.config_changed.should be_false
  end

  it "detects modified template files" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)
    t2 = Time.utc(2025, 1, 1, 0, 0, 5)

    old = {"templates/page.html" => t1}
    new_m = {"templates/page.html" => t2}

    cs = server.test_detect_changes(old, new_m)
    cs.modified_templates.should eq(["templates/page.html"])
    cs.modified_content.should be_empty
  end

  it "detects modified static files" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)
    t2 = Time.utc(2025, 1, 1, 0, 0, 5)

    old = {"static/css/style.css" => t1}
    new_m = {"static/css/style.css" => t2}

    cs = server.test_detect_changes(old, new_m)
    cs.modified_static.should eq(["static/css/style.css"])
    cs.modified_content.should be_empty
  end

  it "detects config.toml change" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)
    t2 = Time.utc(2025, 1, 1, 0, 0, 5)

    old = {"config.toml" => t1}
    new_m = {"config.toml" => t2}

    cs = server.test_detect_changes(old, new_m)
    cs.config_changed.should be_true
    cs.needs_full_rebuild?.should be_true
  end

  it "detects modified data and i18n files and forces a full rebuild" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)
    t2 = Time.utc(2025, 1, 1, 0, 0, 5)

    old = {"data/authors.yml" => t1, "i18n/en.toml" => t1}
    new_m = {"data/authors.yml" => t2, "i18n/en.toml" => t2}

    cs = server.test_detect_changes(old, new_m)
    cs.modified_data.sort.should eq(["data/authors.yml", "i18n/en.toml"])
    cs.modified_content.should be_empty
    cs.empty?.should be_false
    cs.needs_full_rebuild?.should be_true
    cs.rebuild_strategy.should eq(:full)
  end

  it "detects added files" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)

    old = {"content/posts/hello.md" => t1}
    new_m = {"content/posts/hello.md" => t1, "content/posts/new.md" => t1}

    cs = server.test_detect_changes(old, new_m)
    cs.added_files.should eq(["content/posts/new.md"])
    cs.needs_full_rebuild?.should be_true
  end

  it "detects removed files" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)

    old = {"content/posts/hello.md" => t1, "content/posts/old.md" => t1}
    new_m = {"content/posts/hello.md" => t1}

    cs = server.test_detect_changes(old, new_m)
    cs.removed_files.should eq(["content/posts/old.md"])
    cs.needs_full_rebuild?.should be_true
  end

  it "ignores unchanged files" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)

    old = {"content/posts/hello.md" => t1, "static/css/style.css" => t1}
    new_m = {"content/posts/hello.md" => t1, "static/css/style.css" => t1}

    cs = server.test_detect_changes(old, new_m)
    cs.empty?.should be_true
  end

  it "categorizes mixed changes correctly" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)
    t2 = Time.utc(2025, 1, 1, 0, 0, 5)

    old = {
      "content/posts/hello.md" => t1,
      "static/css/style.css"   => t1,
      "templates/page.html"    => t1,
    }
    new_m = {
      "content/posts/hello.md" => t2,
      "static/css/style.css"   => t2,
      "templates/page.html"    => t1,
    }

    cs = server.test_detect_changes(old, new_m)
    cs.modified_content.should eq(["content/posts/hello.md"])
    cs.modified_static.should eq(["static/css/style.css"])
    cs.modified_templates.should be_empty
    cs.content_incremental?.should be_true
  end

  it "routes overwritten non-Markdown content files into modified_content_files (gh#530)" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)
    t2 = Time.utc(2025, 1, 1, 0, 0, 5)

    old = {"content/projects/foo/cover.jpg" => t1}
    new_m = {"content/projects/foo/cover.jpg" => t2}

    cs = server.test_detect_changes(old, new_m)
    cs.modified_content_files.should eq(["content/projects/foo/cover.jpg"])
    cs.modified_content.should be_empty
    cs.modified_static.should be_empty
    cs.added_files.should be_empty
    cs.content_files_only?.should be_true
    cs.rebuild_strategy.should eq(:content_files)
  end

  it "separates markdown and image changes under the same content directory" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)
    t2 = Time.utc(2025, 1, 1, 0, 0, 5)

    old = {
      "content/projects/foo/index.md"  => t1,
      "content/projects/foo/cover.jpg" => t1,
    }
    new_m = {
      "content/projects/foo/index.md"  => t2,
      "content/projects/foo/cover.jpg" => t2,
    }

    cs = server.test_detect_changes(old, new_m)
    cs.modified_content.should eq(["content/projects/foo/index.md"])
    cs.modified_content_files.should eq(["content/projects/foo/cover.jpg"])
    cs.content_files_only?.should be_false
    cs.content_incremental?.should be_true
  end
end

describe "Builder incremental methods" do
  describe "#copy_changed_static" do
    it "copies only specified static files to the output directory" do
      Dir.mktmpdir do |dir|
        # Setup: create static source and output directories
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(File.join(static_dir, "css"))
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "css", "style.css"), "body { color: red; }")
        File.write(File.join(static_dir, "css", "other.css"), "h1 { color: blue; }")

        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          builder.copy_changed_static(
            ["static/css/style.css"],
            output_dir,
            false
          )

          # Only style.css should be copied
          File.exists?(File.join(output_dir, "css", "style.css")).should be_true
          File.read(File.join(output_dir, "css", "style.css")).should eq("body { color: red; }")

          # other.css should NOT be copied
          File.exists?(File.join(output_dir, "css", "other.css")).should be_false
        end
      end
    end

    it "creates parent directories as needed" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(File.join(static_dir, "assets", "js"))

        File.write(File.join(static_dir, "assets", "js", "app.js"), "console.log('hi')")

        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          builder.copy_changed_static(
            ["static/assets/js/app.js"],
            output_dir,
            false
          )

          File.exists?(File.join(output_dir, "assets", "js", "app.js")).should be_true
        end
      end
    end

    it "skips non-existent source files gracefully" do
      Dir.mktmpdir do |dir|
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(output_dir)

        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          # Should not raise
          builder.copy_changed_static(
            ["static/nonexistent.css"],
            output_dir,
            false
          )
        end
      end
    end
  end

  describe "#copy_changed_content_files" do
    it "republishes an in-place overwritten image (gh#530)" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "content", "projects", "foo"))
        FileUtils.mkdir_p(File.join(dir, "templates"))

        File.write(File.join(dir, "config.toml"), <<-TOML
          title = "Test"
          base_url = "http://localhost"

          [content.files]
          allow_extensions = ["jpg", "png"]
          TOML
        )
        File.write(File.join(dir, "templates", "page.html"), "{{ content }}")
        File.write(File.join(dir, "content", "projects", "foo", "_index.md"),
          "---\ntitle: Foo\n---\n")
        File.write(File.join(dir, "content", "projects", "foo", "cover.jpg"), "OLD")

        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
          options = Hwaro::Config::Options::BuildOptions.new
          builder.run(options)

          published = File.join(dir, "public", "projects", "foo", "cover.jpg")
          File.read(published).should eq("OLD")

          # Simulate the bug repro: overwrite the image in place, then ask
          # the watcher's republish path to update output.
          File.write(File.join(dir, "content", "projects", "foo", "cover.jpg"), "NEW")
          builder.copy_changed_content_files(
            ["content/projects/foo/cover.jpg"],
            File.join(dir, "public"),
            false,
          )

          File.read(published).should eq("NEW")
        end
      end
    end

    it "refuses to publish files whose extension isn't allowed" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "content"))
        FileUtils.mkdir_p(File.join(dir, "templates"))

        File.write(File.join(dir, "config.toml"), <<-TOML
          title = "Test"
          base_url = "http://localhost"

          [content.files]
          allow_extensions = ["jpg"]
          TOML
        )
        File.write(File.join(dir, "templates", "page.html"), "{{ content }}")
        File.write(File.join(dir, "content", "secret.psd"), "binary")

        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
          options = Hwaro::Config::Options::BuildOptions.new
          builder.run(options)

          builder.copy_changed_content_files(
            ["content/secret.psd"],
            File.join(dir, "public"),
            false,
          )

          File.exists?(File.join(dir, "public", "secret.psd")).should be_false
        end
      end
    end

    it "is a no-op when content.files is disabled" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "content"))
        FileUtils.mkdir_p(File.join(dir, "templates"))

        File.write(File.join(dir, "config.toml"),
          "title = \"Test\"\nbase_url = \"http://localhost\"\n")
        File.write(File.join(dir, "templates", "page.html"), "{{ content }}")
        File.write(File.join(dir, "content", "cover.jpg"), "bytes")

        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
          options = Hwaro::Config::Options::BuildOptions.new
          builder.run(options)

          builder.copy_changed_content_files(
            ["content/cover.jpg"],
            File.join(dir, "public"),
            false,
          )

          File.exists?(File.join(dir, "public", "cover.jpg")).should be_false
        end
      end
    end
  end

  describe "#run_incremental" do
    it "falls back to full build when no prior state exists" do
      Dir.mktmpdir do |dir|
        # Create minimal project structure
        FileUtils.mkdir_p(File.join(dir, "content"))
        FileUtils.mkdir_p(File.join(dir, "templates"))
        File.write(File.join(dir, "config.toml"), "title = \"Test\"\nbase_url = \"http://localhost\"\n")
        File.write(File.join(dir, "content", "hello.md"), "---\ntitle: Hello\n---\nHello world")
        File.write(File.join(dir, "templates", "page.html"), "{{ content }}")

        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
          options = Hwaro::Config::Options::BuildOptions.new

          # run_incremental should fall back to full build since no prior build happened
          builder.run_incremental(["content/hello.md"], options)

          # Verify output was generated (full build happened)
          File.exists?(File.join(dir, "public", "hello", "index.html")).should be_true
        end
      end
    end
  end

  describe "#run_rerender" do
    it "falls back to full build when no prior state exists" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "content"))
        FileUtils.mkdir_p(File.join(dir, "templates"))
        File.write(File.join(dir, "config.toml"), "title = \"Test\"\nbase_url = \"http://localhost\"\n")
        File.write(File.join(dir, "content", "hello.md"), "---\ntitle: Hello\n---\nHello world")
        File.write(File.join(dir, "templates", "page.html"), "{{ content }}")

        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
          options = Hwaro::Config::Options::BuildOptions.new

          # run_rerender should fall back to full build since no prior build happened
          builder.run_rerender(options)

          File.exists?(File.join(dir, "public", "hello", "index.html")).should be_true
        end
      end
    end
  end
end

describe "Incremental build integration" do
  it "only re-renders the changed page and its section, preserving other pages" do
    Dir.mktmpdir do |dir|
      # --- Setup project structure ---
      FileUtils.mkdir_p(File.join(dir, "content", "posts"))
      FileUtils.mkdir_p(File.join(dir, "templates"))

      File.write(File.join(dir, "config.toml"), <<-TOML
        title = "Incremental Test"
        base_url = "http://localhost"
        TOML
      )
      File.write(File.join(dir, "templates", "page.html"), "<article>{{ content }}</article>")
      File.write(File.join(dir, "templates", "section.html"), "<section>{{ content }}</section>")

      File.write(File.join(dir, "content", "posts", "_index.md"), <<-MD
        ---
        title: Posts
        ---
        Posts section
        MD
      )
      File.write(File.join(dir, "content", "posts", "alpha.md"), <<-MD
        ---
        title: Alpha
        date: 2025-01-01
        ---
        Alpha original content
        MD
      )
      File.write(File.join(dir, "content", "posts", "beta.md"), <<-MD
        ---
        title: Beta
        date: 2025-01-02
        ---
        Beta original content
        MD
      )
      File.write(File.join(dir, "content", "about.md"), <<-MD
        ---
        title: About
        ---
        About page content
        MD
      )

      Dir.cd(dir) do
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new

        # --- Full build ---
        builder.run(options)

        alpha_path = File.join(dir, "public", "posts", "alpha", "index.html")
        beta_path = File.join(dir, "public", "posts", "beta", "index.html")
        about_path = File.join(dir, "public", "about", "index.html")

        File.exists?(alpha_path).should be_true
        File.exists?(beta_path).should be_true
        File.exists?(about_path).should be_true

        original_alpha = File.read(alpha_path)
        original_beta = File.read(beta_path)
        original_about = File.read(about_path)

        original_alpha.should contain("Alpha original content")
        original_beta.should contain("Beta original content")
        original_about.should contain("About page content")

        # Small sleep so mtime changes are detectable
        sleep 0.05.seconds

        # --- Modify only alpha.md ---
        File.write(File.join(dir, "content", "posts", "alpha.md"), <<-MD
          ---
          title: Alpha
          date: 2025-01-01
          ---
          Alpha UPDATED content
          MD
        )

        # --- Incremental build ---
        builder.run_incremental(["content/posts/alpha.md"], options)

        # Alpha should have the updated content
        updated_alpha = File.read(alpha_path)
        updated_alpha.should contain("Alpha UPDATED content")
        updated_alpha.should_not contain("Alpha original content")

        # About page should be UNCHANGED (not in the affected set)
        updated_about = File.read(about_path)
        updated_about.should eq(original_about)
      end
    end
  end

  it "re-renders section index when a page in that section changes" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content", "blog"))
      FileUtils.mkdir_p(File.join(dir, "templates"))

      File.write(File.join(dir, "config.toml"), <<-TOML
        title = "Section Test"
        base_url = "http://localhost"
        TOML
      )
      File.write(File.join(dir, "templates", "page.html"), "<p>{{ content }}</p>")
      File.write(File.join(dir, "templates", "section.html"), "<div>{{ content }}</div>")

      File.write(File.join(dir, "content", "blog", "_index.md"), <<-MD
        ---
        title: Blog
        ---
        Blog index
        MD
      )
      File.write(File.join(dir, "content", "blog", "post1.md"), <<-MD
        ---
        title: Post One
        date: 2025-06-01
        ---
        Post one body
        MD
      )

      Dir.cd(dir) do
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new

        builder.run(options)

        section_path = File.join(dir, "public", "blog", "index.html")
        post_path = File.join(dir, "public", "blog", "post1", "index.html")

        File.exists?(section_path).should be_true
        File.exists?(post_path).should be_true

        # Modify post
        sleep 0.05.seconds
        File.write(File.join(dir, "content", "blog", "post1.md"), <<-MD
          ---
          title: Post One Updated
          date: 2025-06-01
          ---
          Post one UPDATED body
          MD
        )

        builder.run_incremental(["content/blog/post1.md"], options)

        # Post should be updated
        File.read(post_path).should contain("Post one UPDATED body")

        # Section index should also be re-rendered (it's in the affected set)
        File.exists?(section_path).should be_true
      end
    end
  end

  it "re-renders ancestor sections when a page in a nested section changes" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content", "blog", "posts"))
      FileUtils.mkdir_p(File.join(dir, "templates"))

      File.write(File.join(dir, "config.toml"), <<-TOML
        title = "Nested Section Test"
        base_url = "http://localhost"
        TOML
      )
      File.write(File.join(dir, "templates", "page.html"), "<p>{{ content }}</p>")
      File.write(File.join(dir, "templates", "section.html"), "<div>{{ content }}</div>")

      File.write(File.join(dir, "content", "blog", "_index.md"), <<-MD
        ---
        title: Blog
        ---
        Blog index
        MD
      )
      File.write(File.join(dir, "content", "blog", "posts", "_index.md"), <<-MD
        ---
        title: Posts
        ---
        Posts section
        MD
      )
      File.write(File.join(dir, "content", "blog", "posts", "post1.md"), <<-MD
        ---
        title: Post One
        date: 2025-06-01
        ---
        Post one body
        MD
      )

      Dir.cd(dir) do
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new

        builder.run(options)

        blog_section_path = File.join(dir, "public", "blog", "index.html")
        posts_section_path = File.join(dir, "public", "blog", "posts", "index.html")
        post_path = File.join(dir, "public", "blog", "posts", "post1", "index.html")

        File.exists?(blog_section_path).should be_true
        File.exists?(posts_section_path).should be_true
        File.exists?(post_path).should be_true

        # Record mtimes to verify re-rendering
        blog_mtime_before = File.info(blog_section_path).modification_time
        posts_mtime_before = File.info(posts_section_path).modification_time

        # Modify post
        sleep 0.05.seconds
        File.write(File.join(dir, "content", "blog", "posts", "post1.md"), <<-MD
          ---
          title: Post One Updated
          date: 2025-06-01
          ---
          Post one UPDATED body
          MD
        )

        builder.run_incremental(["content/blog/posts/post1.md"], options)

        # Post should be updated
        File.read(post_path).should contain("Post one UPDATED body")

        # Both ancestor sections should be re-rendered
        blog_mtime_after = File.info(blog_section_path).modification_time
        posts_mtime_after = File.info(posts_section_path).modification_time

        blog_mtime_after.should be > blog_mtime_before
        posts_mtime_after.should be > posts_mtime_before
      end
    end
  end

  it "updates taxonomy pages when tags change during incremental build" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content", "posts"))
      FileUtils.mkdir_p(File.join(dir, "templates"))

      File.write(File.join(dir, "config.toml"), "title = \"Taxonomy Test\"\nbase_url = \"http://localhost\"\n\n[[taxonomies]]\nname = \"tags\"\n")
      File.write(File.join(dir, "templates", "page.html"), "<p>{{ content }}</p>")
      File.write(File.join(dir, "templates", "section.html"), "<div>{{ content }}</div>")

      File.write(File.join(dir, "content", "posts", "_index.md"), "---\ntitle: Posts\n---\n")
      File.write(File.join(dir, "content", "posts", "post1.md"), "---\ntitle: Tagged Post\ndate: \"2025-01-01\"\ntags:\n  - crystal\n  - web\n---\nTagged content\n")
      File.write(File.join(dir, "content", "posts", "post2.md"), "---\ntitle: Other Post\ndate: \"2025-01-02\"\ntags:\n  - crystal\n---\nOther content\n")

      Dir.cd(dir) do
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new

        builder.run(options)

        # Verify taxonomy pages exist
        File.exists?(File.join(dir, "public", "tags", "crystal", "index.html")).should be_true
        File.exists?(File.join(dir, "public", "tags", "web", "index.html")).should be_true

        # Change tags: remove "web", add "go"
        sleep 0.05.seconds
        File.write(File.join(dir, "content", "posts", "post1.md"), "---\ntitle: Tagged Post\ndate: \"2025-01-01\"\ntags:\n  - crystal\n  - go\n---\nUpdated tagged content\n")

        builder.run_incremental(["content/posts/post1.md"], options)

        # Updated content should appear
        File.read(File.join(dir, "public", "posts", "post1", "index.html")).should contain("Updated tagged content")

        # New tag page should be generated
        File.exists?(File.join(dir, "public", "tags", "go", "index.html")).should be_true
      end
    end
  end

  it "updates navigation prev/next when date changes during incremental build" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content", "posts"))
      FileUtils.mkdir_p(File.join(dir, "templates"))

      File.write(File.join(dir, "config.toml"), %(title = "Nav Test"\nbase_url = "http://localhost"\n))
      # Template that renders navigation links
      File.write(File.join(dir, "templates", "page.html"),
        "<p>{{ content }}</p>" \
        "{% if page.lower %}<a class=\"prev\" href=\"{{ page.lower.url }}\">{{ page.lower.title }}</a>{% endif %}" \
        "{% if page.higher %}<a class=\"next\" href=\"{{ page.higher.url }}\">{{ page.higher.title }}</a>{% endif %}")
      File.write(File.join(dir, "templates", "section.html"), "<div>{{ content }}</div>")

      File.write(File.join(dir, "content", "posts", "_index.md"), "---\ntitle: Posts\n---\n")
      # Alpha is oldest, Beta middle, Gamma newest
      # Dates must be quoted strings for YAML (unquoted dates become Time objects)
      File.write(File.join(dir, "content", "posts", "alpha.md"), "---\ntitle: Alpha\ndate: \"2025-01-01\"\n---\nAlpha content\n")
      File.write(File.join(dir, "content", "posts", "beta.md"), "---\ntitle: Beta\ndate: \"2025-01-02\"\n---\nBeta content\n")
      File.write(File.join(dir, "content", "posts", "gamma.md"), "---\ntitle: Gamma\ndate: \"2025-01-03\"\n---\nGamma content\n")

      Dir.cd(dir) do
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new

        builder.run(options)

        # Default sort is newest-first: [Gamma(Jan3), Beta(Jan2), Alpha(Jan1)]
        # lower=previous in sorted order, higher=next in sorted order
        # Beta (idx=1): lower=Gamma (idx=0), higher=Alpha (idx=2)
        beta_html = File.read(File.join(dir, "public", "posts", "beta", "index.html"))
        beta_html.should contain("class=\"prev\"")
        beta_html.should contain("Gamma")
        beta_html.should contain("class=\"next\"")
        beta_html.should contain("Alpha")

        # Now change Alpha's date to make it newest (after Gamma)
        sleep 0.05.seconds
        File.write(File.join(dir, "content", "posts", "alpha.md"), "---\ntitle: Alpha\ndate: \"2025-01-10\"\n---\nAlpha updated\n")

        builder.run_incremental(["content/posts/alpha.md"], options)

        # After re-linking, sort: [Alpha(Jan10), Gamma(Jan3), Beta(Jan2)]
        # Beta (idx=2): lower=Gamma (idx=1), higher=nil (last element)
        beta_html_after = File.read(File.join(dir, "public", "posts", "beta", "index.html"))
        beta_html_after.should contain("class=\"prev\"")
        beta_html_after.should contain("Gamma")
        # Alpha is no longer Beta's next neighbor
        beta_html_after.should_not contain("class=\"next\"")
      end
    end
  end

  it "handles page entering/leaving a series during incremental build" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content", "posts"))
      FileUtils.mkdir_p(File.join(dir, "templates"))

      File.write(File.join(dir, "config.toml"), %(title = "Series Test"\nbase_url = "http://localhost"\n\n[series]\nenabled = true\n))
      File.write(File.join(dir, "templates", "page.html"),
        "<p>{{ content }}</p>" \
        "{% if page.series != \"\" %}<span class=\"series\">{{ page.series }}</span>{% endif %}" \
        "{% if page.series_index > 0 %}<span class=\"idx\">{{ page.series_index }}</span>{% endif %}")
      File.write(File.join(dir, "templates", "section.html"), "<div>{{ content }}</div>")

      File.write(File.join(dir, "content", "posts", "_index.md"), "---\ntitle: Posts\n---\n")
      File.write(File.join(dir, "content", "posts", "part1.md"), "---\ntitle: Part 1\ndate: \"2025-01-01\"\nseries: my-series\nseries_weight: 1\n---\nPart 1 content\n")
      File.write(File.join(dir, "content", "posts", "part2.md"), "---\ntitle: Part 2\ndate: \"2025-01-02\"\nseries: my-series\nseries_weight: 2\n---\nPart 2 content\n")

      Dir.cd(dir) do
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new

        builder.run(options)

        # Verify series is rendered
        part1_html = File.read(File.join(dir, "public", "posts", "part1", "index.html"))
        part1_html.should contain("my-series")
        part1_html.should contain("<span class=\"idx\">1</span>")

        # Remove part1 from the series
        sleep 0.05.seconds
        File.write(File.join(dir, "content", "posts", "part1.md"), "---\ntitle: Part 1\ndate: \"2025-01-01\"\n---\nPart 1 no longer in series\n")

        builder.run_incremental(["content/posts/part1.md"], options)

        # Part1 should no longer show series
        part1_after = File.read(File.join(dir, "public", "posts", "part1", "index.html"))
        part1_after.should_not contain("my-series")

        # Part2 should be updated (series_index changes since part1 left)
        part2_after = File.read(File.join(dir, "public", "posts", "part2", "index.html"))
        part2_after.should contain("my-series")
        part2_after.should contain("<span class=\"idx\">1</span>")
      end
    end
  end

  it "updates related_posts when a page gains new taxonomy terms" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content", "posts"))
      FileUtils.mkdir_p(File.join(dir, "templates"))

      File.write(File.join(dir, "config.toml"), %(title = "Related Test"\nbase_url = "http://localhost"\ntaxonomies = ["tags"]\n\n[related]\nenabled = true\nlimit = 5\ntaxonomies = ["tags"]\n))
      File.write(File.join(dir, "templates", "page.html"),
        "<p>{{ content }}</p>" \
        "{% for rp in page.related_posts %}<a class=\"related\" href=\"{{ rp.url }}\">{{ rp.title }}</a>{% endfor %}")
      File.write(File.join(dir, "templates", "section.html"), "<div>{{ content }}</div>")

      File.write(File.join(dir, "content", "posts", "_index.md"), "---\ntitle: Posts\n---\n")
      File.write(File.join(dir, "content", "posts", "post1.md"), "---\ntitle: Post One\ndate: \"2025-01-01\"\ntags:\n  - rust\n---\nPost one content\n")
      File.write(File.join(dir, "content", "posts", "post2.md"), "---\ntitle: Post Two\ndate: \"2025-01-02\"\ntags:\n  - go\n---\nPost two content\n")
      File.write(File.join(dir, "content", "posts", "post3.md"), "---\ntitle: Post Three\ndate: \"2025-01-03\"\ntags:\n  - go\n---\nPost three content\n")

      Dir.cd(dir) do
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new

        builder.run(options)

        # Post1 has "rust" tag, no related posts with go-tagged posts
        post1_html = File.read(File.join(dir, "public", "posts", "post1", "index.html"))
        post1_html.should_not contain("Post Two")
        post1_html.should_not contain("Post Three")

        # Now add "go" tag to post1 — should become related to post2 and post3
        sleep 0.05.seconds
        File.write(File.join(dir, "content", "posts", "post1.md"), "---\ntitle: Post One\ndate: \"2025-01-01\"\ntags:\n  - rust\n  - go\n---\nPost one updated\n")

        builder.run_incremental(["content/posts/post1.md"], options)

        # Post1 should now list post2 and post3 as related
        post1_after = File.read(File.join(dir, "public", "posts", "post1", "index.html"))
        post1_after.should contain("Post Two")
        post1_after.should contain("Post Three")

        # Post2 should now list post1 as related (newly-related page)
        post2_after = File.read(File.join(dir, "public", "posts", "post2", "index.html"))
        post2_after.should contain("Post One")
      end
    end
  end

  it "re-renders with updated template via run_rerender" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content"))
      FileUtils.mkdir_p(File.join(dir, "templates"))

      File.write(File.join(dir, "config.toml"), <<-TOML
        title = "Rerender Test"
        base_url = "http://localhost"
        TOML
      )
      File.write(File.join(dir, "templates", "page.html"), "<old>{{ content }}</old>")
      File.write(File.join(dir, "content", "hello.md"), <<-MD
        ---
        title: Hello
        ---
        Hello world
        MD
      )

      Dir.cd(dir) do
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new

        builder.run(options)

        output_path = File.join(dir, "public", "hello", "index.html")
        File.read(output_path).should contain("<old>")

        # Update template
        File.write(File.join(dir, "templates", "page.html"), "<new>{{ content }}</new>")

        builder.run_rerender(options)

        updated = File.read(output_path)
        updated.should contain("<new>")
        updated.should_not contain("<old>")
        # Content itself is preserved (not re-parsed)
        updated.should contain("Hello world")
      end
    end
  end
end

describe Hwaro::Services::LiveReloadInjectHandler do
  it "injects script before </body>" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.html"), "<html><body><p>Hello</p></body></html>")

      handler = Hwaro::Services::LiveReloadInjectHandler.new(dir)
      dummy = DummyHandler.new
      handler.next = dummy

      request = HTTP::Request.new("GET", "/test.html")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)
      response.close

      io.rewind
      content = io.to_s
      content.should contain("__hwaro_livereload")
      content.should contain("location.reload()")
      # Script should be before </body>
      script_pos = content.index!("__hwaro_livereload")
      body_pos = content.rindex!("</body>")
      script_pos.should be < body_pos
      dummy.called.should be_false
    end
  end

  it "appends script when no </body> exists" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.html"), "<p>Simple content</p>")

      handler = Hwaro::Services::LiveReloadInjectHandler.new(dir)
      dummy = DummyHandler.new
      handler.next = dummy

      request = HTTP::Request.new("GET", "/test.html")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)
      response.close

      io.rewind
      content = io.to_s
      content.should contain("__hwaro_livereload")
      content.should contain("<p>Simple content</p>")
      dummy.called.should be_false
    end
  end

  it "passes non-HTML requests through" do
    Dir.mktmpdir do |dir|
      handler = Hwaro::Services::LiveReloadInjectHandler.new(dir)
      dummy = DummyHandler.new
      handler.next = dummy

      request = HTTP::Request.new("GET", "/style.css")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      dummy.called.should be_true
    end
  end
end

# Helper for LiveReloadHandler specs: builds a request targeting the
# live reload endpoint with optional Origin/Host headers.
private def build_ws_request(origin : String?, host : String?)
  headers = HTTP::Headers.new
  headers["Origin"] = origin if origin
  headers["Host"] = host if host
  HTTP::Request.new("GET", Hwaro::Services::LiveReloadHandler::LIVE_RELOAD_PATH, headers)
end

private def make_context(request : HTTP::Request)
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  {HTTP::Server::Context.new(request, response), io}
end

# Marker emitted by LiveReloadHandler when it rejects an Origin. Asserting on
# this (rather than "not 403") proves the rejection branch was NOT taken,
# since the WS handshake would also produce non-403 errors for unrelated
# reasons (missing Upgrade headers, etc.).
private ORIGIN_REJECT_MARKER = "Forbidden: invalid origin"

describe Hwaro::Services::LiveReloadHandler do
  it "passes non-matching paths through" do
    handler = Hwaro::Services::LiveReloadHandler.new
    dummy = DummyHandler.new
    handler.next = dummy

    request = HTTP::Request.new("GET", "/index.html")
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)

    handler.call(context)

    dummy.called.should be_true
  end

  describe "Origin validation (CSWSH protection)" do
    it "rejects mismatched Origin with 403" do
      handler = Hwaro::Services::LiveReloadHandler.new
      dummy = DummyHandler.new
      handler.next = dummy

      request = build_ws_request("http://evil.example.com", "localhost:3000")
      context, io = make_context(request)

      handler.call(context)
      context.response.close

      context.response.status_code.should eq(403)
      io.to_s.should contain(ORIGIN_REJECT_MARKER)
      dummy.called.should be_false
    end

    it "rejects Origin on a different host (cross-origin)" do
      handler = Hwaro::Services::LiveReloadHandler.new
      request = build_ws_request("http://attacker.com", "example.com:3000")
      context, io = make_context(request)

      handler.call(context)
      context.response.close

      context.response.status_code.should eq(403)
      io.to_s.should contain(ORIGIN_REJECT_MARKER)
    end

    it "allows Origin whose host matches the server Host header" do
      handler = Hwaro::Services::LiveReloadHandler.new
      request = build_ws_request("http://example.com", "example.com:3000")
      context, io = make_context(request)

      handler.call(context)
      context.response.close

      # Origin validation must NOT reject. WS handshake fails for unrelated
      # reasons (missing Upgrade headers), so asserting the rejection marker
      # is absent is a tighter check than "status != 403".
      io.to_s.should_not contain(ORIGIN_REJECT_MARKER)
    end

    it "always allows localhost origin" do
      handler = Hwaro::Services::LiveReloadHandler.new
      request = build_ws_request("http://localhost:8080", "127.0.0.1:3000")
      context, io = make_context(request)

      handler.call(context)
      context.response.close

      io.to_s.should_not contain(ORIGIN_REJECT_MARKER)
    end

    it "always allows 127.0.0.1 origin" do
      handler = Hwaro::Services::LiveReloadHandler.new
      request = build_ws_request("http://127.0.0.1:8080", "example.com:3000")
      context, io = make_context(request)

      handler.call(context)
      context.response.close

      io.to_s.should_not contain(ORIGIN_REJECT_MARKER)
    end

    it "always allows ::1 origin" do
      handler = Hwaro::Services::LiveReloadHandler.new
      request = build_ws_request("http://[::1]:8080", "example.com:3000")
      context, io = make_context(request)

      handler.call(context)
      context.response.close

      io.to_s.should_not contain(ORIGIN_REJECT_MARKER)
    end

    it "allows request when Origin header is absent (non-browser client)" do
      handler = Hwaro::Services::LiveReloadHandler.new
      request = build_ws_request(nil, "localhost:3000")
      context, io = make_context(request)

      handler.call(context)
      context.response.close

      io.to_s.should_not contain(ORIGIN_REJECT_MARKER)
    end

    it "allows request when Host header is absent" do
      handler = Hwaro::Services::LiveReloadHandler.new
      request = build_ws_request("http://evil.example.com", nil)
      context, io = make_context(request)

      handler.call(context)
      context.response.close

      io.to_s.should_not contain(ORIGIN_REJECT_MARKER)
    end
  end

  describe "#notify_reload" do
    it "does not raise when there are no connected sockets" do
      handler = Hwaro::Services::LiveReloadHandler.new
      handler.notify_reload
    end
  end
end

describe Hwaro::Services::LiveReloadInjectHandler, "#inject_script" do
  it "injects before the LAST </body> when multiple appear in content" do
    handler = Hwaro::Services::LiveReloadInjectHandler.new(".")
    html = "<html><body><pre>&lt;/body&gt; literal</pre><div>sentinel</body>trailing</body></html>"
    result = handler.inject_script(html)

    # Script must appear before the final </body>, not any earlier one
    script_pos = result.index!("__hwaro_livereload")
    last_body = result.rindex!("</body>")
    script_pos.should be < last_body

    # An earlier literal </body> should precede the injected script
    first_body = result.index!("</body>")
    first_body.should be < script_pos
  end

  it "appends script when no </body> tag exists" do
    handler = Hwaro::Services::LiveReloadInjectHandler.new(".")
    result = handler.inject_script("<p>hi</p>")
    result.should end_with(Hwaro::Services::LiveReloadInjectHandler::LIVE_RELOAD_SCRIPT)
  end
end

describe Hwaro::Services::LiveReloadInjectHandler, "path sanitization" do
  it "passes through when path escapes public_dir via traversal" do
    Dir.mktmpdir do |dir|
      # Put an HTML file OUTSIDE public_dir that traversal would try to hit
      outside = File.join(dir, "outside.html")
      File.write(outside, "<html><body>SECRET</body></html>")

      public_dir = File.join(dir, "public")
      FileUtils.mkdir_p(public_dir)

      handler = Hwaro::Services::LiveReloadInjectHandler.new(public_dir)
      dummy = DummyHandler.new
      handler.next = dummy

      request = HTTP::Request.new("GET", "/../outside.html")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      # Must not serve the outside file; delegate to next handler instead,
      # and must not have written the injected script to the response.
      dummy.called.should be_true
      io.to_s.should_not contain("SECRET")
      io.to_s.should_not contain("__hwaro_livereload")
    end
  end

  it "passes through when the requested HTML file does not exist" do
    Dir.mktmpdir do |dir|
      handler = Hwaro::Services::LiveReloadInjectHandler.new(dir)
      dummy = DummyHandler.new
      handler.next = dummy

      request = HTTP::Request.new("GET", "/missing.html")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      dummy.called.should be_true
    end
  end
end

# Regression: when bind_tcp fails (port conflict), `hwaro serve` used
# to print "Serving site at …", "Live reload enabled", and the watcher
# fiber would emit "Watching for changes …" — all *before* the final
# "Could not bind" error surfaced, suggesting the server was up when
# it wasn't. The fix reorders bind to happen before any banner, and
# spawns the watcher fiber only after bind succeeds.
describe "watcher ignore patterns" do
  # Regression: `sed -i.bak`, vim's default `.swp` files, emacs
  # lock/autosave files, and `.DS_Store` used to show up as watcher
  # events — each one counted as an added/removed file and forced a
  # `:full` rebuild. Now the watcher drops them before scan_mtimes
  # records anything.

  {
    ".bak backup"           => "note.md.bak",
    "vim swap"              => ".note.md.swp",
    "trailing-tilde backup" => "note.md~",
    "emacs lock file"       => ".#note.md",
    "emacs autosave"        => "#note.md#",
    ".DS_Store"             => ".DS_Store",
    ".tmp atomic-save file" => "page.html.tmp",
    "VS Code crswap"        => "page.html.crswap",
    "JetBrains safe write"  => "page.html___jb_tmp___",
    "JetBrains old backup"  => "page.html___jb_old___",
    "gedit atomic save"     => ".goutputstream-4XQ2K1",
    "vim write probe"       => "4913",
  }.each do |label, name|
    it "ignores #{label} (#{name})" do
      Hwaro::Services::Server.test_watcher_ignored?(name).should be_true
      Hwaro::Services::Server.test_watcher_ignored?(File.join("content", "posts", name)).should be_true
    end
  end

  it "does NOT ignore regular content files" do
    [
      "index.md",
      "about.md",
      "posts/hello-world.md",
      "templates/page.html",
      "static/css/style.css",
    ].each do |path|
      Hwaro::Services::Server.test_watcher_ignored?(path).should be_false
    end
  end

  it "does NOT ignore files that merely contain a tilde or hash inside" do
    # Bare tildes/hashes inside the basename are fine — only the
    # specific editor-byproduct shapes (trailing ~, wrapping #…#,
    # leading .#) should be dropped.
    Hwaro::Services::Server.test_watcher_ignored?("notes-for-~user.md").should be_false
    Hwaro::Services::Server.test_watcher_ignored?("tag-#python.md").should be_false
  end

  it "does NOT ignore files that merely resemble atomic-save byproducts" do
    # "tmp" inside a name (or as a stem) is fine — only the trailing
    # `.tmp` extension is a save byproduct. Same for a numeric name that
    # isn't exactly vim's `4913` probe.
    Hwaro::Services::Server.test_watcher_ignored?("tmp.html").should be_false
    Hwaro::Services::Server.test_watcher_ignored?("templates/tmpl.html").should be_false
    Hwaro::Services::Server.test_watcher_ignored?("content/posts/14913.md").should be_false
    Hwaro::Services::Server.test_watcher_ignored?("static/img/4913.png").should be_false
  end

  it "excludes matched files from scan_mtimes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("content/posts")
        File.write("content/posts/hello.md", "real")
        File.write("content/posts/hello.md.bak", "backup")
        File.write("content/posts/.hello.md.swp", "swap")
        File.write("content/posts/.DS_Store", "apple")

        mtimes = Hwaro::Services::Server.new.test_scan_mtimes
        mtimes.keys.should contain("content/posts/hello.md")
        mtimes.keys.should_not contain("content/posts/hello.md.bak")
        mtimes.keys.should_not contain("content/posts/.hello.md.swp")
        mtimes.keys.should_not contain("content/posts/.DS_Store")
      end
    end
  end
end

describe "bind failure handling" do
  it "raises HwaroError(HWARO_E_IO) when the port is already in use" do
    Dir.mktmpdir do |project_dir|
      Dir.cd(project_dir) do
        File.write("config.toml", "title = \"Test\"\nbase_url = \"http://localhost:3000\"\n")
        FileUtils.mkdir_p("content")
        File.write("content/index.md", "---\ntitle: Home\n---\nHello")

        # Grab a free port, then hold it so the Server tries to bind onto it.
        occupied = TCPServer.new("127.0.0.1", 0)
        port = occupied.local_address.port

        build_options = Hwaro::Config::Options::BuildOptions.new

        buffer = IO::Memory.new
        previous_io = Hwaro::Logger.io
        Hwaro::Logger.io = buffer
        # Force plain output so the serve-receipt markers are deterministic.
        Hwaro::Logger.color_enabled = false

        begin
          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::Services::Server.new.test_run_with_options(
              "127.0.0.1", port, false, false, true, build_options, false,
            )
          end

          err.code.should eq(Hwaro::Errors::HWARO_E_IO)
          err.exit_code.should eq(Hwaro::Errors::EXIT_IO)
          (err.message || "").downcase.should contain("bind")

          # The serve receipt (heading + ready line) is printed only AFTER a
          # successful bind, so a bind failure must show none of it.
          output = buffer.to_s
          output.should_not contain("hwaro: serve")
          output.should_not contain("ready: Ctrl+C to stop")
          output.should_not contain("reload:")
        ensure
          Hwaro::Logger.io = previous_io
          Hwaro::Logger.color_enabled = nil
          occupied.close
        end
      end
    end
  end
end
