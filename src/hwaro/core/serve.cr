require "http/server"
require "./build"
require "../options/serve_options"

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

      def initialize
        @build = Build.new
      end

      def run(options : Options::ServeOptions)
        run(options.host, options.port, options.drafts)
      end

      def run(host : String = "0.0.0.0", port : Int32 = 3000, drafts : Bool = false)
        # Ensure site is built first
        puts "Performing initial build..."
        @build.run(drafts: drafts)

        # Start watcher in a background fiber
        spawn do
          watch_for_changes(drafts)
        end

        # Start server
        puts "Serving site at http://#{host}:#{port}"
        puts "Press Ctrl+C to stop."

        server = HTTP::Server.new([
          HTTP::LogHandler.new,
          IndexRewriteHandler.new,
          HTTP::StaticFileHandler.new("public", directory_listing: false, fallthrough: false),
        ])

        address = server.bind_tcp host, port
        server.listen
      end

      private def watch_for_changes(drafts : Bool)
        puts "Watching for changes in content/, layouts/, static/ and config.toml..."
        last_mtimes = scan_mtimes

        loop do
          sleep 1.seconds

          current_mtimes = scan_mtimes
          if current_mtimes != last_mtimes
            puts "\n[Watch] Change detected. Rebuilding..."
            begin
              @build.run(drafts: drafts)
            rescue ex
              puts "[Watch] Build failed: #{ex.message}"
            end
            last_mtimes = current_mtimes
          end
        end
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
