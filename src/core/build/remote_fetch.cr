# The one outbound HTTP client of the build: `[[data.remote]]`
# (`RemoteData`) and `[privacy]` (`Privacy`) both fetch through it.
#
# GET only, http(s) only on every redirect hop, a byte cap and a wall-clock
# deadline spanning the whole redirect chain, and configured headers dropped
# from the first cross-origin hop on. No cookie jar: nothing a response sets
# is ever sent back.

require "http/client"
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
        rescue URI::Error
          "<unparseable url>"
        end

        # Returns the body, the response Content-Type, and the FINAL url —
        # the one the last hop actually served. `url` is returned verbatim
        # (not round-tripped through URI) when no redirect moved it.
        def fetch(url : String, headers : Hash(String, String), max_bytes : Int64,
                  deadline : Time::Span, user_agent : String = "Hwaro") : {String, String?, String}
          original = URI.parse(url)
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
            credentials &&= same_origin?(original, current)
            client = build_client(current)
            outcome = begin
              client.get(current.request_target, headers: request_headers(headers, credentials, user_agent)) do |response|
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
            ensure
              client.close
            end

            location, body, content_type = outcome
            if location
              redirects += 1
              raise FetchError.new("too many redirects (limit #{MAX_REDIRECTS})") if redirects > MAX_REDIRECTS
              current = current.resolve(location)
              final_url = current.to_s
            else
              return {body.as(String), content_type, final_url}
            end
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

        private def build_client(uri : URI) : HTTP::Client
          client = HTTP::Client.new(uri)
          client.connect_timeout = CONNECT_TIMEOUT
          client.read_timeout = READ_TIMEOUT
          client
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
