# Privacy mode (`[privacy]` in config.toml, issue #840).
#
# Downloads the third-party assets an emitted HTML page references —
# stylesheets, scripts, images, media — and rewrites the page to serve them
# from the site itself, so the built site makes no third-party requests.
# Downloaded stylesheets are rewritten the same way, recursively, so a
# Google Fonts `<link>` ends up as a local CSS file pointing at local woff2s.
#
# The rewrite runs at WRITE time, on the final (minified) HTML of each page,
# section, pagination page, taxonomy page and the 404 page. A `--cache` hit
# keeps the already-rewritten file, and the page's cache entry remembers the
# files it published (`derived_paths`), so they stay claimed.
#
# Downloads persist under `.hwaro/external/` — outside every directory
# `hwaro serve` watches and outside the build cache, like
# `.hwaro/remote_data/` — with a small JSON index. A fresh entry is used
# without touching the network, so serve rebuilds and warm builds within
# `cache_ttl` stay offline.
#
# Published files are content-addressed: `<sha256-12>-<name>.<ext>` under
# `[privacy] output_dir`, so identical bytes dedupe and a changed upstream
# file gets a new URL.
#
# The URLs fetched here come from third parties (redirects, stylesheet
# bodies), not from the author, so every hop is vetted: a host that resolves
# to a loopback, private, link-local, CGNAT, unspecified or multicast address
# is refused unless `include` names it, and the connection is pinned to the
# address that was vetted. The extension a file is published under comes
# from a per-tag allowlist, so a fetched body can never become same-origin
# HTML.

require "digest/sha256"
require "html"
require "json"
require "openssl"
require "socket"
require "uri"
require "../../models/config"
require "../../utils/digest_utils"
require "../../utils/errors"
require "../../utils/file_safe"
require "../../utils/hwaro_dir"
require "../../utils/logger"
require "../../utils/path_utils"
require "./remote_fetch"

