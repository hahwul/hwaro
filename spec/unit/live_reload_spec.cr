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
  end
end

describe Hwaro::Services::LiveReloadHandler do
  it "defines the livereload path constant" do
    Hwaro::Services::LiveReloadHandler::LIVE_RELOAD_PATH.should eq("/__hwaro_livereload")
  end
end
