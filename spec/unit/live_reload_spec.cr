require "../spec_helper"
require "../../src/services/server/live_reload_handler"

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
end
