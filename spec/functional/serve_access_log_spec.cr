require "../spec_helper"
require "../../src/services/server/server"
require "http/client"
require "socket"

# Regression coverage for a `hwaro serve --access-log` defect: the log
# reported a path the client never sent. IndexRewriteHandler rewrites `/` to
# `/index.html` so the static handler can find the file, but it never put the
# request back — and `HTTP::LogHandler` sits outermost and reads
# `request.resource` AFTER call_next. Every directory request was therefore
# logged as its index file, so the access log could not be correlated with the
# browser's own network panel. (BasePathHandler already restores its strip for
# exactly this reason; nothing was undoing this rewrite.)
#
# Reopened with prefixed names so they cannot collide with the shims other
# server specs install.
module Hwaro
  module Services
    class Server
      def access_log_build_handlers(output_dir : String) : Array(HTTP::Handler)
        build_handlers(output_dir, "127.0.0.1", false, true, {} of String => String, "")
      end
    end
  end
end

# Stands in for `HTTP::LogHandler`: same position (outermost) and the same
# read — `request.resource` after `call_next` has returned.
private class ResourceProbeHandler
  include HTTP::Handler

  getter seen = [] of String

  def call(context)
    call_next(context)
  ensure
    @seen << context.request.resource
  end
end

private def with_logging_dev_server(&)
  Dir.mktmpdir do |dir|
    FileUtils.mkdir_p(File.join(dir, "about"))
    File.write(File.join(dir, "index.html"), "<html><body>HOME</body></html>")
    File.write(File.join(dir, "404.html"), "<html><body>NOT FOUND</body></html>")
    File.write(File.join(dir, "about", "index.html"), "<html><body>ABOUT</body></html>")
    File.write(File.join(dir, "robots.txt"), "User-agent: *\n")

    Hwaro::Services::Server.register_utf8_mime_types
    probe = ResourceProbeHandler.new
    handlers = [probe.as(HTTP::Handler)]
    handlers.concat(Hwaro::Services::Server.new.access_log_build_handlers(dir))
    server = Hwaro::Services::DevHTTPServer.new(handlers)
    address = server.bind_unused_port("127.0.0.1")
    spawn { server.listen }
    until server.listening?
      Fiber.yield
    end

    begin
      yield address.port, probe
    ensure
      server.close
    end
  end
end

private def access_log_get(port : Int32, path : String) : HTTP::Client::Response
  client = HTTP::Client.new("127.0.0.1", port)
  client.read_timeout = 5.seconds
  client.connect_timeout = 2.seconds
  begin
    client.get(path)
  ensure
    client.close
  end
end

describe "hwaro serve access log fidelity" do
  it "logs the request path the client sent, not the rewritten index file" do
    with_logging_dev_server do |port, probe|
      access_log_get(port, "/").status_code.should eq(200)
      access_log_get(port, "/about/").status_code.should eq(200)

      probe.seen.should eq(["/", "/about/"])
    end
  end

  it "keeps the query string on a rewritten directory request" do
    with_logging_dev_server do |port, probe|
      access_log_get(port, "/?q=hwaro+serve").status_code.should eq(200)

      probe.seen.should eq(["/?q=hwaro+serve"])
    end
  end

  it "leaves non-directory requests untouched" do
    with_logging_dev_server do |port, probe|
      access_log_get(port, "/robots.txt").status_code.should eq(200)
      access_log_get(port, "/about").status_code.should eq(302)
      access_log_get(port, "/missing").status_code.should eq(404)

      probe.seen.should eq(["/robots.txt", "/about", "/missing"])
    end
  end
end
