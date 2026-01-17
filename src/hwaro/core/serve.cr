require "http/server"
require "./build"
require "../options/serve_options"
require "../options/build_options"

module Hwaro
  module Core
    class IndexRewriteHandler
      include HTTP::Handler

      def call(context)
        if context.request.path.ends_with?("/")
          context.request.path += "index.html"
        end
        call_next(context)
      end
    end

    class Serve
      @build : Build
      @build_options : Options::BuildOptions?

      def initialize
        @build = Build.new
      end

      def run(options : Options::ServeOptions)
        # Convert serve options to build options for consistency
        @build_options = options.to_build_options
        run_with_options(options.host, options.port, options.open_browser)
      end

      def run(host : String = "0.0.0.0", port : Int32 = 3000, drafts : Bool = false)
        @build_options = Options::BuildOptions.new(drafts: drafts)
        run_with_options(host, port, false)
      end

      private def run_with_options(host : String, port : Int32, open_browser : Bool)
        build_options = @build_options.not_nil!

        # Ensure site is built first
        puts "Performing initial build..."
        @build.run(build_options)

        # Start watcher in a background fiber
        spawn do
          watch_for_changes(build_options)
        end

        # Start server
        url = "http://#{host}:#{port}"
        puts "Serving site at #{url}"
        puts "Press Ctrl+C to stop."

        # Open browser if requested
        if open_browser
          spawn do
            sleep 0.5.seconds
            open_browser_url(url)
          end
        end

        server = HTTP::Server.new([
          HTTP::LogHandler.new,
          IndexRewriteHandler.new,
          HTTP::StaticFileHandler.new(build_options.output_dir, directory_listing: false, fallthrough: false),
        ])

        address = server.bind_tcp host, port
        server.listen
      end

      private def watch_for_changes(build_options : Options::BuildOptions)
        puts "Watching for changes in content/, layouts/, static/ and config.toml..."
        last_mtimes = scan_mtimes

        loop do
          sleep 1.seconds

          current_mtimes = scan_mtimes
          if current_mtimes != last_mtimes
            puts "\n[Watch] Change detected. Rebuilding..."
            begin
              @build.run(build_options)
            rescue ex
              puts "[Watch] Build failed: #{ex.message}"
            end
            last_mtimes = current_mtimes
          end
        end
      end

      private def open_browser_url(url : String)
        {% if flag?(:darwin) %}
          Process.run("open", [url])
        {% elsif flag?(:linux) %}
          Process.run("xdg-open", [url])
        {% elsif flag?(:windows) %}
          Process.run("cmd", ["/c", "start", url])
        {% end %}
      rescue
        # Ignore if unable to open browser
      end

      private def scan_mtimes : Hash(String, Time)
        mtimes = {} of String => Time
        dirs_to_watch = ["content", "layouts", "static"]

        dirs_to_watch.each do |dir|
          next unless Dir.exists?(dir)
          Dir.glob(File.join(dir, "**", "*")) do |file|
            next if File.directory?(file)
            begin
              mtimes[file] = File.info(file).modification_time
            rescue
              # Handle case where file might be deleted during scan
            end
          end
        end

        if File.exists?("config.toml")
          begin
            mtimes["config.toml"] = File.info("config.toml").modification_time
          rescue
          end
        end

        mtimes
      end
    end
  end
end
