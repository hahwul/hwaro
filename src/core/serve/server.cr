# Server module for development serving with live reload
#
# Provides a local HTTP server with:
# - Static file serving
# - Directory index handling
# - File watching for automatic rebuilds
# - 404 page handling

require "http/server"
require "../build/builder"
require "../../utils/logger"
require "../../options/serve_options"
require "../../options/build_options"

module Hwaro
  module Core
    module Serve
      class IndexRewriteHandler
        include HTTP::Handler

        def initialize(@public_dir : String)
        end

        def call(context)
          path = context.request.path

          if path.ends_with?("/")
            context.request.path += "index.html"
          elsif File.extname(path).empty?
            local_path = path.sub(/^\//, "")
            fs_path = Path[@public_dir, local_path]

            if Dir.exists?(fs_path)
              context.response.status_code = 301
              context.response.headers["Location"] = path + "/"
              return
            end
          end

          call_next(context)
        end
      end

      class NotFoundHandler
        include HTTP::Handler

        def initialize(@public_dir : String)
        end

        def call(context)
          context.response.status_code = 404
          context.response.content_type = "text/html"

          path_404 = File.join(@public_dir, "404.html")
          if File.exists?(path_404)
            context.response.print File.read(path_404)
          else
            context.response.print "404 Not Found"
          end
        end
      end

      class Server
        @builder : Build::Builder

        def initialize
          @builder = Build::Builder.new
        end

        def run(options : Options::ServeOptions)
          build_options = options.to_build_options
          run_with_options(options.host, options.port, options.open_browser, build_options)
        end

        def run(host : String = "0.0.0.0", port : Int32 = 3000, drafts : Bool = false)
          build_options = Options::BuildOptions.new(drafts: drafts)
          run_with_options(host, port, false, build_options)
        end

        private def run_with_options(host : String, port : Int32, open_browser : Bool, build_options : Options::BuildOptions)
          Logger.info "Performing initial build..."
          @builder.run(build_options)

          spawn do
            watch_for_changes(build_options)
          end

          url = "http://#{host}:#{port}"
          Logger.success "Serving site at #{url}"
          Logger.info "Press Ctrl+C to stop."

          if open_browser
            spawn do
              sleep 0.5.seconds
              open_browser_url(url)
            end
          end

          output_dir = sanitize_output_dir(build_options.output_dir)

          server = HTTP::Server.new([
            HTTP::LogHandler.new,
            IndexRewriteHandler.new(output_dir),
            HTTP::StaticFileHandler.new(output_dir, directory_listing: false, fallthrough: true),
            NotFoundHandler.new(output_dir),
          ])

          address = server.bind_tcp host, port
          server.listen
        end

        private def sanitize_output_dir(dir : String) : String
          normalized = Path[dir].normalize.to_s
          if normalized.starts_with?("..") || normalized.starts_with?("/")
            Logger.warn "Invalid output directory: #{dir}. Using 'public' instead."
            return "public"
          end
          normalized
        end

        private def watch_for_changes(build_options : Options::BuildOptions)
          Logger.info "Watching for changes in content/, templates/, static/ and config.toml..."
          last_mtimes = scan_mtimes

          loop do
            sleep 1.seconds

            current_mtimes = scan_mtimes
            if current_mtimes != last_mtimes
              Logger.info "\n[Watch] Change detected. Rebuilding..."
              begin
                @builder.run(build_options)
              rescue ex
                Logger.error "[Watch] Build failed: #{ex.message}"
              end
              last_mtimes = current_mtimes
            end
          end
        end

        private def open_browser_url(url : String)
          unless url.starts_with?("http://") || url.starts_with?("https://")
            return
          end

          unless url.matches?(/\Ahttps?:\/\/[a-zA-Z0-9.:\/\-_]+\z/)
            return
          end

          {% if flag?(:darwin) %}
            Process.run("open", [url])
          {% elsif flag?(:linux) %}
            Process.run("xdg-open", [url])
          {% elsif flag?(:windows) %}
            Process.run("cmd", ["/c", "start", url])
          {% end %}
        rescue
        end

        private def scan_mtimes : Hash(String, Time)
          mtimes = {} of String => Time
          dirs_to_watch = ["content", "templates", "static"]

          dirs_to_watch.each do |dir|
            next unless Dir.exists?(dir)
            Dir.glob(File.join(dir, "**", "*")) do |file|
              next if File.directory?(file)
              begin
                mtimes[file] = File.info(file).modification_time
              rescue
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
end

# Backward compatibility alias
module Hwaro
  module Core
    class Serve
      def initialize
        @server = Serve::Server.new
      end

      def run(options : Options::ServeOptions)
        @server.run(options)
      end

      def run(host : String = "0.0.0.0", port : Int32 = 3000, drafts : Bool = false)
        @server.run(host, port, drafts)
      end

      @server : Serve::Server
    end
  end
end
