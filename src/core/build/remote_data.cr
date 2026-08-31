# Remote data sources (`[[data.remote]]` in config.toml).
#
# Each configured source is fetched ONCE per build, during the Initialize
# phase (`load_data_files`), so `site.data.<key>` is fully assembled before
# anything renders. Templates never trigger network I/O — the template
# sandbox (and `load_data()`) stays disk-only by design; see issue #753.
#
# Payloads are disk-cached under `.hwaro/remote_data/` — deliberately
# OUTSIDE every directory `hwaro serve` watches (content/templates/static/
# data/i18n) and outside the build cache that `--full` clears — so serve
# rebuilds within the TTL never re-hit the network, cache writes never
# trigger the watcher, and `on_error = "warn-and-use-cache"` can build
# offline from the last good payload.

require "csv"
require "digest/md5"
require "http/client"
require "json"
require "toml"
require "uri"
require "yaml"
require "../../models/config"
require "../../utils/crinja_utils"
require "../../utils/errors"
require "../../utils/file_safe"
require "../../utils/logger"
require "../../utils/text_utils"

module Hwaro
  module Core
    module Build
      module RemoteData
        extend self

        CACHE_DIR     = ".hwaro/remote_data"
        MAX_REDIRECTS = 5
        # 20 MiB: generous for a data payload, small enough that a
        # misconfigured URL (a tarball, a video) can't balloon the build.
        DEFAULT_MAX_BYTES = 20_i64 * 1024 * 1024
        CONNECT_TIMEOUT   = 10.seconds
        READ_TIMEOUT      = 30.seconds

        # A fetch/parse failure that `on_error` may soften. Internal to this
        # module — callers only ever see a value, nil, or `HwaroError`.
        class FetchError < Exception
        end

        # The parsed payload plus the raw body. The body feeds the build
        # cache's data digest so a changed payload invalidates cached pages
        # exactly like an edited `data/` file.
        record Result, value : Crinja::Value, body : String

        # Load one `[[data.remote]]` entry: serve it from a fresh disk cache
        # when the TTL allows, otherwise fetch it. Returns nil only for
        # `on_error = "warn-and-skip"` failures; `fail` (and an unusable
        # cache under `warn-and-use-cache`) raise a classified `HwaroError`.
        #
        # `now` and `max_bytes` are parameters for the specs; production
        # callers use the defaults.
        def load(entry : Models::RemoteDataConfig,
                 cache_dir : String = CACHE_DIR,
                 now : Time = Time.utc,
                 max_bytes : Int64 = DEFAULT_MAX_BYTES) : Result?
          digest = url_digest(entry.url)

          if cached = fresh_cached_result(entry, cache_dir, digest, now)
            return cached
          end

          begin
            body, content_type = fetch(entry, max_bytes)
            format = resolve_format(entry.format, content_type, entry.url) ||
                     raise FetchError.new("cannot infer the payload format (Content-Type #{content_type.inspect}, no recognized URL extension); set format = \"json\" | \"toml\" | \"yaml\" | \"csv\" on the [[data.remote]] entry")
            value = parse_body(body, format)
          rescue ex : FetchError | Socket::Error | IO::Error | OpenSSL::SSL::Error | URI::Error | JSON::ParseException | YAML::ParseException | TOML::ParseException | CSV::MalformedCSVError | ArgumentError | InvalidByteSequenceError
            return handle_failure(entry, cache_dir, digest, ex.message || ex.class.name)
          end

          write_cache(entry, cache_dir, digest, now, body, format)
          Logger.debug "Remote data site.data.#{entry.key}: fetched #{sanitized_url(entry.url)} (#{body.bytesize} bytes, #{format})"
          Result.new(value, body)
        end

        # Explicit `format` wins; otherwise the response Content-Type, then
        # the URL's path extension. Returns nil when nothing matches.
        def resolve_format(explicit : String?, content_type : String?, url : String) : String?
          return explicit if explicit

          if content_type
            media_type = content_type.split(';', 2).first.strip.downcase
            case
            when media_type.includes?("json") then return "json"
            when media_type.includes?("toml") then return "toml"
            when media_type.includes?("yaml") then return "yaml"
            when media_type.includes?("csv")  then return "csv"
            end
          end

          path = begin
            URI.parse(url).path
          rescue URI::Error
            url
          end
          case File.extname(path).downcase
          when ".json"         then "json"
          when ".toml"         then "toml"
          when ".yaml", ".yml" then "yaml"
          when ".csv"          then "csv"
          end
        end

        # Parse a payload the same way `data/` files parse, so a key can move
        # between a local file and a remote source without templates noticing.
        # CSV matches the template-facing `load_data()` shape: an array of
        # rows, each an array of stripped string cells.
        def parse_body(body : String, format : String) : Crinja::Value
          content = Utils::TextUtils.strip_bom(body)
          case format
          when "json" then Utils::CrinjaUtils.from_json(JSON.parse(content))
          when "toml" then Utils::CrinjaUtils.from_toml(TOML.parse(content))
          when "yaml" then Utils::CrinjaUtils.from_yaml(YAML.parse(content))
          when "csv"
            rows = CSV.parse(content).map do |row|
              Crinja::Value.new(row.map { |cell| Crinja::Value.new(cell.strip) })
            end
            Crinja::Value.new(rows)
          else
            raise FetchError.new("unsupported format #{format.inspect}")
          end
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

        private def fetch(entry : Models::RemoteDataConfig, max_bytes : Int64) : {String, String?}
          original = URI.parse(entry.url)
          current = original
          redirects = 0

          loop do
            validate_hop!(current)
            client = build_client(current)
            outcome = begin
              client.get(current.request_target, headers: request_headers(entry, original, current)) do |response|
                if response.status.redirection?
                  location = response.headers["Location"]? ||
                             raise FetchError.new("redirect (HTTP #{response.status_code}) without a Location header")
                  {location, nil, nil}
                elsif response.success?
                  {nil, read_capped(response, max_bytes), response.headers["Content-Type"]?}
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
            else
              return {body.as(String), content_type}
            end
          end
        end

        # Every hop must stay http(s) — a redirect to file:// or ftp:// is
        # re-validated here even though config load already vetted the
        # configured URL itself.
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

        private def request_headers(entry : Models::RemoteDataConfig, original : URI, current : URI) : HTTP::Headers
          headers = HTTP::Headers{"User-Agent" => "Hwaro", "Accept" => "*/*"}
          # Configured headers usually carry credentials; a redirect that
          # leaves the original origin must not receive them (curl and
          # browser fetch drop Authorization the same way).
          if same_origin?(original, current)
            entry.headers.each { |name, value| headers[name] = value }
          end
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

        private def read_capped(response : HTTP::Client::Response, max_bytes : Int64) : String
          body = if io = response.body_io?
                   buffer = IO::Memory.new
                   IO.copy(io, buffer, max_bytes + 1)
                   buffer.to_s
                 else
                   response.body
                 end
          if body.bytesize > max_bytes
            raise FetchError.new("response exceeds the #{max_bytes.humanize_bytes} size cap")
          end
          body
        end

        # A cache entry is only usable when its digest matches the CURRENT
        # url — editing the url in config.toml must never serve the old
        # endpoint's payload, fresh or not.
        private def fresh_cached_result(entry : Models::RemoteDataConfig, cache_dir : String,
                                        digest : String, now : Time) : Result?
          ttl = entry.cache_ttl
          return unless ttl
          meta = read_meta(cache_dir, entry.key)
          return unless meta && meta[:url_digest] == digest
          return unless now - meta[:fetched_at] < ttl
          result = cached_result(entry, cache_dir, meta)
          if result
            Logger.debug "Remote data site.data.#{entry.key}: disk cache is fresh (fetched #{meta[:fetched_at]}, ttl #{ttl}); skipping fetch"
          end
          result
        end

        # TTL-blind read for the `warn-and-use-cache` fallback: any cached
        # copy of the SAME url is better than no data at all.
        private def stale_cached_result(entry : Models::RemoteDataConfig, cache_dir : String,
                                        digest : String) : Result?
          meta = read_meta(cache_dir, entry.key)
          return unless meta && meta[:url_digest] == digest
          cached_result(entry, cache_dir, meta)
        end

        private def cached_result(entry : Models::RemoteDataConfig, cache_dir : String,
                                  meta : {url_digest: String, fetched_at: Time, format: String?}) : Result?
          body = read_body(cache_dir, entry.key)
          return unless body
          format = entry.format || meta[:format]
          return unless format
          value = begin
            parse_body(body, format)
          rescue
            return
          end
          Result.new(value, body)
        end

        private def handle_failure(entry : Models::RemoteDataConfig, cache_dir : String,
                                   digest : String, reason : String) : Result?
          target = "site.data.#{entry.key} (#{sanitized_url(entry.url)})"
          case entry.on_error
          when "warn-and-skip"
            Logger.warn "Remote data #{target}: #{reason} — skipping; site.data.#{entry.key} will be missing this build (on_error = \"warn-and-skip\")."
            nil
          when "warn-and-use-cache"
            if result = stale_cached_result(entry, cache_dir, digest)
              Logger.warn "Remote data #{target}: #{reason} — using the last cached copy (on_error = \"warn-and-use-cache\")."
              result
            else
              raise fetch_failed_error(entry, "#{reason} — and no usable cached copy exists under #{cache_dir}/")
            end
          else # "fail"
            raise fetch_failed_error(entry, reason)
          end
        end

        private def fetch_failed_error(entry : Models::RemoteDataConfig, reason : String) : Hwaro::HwaroError
          Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_NETWORK,
            message: "Remote data site.data.#{entry.key} (#{sanitized_url(entry.url)}): #{reason}",
            hint: "Check the URL and your network. To keep building when this source is down, set on_error = \"warn-and-use-cache\" (serve the last good payload) or \"warn-and-skip\" on the [[data.remote]] entry.",
          )
        end

        private def url_digest(url : String) : String
          Digest::MD5.hexdigest(url)
        end

        private def body_path(cache_dir : String, key : String) : String
          File.join(cache_dir, "#{key}.data")
        end

        private def meta_path(cache_dir : String, key : String) : String
          File.join(cache_dir, "#{key}.json")
        end

        # The meta file deliberately stores a digest of the url rather than
        # the url itself — an interpolated `${VAR}` can put a credential in
        # the query string, and the cache must not persist it.
        private def read_meta(cache_dir : String, key : String) : {url_digest: String, fetched_at: Time, format: String?}?
          path = meta_path(cache_dir, key)
          return unless File.file?(path)
          json = JSON.parse(File.read(path))
          url_digest = json["url_digest"]?.try(&.as_s?)
          fetched_at = json["fetched_at"]?.try(&.as_i64?)
          return unless url_digest && fetched_at
          {url_digest: url_digest, fetched_at: Time.unix(fetched_at), format: json["format"]?.try(&.as_s?)}
        rescue JSON::ParseException | IO::Error | ArgumentError
          nil
        end

        private def read_body(cache_dir : String, key : String) : String?
          path = body_path(cache_dir, key)
          File.file?(path) ? File.read(path) : nil
        rescue IO::Error
          nil
        end

        # Best-effort: a cache write failure must not fail a build that has
        # the payload in hand. Body first, meta last, both atomic renames —
        # a crash between the two leaves the OLD meta pointing at the new
        # body, which the digest/TTL checks read as stale, never a torn file.
        private def write_cache(entry : Models::RemoteDataConfig, cache_dir : String,
                                digest : String, now : Time, body : String, format : String) : Nil
          Utils::FileSafe.mkdir_p(cache_dir)
          Utils::FileSafe.atomic_write(body_path(cache_dir, entry.key), body)
          meta = {url_digest: digest, fetched_at: now.to_unix, format: format}
          Utils::FileSafe.atomic_write(meta_path(cache_dir, entry.key), meta.to_json)
        rescue ex
          Logger.warn "Remote data site.data.#{entry.key}: could not write the disk cache under #{cache_dir}/: #{ex.message}"
        end
      end
    end
  end
end
