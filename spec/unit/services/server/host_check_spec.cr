require "../../../spec_helper"
require "../../../../src/services/server/server"

module Hwaro
  module Services
    class Server
      def host_check_chain(output_dir : String, allow_hosts : Array(String) = [] of String) : HTTP::Handler
        HTTP::Server.build_middleware(build_handlers(output_dir, "127.0.0.1", false, true, {} of String => String, "", allow_hosts))
      end
    end
  end
end

private def host_check_get(chain : HTTP::Handler, path : String, host : String?, extra : Hash(String, String) = {} of String => String) : Int32
  headers = HTTP::Headers.new
  headers["Host"] = host if host
  extra.each { |k, v| headers[k] = v }
  response = HTTP::Server::Response.new(IO::Memory.new)
  chain.call(HTTP::Server::Context.new(HTTP::Request.new("GET", path, headers), response))
  response.status_code
end

# DNS rebinding: a page on a name the attacker controls re-points it at
# 127.0.0.1 and then reads the dev server (drafts, build errors) as
# same-origin. Neither CORS nor the WebSocket Origin check helps — both
# compare against the attacker's own Host — so the Host itself is checked.
describe "HostCheckHandler" do
  it "refuses a Host name the developer did not choose, everywhere in the chain" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "index.html"), "<html><body>draft</body></html>")
      chain = Hwaro::Services::Server.new.host_check_chain(dir)

      host_check_get(chain, "/index.html", "attacker.example").should eq(403)
      host_check_get(chain, "/index.html", "attacker.example:3000").should eq(403)
      host_check_get(chain, "/index.html", "127.0.0.1.attacker.example").should eq(403)
      host_check_get(chain, "/index.html", "localhost.attacker.example").should eq(403)
      ws_headers = {"Origin" => "http://attacker.example"}
      host_check_get(chain, "/__hwaro_livereload", "attacker.example", ws_headers).should eq(403)
    end
  end

  it "answers loopback names, IP literals, a missing Host and the base_url host" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "index.html"), "<html><body>ok</body></html>")
      chain = Hwaro::Services::Server.new.host_check_chain(dir, ["myapp.example.dev"])

      ["127.0.0.1:3000", "localhost:3000", "LOCALHOST.", "foo.localhost", "[::1]:3000",
       "192.168.1.20:3000", "myapp.example.dev", "MyApp.Example.Dev:443"].each do |host|
        host_check_get(chain, "/index.html", host).should eq(200)
      end
      host_check_get(chain, "/index.html", nil).should eq(200)
    end
  end

  it "supports suffix patterns and a wildcard opt-out" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "index.html"), "ok")
      suffix = Hwaro::Services::Server.new.host_check_chain(dir, ["*.tunnel.example"])
      host_check_get(suffix, "/index.html", "abc.tunnel.example").should eq(200)
      host_check_get(suffix, "/index.html", "tunnel.example.attacker.example").should eq(403)

      any = Hwaro::Services::Server.new.host_check_chain(dir, ["*"])
      host_check_get(any, "/index.html", "attacker.example").should eq(200)
    end
  end
end
