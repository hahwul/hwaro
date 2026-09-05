# Dev server — HTTP::Server subclass that answers malformed requests instead of dropping them.
#
# Split out of server.cr, which keeps the require order, the Server ivars
# and the boot sequence. Parts only define or reopen types: no requires, no
# load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    # The dev server's `HTTP::Server`, hardened against requests the stdlib
    # refuses to parse.
    #
    # `HTTP::Request.from_io` runs at the very top of
    # `HTTP::Server::RequestProcessor#process` — outside that method's
    # `rescue IO::Error` and outside the per-handler 500 rescue — and it parses
    # `Content-Length` eagerly and strictly. So `Content-Length: abc`, `0x5`, a
    # value past UInt64, or two Content-Length headers that disagree raise
    # `ArgumentError` straight out of the fiber `HTTP::Server#dispatch` spawned:
    # the client received zero bytes (not even a status line) and the
    # developer's terminal was repainted with an "Unhandled exception in spawn"
    # backtrace for every such request. No handler in hwaro's chain runs early
    # enough to catch it — the request object does not exist yet — so the only
    # place to intervene is around the processor itself.
    class DevHTTPServer < HTTP::Server
      BAD_REQUEST_BODY = "400 Bad Request\n"

      # Mirrors `HTTP::Server#handle_client` minus its TLS branch (the dev
      # server only ever binds plain TCP) plus the ArgumentError rescue.
      # Wrapping `super` instead would not work: the parent's `ensure` closes
      # the connection before the rescue could answer on it.
      private def handle_client(io : IO)
        if io.is_a?(IO::Buffered)
          io.sync = false
        end

        begin
          @processor.process(io, io)
        rescue ex : ArgumentError
          # Only the request parser can raise out here — an exception from a
          # handler is already turned into a 500 inside the processor — so this
          # is a malformed request, not an internal error. Debug level: the
          # console belongs to the build output.
          Logger.debug "Malformed request answered with 400: #{ex.message}"
          respond_bad_request(io)
        end
      ensure
        begin
          io.close
        rescue IO::Error
        end
      end

      # Written by hand because the connection never produced an
      # `HTTP::Server::Response` to write through.
      private def respond_bad_request(io : IO)
        io << "HTTP/1.1 400 Bad Request\r\n"
        io << "Content-Type: text/plain; charset=utf-8\r\n"
        io << "Content-Length: #{BAD_REQUEST_BODY.bytesize}\r\n"
        io << "Connection: close\r\n"
        io << "\r\n"
        io << BAD_REQUEST_BODY
        io.flush
      rescue IO::Error
        # Peer hung up first; nothing to report.
      end
    end
  end
end
