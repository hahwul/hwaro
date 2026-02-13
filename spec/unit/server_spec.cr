require "../spec_helper"
require "../../src/services/server/server"

# Reopen Server to test private methods
module Hwaro
  module Services
    class Server
      def test_sanitize_output_dir(dir : String)
        sanitize_output_dir(dir)
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
