require "http/server"
require "http/web_socket"
require "./dev_path"

module Hwaro
  module Services
    class LiveReloadHandler
      include HTTP::Handler

      LIVE_RELOAD_PATH = "/__hwaro_livereload"

      # How many outbound messages one client may fall behind by. Broadcast
      # enqueues here instead of writing to the socket, so a tab that
      # handshakes and then stops reading (suspended laptop, paused debugger,
      # a hand-rolled client left open) can absorb this many messages before
      # we give up on it. The watcher emits at most one message per rebuild,
      # so a client this far behind is wedged, not merely slow.
      QUEUE_LIMIT = 32

      # A connected client: the socket, the bounded queue its writer fiber
      # drains, and a teardown flag.
      #
      # HTTP::WebSocket::Protocol#send has no internal lock, so the socket must
      # have exactly ONE writer or frames from two fibers interleave their
      # bytes — a WebSocket protocol error. That single writer is the client's
      # writer fiber, which is why `dropped` exists instead of a second fiber
      # closing the socket: a close frame is itself a blocking write, and the
      # only situation `drop_client` fires in is a peer that has stopped
      # reading, i.e. the writer fiber is *inside* `send` on that socket. A
      # would-be closer therefore has nothing to serialize against — it can
      # only wait for the writer, which is exactly what handing the teardown to
      # the writer does, without leaking a parked fiber for the rest of the
      # serve session.
      private class Client
        getter socket : HTTP::WebSocket
        # Outbound messages waiting for this client's writer fiber, which is
        # the only thing that ever writes to `socket`. Bounded — see
        # QUEUE_LIMIT.
        getter queue : Channel(String) = Channel(String).new(QUEUE_LIMIT)
        # Set by `drop_client` (under @sockets_mutex): close the socket when
        # the writer fiber retires, so the browser's `onclose` fires and its
        # reconnect replays the current build state.
        property? dropped : Bool = false

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
            register_client(socket)
          end
          ws.call(context)
        else
          call_next(context)
        end
      end

      # Track a freshly handshaken live-reload socket: start its writer fiber,
      # register it for broadcasts, and queue the connect-time replay.
      private def register_client(socket : HTTP::WebSocket)
        client = Client.new(socket)
        # Started before the client is visible to broadcast: nothing else ever
        # writes to the socket, so a queued message with no writer is a message
        # that never arrives.
        spawn_writer(client)
        @sockets_mutex.synchronize do
          @clients << client
          # Replay the current build-error so a tab opened while the
          # build is broken sees the overlay immediately instead of
          # silently rendering whatever stale HTML happens to be on
          # disk. With NO pending error, send an explicit clear instead:
          # a tab that showed the overlay, lost its socket (laptop sleep,
          # the long recovery rebuild), and reconnected after the fix
          # would otherwise display "Build failed" forever over a healthy
          # site — the successful build's `reload` broadcast is long gone.
          #
          # Enqueued while holding the lock so the replay is guaranteed to be
          # this client's FIRST message; the queue is empty and bounded at
          # QUEUE_LIMIT, so the send cannot block here.
          if message = @current_error
            client.queue.send("error:#{{"message" => message}.to_json}")
          else
            client.queue.send("clear-error")
          end
        end
        socket.on_close do
          @sockets_mutex.synchronize { @clients.delete(client) }
          # Let the writer fiber retire: `receive?` returns nil once the queue
          # is closed and drained.
          client.queue.close
        end
      end

      # Drain one client's queue on its own fiber — the ONLY place this handler
      # writes to a socket. `HTTP::WebSocket#send` blocks until the kernel
      # accepts the frame, and `broadcast` runs on the WATCHER fiber, so
      # writing there let one tab that stopped reading freeze every rebuild for
      # the rest of the serve session: the HTTP server kept answering from the
      # frozen output, so the session looked perfectly healthy while no save
      # took effect.
      private def spawn_writer(client : Client)
        spawn do
          while message = client.queue.receive?
            begin
              client.socket.send(message)
            rescue IO::Error | Socket::Error
              # Peer is gone. `on_close` normally unregisters the client, but a
              # write error can beat the read loop to it.
              @sockets_mutex.synchronize { @clients.delete(client) }
              break
            end
          end

          # Sole owner of the socket, so the teardown for a dropped client
          # belongs here: nothing else can be mid-`send` at this point.
          if @sockets_mutex.synchronize { client.dropped? }
            begin
              client.socket.close
            rescue IO::Error | Socket::Error
              # Already gone.
            end
          end
        end
      end

      # Give up on a client whose queue overflowed: unregister it so no further
      # broadcast targets it, then retire its writer fiber, which closes the
      # socket on its way out (see spawn_writer). Closing is what keeps this
      # recoverable — the client script reconnects on `onclose` and a fresh
      # connection replays the current build state, so a tab that was merely
      # suspended catches up instead of silently going stale.
      #
      # Handing the close to the writer rather than spawning one here is not a
      # style choice: a close frame is a blocking write on a socket whose peer
      # has stopped reading, so a second fiber could only block too — either on
      # the socket or (worse) on a lock the wedged writer holds, parking a
      # fiber for the rest of the serve session. Residual: while the peer stays
      # wedged the writer stays inside `send`, so the close lands when that
      # write finally completes or errors, not immediately. Forcing it sooner
      # needs the raw IO, which HTTP::WebSocket does not expose.
      private def drop_client(client : Client)
        @sockets_mutex.synchronize do
          @clients.delete(client)
          client.dropped = true
        end
        client.queue.close
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
        # @clients concurrently. Nothing below can wait on a socket — the
        # enqueue is non-blocking and each client's writer fiber owns the
        # actual write — because this runs on the watcher fiber.
        snapshot = @sockets_mutex.synchronize { @clients.dup }
        overflowed = [] of Client
        snapshot.each do |client|
          # `select` with an `else` branch is the non-blocking send: a full
          # queue means the client is too far behind to be worth keeping.
          select
          when client.queue.send(message)
            # Handed off to that client's writer fiber.
          else
            overflowed << client
          end
        rescue Channel::ClosedError
          # Socket closed between the snapshot and the send; its `on_close`
          # has already unregistered it.
        end
        overflowed.each { |client| drop_client(client) }
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

        # GET and HEAD both answered here. HEAD used to fall through to
        # StaticFileHandler, which reported the on-disk size — short by the
        # injected script — so HEAD and GET disagreed on Content-Length for
        # every page. Crystal never suppresses a handler-written body for
        # HEAD, so we set the length and return without printing.
        method = context.request.method
        unless method == "GET" || method == "HEAD"
          call_next(context)
          return
        end

        unless path.ends_with?(".html")
          call_next(context)
          return
        end

        # A non-canonical path (`//` or `/./` segments — `/guide//index.html`)
        # is answered by HTTP::StaticFileHandler with a canonicalising 302,
        # and the base-path mount pre-empts the same redirect. Serving it
        # here with a 200 (DevPath.safe_relative collapses those segments)
        # made dev accept URLs production redirects or 404s. Defer to the
        # next handler so the request gets the same treatment as everywhere
        # else in the chain.
        if noncanonical_request?(path)
          call_next(context)
          return
        end

        # Resolve strictly (see DevPath): routing through the lenient
        # `sanitize_path` made `/a%5Cb.html` and `/%2Fa%2Fb.html` serve pages
        # that every static host 404s.
        relative = DevPath.safe_relative(path)
        if relative.nil? || relative.empty?
          call_next(context)
          return
        end
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
        # Set the length explicitly so HEAD matches GET byte-for-byte and so
        # pages larger than the response output buffer get a Content-Length
        # instead of chunked framing.
        context.response.content_length = injected.bytesize
        return if method == "HEAD"
        context.response.print(injected)
      end

      # Mirrors HTTP::StaticFileHandler's own canonicalisation test (decode
      # once, `Path.posix(...).expand("/")`, compare as Path) — the same
      # shape as BasePathHandler#noncanonical_target — so this defers when
      # and only when stdlib would redirect. Unservable paths are refused
      # upstream (and `Path.posix` raises on NUL), so they are excluded
      # before anything here can raise.
      private def noncanonical_request?(path : String) : Bool
        return false if DevPath.unservable?(path)

        decoded = URI.decode(path)
        return false unless decoded.valid_encoding?

        request_path = Path.posix(decoded)
        request_path != request_path.expand("/")
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
