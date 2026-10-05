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

require "digest/sha256"
require "html"
require "json"
require "openssl"
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

        # A localized URL: what to print in its place, its file in the output,
        # and every output file it published (itself plus, for a stylesheet,
        # what it pulls in).
        record Localized, url : String, path : String, files : Array(String)

        record IndexEntry, file : String, fetched_at : Int64, content_type : String?,
          sha256 : String, final_url : String do
          include JSON::Serializable
        end

        HTML_RE = /<!--[\s\S]*?-->|<(script|style|textarea)\b([^>]*)>([\s\S]*?)<\/\1\s*>|<(link|img|source|video|audio)\b([^>]*)>/i
        ATTR_RE = /\s([a-zA-Z_:][-\w:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/
        SRI_RE  = /\s(?:integrity|crossorigin)(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?/i
        CSS_RE  = /\/\*[\s\S]*?\*\/|url\(\s*(?:"([^"]*)"|'([^']*)'|([^)"'\s]*))\s*\)|@import\s+(?:"([^"]*)"|'([^']*)')/i

        URL_ATTRS = {
          "link"   => %w[href],
          "script" => %w[src],
          "img"    => %w[src srcset],
          "source" => %w[src srcset],
          "video"  => %w[src poster],
          "audio"  => %w[src],
        }

        CONTENT_TYPE_EXTENSIONS = {
          "text/css"               => ".css",
          "text/javascript"        => ".js",
          "application/javascript" => ".js",
          "font/woff2"             => ".woff2",
          "font/woff"              => ".woff",
          "font/ttf"               => ".ttf",
          "font/otf"               => ".otf",
          "image/png"              => ".png",
          "image/jpeg"             => ".jpg",
          "image/gif"              => ".gif",
          "image/webp"             => ".webp",
          "image/avif"             => ".avif",
          "image/svg+xml"          => ".svg",
          "image/x-icon"           => ".ico",
          "video/mp4"              => ".mp4",
          "video/webm"             => ".webm",
          "audio/mpeg"             => ".mp3",
          "audio/ogg"              => ".ogg",
        }

        @site_hosts : Set(String)
        @scheme : String
        @base_path : String
        @output_root : String
        @sri_root : String?
        @memo = {} of String => Localized?
        @warned = Set(String).new
        @index : Hash(String, IndexEntry)
        # ponytail: one lock around memo + fetch + index, so concurrent render
        # fibers never fetch the same URL twice; fetches serialize. Reentrant
        # because a stylesheet localizes its own references while holding it.
        @mutex = Mutex.new(:reentrant)

        # `output_dir` is the build output root; `sri_root` is it again when
        # `[assets] sri` is on (nil otherwise).
        def initialize(config : Models::Config, output_dir : String, @sri_root : String? = nil,
                       @cache_dir : String = CACHE_DIR, @now : Time = Time.utc,
                       @max_bytes : Int64 = MAX_BYTES, @deadline : Time::Span = FETCH_DEADLINE)
          @privacy = config.privacy
          @base_path = config.base_path
          @output_root = File.join(output_dir, @privacy.output_dir)
          # The configured host AND a `--base-url` override (serve's
          # localhost): a URL on either is the site's own.
          configured = config.raw["base_url"]?.try(&.as_s?) || config.base_url
          @site_hosts = {config.base_url, configured}.compact_map { |u| host_of(u) }.to_set
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
          {result, files.uniq}
        end

        # Localize one absolute (or protocol-relative) URL if the filters
        # allow it. Nil = keep the external URL (filtered out, or a failed
        # fetch under `warn-and-keep`).
        def localize(url : String) : Localized?
          absolute = absolute_url(url)
          return unless absolute && included?(absolute)
          localize_absolute(absolute, 0, [] of String)
        end

        # The rewritten attribute string, or nil when nothing changed.
        private def rewrite_tag(tag : String, attrs : String, files : Array(String)) : String?
          targets = URL_ATTRS[tag]
          parsed = parse_attrs(attrs)
          if tag == "link"
            rel = parsed["rel"]?.try(&.downcase.split) || [] of String
            return unless rel.any?(&.in?("stylesheet", "preload", "modulepreload"))
          end

          localized = [] of Localized
          changed = attrs.gsub(ATTR_RE) do |full, m|
            name = m[1].downcase
            raw = m[2]? || m[3]? || m[4]?
            next full unless raw && targets.includes?(name)
            value = HTML.unescape(raw)
            new_value = name == "srcset" ? rewrite_srcset(value, localized) : localize_one(value, localized)
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
            warn_once("integrity:#{local.url}", "[privacy] #{local.url}: the integrity attribute does not match the downloaded bytes — dropping integrity and crossorigin (enable [assets] sri to have Hwaro compute its own).")
            changed = changed.gsub(SRI_RE, "")
          end
          changed
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

        private def localize_one(value : String, localized : Array(Localized)) : String?
          return unless l = localize(value.strip)
          localized << l
          l.url
        end

        # One `srcset` entry is `url [descriptor]`, comma-separated.
        private def rewrite_srcset(value : String, localized : Array(Localized)) : String?
          changed = false
          candidates = value.split(',').map do |candidate|
            parts = candidate.strip.split(/\s+/, 2)
            if (url = parts[0]?) && !url.empty? && (local = localize_one(url, localized))
              changed = true
              parts[0] = local
            end
            parts.join(' ')
          end
          changed ? candidates.join(", ") : nil
        end

        private def localize_absolute(url : String, depth : Int32, chain : Array(String)) : Localized?
          @mutex.synchronize do
            return @memo[url] if @memo.has_key?(url)
            @memo[url] = localize_uncached(url, depth, chain)
          end
        end

        private def localize_uncached(url : String, depth : Int32, chain : Array(String)) : Localized?
          return unless fetched = obtain(url)
          body, content_type, final_url = fetched
          files = [] of String
          if stylesheet?(content_type, url)
            body = rewrite_css(body, final_url, depth + 1, chain + [url], files)
          end
          name = published_name(url, content_type, body)
          path = File.join(@output_root, name)
          unless File.info?(path).try(&.size) == body.bytesize
            Utils::FileSafe.mkdir_p(@output_root)
            Utils::FileSafe.atomic_write(path, body)
          end
          files.unshift(path)
          Localized.new(public_url(name), path, files)
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
            raw = m[1]? || m[2]? || m[3]? || m[4]? || m[5]? || ""
            ref = raw.strip
            next match if ref.empty? || ref.starts_with?('#') || ref.downcase.starts_with?("data:")
            fragment = ""
            if hash = ref.index('#')
              fragment = ref[hash..]
              ref = ref[0, hash]
            end
            resolved = begin
              base_uri.resolve(ref).to_s
            rescue URI::Error
              next match
            end
            next match unless resolved.downcase.matches?(/\Ahttps?:\/\//)
            target = if depth <= MAX_DEPTH && !chain.includes?(resolved) && !excluded?(resolved) && !site_url?(resolved)
                       if l = localize_absolute(resolved, depth, chain)
                         files.concat(l.files)
                         File.basename(l.path)
                       end
                     end
            replacement = (target || resolved) + fragment
            match.starts_with?("@") ? %(@import "#{replacement}") : %(url("#{replacement}"))
          end
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

          reason = begin
            body, content_type, final_url = RemoteFetch.fetch(url, {} of String => String, @max_bytes, @deadline, USER_AGENT)
            store(url, body, content_type, final_url)
            Logger.debug "[privacy] fetched #{RemoteFetch.sanitized_url(url)} (#{body.bytesize} bytes)"
            return {body, content_type, final_url}
          rescue ex : RemoteFetch::FetchError | Socket::Error | IO::Error | OpenSSL::SSL::Error | URI::Error | Compress::Gzip::Error | Compress::Deflate::Error | ArgumentError
            ex.message || ex.class.name
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

        private def stylesheet?(content_type : String?, url : String) : Bool
          return media_type(content_type) == "text/css" if content_type
          File.extname(url_path(url)).downcase == ".css"
        end

        private def media_type(content_type : String?) : String?
          content_type.try(&.split(';', 2).first.strip.downcase)
        end

        private def url_path(url : String) : String
          URI.parse(url).path
        rescue URI::Error
          ""
        end

        # `<sha256-12>-<name><ext>`: the name and extension come from the URL
        # path (the extension from the Content-Type when the path has none),
        # reduced to a safe character set.
        private def published_name(url : String, content_type : String?, body : String) : String
          base = File.basename(Utils::PathUtils.sanitize_path(URI.decode(url_path(url))))
          ext = File.extname(base).downcase
          stem = base.chomp(File.extname(base))
          ext = "" unless ext.matches?(/\A\.[a-z0-9]{1,8}\z/)
          ext = CONTENT_TYPE_EXTENSIONS[media_type(content_type)]? || "" if ext.empty?
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
          return false if @site_hosts.includes?(host) || @privacy.exclude.includes?(host)
          @privacy.include.empty? || @privacy.include.includes?(host)
        end

        private def excluded?(url : String) : Bool
          host_of(url).try { |h| @privacy.exclude.includes?(h) } || false
        end

        private def site_url?(url : String) : Bool
          host_of(url).try { |h| @site_hosts.includes?(h) } || false
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
