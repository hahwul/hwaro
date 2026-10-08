# The one outbound HTTP client of the build: `[[data.remote]]`
# (`RemoteData`) and `[privacy]` (`Privacy`) both fetch through it.
#
# GET only, http(s) only on every redirect hop, a byte cap and a wall-clock
# deadline spanning the whole redirect chain, and configured headers dropped
# from the first cross-origin hop on. No cookie jar: nothing a response sets
# is ever sent back.

require "http/client"
require "openssl"
require "socket"
require "uri"

module Hwaro
  module Core
    module Build
      module RemoteFetch
        extend self

        MAX_REDIRECTS   = 5
        CONNECT_TIMEOUT = 10.seconds
        READ_TIMEOUT    = 30.seconds

        # A transport-level failure (status, redirect, size cap, deadline).
        # Callers decide whether their `on_error` policy softens it.
        class FetchError < Exception
        end

        # Secrets travel in headers and (via `${VAR}`) sometimes in the query
        # string, so log lines and error messages carry only
        # scheme://host[:port]/path — never headers, query, or userinfo.
        def sanitized_url(url : String) : String
          uri = URI.parse(url)
          port = uri.port ? ":#{uri.port}" : ""
          "#{uri.scheme}://#{uri.host}#{port}#{uri.path}"
        rescue URI::Error | OverflowError
          "<unparseable url>"
        end

        # Returns the body, the response Content-Type, and the FINAL url —
        # the one the last hop actually served. `url` is returned verbatim
        # (not round-tripped through URI) when no redirect moved it.
        #
        # `guard` vets every hop before it connects: it raises `FetchError`
        # to refuse the hop, or returns the IP addresses it vetted, which the
        # connection is then pinned to (tried in order, so a second DNS answer
        # can't swap in another address), or nil to connect normally.
        def fetch(url : String, headers : Hash(String, String), max_bytes : Int64,
                  deadline : Time::Span, user_agent : String = "Hwaro",
                  guard : (URI -> Array(String)?)? = nil) : {String, String?, String}
          original = begin
            URI.parse(url)
          rescue OverflowError
            raise FetchError.new("invalid URL (port out of range)")
          end
          current = original
          final_url = url
          redirects = 0
          # One clock for the whole entry: hops and body reads share it, so a
          # chain of individually-prompt responses can't outlast the budget.
          started = Time.instant
          # Once any hop leaves the original origin the configured headers are
          # gone for the rest of the chain: a host we never sent them to must
          # not be able to redirect back and pick which URL on the origin
          # receives the credential (curl and `requests` behave the same).
          credentials = true

          loop do
            check_deadline!(started, deadline)
            validate_hop!(current)
            pinned = guard.try(&.call(current))
            credentials &&= same_origin?(original, current)
            outcome = exchange(current, pinned) do |client|
              hop_headers = request_headers(headers, credentials, user_agent)
              hop_headers["Host"] = host_header(current) if pinned
              client.get(request_target(current), headers: hop_headers) do |response|
                if response.status.redirection?
                  location = response.headers["Location"]? ||
                             raise FetchError.new("redirect (HTTP #{response.status_code}) without a Location header")
                  {location, nil, nil}
                elsif response.success?
                  {nil, read_capped(response, max_bytes, started, deadline), response.headers["Content-Type"]?}
                else
                  raise FetchError.new("HTTP #{response.status_code}")
                end
              end
            end

            location, body, content_type = outcome
            if location
              redirects += 1
              raise FetchError.new("too many redirects (limit #{MAX_REDIRECTS})") if redirects > MAX_REDIRECTS
              # `URI.parse` raises OverflowError, not URI::Error, for a port
              # beyond Int32; a hostile Location must not escape `on_error`.
              current = begin
                current.resolve(location)
              rescue OverflowError
                raise FetchError.new("invalid redirect target (port out of range)")
              end
              final_url = current.to_s
            else
              return {body.as(String), content_type, final_url}
            end
          end
        end

        # The request line carries what a browser or curl would send: bytes
        # outside printable ASCII (raw UTF-8, spaces) are percent-encoded,
        # existing `%XX` escapes and reserved characters stay as they are.
        private def request_target(uri : URI) : String
          target = uri.request_target
          return target unless target.to_slice.any? { |b| b <= 0x20 || b >= 0x7f }
          String.build(target.bytesize + 8) do |io|
            target.each_byte { |b| b <= 0x20 || b >= 0x7f ? io << '%' << (b < 0x10 ? "0" : "") << b.to_s(16, upcase: true) : io.write_byte(b) }
          end
        end

        private def check_deadline!(started : Time::Instant, deadline : Time::Span) : Nil
          return if Time.instant - started < deadline
          raise FetchError.new("exceeded the #{deadline.total_seconds.round.to_i}s fetch deadline")
        end

        # Every hop must stay http(s) — a redirect to file:// or ftp:// is
        # re-validated here even though the caller vetted the first URL.
        private def validate_hop!(uri : URI) : Nil
          scheme = uri.scheme.try(&.downcase)
          host = uri.host
          return if {"http", "https"}.includes?(scheme) && host && !host.empty?
          raise FetchError.new("URL is not absolute http(s) (#{sanitized_url(uri.to_s)})")
        end

        # One hop's request. Every failure surfaces as `FetchError`, keeping
        # the original message: HTTP::Client raises a bare `Exception` for a
        # malformed response ("Invalid HTTP response"), which no caller's
        # rescue list could name.
        private def exchange(uri : URI, pinned : Array(String)?, & : HTTP::Client -> T) : T forall T
          client = build_client(uri, pinned)
          begin
            yield client
          ensure
            client.close
          end
        rescue ex : FetchError
          raise ex
        rescue ex
          message = ex.message || ex.class.name
          # A client built on a connected socket treats an early EOF, or a
          # reset/broken pipe on its first request, as a stale keep-alive and
          # "retries" into this. Which one happened is lost, so stay neutral.
          message = "connection closed or reset before a response" if message == "This HTTP::Client cannot be reconnected"
          raise FetchError.new(message, cause: ex)
        end

        private def build_client(uri : URI, pinned : Array(String)?) : HTTP::Client
          return pinned_client(uri, pinned) if pinned
          client = HTTP::Client.new(uri)
          client.connect_timeout = CONNECT_TIMEOUT
          client.read_timeout = READ_TIMEOUT
          client
        end

        # Connect to a vetted address (each in turn, as TCPSocket does for a
        # name) but speak to the URL's host: TLS SNI and certificate
        # verification use the name, as HTTP::Client itself does, and the
        # Host header is set by `fetch` — the client below is built without a
        # port, so it can't compute one.
        private def pinned_client(uri : URI, ips : Array(String)) : HTTP::Client
          host = uri.host.to_s.lchop('[').rchop(']')
          port = effective_port(uri) || 80
          tcp = connect_any(ips, port)
          tcp.read_timeout = READ_TIMEOUT
          tcp.sync = false
          io = if uri.scheme.try(&.downcase) == "https"
                 begin
                   OpenSSL::SSL::Socket::Client.new(tcp, context: OpenSSL::SSL::Context::Client.new, sync_close: true, hostname: host.rchop('.'))
                 rescue ex
                   tcp.close
                   raise ex
                 end
               else
                 tcp
               end
          HTTP::Client.new(io, host)
        end

        private def connect_any(ips : Array(String), port : Int32) : TCPSocket
          error = nil
          ips.each do |ip|
            return TCPSocket.new(ip, port, connect_timeout: CONNECT_TIMEOUT)
          rescue ex : Socket::Error | IO::TimeoutError
            error = ex
          end
          raise(error || FetchError.new("no address to connect to"))
        end

        private def host_header(uri : URI) : String
          host = uri.host.to_s
          port = uri.port
          port && port != (uri.scheme.try(&.downcase) == "https" ? 443 : 80) ? "#{host}:#{port}" : host
        end

        # Configured headers usually carry credentials; a redirect that
        # leaves the original origin must not receive them (curl and browser
        # fetch drop Authorization the same way). `credentials` is false from
        # the first cross-origin hop on (see `fetch`).
        private def request_headers(configured : Hash(String, String), credentials : Bool, user_agent : String) : HTTP::Headers
          headers = HTTP::Headers{"User-Agent" => user_agent, "Accept" => "*/*"}
          configured.each { |name, value| headers[name] = value } if credentials
          headers
        end

        private def same_origin?(a : URI, b : URI) : Bool
          a.scheme.try(&.downcase) == b.scheme.try(&.downcase) &&
            a.host.try(&.downcase) == b.host.try(&.downcase) &&
            effective_port(a) == effective_port(b)
        end

        private def effective_port(uri : URI) : Int32?
          uri.port || (uri.scheme.try(&.downcase) == "https" ? 443 : 80)
        end

        # Chunk-at-a-time rather than `IO.copy` so the wall-clock deadline is
        # re-checked between reads: each individual read can complete inside
        # READ_TIMEOUT forever while the transfer as a whole never ends.
        private def read_capped(response : HTTP::Client::Response, max_bytes : Int64,
                                started : Time::Instant, deadline : Time::Span) : String
          io = response.body_io?
          unless io
            body = response.body
            raise size_cap_error(max_bytes) if body.bytesize > max_bytes
            return body
          end

          buffer = IO::Memory.new
          chunk = Bytes.new(32 * 1024)
          total = 0_i64
          loop do
            check_deadline!(started, deadline)
            read = io.read(chunk)
            break if read.zero?
            total += read
            raise size_cap_error(max_bytes) if total > max_bytes
            buffer.write(chunk[0, read])
          end
          buffer.to_s
        end

        private def size_cap_error(max_bytes : Int64) : FetchError
          FetchError.new("response exceeds the #{max_bytes.humanize_bytes} size cap")
        end
      end
    end
  end
end
