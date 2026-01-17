require "http/server"
require "./build"

module Hwaro
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
    def run
      # Ensure site is built first
      puts "Performing initial build..."
      Build.new.run

      # Start watcher in a background fiber
      spawn do
        watch_for_changes
      end

      # Start server
      port = 3000
      puts "Serving site at http://localhost:#{port}"
      puts "Press Ctrl+C to stop."

      server = HTTP::Server.new([
        HTTP::LogHandler.new,
        IndexRewriteHandler.new,
        HTTP::StaticFileHandler.new("public", directory_listing: false, fallthrough: false)
      ])

      address = server.bind_tcp "0.0.0.0", port
      server.listen
    end

    private def watch_for_changes
      puts "Watching for changes in content/ and layouts/..."
      last_mtimes = scan_mtimes

      loop do
        sleep 1.seconds

        current_mtimes = scan_mtimes
        # If the hash differs (files added, removed, or modified timestamp changed)
        if current_mtimes != last_mtimes
          puts "\n[Watch] Change detected. Rebuilding..."
          begin
            Build.new.run
          rescue ex
            puts "[Watch] Build failed: #{ex.message}"
          end
          last_mtimes = current_mtimes
        end
      end
    end

    private def scan_mtimes
      mtimes = {} of String => Time
      dirs_to_watch = ["content", "layouts"]

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

      mtimes
    end
  end
end
