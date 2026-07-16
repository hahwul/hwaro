require "http/server"
require "http/web_socket"
require "../../utils/path_utils"

module Hwaro
  module Services
    class LiveReloadHandler
      include HTTP::Handler

      LIVE_RELOAD_PATH = "/__hwaro_livereload"

      # A connected client: the socket plus a per-socket write mutex.
      # HTTP::WebSocket::Protocol#send has no internal lock, so the
      # connect-time replay (connection fiber) and the watcher fiber's
      # broadcast could interleave frame bytes on the same socket under
      # -Dpreview_mt — a WebSocket protocol error that drops the client.
      private class Client
        getter socket : HTTP::WebSocket
        getter write_mutex : Mutex = Mutex.new

        def initialize(@socket)
        end
      end

      @clients : Array(Client) = [] of Client
      # Guards every access to @clients and @current_error. Under -Dpreview_mt
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
          # Fail closed when either header is missing. Browsers always send an
          # Origin on a WebSocket handshake, so a same-origin live-reload client
          # never trips this; an absent Origin means a non-browser or crafted
          # request, which we reject rather than letting it skip the check
          # entirely (the previous `if origin && host` silently accepted those).
          unless origin && host
            context.response.status_code = 403
            context.response.print "Forbidden: missing origin or host"
            return
          end
          # Fail closed on unparseable Origins: URI.parse raises on inputs
          # like an oversized port ("http://h:99999999999" -> OverflowError),
          # and an attacker-controlled header must never crash the handler
          # or slip past the check.
          origin_uri = begin
            URI.parse(origin)
          rescue
            context.response.status_code = 403
            context.response.print "Forbidden: invalid origin"
            return
          end
          origin_host = origin_uri.host
          # Strip brackets from IPv6 literals (e.g. "[::1]" -> "::1")
          if origin_host && origin_host.starts_with?('[') && origin_host.ends_with?(']')
            origin_host = origin_host[1..-2]
          end
          # Host may be a bracketed IPv6 literal ("[::1]:1313") whose colons
          # would confuse a plain split-on-":" port strip.
          server_host = if host.starts_with?('[') && (close = host.index(']'))
                          host[1...close]
                        else
                          host.split(":").first?
                        end
          unless origin_host == server_host || origin_host == "localhost" || origin_host == "127.0.0.1" || origin_host == "::1"
            context.response.status_code = 403
            context.response.print "Forbidden: invalid origin"
            return
          end

          ws = HTTP::WebSocketHandler.new do |socket, _ctx|
            client = Client.new(socket)
            message = @sockets_mutex.synchronize do
              @clients << client
              @current_error
            end
            # Replay the current build-error so a tab opened while the
            # build is broken sees the overlay immediately instead of
            # silently rendering whatever stale HTML happens to be on
            # disk. With NO pending error, send an explicit clear instead:
            # a tab that showed the overlay, lost its socket (laptop sleep,
            # the long recovery rebuild), and reconnected after the fix
            # would otherwise display "Build failed" forever over a healthy
            # site — the successful build's `reload` broadcast is long gone.
            begin
              client.write_mutex.synchronize do
                if message
                  socket.send("error:#{{"message" => message}.to_json}")
                else
                  socket.send("clear-error")
                end
              end
            rescue IO::Error | Socket::Error
              # Connection torn down before the replay; harmless.
            end
            socket.on_close do
              @sockets_mutex.synchronize { @clients.delete(client) }
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
        # @clients concurrently. We send outside the global lock so a slow/
        # blocked socket doesn't stall connection handling; the per-client
        # write mutex only serializes writes to that one socket (against the
        # connect-time replay).
        snapshot = @sockets_mutex.synchronize { @clients.dup }
        dead = [] of Client
        snapshot.each do |client|
          client.write_mutex.synchronize { client.socket.send(message) }
        rescue IO::Error | Socket::Error
          dead << client
        end
        unless dead.empty?
          @sockets_mutex.synchronize { dead.each { |c| @clients.delete(c) } }
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

        # GET only: StaticFileHandler correctly rejects other methods, and a
        # full HTML body on HEAD (Crystal never suppresses it for handlers
        # that print) desyncs spec-conformant keep-alive clients — the body
        # bytes read as the start of the next response.
        unless context.request.method == "GET"
          call_next(context)
          return
        end

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
