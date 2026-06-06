require "http/server"
require "http/web_socket"
require "../../utils/path_utils"

module Hwaro
  module Services
    class LiveReloadHandler
      include HTTP::Handler

      LIVE_RELOAD_PATH = "/__hwaro_livereload"

      @sockets : Array(HTTP::WebSocket) = [] of HTTP::WebSocket
      # Guards every access to @sockets and @current_error. Under -Dpreview_mt
      # (the CI/release build flag) HTTP::Server runs each connection in its own
      # fiber across worker threads, so the per-client `<<`/`delete` callbacks
      # race with the watcher fiber's broadcast. Array#<< triggering a resize
      # concurrently with a read/delete corrupts the buffer. Mirrors the mutex
      # pattern already used in builder.cr.
      @sockets_mutex = Mutex.new
      # Latest unresolved build-error message, replayed to any new
      # WebSocket so a tab opened mid-failure still gets the overlay
      # without waiting for the next save.
      @current_error : String? = nil

      def call(context)
        if context.request.path == LIVE_RELOAD_PATH
          # Validate Origin header to prevent Cross-Site WebSocket Hijacking.
          # Only allow connections from the same host the dev server is bound to.
          origin = context.request.headers["Origin"]?
          host = context.request.headers["Host"]?
          if origin && host
            origin_uri = URI.parse(origin)
            origin_host = origin_uri.host
            # Strip brackets from IPv6 literals (e.g. "[::1]" -> "::1")
            if origin_host && origin_host.starts_with?('[') && origin_host.ends_with?(']')
              origin_host = origin_host[1..-2]
            end
            server_host = host.split(":").first?
            unless origin_host == server_host || origin_host == "localhost" || origin_host == "127.0.0.1" || origin_host == "::1"
              context.response.status_code = 403
              context.response.print "Forbidden: invalid origin"
              return
            end
          end

          ws = HTTP::WebSocketHandler.new do |socket, _ctx|
            message = @sockets_mutex.synchronize do
              @sockets << socket
              @current_error
            end
            # Replay the current build-error so a tab opened while the
            # build is broken sees the overlay immediately instead of
            # silently rendering whatever stale HTML happens to be on
            # disk.
            if message
              begin
                socket.send("error:#{{"message" => message}.to_json}")
              rescue IO::Error | Socket::Error
                # Connection torn down before the replay; harmless.
              end
            end
            socket.on_close do
              @sockets_mutex.synchronize { @sockets.delete(socket) }
            end
          end
          ws.call(context)
        else
          call_next(context)
        end
      end

      def notify_reload
        # A successful reload implicitly clears any previous error —
        # the client script removes the overlay before reloading.
        @sockets_mutex.synchronize { @current_error = nil }
        broadcast("reload")
      end

      # Push a build-error message so connected browsers can render an
      # overlay. The message is a single line `error:<json>` so the
      # client side can split on the first colon and parse the rest;
      # using JSON keeps the schema extensible (we may want to add
      # `file`, `line`, etc. later) without ad-hoc string parsing.
      def notify_build_error(message : String)
        @sockets_mutex.synchronize { @current_error = message }
        payload = {"message" => message}.to_json
        broadcast("error:#{payload}")
      end

      # Tell connected browsers to dismiss any error overlay — sent
      # right before a successful reload so the UI clears even if the
      # rebuild produced no other visible change.
      def notify_clear_error
        @sockets_mutex.synchronize { @current_error = nil }
        broadcast("clear-error")
      end

      private def broadcast(message : String)
        # Snapshot under the lock: a connection fiber may `<<`/`delete` from
        # @sockets concurrently. We send outside the lock so a slow/blocked
        # socket doesn't stall connection handling.
        snapshot = @sockets_mutex.synchronize { @sockets.dup }
        dead = [] of HTTP::WebSocket
        snapshot.each do |socket|
          begin
            socket.send(message)
          rescue IO::Error | Socket::Error
            dead << socket
          end
        end
        unless dead.empty?
          @sockets_mutex.synchronize { dead.each { |s| @sockets.delete(s) } }
        end
      end
    end

    class LiveReloadInjectHandler
      include HTTP::Handler

      # Client-side script bundle: WebSocket reconnect loop + a
      # full-screen amber overlay rendered on `error:<json>` messages.
      # We render the overlay client-side (not server-side) because a
      # whole-build failure produces no new HTML to inject into. The
      # overlay clears on the next `reload` or `clear-error` message.
      LIVE_RELOAD_SCRIPT = <<-JS
        <script>
        (function() {
          var reconnectDelay = 1000;
          var maxDelay = 30000;
          var OVERLAY_ID = '__hwaro_build_error__';
          function showError(message) {
            var existing = document.getElementById(OVERLAY_ID);
            if (existing) existing.remove();
            var overlay = document.createElement('div');
            overlay.id = OVERLAY_ID;
            overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#fef3c7;color:#78350f;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:14px;line-height:1.55;padding:32px 40px;overflow:auto;box-sizing:border-box;';
            var title = document.createElement('div');
            title.textContent = 'Build failed';
            title.style.cssText = 'font-size:20px;font-weight:600;margin-bottom:16px;color:#92400e;';
            var body = document.createElement('pre');
            body.textContent = message || 'Unknown error';
            body.style.cssText = 'white-space:pre-wrap;margin:0;font-family:inherit;';
            var hint = document.createElement('div');
            hint.textContent = 'hwaro will clear this overlay on the next successful build.';
            hint.style.cssText = 'margin-top:24px;font-size:12px;color:#a16207;';
            overlay.appendChild(title);
            overlay.appendChild(body);
            overlay.appendChild(hint);
            document.body.appendChild(overlay);
          }
          function clearError() {
            var existing = document.getElementById(OVERLAY_ID);
            if (existing) existing.remove();
          }
          function connect() {
            var protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
            var ws = new WebSocket(protocol + '//' + location.host + '/__hwaro_livereload');
            ws.onopen = function() { reconnectDelay = 1000; };
            ws.onmessage = function(event) {
              var data = event.data;
              if (data === 'reload') {
                clearError();
                location.reload();
              } else if (data === 'clear-error') {
                clearError();
              } else if (typeof data === 'string' && data.indexOf('error:') === 0) {
                try {
                  var payload = JSON.parse(data.slice('error:'.length));
                  showError(payload && payload.message);
                } catch (e) {
                  showError(data.slice('error:'.length));
                }
              }
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
        resolved = begin
          File.realpath(file_path)
        rescue File::Error
          nil
        end
        public_real = begin
          File.realpath(@public_dir)
        rescue File::Error
          @public_dir
        end
        unless resolved && (resolved == public_real || resolved.starts_with?(public_real + "/"))
          call_next(context)
          return
        end

        unless File.file?(resolved)
          call_next(context)
          return
        end

        html = File.read(resolved)
        injected = inject_script(html)

        context.response.content_type = "text/html; charset=utf-8"
        context.response.print(injected)
      end

      def inject_script(html : String) : String
        # Use rindex to find the LAST </body> tag (the real one, not one in content)
        if idx = html.rindex("</body>")
          String.build(html.bytesize + LIVE_RELOAD_SCRIPT.bytesize) do |io|
            io << html[0, idx]
            io << LIVE_RELOAD_SCRIPT
            io << html[idx, html.size - idx]
          end
        else
          html + LIVE_RELOAD_SCRIPT
        end
      end
    end
  end
end