module Hwaro
  module Core
    module Build
      class Privacy
        CACHE_DIR      = ".hwaro/external"
        INDEX_FILE     = "index.json"
        MAX_BYTES      = 20_i64 * 1024 * 1024
        FETCH_DEADLINE = 120.seconds
        # Stylesheet nesting followed from a page: the page's own `<link>` is
        # depth 0, what that file imports or references is depth 1, and so on.
        # Anything deeper keeps its absolute URL.
        MAX_DEPTH = 4
        # Google Fonts picks the font format from the User-Agent: an unknown
        # agent gets TrueType, a modern browser gets woff2.
        USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        # A URL that failed is not retried for this long by the same process
        # (a `hwaro serve` session's full rebuilds), so a dead host costs one
        # timeout, not one per rebuild.
        RETRY_AFTER = 10.minutes
        # Scripts that load their own siblings relative to their URL and
        # break when moved (Hwaro's `math = "mathjax"` tag): left external.
        SELF_LOCATING = {"https://cdn.jsdelivr.net/npm/mathjax@"}

        # What a reference is loaded as; it decides which file types may be
        # published for it.
        enum Kind
          Style
          Script
          Image
          Media
          Source
          CssRef
          Preload
        end

        STYLE  = {"text/css" => ".css"}
        SCRIPT = {
          "text/javascript"          => ".js",
          "application/javascript"   => ".js",
          "application/x-javascript" => ".js",
          "text/ecmascript"          => ".js",
          "application/ecmascript"   => ".js",
        }
        IMAGE = {
          "image/png"                => ".png",
          "image/jpeg"               => ".jpg",
          "image/gif"                => ".gif",
          "image/webp"               => ".webp",
          "image/avif"               => ".avif",
          "image/bmp"                => ".bmp",
          "image/x-icon"             => ".ico",
          "image/vnd.microsoft.icon" => ".ico",
        }
        # SVG can carry script when opened directly, so it is published only
        # for `<img>`-like references, with a warning.
        SVG  = {"image/svg+xml" => ".svg"}
        FONT = {
          "font/woff2"                    => ".woff2",
          "font/woff"                     => ".woff",
          "font/ttf"                      => ".ttf",
          "font/otf"                      => ".otf",
          "application/font-woff2"        => ".woff2",
          "application/font-woff"         => ".woff",
          "application/x-font-ttf"        => ".ttf",
          "application/vnd.ms-fontobject" => ".eot",
        }
        MEDIA = {
          "video/mp4"  => ".mp4",
          "video/webm" => ".webm",
          "video/ogg"  => ".ogv",
          "audio/mpeg" => ".mp3",
          "audio/ogg"  => ".ogg",
          "audio/wav"  => ".wav",
          "audio/mp4"  => ".m4a",
          "audio/webm" => ".weba",
        }
        ALLOWED = {
          Kind::Style   => STYLE,
          Kind::Script  => SCRIPT,
          Kind::Image   => IMAGE.merge(SVG),
          Kind::Media   => MEDIA,
          Kind::Source  => IMAGE.merge(SVG).merge(MEDIA),
          Kind::CssRef  => FONT.merge(IMAGE).merge(STYLE),
          Kind::Preload => STYLE.merge(SCRIPT).merge(FONT).merge(IMAGE).merge(MEDIA),
        }
        # Spellings a URL path may use for an allowed extension.
        EXTENSION_ALIASES = {".jpeg" => ".jpg", ".mjs" => ".js"}

        # A localized URL: what to print in its place, its file in the output,
        # every output file it published (itself plus, for a stylesheet, what
        # it pulls in), and the remote URL it came from.
        record Localized, url : String, path : String, files : Array(String), source : String

        record IndexEntry, file : String, fetched_at : Int64, content_type : String?,
          sha256 : String, final_url : String do
          include JSON::Serializable
        end

        HTML_RE = /<!--[\s\S]*?-->|<(script|style|textarea)\b([^>]*)>([\s\S]*?)<\/\1\s*>|<(link|img|source|video|audio)\b([^>]*)>/i
        LINK_RE = /<link\b[^>]*>/i
        ATTR_RE = /\s([a-zA-Z_:][-\w:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/
        SRI_RE  = /\s(?:integrity|crossorigin)(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?/i
        CSS_RE  = /\/\*[\s\S]*?\*\/|((?:-webkit-)?image-set\((?:[^()]|\([^()]*\))*\))|url\(\s*(?:"([^"]*)"|'([^']*)'|([^)"'\s]*))\s*\)|@import\s+(?:"([^"]*)"|'([^']*)')/i
        # A reference inside `image-set(...)`: `url(...)` or a bare string.
        IMAGE_SET_REF_RE = /url\(\s*(?:"([^"]*)"|'([^']*)'|([^)"'\s]*))\s*\)|"([^"]*)"|'([^']*)'/

        URL_ATTRS = {
          "link"   => %w[href],
          "script" => %w[src],
          "img"    => %w[src srcset],
          "source" => %w[src srcset],
          "video"  => %w[src poster],
          "audio"  => %w[src],
        }

        # A hop `vet_hop` refused: policy, not a flaky network, so it is
        # never remembered as a failure.
        class Refused < RemoteFetch::FetchError
        end

        # url => when it last failed, and why.
        @@failures = {} of String => {Time::Instant, String}
        @@failures_mutex = Mutex.new

        # True for an address a build must never fetch from on a third
        # party's say-so: loopback, private (RFC 1918, ULA), link-local,
        # CGNAT, unspecified, multicast/reserved, and IPv4-mapped forms.
        def self.internal_address?(ip : Socket::IPAddress) : Bool
          address = ip.address
          if address.starts_with?("::ffff:") && (v4 = address.lchop("::ffff:")).includes?('.')
            return internal_address?(Socket::IPAddress.new(v4, 0))
          end
          return true if ip.loopback? || ip.private? || ip.link_local? || ip.unspecified?
          if ip.family.inet?
            a, b = address.split('.').first(2).map(&.to_i)
            a == 0 || (a == 100 && 64 <= b <= 127) || a >= 224
          else
            address.downcase.starts_with?("ff")
          end
        end

        @site_origins : Set(String)
        @scheme : String
        @base_path : String
        @output_root : String
        @sri_root : String?
        @memo = {} of String => Localized?
        @warned = Set(String).new
        # Hosts something was downloaded from: their preconnect hints go.
        @localized_hosts = Set(String).new
        @index : Hash(String, IndexEntry)
        # ponytail: one lock around memo + fetch + index, so concurrent render
        # fibers never fetch the same URL twice; fetches serialize. Reentrant
        # because a stylesheet localizes its own references while holding it.
        # Per-URL locks would deadlock on an import cycle reached from two
        # pages at once.
        @mutex = Mutex.new(:reentrant)

        # `output_dir` is the build output root; `sri_root` is it again when
        # `[assets] sri` is on (nil otherwise).
        def initialize(config : Models::Config, output_dir : String, @sri_root : String? = nil,
                       @cache_dir : String = CACHE_DIR, @now : Time = Time.utc,
                       @max_bytes : Int64 = MAX_BYTES, @deadline : Time::Span = FETCH_DEADLINE)
          @privacy = config.privacy
          @base_path = config.base_path
          @output_root = File.join(output_dir, @privacy.output_dir)
          # The configured origin AND a `--base-url` override (serve's
          # localhost): a URL on either is the site's own.
          configured = config.raw["base_url"]?.try(&.as_s?) || config.base_url
          @site_origins = {config.base_url, configured}.compact_map { |u| origin_of(u) }.to_set
          # A protocol-relative `//host/x` loads over the page's scheme: the
          # CONFIGURED one, so serve (http://localhost) and build share cache
          # entries.
          @scheme = (URI.parse(configured).scheme rescue nil).try(&.downcase).presence || "https"
          @index = read_index
        end

        # Rewrite every localizable reference in `html`. Returns the new HTML
        # and the output files those references now point at.
        def rewrite_html(html : String) : {String, Array(String)}
          files = [] of String
          return {html, files} unless html.includes?("//")
          result = html.gsub(HTML_RE) do |match, m|
            if script_attrs = m[2]?
              next match unless m[1].downcase == "script"
              open_tag = "<#{m[1]}#{script_attrs}>"
              rewritten = rewrite_tag("script", script_attrs, files)
              rewritten ? "<#{m[1]}#{rewritten}>#{match[open_tag.size..]}" : match
            elsif tag_attrs = m[5]?
              rewritten = rewrite_tag(m[4].downcase, tag_attrs, files)
              rewritten ? "<#{m[4]}#{rewritten}>" : match
            else
              match # a comment
            end
          end
          result = drop_connection_hints(result) if result.includes?("preconnect") || result.includes?("dns-prefetch")
          {result, files.uniq}
        end

        # Localize one absolute (or protocol-relative) URL if the filters
        # allow it. Nil = keep the external URL (filtered out, refused, or a
        # failed fetch under `warn-and-keep`).
        def localize(url : String, kind : Kind = Kind::Preload) : Localized?
          absolute = absolute_url(url)
          return unless absolute && included?(absolute)
          return if SELF_LOCATING.any? { |prefix| absolute.starts_with?(prefix) }
          localize_absolute(absolute, kind, 0, [] of String)
        end

        # Every output file this instance has published — the serve prune
        # keeps them (an incremental pass re-claims nothing).
        def published_files : Array(String)
          @mutex.synchronize { @memo.values.compact.flat_map(&.files).uniq! }
        end

        # `<link rel=preconnect|dns-prefetch>` to a host whose assets are now
        # served locally would still open a connection to it from every
        # visitor's browser.
        private def drop_connection_hints(html : String) : String
          html.gsub(LINK_RE) do |tag|
            attrs = parse_attrs(tag.lchop("<link").rchop(">"))
            rel = attrs["rel"]?.try(&.downcase.split) || [] of String
            next tag unless rel.any?(&.in?("preconnect", "dns-prefetch"))
            next tag unless (href = attrs["href"]?) && (absolute = absolute_url(href.strip))
            host = host_of(absolute)
            localized = host && @mutex.synchronize { @localized_hosts.includes?(host) }
            localized || included?(absolute) ? "" : tag
          end
        end

        # The rewritten attribute string, or nil when nothing changed.
        private def rewrite_tag(tag : String, attrs : String, files : Array(String)) : String?
          targets = URL_ATTRS[tag]
          parsed = parse_attrs(attrs)
          link_kind = nil
          if tag == "link"
            rel = parsed["rel"]?.try(&.downcase.split) || [] of String
            link_kind = if rel.includes?("stylesheet")
                          Kind::Style
                        elsif rel.includes?("modulepreload")
                          Kind::Script
                        elsif rel.includes?("preload")
                          preload_kind(parsed["as"]?)
                        end
            return unless link_kind
          end

          localized = [] of Localized
          changed = attrs.gsub(ATTR_RE) do |full, m|
            name = m[1].downcase
            raw = m[2]? || m[3]? || m[4]?
            next full unless raw && targets.includes?(name)
            kind = link_kind || attr_kind(tag, name)
            value = HTML.unescape(raw)
            new_value = name == "srcset" ? rewrite_srcset(value, kind, localized) : localize_one(value, kind, localized)
            new_value ? %( #{m[1]}="#{HTML.escape(new_value)}") : full
          end
          return if localized.empty?
          localized.each { |l| files.concat(l.files) }
          return changed unless tag.in?("link", "script")

          local = localized.first
          sri_root = @sri_root
          if sri_root
            # Hwaro's own value over the bytes it serves.
            relative = "/#{@privacy.output_dir}/#{File.basename(local.path)}"
            changed = append_attrs(changed.gsub(SRI_RE, ""), Models.integrity_attr(sri_root, relative))
          elsif (integrity = parsed["integrity"]?) && !integrity_matches?(integrity, local.path)
            source = RemoteFetch.sanitized_url(local.source)
            warn_once("integrity:#{local.source}", "[privacy] #{source}: the integrity attribute does not match the downloaded bytes — dropping integrity and crossorigin (enable [assets] sri to have Hwaro compute its own).")
            changed = changed.gsub(SRI_RE, "")
          end
          changed
        end

        private def attr_kind(tag : String, attr : String) : Kind
          case tag
          when "script" then Kind::Script
          when "img"    then Kind::Image
          when "source" then Kind::Source
          else               attr == "poster" ? Kind::Image : Kind::Media
          end
        end

        private def preload_kind(as_value : String?) : Kind
          case as_value.try(&.downcase)
          when "style"          then Kind::Style
          when "script"         then Kind::Script
          when "image"          then Kind::Image
          when "audio", "video" then Kind::Media
          else                       Kind::Preload
          end
        end

        private def append_attrs(attrs : String, extra : String) : String
          stripped = attrs.rstrip
          if stripped.ends_with?('/')
            "#{stripped.rchop.rstrip}#{extra} /"
          else
            "#{attrs.rstrip}#{extra}"
          end
        end

        private def parse_attrs(attrs : String) : Hash(String, String)
          parsed = {} of String => String
          attrs.scan(ATTR_RE) do |m|
            parsed[m[1].downcase] ||= HTML.unescape(m[2]? || m[3]? || m[4]? || "")
          end
          parsed
        end

        private def localize_one(value : String, kind : Kind, localized : Array(Localized)) : String?
          return unless l = localize(value.strip, kind)
          localized << l
          l.url
        end

        # WHATWG srcset candidates: a URL is a run of non-whitespace (trailing
        # commas end it), its descriptors run to the next comma outside
        # parentheses. Only the URL spans are replaced, so the rest of the
        # attribute keeps its exact spelling.
        private def rewrite_srcset(value : String, kind : Kind, localized : Array(Localized)) : String?
          spans = srcset_url_spans(value)
          changed = false
          result = value
          spans.reverse_each do |(start, stop)|
            next unless local = localize_one(value[start...stop], kind, localized)
            result = result[0, start] + local + result[stop..]
            changed = true
          end
          changed ? result : nil
        end

        # Character ranges of each candidate URL in a srcset value.
        def srcset_url_spans(value : String) : Array({Int32, Int32})
          chars = value.chars
          n = chars.size
          spans = [] of {Int32, Int32}
          i = 0
          while i < n
            while i < n && (chars[i].ascii_whitespace? || chars[i] == ',')
              i += 1
            end
            break if i >= n
            start = i
            while i < n && !chars[i].ascii_whitespace?
              i += 1
            end
            stop = i
            if chars[stop - 1] == ','
              while stop > start && chars[stop - 1] == ','
                stop -= 1
              end
              spans << {start, stop} if stop > start
              next
            end
            spans << {start, stop}
            depth = 0
            while i < n
              c = chars[i]
              i += 1
              if c == '('
                depth += 1
              elsif c == ')'
                depth -= 1 if depth > 0
              elsif c == ',' && depth == 0
                break
              end
            end
          end
          spans
        end

        private def localize_absolute(url : String, kind : Kind, depth : Int32, chain : Array(String)) : Localized?
          key = "#{kind}\t#{url}"
          @mutex.synchronize do
            return @memo[key] if @memo.has_key?(key)
            @memo[key] = localize_uncached(url, kind, depth, chain)
          end
        end

        private def localize_uncached(url : String, kind : Kind, depth : Int32, chain : Array(String)) : Localized?
          return unless fetched = obtain(url)
          body, content_type, final_url = fetched
          unless ext = extension_for(kind, url, content_type)
            warn_once("type:#{url}", "[privacy] #{RemoteFetch.sanitized_url(url)}: #{media_type(content_type) || "an unknown type"} is not a file type Hwaro publishes for this reference — keeping the external URL.")
            return
          end
          if ext == ".svg"
            warn_once("svg:#{url}", "[privacy] #{RemoteFetch.sanitized_url(url)}: published an SVG, which can run script when opened directly on your site. Add its host to [privacy] exclude if you do not trust it.")
          end
          files = [] of String
          body = rewrite_css(body, final_url, depth + 1, chain + [url], files) if ext == ".css"
          name = published_name(url, ext, body)
          path = File.join(@output_root, name)
          unless File.info?(path).try(&.size) == body.bytesize
            Utils::FileSafe.mkdir_p(@output_root)
            Utils::FileSafe.atomic_write(path, body)
          end
          files.unshift(path)
          host_of(url).try { |h| @localized_hosts << h }
          Localized.new(public_url(name), path, files, url)
        end

        # The extension to publish under: the Content-Type's, else the URL
        # path's, and only from the allowlist for `kind`. Nil = not a type
        # this reference may publish (an `<img>` answered with HTML).
        private def extension_for(kind : Kind, url : String, content_type : String?) : String?
          allowed = ALLOWED[kind]
          if ext = allowed[media_type(content_type)]?
            return ext
          end
          ext = File.extname(URI.decode(url_path(url)).scrub).downcase
          ext = EXTENSION_ALIASES[ext]? || ext
          allowed.values.includes?(ext) ? ext : nil
        end

        # References inside a downloaded stylesheet resolve against the URL it
        # was served from. Every external one is localized (the `include`
        # filter picks pages' references; what a localized stylesheet needs
        # comes with it), except excluded hosts. A reference that stays
        # remote is written back absolute, so it still resolves from here.
        private def rewrite_css(css : String, base : String, depth : Int32, chain : Array(String), files : Array(String)) : String
          css = css.scrub unless css.valid_encoding?
          base_uri = URI.parse(base)
          css.gsub(CSS_RE) do |match, m|
            next match if match.starts_with?("/*")
            if image_set = m[1]?
              next image_set.gsub(IMAGE_SET_REF_RE) do |ref_match, r|
                raw = r[1]? || r[2]? || r[3]? || r[4]? || r[5]? || ""
                next ref_match unless target = css_ref(raw, base_uri, depth, chain, files)
                ref_match.starts_with?("url") ? %(url("#{target}")) : %("#{target}")
              end
            end
            raw = m[2]? || m[3]? || m[4]? || m[5]? || m[6]? || ""
            next match unless target = css_ref(raw, base_uri, depth, chain, files)
            match.starts_with?("@") ? %(@import "#{target}") : %(url("#{target}"))
          end
        end

        # What one stylesheet reference becomes: the local sibling filename,
        # or the absolute remote URL. Nil = leave it as written.
        private def css_ref(raw : String, base_uri : URI, depth : Int32, chain : Array(String), files : Array(String)) : String?
          ref = raw.strip
          return if ref.empty? || ref.starts_with?('#') || ref.downcase.starts_with?("data:")
          fragment = ""
          if hash = ref.index('#')
            fragment = ref[hash..]
            ref = ref[0, hash]
          end
          resolved = begin
            base_uri.resolve(ref).to_s
          rescue URI::Error
            return
          end
          return unless resolved.downcase.matches?(/\Ahttps?:\/\//)
          target = if depth <= MAX_DEPTH && !chain.includes?(resolved) && !excluded?(resolved) && !site_url?(resolved)
                     if l = localize_absolute(resolved, Kind::CssRef, depth, chain)
                       files.concat(l.files)
                       File.basename(l.path)
                     end
                   end
          (target || resolved) + fragment
        end

        # The body, Content-Type and final URL for `url`: a fresh cache entry,
        # else the network, else (with a warning) a stale entry. Nil when
        # nothing is available under `warn-and-keep`; raises under `fail`.
        private def obtain(url : String) : {String, String?, String}?
          entry = @index[url]?
          cached = entry.try { |e| read_blob(e.file) }
          if entry && cached && @now - Time.unix(entry.fetched_at) < @privacy.cache_ttl
            return {cached, entry.content_type, entry.final_url}
          end

          if (failed = @@failures_mutex.synchronize { @@failures[url]? }) && Time.instant - failed[0] < RETRY_AFTER
            reason = "#{failed[1]} (not retried for #{RETRY_AFTER.total_minutes.to_i} minutes)"
          end
          reason ||= begin
            body, content_type, final_url = RemoteFetch.fetch(url, {} of String => String, @max_bytes, @deadline, USER_AGENT,
              ->(hop : URI) { vet_hop(hop) })
            store(url, body, content_type, final_url)
            Logger.debug "[privacy] fetched #{RemoteFetch.sanitized_url(url)} (#{body.bytesize} bytes)"
            return {body, content_type, final_url}
          rescue ex : RemoteFetch::FetchError | Socket::Error | IO::Error | OpenSSL::SSL::Error | URI::Error | Compress::Gzip::Error | Compress::Deflate::Error | ArgumentError
            message = ex.message || ex.class.name
            @@failures_mutex.synchronize { @@failures[url] = {Time.instant, message} } unless ex.is_a?(Refused)
            message
          end

          if entry && cached
            Logger.warn "[privacy] #{RemoteFetch.sanitized_url(url)}: #{reason} — using the cached copy from #{Time.unix(entry.fetched_at)}."
            return {cached, entry.content_type, entry.final_url}
          end
          if @privacy.on_error == "fail"
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_NETWORK,
              message: "[privacy] could not download #{RemoteFetch.sanitized_url(url)}: #{reason}",
              hint: "Check the URL and your network, add the host to [privacy] exclude, or set [privacy] on_error = \"warn-and-keep\" to leave it external.",
            )
          end
          warn_once(url, "[privacy] could not download #{RemoteFetch.sanitized_url(url)}: #{reason} — keeping the external URL (on_error = \"warn-and-keep\").")
          nil
        end

        # Every hop of every privacy fetch: refuse a host that resolves to an
        # internal address (a redirect or a stylesheet must not make the
        # build read the machine's own network and publish it), and pin the
        # connection to the address vetted here. A host listed in `include`
        # is trusted as is (intranet CDNs, local fixtures).
        private def vet_hop(uri : URI) : String?
          host = uri.host.to_s.downcase.lchop('[').rchop(']')
          return if @privacy.include.includes?(host)
          port = uri.port || (uri.scheme.try(&.downcase) == "https" ? 443 : 80)
          addresses = Socket::Addrinfo.tcp(host, port, timeout: RemoteFetch::CONNECT_TIMEOUT).map(&.ip_address)
          raise RemoteFetch::FetchError.new("#{host} did not resolve") if addresses.empty?
          if internal = addresses.find { |ip| Privacy.internal_address?(ip) }
            raise Refused.new("refused: #{host} resolves to the non-public address #{internal.address} (list the host in [privacy] include to allow it)")
          end
          addresses.first.address
        end

        private def media_type(content_type : String?) : String?
          content_type.try(&.split(';', 2).first.strip.downcase)
        end

        private def url_path(url : String) : String
          URI.parse(url).path
        rescue URI::Error
          ""
        end

        # `<sha256-12>-<name><ext>`: the name comes from the URL path, reduced
        # to a safe character set; `ext` from `extension_for`.
        private def published_name(url : String, ext : String, body : String) : String
          base = File.basename(Utils::PathUtils.sanitize_path(URI.decode(url_path(url)).scrub))
          stem = base.chomp(File.extname(base))
          stem = stem.gsub(/[^A-Za-z0-9._-]/, "-").strip("-.")[0, 48]
          stem = "file" if stem.empty?
          "#{Digest::SHA256.hexdigest(body)[0, 12]}-#{stem}#{ext}"
        end

        private def public_url(name : String) : String
          "#{@base_path}/#{@privacy.output_dir}/#{name}"
        end

        # `integrity` holds space-separated `<alg>-<base64>` tokens; any one
        # matching the served bytes keeps the attribute valid.
        private def integrity_matches?(integrity : String, path : String) : Bool
          integrity.split.any? do |token|
            alg, _, expected = token.partition('-')
            next false unless alg.downcase.in?("sha256", "sha384", "sha512")
            Base64.strict_encode(OpenSSL::Digest.new(alg.upcase).file(path).final) == expected.split('?').first
          end
        rescue File::Error | IO::Error
          false
        end

        private def absolute_url(url : String) : String?
          url = "#{@scheme}:#{url}" if url.starts_with?("//")
          url.downcase.matches?(/\Ahttps?:\/\//) ? url.split('#', 2).first : nil
        end

        private def included?(url : String) : Bool
          return false unless host = host_of(url)
          return false if site_url?(url) || @privacy.exclude.includes?(host)
          @privacy.include.empty? || @privacy.include.includes?(host)
        end

        private def excluded?(url : String) : Bool
          host_of(url).try { |h| @privacy.exclude.includes?(h) } || false
        end

        # Same origin as the site: host AND effective port, so another port
        # on `localhost` is a different site.
        private def site_url?(url : String) : Bool
          origin_of(url).try { |o| @site_origins.includes?(o) } || false
        end

        private def origin_of(url : String) : String?
          uri = URI.parse(url)
          return unless host = uri.host.try(&.downcase).presence
          "#{host}:#{uri.port || (uri.scheme.try(&.downcase) == "https" ? 443 : 80)}"
        rescue URI::Error
          nil
        end

        private def host_of(url : String) : String?
          URI.parse(url).host.try(&.downcase).presence
        rescue URI::Error
          nil
        end

        private def warn_once(key : String, message : String) : Nil
          Logger.warn message if @mutex.synchronize { @warned.add?(key) }
        end

        private def index_path : String
          File.join(@cache_dir, INDEX_FILE)
        end

        private def read_index : Hash(String, IndexEntry)
          return {} of String => IndexEntry unless File.file?(index_path)
          Hash(String, IndexEntry).from_json(File.read(index_path))
        rescue JSON::ParseException | JSON::SerializableError | IO::Error
          {} of String => IndexEntry
        end

        private def read_blob(file : String) : String?
          path = File.join(@cache_dir, File.basename(file))
          File.file?(path) ? File.read(path) : nil
        rescue IO::Error
          nil
        end

        # Best-effort, like the remote-data cache: a failed write costs a
        # refetch next build, never this build.
        private def store(url : String, body : String, content_type : String?, final_url : String) : Nil
          sha = Digest::SHA256.hexdigest(body)
          Utils::FileSafe.mkdir_p(@cache_dir)
          Utils::HwaroDir.ensure_self_ignore(File.dirname(@cache_dir))
          Utils::FileSafe.atomic_write(File.join(@cache_dir, sha), body)
          @index[url] = IndexEntry.new(sha, @now.to_unix, content_type, sha, final_url)
          Utils::FileSafe.atomic_write(index_path, @index.to_pretty_json)
        rescue ex
          Logger.warn "[privacy] could not write the download cache under #{@cache_dir}/: #{ex.message}"
        end
      end
    end
  end
end
