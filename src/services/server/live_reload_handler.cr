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
        @sockets.each do |socket|
          begin
            socket.send("reload")
          rescue
            @sockets.delete(socket)
          end
        end
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
        if idx = html.rindex("</body>")
          html.insert(idx, LIVE_RELOAD_SCRIPT)
        else
          html + LIVE_RELOAD_SCRIPT
        end
      end
    end
  end
end
