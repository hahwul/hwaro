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

      def css_swap_spec_build(options : Config::Options::BuildOptions, handler : LiveReloadHandler)
        @live_reload_handler = handler
        run_full_build(options)
      end

      def css_swap_spec_apply(changeset : ChangeSet, options : Config::Options::BuildOptions)
        apply_changeset(changeset, options)
      end
    end

    class LiveReloadHandler
      def css_swap_spec_register(socket : HTTP::WebSocket, css_swap : Bool)
        register_client(socket)
        @sockets_mutex.synchronize { @clients.last.css_swap = css_swap }
      end

      # Registered the way the WebSocket upgrade does, opted out.
      def css_swap_spec_register(socket : HTTP::WebSocket)
        register_client(socket)
      end

      def css_swap_spec_opted_in? : Bool
        @sockets_mutex.synchronize { @clients.any?(&.css_swap?) }
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

# Reads the client's frames from a pipe; writes park like CssSwapParkedIO.
private class CssSwapPipedIO < IO
  @gate = Channel(Nil).new

  def initialize(@input : IO)
  end

  def read(slice : Bytes) : Int32
    @input.read(slice)
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

CSS_SWAP_TEMPLATE = %(<link rel="stylesheet" href="/css/a.css">{{ content }})

# Builds a small site, edits every file in `static`, runs the watcher rebuild
# for that changeset and yields the live-reload pushes plus the home page HTML
# from before the edit (still inside the project dir, for disk assertions).
private def css_swap_site(static : Array(String), template = CSS_SWAP_TEMPLATE, config = "", files = {} of String => String, &)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      File.write("config.toml", %(title = "t"\nbase_url = "http://localhost"\n#{config}))
      Dir.mkdir_p("content")
      File.write("content/index.md", "+++\ntitle = \"Home\"\n+++\nhi\n")
      Dir.mkdir_p("templates")
      {"page.html", "section.html", "index.html"}.each { |name| File.write("templates/#{name}", template) }
      Dir.mkdir_p("static/css")
      Dir.mkdir_p("static/js")
      File.write("static/css/a.css", "body{}")
      File.write("static/js/app.js", "1")
      files.each do |path, body|
        Dir.mkdir_p(File.dirname(path))
        File.write(path, body)
      end

      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
      handler = CssSwapRecordingHandler.new
      server = Hwaro::Services::Server.new
      server.css_swap_spec_build(options, handler)
      html_before = File.read("public/index.html")
      static.each { |path| File.write(path, File.read(path) + "/* edited */") }
      server.css_swap_spec_apply(css_changeset(static), options)
      yield handler.pushes, html_before
    end
  end
end

private def css_swap_push(static : Array(String), template = CSS_SWAP_TEMPLATE, config = "") : Array(String)
  pushes = [] of String
  css_swap_site(static, template, config) { |got| pushes = got }
  pushes
end

private def css_swap_bundle_config(fingerprint : Bool) : String
  <<-TOML
    [assets]
    enabled = true
    minify = false
    fingerprint = #{fingerprint}

    [[assets.bundles]]
    name = "main.css"
    files = ["css/a.css"]
    TOML
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

    # The rebuild renames main.<hash>.css and prunes the old file the open
    # page still links to — only a reload picks up the new name.
    it "reloads when a fingerprinted bundle source changed" do
      template = %(<link rel="stylesheet" href="{{ asset(name='main.css') }}">{{ content }})
      css_swap_push(["static/css/a.css"], template, css_swap_bundle_config(fingerprint: true)).should eq(["reload"])
    end

    # Unfingerprinted: the bundle keeps its name, but it does not live at the
    # source's path, so every stylesheet is refreshed.
    it "swaps every stylesheet when an unfingerprinted bundle source changed" do
      css_swap_push(["static/css/a.css"], config: css_swap_bundle_config(fingerprint: false)).should eq([%(css:[])])
    end

    # Cache busting re-renders the pages for the new `?v=`, but only the query
    # moves: the open page can keep its link and swap the bytes.
    it "swaps a cache-busted auto-include and still re-renders its ?v=" do
      config = %([auto_includes]\nenabled = true\ndirs = ["css"]\n)
      template = %({{ auto_includes_css }}{{ content }})
      css_swap_site(["static/css/a.css"], template, config) do |pushes, html_before|
        pushes.should eq([%(css:["/css/a.css"])])
        html_before.should contain("/css/a.css?v=")
        html_after = File.read("public/index.html")
        html_after.should contain("/css/a.css?v=")
        html_after.should_not eq(html_before)
      end
    end
  end

  describe "LiveReloadHandler#notify_css" do
    it "opts a client in when it sends the hello over the socket" do
      handler = Hwaro::Services::LiveReloadHandler.new
      frames_in, frames_out = IO.pipe
      socket = HTTP::WebSocket.new(CssSwapPipedIO.new(frames_in))
      handler.css_swap_spec_register(socket)
      spawn { socket.run }
      HTTP::WebSocket::Protocol.new(frames_out, masked: true).send(Hwaro::Services::LiveReloadHandler::CSS_SWAP_HELLO)

      deadline = Time.instant + 5.seconds
      until handler.css_swap_spec_opted_in? || Time.instant > deadline
        Fiber.yield
      end
      handler.notify_css(["/css/a.css"])
      handler.css_swap_spec_queued[0].last.should eq(%(css:{"paths":["/css/a.css"]}))
      frames_out.close
    end

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

    it "retires in-flight swaps, drops SRI and reloads when a swap fails" do
      script.should contain("if (links[i].__hwaroPending) continue;")
      script.should contain("pending.remove();")
      script.should contain("next.removeAttribute('integrity');")
      script.should contain("next.onerror = function() { location.reload(); };")
    end

    it "keeps the existing message types" do
      script.should contain("data === 'reload'")
      script.should contain("data === 'clear-error'")
      script.should contain("data.indexOf('error:') === 0")
    end
  end
end
