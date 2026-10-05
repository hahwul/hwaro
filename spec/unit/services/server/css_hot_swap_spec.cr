require "../../../spec_helper"
require "../../../../src/services/server/server"

# CSS hot-swap: a rebuild that changed only stylesheets pushes `css:<json>`
# to clients that opted in, instead of `reload`.

module Hwaro
  module Services
    class Server
      def css_swap_spec_paths(changeset : ChangeSet) : Array(String)?
        css_swap_paths(changeset)
      end

      # Initial build, then one watcher rebuild, pushing into `handler`.
      def css_swap_spec_apply(changeset : ChangeSet, options : Config::Options::BuildOptions, handler : LiveReloadHandler)
        @live_reload_handler = handler
        run_full_build(options)
        apply_changeset(changeset, options)
      end
    end

    class LiveReloadHandler
      def css_swap_spec_register(socket : HTTP::WebSocket, css_swap : Bool)
        register_client(socket)
        @sockets_mutex.synchronize { @clients.last.css_swap = css_swap }
      end

      # Every queued message, connect-time replay included, per client.
      def css_swap_spec_queued : Array(Array(String))
        @clients.map do |client|
          messages = [] of String
          loop do
            select
            when message = client.queue.receive
              messages << message
            else
              break
            end
          end
          messages
        end
      end
    end
  end
end

private class CssSwapRecordingHandler < Hwaro::Services::LiveReloadHandler
  getter pushes = [] of String

  def notify_reload
    @pushes << "reload"
  end

  def notify_css(paths : Array(String))
    @pushes << "css:#{paths.to_json}"
  end
end

# A socket whose writes park forever, so queued messages stay in the queue
# for the spec to read back.
private class CssSwapParkedIO < IO
  @gate = Channel(Nil).new

  def read(slice : Bytes) : Int32
    @gate.receive
    0
  end

  def write(slice : Bytes) : Nil
    @gate.receive
  end
end

private def css_changeset(static : Array(String)) : Hwaro::Services::ChangeSet
  Hwaro::Services::ChangeSet.new(
    modified_content: [] of String,
    modified_templates: [] of String,
    modified_static: static,
    added_files: [] of String,
    removed_files: [] of String,
    config_changed: false,
  )
end

private def css_swap_push(static : Array(String), template = %(<link rel="stylesheet" href="/css/a.css">{{ content }})) : Array(String)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      File.write("config.toml", %(title = "t"\nbase_url = "http://localhost"\n))
      Dir.mkdir_p("content")
      File.write("content/index.md", "+++\ntitle = \"Home\"\n+++\nhi\n")
      Dir.mkdir_p("templates")
      {"page.html", "section.html", "index.html"}.each { |name| File.write("templates/#{name}", template) }
      Dir.mkdir_p("static/css")
      Dir.mkdir_p("static/js")
      File.write("static/css/a.css", "body{}")
      File.write("static/js/app.js", "1")

      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
      handler = CssSwapRecordingHandler.new
      Hwaro::Services::Server.new.css_swap_spec_apply(css_changeset(static), options, handler)
      handler.pushes
    end
  end
end

describe "CSS hot-swap" do
  describe "ChangeSet#css_only?" do
    it "is true for stylesheet sources only" do
      css_changeset(["static/css/a.css", "static/scss/main.scss", "static/B.CSS"]).css_only?.should be_true
    end

    it "is false when anything else rides along" do
      css_changeset(["static/css/a.css", "static/js/app.js"]).css_only?.should be_false
      css_changeset(["static/img/a.png"]).css_only?.should be_false
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: ["templates/page.html"],
        modified_static: ["static/css/a.css"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.css_only?.should be_false
    end
  end

  describe "Server#css_swap_paths" do
    it "maps plain static stylesheets to their URL paths" do
      Hwaro::Services::Server.new.css_swap_spec_paths(css_changeset(["static/css/a.css", "static/b.css"]))
        .should eq(["/css/a.css", "/b.css"])
    end

    it "falls back to every stylesheet when a source does not publish 1:1" do
      Hwaro::Services::Server.new.css_swap_spec_paths(css_changeset(["static/css/a.css", "static/scss/main.scss"]))
        .should eq([] of String)
    end

    it "is nil for a non-stylesheet change" do
      Hwaro::Services::Server.new.css_swap_spec_paths(css_changeset(["static/js/app.js"])).should be_nil
    end
  end

  describe "apply_changeset" do
    it "pushes css for a stylesheet-only save" do
      css_swap_push(["static/css/a.css"]).should eq([%(css:["/css/a.css"])])
    end

    it "reloads when anything besides a stylesheet changed" do
      css_swap_push(["static/js/app.js"]).should eq(["reload"])
      css_swap_push(["static/css/a.css", "static/js/app.js"]).should eq(["reload"])
    end

    it "reloads when the stylesheet save rebuilt the pages" do
      template = %({# load_data(path="static/css/a.css") #}{{ content }})
      css_swap_push(["static/css/a.css"], template).should eq(["reload"])
    end
  end

  describe "LiveReloadHandler#notify_css" do
    it "sends css only to clients that opted in, reload to the rest" do
      handler = Hwaro::Services::LiveReloadHandler.new
      handler.css_swap_spec_register(HTTP::WebSocket.new(CssSwapParkedIO.new), css_swap: true)
      handler.css_swap_spec_register(HTTP::WebSocket.new(CssSwapParkedIO.new), css_swap: false)
      handler.notify_build_error("boom")
      handler.notify_css(["/css/a.css"])

      handler.@current_error.should be_nil
      queued = handler.css_swap_spec_queued
      # The writer fiber may already hold the first (replay) message.
      queued[0].last.should eq(%(css:{"paths":["/css/a.css"]}))
      queued[1].last.should eq("reload")
    end
  end

  describe "client script" do
    script = Hwaro::Services::LiveReloadInjectHandler::LIVE_RELOAD_SCRIPT

    it "opts in on connect and handles the css message" do
      script.should contain("ws.send('#{Hwaro::Services::LiveReloadHandler::CSS_SWAP_HELLO}')")
      script.should contain("data.indexOf('css:') === 0")
      script.should contain("swapCss(paths)")
    end

    it "keeps the existing message types" do
      script.should contain("data === 'reload'")
      script.should contain("data === 'clear-error'")
      script.should contain("data.indexOf('error:') === 0")
    end
  end
end
