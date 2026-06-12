require "../spec_helper"
require "../../src/services/server/live_reload_handler"

# Runs the handler against a synthetic livereload request carrying the given
# Origin (no real server needed) and returns the response status code.
private def livereload_status_for_origin(origin : String) : Int32
  headers = HTTP::Headers{"Origin" => origin, "Host" => "localhost:1313"}
  request = HTTP::Request.new("GET", Hwaro::Services::LiveReloadHandler::LIVE_RELOAD_PATH, headers)
  response = HTTP::Server::Response.new(IO::Memory.new)
  context = HTTP::Server::Context.new(request, response)
  Hwaro::Services::LiveReloadHandler.new.call(context)
  context.response.status_code
end

describe Hwaro::Services::LiveReloadInjectHandler do
  describe "#inject_script" do
    it "injects script before </body>" do
      handler = Hwaro::Services::LiveReloadInjectHandler.new("/tmp/public")
      html = "<html><body><p>Hello</p></body></html>"

      result = handler.inject_script(html)
      result.should contain("__hwaro_livereload")
      result.should contain("</body>")
      # Script should appear before </body>
      script_idx = result.index!("__hwaro_livereload")
      body_idx = result.index!("</body>")
      script_idx.should be < body_idx
    end

    it "appends script when no </body> tag exists" do
      handler = Hwaro::Services::LiveReloadInjectHandler.new("/tmp/public")
      html = "<p>No body tag</p>"

      result = handler.inject_script(html)
      result.should contain("__hwaro_livereload")
      result.should start_with("<p>No body tag</p>")
    end

    it "includes WebSocket reconnection logic" do
      handler = Hwaro::Services::LiveReloadInjectHandler.new("/tmp/public")
      result = handler.inject_script("<body></body>")

      result.should contain("WebSocket")
      result.should contain("reconnectDelay")
      result.should contain("location.reload()")
    end

    it "ships the build-error overlay branch in the client script" do
      handler = Hwaro::Services::LiveReloadInjectHandler.new("/tmp/public")
      result = handler.inject_script("<body></body>")

      # Client must dispatch on the three message shapes the server sends.
      result.should contain("'reload'")
      result.should contain("'clear-error'")
      result.should contain("'error:'")
      # And actually render an overlay node + clean it up.
      result.should contain("__hwaro_build_error__")
      result.should contain("Build failed")
    end
  end
end

describe Hwaro::Services::LiveReloadHandler do
  it "defines the livereload path constant" do
    Hwaro::Services::LiveReloadHandler::LIVE_RELOAD_PATH.should eq("/__hwaro_livereload")
  end

  # The handler tracks the latest unresolved build error so a tab
  # opened mid-failure replays the overlay on connect. These tests
  # exercise the state-machine transitions without spinning up the
  # full HTTP server (the broadcast itself is best-effort over live
  # WebSocket connections, which we don't fixture here).
  describe "build-error state machine" do
    it "starts with no current error" do
      handler = Hwaro::Services::LiveReloadHandler.new
      handler.@current_error.should be_nil
    end

    it "stores the message on notify_build_error" do
      handler = Hwaro::Services::LiveReloadHandler.new
      handler.notify_build_error("Template error: unterminated tag")
      handler.@current_error.should eq("Template error: unterminated tag")
    end

    it "clears the error on notify_reload (successful rebuild)" do
      handler = Hwaro::Services::LiveReloadHandler.new
      handler.notify_build_error("boom")
      handler.notify_reload
      handler.@current_error.should be_nil
    end

    it "clears the error on notify_clear_error" do
      handler = Hwaro::Services::LiveReloadHandler.new
      handler.notify_build_error("boom")
      handler.notify_clear_error
      handler.@current_error.should be_nil
    end

    it "overwrites the previous error so only the latest is replayed" do
      handler = Hwaro::Services::LiveReloadHandler.new
      handler.notify_build_error("first")
      handler.notify_build_error("second")
      handler.@current_error.should eq("second")
    end
  end

  describe "Origin validation" do
    it "rejects an unparseable Origin with 403 instead of raising" do
      # URI.parse raises on inputs like an oversized port; the handler must
      # fail closed, not crash. (This used to raise OverflowError.)
      livereload_status_for_origin("http://localhost:999999999999").should eq(403)
    end

    it "rejects a cross-site Origin with 403" do
      livereload_status_for_origin("http://evil.example.com").should eq(403)
    end

    it "rejects a request with no Origin header with 403 (fail closed)" do
      # A browser always sends Origin on a WebSocket handshake; an absent
      # Origin means a non-browser or crafted request. The handler must
      # reject it rather than skip validation entirely.
      headers = HTTP::Headers{"Host" => "localhost:1313"}
      request = HTTP::Request.new("GET", Hwaro::Services::LiveReloadHandler::LIVE_RELOAD_PATH, headers)
      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(request, response)
      Hwaro::Services::LiveReloadHandler.new.call(context)
      context.response.status_code.should eq(403)
    end
  end
end
