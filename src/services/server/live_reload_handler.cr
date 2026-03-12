require "http/server"
require "http/web_socket"
require "../../utils/path_utils"

module Hwaro
  module Services
    class LiveReloadHandler
      include HTTP::Handler

      LIVE_RELOAD_PATH = "/__hwaro_livereload"

      @sockets : Array(HTTP::WebSocket) = [] of HTTP::WebSocket

      def call(context)
        if context.request.path == LIVE_RELOAD_PATH
          ws = HTTP::WebSocketHandler.new do |socket, _ctx|
            @sockets << socket
            socket.on_close do
              @sockets.delete(socket)
            end
          end
          ws.call(context)
        else
          call_next(context)
        end
      end

      def notify_reload
        # Snapshot to avoid race: on_close can delete from @sockets
        # while we yield in socket.send during iteration
        snapshot = @sockets.dup
        dead = [] of HTTP::WebSocket
        snapshot.each do |socket|
          begin
            socket.send("reload")
          rescue
            dead << socket
          end
        end
        dead.each { |s| @sockets.delete(s) }
      end
    end

    class LiveReloadInjectHandler
      include HTTP::Handler

      LIVE_RELOAD_SCRIPT = <<-JS
      <script>
      (function() {
        var reconnectDelay = 1000;
        var maxDelay = 30000;
        function connect() {
          var protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
          var ws = new WebSocket(protocol + '//' + location.host + '/__hwaro_livereload');
          ws.onopen = function() { reconnectDelay = 1000; };
          ws.onmessage = function(event) {
            if (event.data === 'reload') { location.reload(); }
          };
          ws.onclose = function() {
            setTimeout(function() {
              reconnectDelay = Math.min(reconnectDelay * 2, maxDelay);
              connect();
            }, reconnectDelay);
          };
        }
        connect();
      })();
      </script>
      JS

      def initialize(@public_dir : String)
      end

      def call(context)
        path = context.request.path

        unless path.ends_with?(".html")
          call_next(context)
          return
        end

        # Resolve file path from request, sanitizing to prevent directory traversal
        relative = Utils::PathUtils.sanitize_path(path)
        file_path = File.join(@public_dir, relative)

        # Verify resolved path is within public_dir
        resolved = File.realpath(file_path) rescue nil
        public_real = File.realpath(@public_dir) rescue @public_dir
        unless resolved && resolved.starts_with?(public_real + "/")
          call_next(context)
          return
        end

        unless File.file?(resolved)
          call_next(context)
          return
        end

        html = File.read(resolved)
        injected = inject_script(html)

        context.response.content_type = "text/html"
        context.response.print(injected)
      end

      def inject_script(html : String) : String
        # Use rindex to find the LAST </body> tag (the real one, not one in content)
        if idx = html.rindex("</body>")
          String.build(html.bytesize + LIVE_RELOAD_SCRIPT.bytesize) do |io|
            io << html[0...idx]
            io << LIVE_RELOAD_SCRIPT
            io << html[idx..]
          end
        else
          html + LIVE_RELOAD_SCRIPT
        end
      end
    end
  end
end
