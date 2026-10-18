require "../../../spec_helper"
require "../../../../src/services/server/server"

module Hwaro
  module Services
    class Server
      def handlers_spec_chain(output_dir : String) : HTTP::Handler
        HTTP::Server.build_middleware(build_handlers(output_dir, "127.0.0.1", false, false, {} of String => String, ""))
      end
    end
  end
end

private def handlers_spec_get(chain : HTTP::Handler, path : String) : Int32
  response = HTTP::Server::Response.new(IO::Memory.new)
  chain.call(HTTP::Server::Context.new(HTTP::Request.new("GET", path), response))
  response.status_code
end

# On a case-insensitive file system (macOS, Windows) `/About/` resolved to
# `about/` and served 200; every case-sensitive static host answers 404.
describe "CaseMismatchHandler" do
  it "answers 404 for a path whose on-disk spelling differs only in case" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "about"))
      File.write(File.join(dir, "about", "index.html"), "about")
      File.write(File.join(dir, "logo.png"), "png")
      chain = Hwaro::Services::Server.new.handlers_spec_chain(dir)

      handlers_spec_get(chain, "/about/").should eq(200)
      handlers_spec_get(chain, "/logo.png").should eq(200)
      handlers_spec_get(chain, "/About/").should eq(404)
      handlers_spec_get(chain, "/About").should eq(404)
      handlers_spec_get(chain, "/about/Index.html").should eq(404)
      handlers_spec_get(chain, "/LOGO.png").should eq(404)
    end
  end
end
