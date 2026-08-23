# Server module for development serving with live reload
#
# Provides a local HTTP server with:
# - Static file serving
# - Directory index handling
# - File watching for automatic rebuilds
# - 404 page handling
# - Incremental rebuild for content-only changes
# - Template-only re-render when only templates change
# - Static-only copy when only static files change

require "http/server"
require "json"
require "mime"
require "socket"
require "../../core/build/builder"
require "../../content/hooks"
require "../../utils/errors"
require "../../utils/logger"
require "../../config/options/serve_options"
require "../../config/options/build_options"
require "../../utils/command_runner"
require "./dev_path"
require "./live_reload_handler"

module Hwaro
  module Services
    class IndexRewriteHandler
      include HTTP::Handler

      def initialize(@public_dir : String)
      end

      def call(context)
        path = context.request.path

        if path.ends_with?("/")
          context.request.path += "index.html"
        else
          # No extname pre-filter here: deciding by extension 404'd every
          # directory with a dot in its last segment (/docs/v1.2, /node.js)
          # because stdlib's StaticFileHandler only appends the trailing
          # slash when directory_listing is on. What's on disk decides.
          #
          # Resolve strictly (see DevPath) to prevent directory traversal and
          # separator smuggling before filesystem access. A nil result is a
          # path we refuse to route; an empty one is the output root itself,
          # which must not produce `Location: //`.
          sanitized = DevPath.safe_relative(path)
          if sanitized.nil? || sanitized.empty?
            call_next(context)
            return
          end
          fs_path = Path[@public_dir, sanitized]

          # Verify resolved path is within public_dir.
          # Only attempt realpath if the path exists on disk; otherwise skip
          # the redirect entirely so non-existent traversal paths cannot
          # bypass the boundary check (realpath returns nil for missing paths).
          public_real = begin
            File.realpath(@public_dir)
          rescue File::Error
            @public_dir
          end
          resolved = if File.exists?(fs_path.to_s)
                       begin
                         File.realpath(fs_path)
                       rescue File::Error
                         nil
                       end
                     end
          if resolved && (resolved == public_real || resolved.starts_with?(public_real + "/")) && Dir.exists?(resolved)
            # 302, not 301: browsers cache permanent redirects per URL, so a
            # 301 would keep redirecting to a section long after a rebuild
            # removed or renamed it (or after a different project reuses the
            # port) until the user clears their browser cache.
            context.response.status_code = 302
            # Build the Location from the already-resolved path to prevent
            # CRLF injection and path traversal in the redirect target, then
            # re-encode it: resolution decodes, so `/my page` would otherwise
            # emit a raw space (and `/한글` raw UTF-8) into the header, which
            # is not a valid URI reference. Keep the query string — /search?q=term
            # must land on /search/?q=term, not an empty-query page. (A
            # request-line query can't contain CR/LF.)
            location = "/" + DevPath.encode_relative(sanitized) + "/"
            if (query = context.request.query) && !query.empty?
              location += "?#{query}"
            end
            context.response.headers["Location"] = location
            return
          end
        end

        call_next(context)
      end
    end

    class NotFoundHandler
      include HTTP::Handler

      # With live reload on, 404 responses embed the reload script too: a
      # tab parked on a not-yet-rendered URL (a page still building, a
      # --fast-start deferred page) then refreshes itself the moment its
      # HTML lands on disk, and build-error overlays reach 404 tabs as well.
      # Without the script those tabs sat on the 404 forever.
      # Methods the dev server actually answers. Anything else gets a 405 with
      # an Allow header instead of a 404: `StaticFileHandler` is built with
      # `fallthrough: true`, so a POST used to fall through to here and be
      # reported as "no such page", which reads as a routing bug to anyone
      # pointing a form or API mock at the dev server.
      #
      # OPTIONS is advertised because the server does answer it — just further
      # up, where `DevCorsHandler` returns its 204 preflight without calling
      # down the chain. It therefore never reaches the branch below, but the
      # advertised `Allow` value has to tell the truth about the server.
      ALLOWED_METHODS = "GET, HEAD, OPTIONS"

      def initialize(@public_dir : String, @injector : LiveReloadInjectHandler? = nil)
      end

      def call(context)
        method = context.request.method
        unless method == "GET" || method == "HEAD" || method == "OPTIONS"
          # No HEAD guard needed here: HEAD is in the allowed set above, so it
          # can never reach this branch.
          context.response.status_code = 405
          context.response.headers["Allow"] = ALLOWED_METHODS
          context.response.content_type = "text/plain; charset=utf-8"
          context.response.print "405 Method Not Allowed"
          return
        end

        context.response.status_code = 404
        context.response.content_type = "text/html; charset=utf-8"

        path_404 = File.join(@public_dir, "404.html")
        body = File.exists?(path_404) ? File.read(path_404) : "404 Not Found"
        if injector = @injector
          body = injector.inject_script(body)
        end
        # HEAD must carry the headers of the matching GET but no body. Crystal
        # never suppresses a handler-written body, so printing here desynced
        # every keep-alive client: it read the 404 page as the start of the
        # next response. Set the length explicitly and return.
        context.response.content_length = body.bytesize
        return if method == "HEAD"
        context.response.print body
      end
    end

    # Dev responses must never be cached by the browser: watch rebuilds
    # rewrite files whose Etag/Last-Modified derive from second-granularity
    # mtimes, so two quick saves inside one second produce a "new" version
    # whose validators match the cached one — the browser then 304s onto the
    # stale copy until a hard refresh. `no-store` matches what other SSG dev
    # servers ship. The header is set BEFORE call_next so it also reaches
    # responses that flush their headers mid-body (static files larger than
    # the response's output buffer — `IO::DEFAULT_BUFFER_SIZE`, 32 KiB).
    # Skipped entirely when the user supplies their own Cache-Control via
    # [serve.headers]/--header.
    class NoCacheHandler
      include HTTP::Handler

      def call(context)
        context.response.headers["Cache-Control"] = "no-store"
        call_next(context)
      end
    end

    # Emits `Access-Control-Allow-Origin: *` on every dev-server response so
    # a site loaded via one local hostname can still `fetch()` resources
    # served under another — the canonical example being `localhost:3000`
    # in the address bar while `{{ base_url }}` was baked as
    # `http://127.0.0.1:3000` (the default bind). Same-origin policy treats
    # those as different origins and would otherwise block the fetch.
    #
    # Dev-only: the built output is untouched. Matches what other SSG dev
    # servers do (Zola, Hugo).
    class DevCorsHandler
      include HTTP::Handler

      # Allowed CORS origin hosts: loopback literals plus the host the server
      # was bound to (when it's concrete, not a 0.0.0.0/:: wildcard).
      def initialize(@allowed_hosts : Set(String) = Set{"localhost", "127.0.0.1", "::1"})
      end

      def call(context)
        allowed_origin = allowed_cors_origin(context.request.headers["Origin"]?)
        if allowed_origin
          context.response.headers["Access-Control-Allow-Origin"] = allowed_origin
          context.response.headers["Vary"] = "Origin"
        end

        if context.request.method == "OPTIONS"
          if allowed_origin
            requested_headers = context.request.headers["Access-Control-Request-Headers"]?
            context.response.headers["Access-Control-Allow-Methods"] = "GET, HEAD, OPTIONS"
            context.response.headers["Access-Control-Allow-Headers"] = requested_headers || "*"
            context.response.headers["Access-Control-Max-Age"] = "86400"
          end
          context.response.status_code = 204
          return
        end

        call_next(context)
      end

      # Reflect the request Origin only when its host is a loopback literal or
      # the exact host the dev server was bound to. Returns nil for any other
      # origin so the browser's default same-origin policy applies — an
      # arbitrary website the developer visits can no longer cross-origin read
      # served content (e.g. `--drafts`). This keeps the legitimate
      # localhost-vs-127.0.0.1 fetch() ergonomic while denying internet/LAN
      # origins the blanket `*` previously granted.
      private def allowed_cors_origin(origin : String?) : String?
        return unless origin
        host = begin
          URI.parse(origin).host
        rescue
          nil
        end
        return unless host
        host = host[1..-2] if host.starts_with?('[') && host.ends_with?(']')
        @allowed_hosts.includes?(host) ? origin : nil
      end
    end

    # `HTTP::StaticFileHandler` derives `Content-Type` from the file
    # extension via `MIME.from_extension` and writes it without a
    # charset parameter — so `robots.txt` / `llms.txt` / sitemap and
    # search index responses all advertise no charset, leaving UTF-8
    # bytes (e.g. Korean LLM-instructions) at the mercy of client-side
    # heuristics.
    #
    # The primary fix is `Server.register_utf8_mime_types`, which teaches the
    # MIME table the charset up front so `StaticFileHandler` writes the right
    # value at any response size. This handler stays as the safety net for
    # types we don't enumerate there and for handlers that set a bare
    # text-shaped Content-Type themselves — but note it can only work below
    # the response output buffer (`IO::DEFAULT_BUFFER_SIZE`, 32 KiB): past
    # that the headers are already on the wire when `call_next` returns.
    #
    # We only touch types we know are text. Binary types (image/png,
    # font/woff2, etc.) are left alone — adding a charset there would
    # be wrong, not just useless. `image/svg+xml` is treated as text
    # because it's XML.
    class CharsetHandler
      include HTTP::Handler

      TEXT_PREFIXES = ["text/"]
      TEXT_SUFFIXES = ["+xml", "+json"]
      TEXT_TYPES    = Set{
        "application/xml",
        "application/json",
        "application/javascript",
        "application/rss+xml",
        "application/atom+xml",
        "image/svg+xml",
      }

      def call(context)
        call_next(context)

        existing = context.response.headers["Content-Type"]?
        return unless existing
        return if existing.includes?("charset=")

        base = existing.split(';', 2).first.strip.downcase
        return unless text_like?(base)

        context.response.headers["Content-Type"] = "#{existing}; charset=utf-8"
      end

      private def text_like?(base : String) : Bool
        TEXT_TYPES.includes?(base) ||
          TEXT_PREFIXES.any? { |p| base.starts_with?(p) } ||
          TEXT_SUFFIXES.any? { |s| base.ends_with?(s) }
      end
    end

    # Injects user-provided custom response headers on every dev-server response.
    #
    # Runs *after* `call_next` so the configured headers always win over any
    # headers set by built-in handlers (DevCorsHandler, CharsetHandler, 404
    # handler, redirect Location from IndexRewriteHandler, etc.). This gives
    # predictable "what I put in [serve.headers] is what the browser receives"
    # behaviour — exactly what users need when reproducing production server
    # configuration locally.
    class CustomHeadersHandler
      include HTTP::Handler

      def initialize(@headers : Hash(String, String))
      end

      def call(context)
        # Pre-set BEFORE call_next so the values survive responses that
        # flush their headers mid-body: files larger than the response's
        # output buffer (`IO::DEFAULT_BUFFER_SIZE`, 32 KiB) serialize
        # headers at first flush, and post-call_next edits never reach the
        # wire for those.
        apply_headers(context)
        call_next(context)
        # Re-assert after so user values still win over anything a
        # downstream handler set in between (Content-Type charset, CORS)
        # for the buffered small-response case. Only headers the static
        # handler itself overwrites (Content-Type, validators) remain
        # theirs on responses past the output buffer.
        apply_headers(context)
      end

      private def apply_headers(context)
        @headers.each do |name, value|
          # Final guard: never emit control characters in headers even if they
          # somehow made it through config/CLI validation.
          next if name.each_char.any?(&.ascii_control?) || value.each_char.any?(&.ascii_control?)
          context.response.headers[name] = value
        end
      end
    end

    # Answers 404 for the request shapes no static host serves (see
    # `DevPath.unservable?`): an encoded `/` or `\`, a literal backslash, or a
    # NUL in any form.
    #
    # Having our own handlers decline them was not enough — the request just
    # fell through to `HTTP::StaticFileHandler`, which decodes once as well and
    # resolved `/%2Fguide%2Findex.html` to the real page via a 302. That is the
    # exact dev/prod divergence this module exists to remove: a link that works
    # locally and 404s once deployed. Delegating to `NotFoundHandler` keeps the
    # 404 body (and its live-reload script) identical to every other 404.
    class UnservablePathHandler
      include HTTP::Handler

      def initialize(@not_found : NotFoundHandler)
      end

      def call(context)
        # Only the path — a query string may legitimately carry `%2F`.
        if DevPath.unservable?(context.request.path)
          @not_found.call(context)
          return
        end

        call_next(context)
      end
    end

    # Mounts the built output under `base_url`'s path component.
    #
    # `hwaro serve --base-url http://localhost:3000/myblog/` builds a site
    # whose every link, stylesheet and script is `/myblog/…`, but the dev
    # server used to answer only at `/` — so the homepage loaded unstyled and
    # every internal link 404'd. Requests carrying the prefix now have it
    # stripped before routing, and `Location` headers produced downstream get
    # it added back so the address bar stays coherent.
    #
    # Deliberately lenient: an unprefixed request is passed through untouched
    # rather than 404'd, so `/css/style.css` typed by hand (or requested by an
    # older cached page) still resolves. Only the bare root is redirected, so
    # `--open` and manual browsing land on the prefixed site.
    #
    # A no-op when `base_path` is "" — the default, since serve derives
    # `base_url` from host:port unless `--base-url` says otherwise.
    class BasePathHandler
      include HTTP::Handler

      # Normalised here rather than assumed: a trailing slash made every
      # `starts_with?("#{@base_path}/")` test unmatchable and produced
      # `Location: /myblog//`, so the documented contract is now enforced.
      def initialize(base_path : String)
        @base_path = base_path.rstrip("/")
      end

      def call(context)
        return call_next(context) if @base_path.empty?

        path = context.request.path

        if path == "/"
          redirect(context, "#{@base_path}/")
          return
        end

        if path == @base_path
          redirect(context, "#{@base_path}/")
          return
        end

        stripped = path.starts_with?("#{@base_path}/")
        if stripped
          context.request.path = path[@base_path.size..]

          # `HTTP::StaticFileHandler` answers a non-canonical path (`//x`,
          # `/./x`, `/a/../x`) with its own canonicalising redirect, emitted
          # through `Response#redirect` — which CLOSES the response and flushes
          # the headers. A post-`call_next` edit therefore never reaches the
          # wire for those, so the mount point was silently dropped from the
          # Location. (`//` is a routine artifact of `{{ base_url }}/…`
          # concatenation, so this is reachable in ordinary use.) Issue the
          # same redirect ourselves, prefixed, before it can.
          if target = noncanonical_target(context.request.path)
            redirect(context, "#{@base_path}#{target}")
            return
          end
        end

        call_next(context)

        # Put the request back the way it arrived. `HTTP::LogHandler` sits
        # outermost and reads `request.resource` AFTER call_next, so leaving it
        # stripped made `--access-log` report `/posts/` for a request to
        # `/myblog/posts/` — the access log was useless for debugging exactly
        # the mount-point problems this handler can cause.
        context.request.path = path if stripped

        # Re-prefix a downstream redirect (e.g. IndexRewriteHandler's
        # trailing-slash 302) so following it doesn't silently drop the mount
        # point from the URL.
        #
        # Keyed on whether we actually stripped, NOT on what the outgoing
        # Location looks like: a site with a top-level section named after the
        # mount point (`content/myblog/` under `--base-url http://host/myblog/`)
        # legitimately produces a downstream `/myblog/x` in stripped space, and
        # an "already prefixed?" string test would read that as done and emit a
        # Location that had lost the mount point. An unprefixed pass-through
        # request keeps its unprefixed redirect, matching how it was routed.
        return unless stripped

        location = context.response.headers["Location"]?
        if location && location.starts_with?("/") && !location.starts_with?("//")
          context.response.headers["Location"] = "#{@base_path}#{location}"
        end
      end

      # The path `HTTP::StaticFileHandler` would redirect to, or nil when it
      # would not redirect at all. Mirrors its own logic exactly — decode once,
      # `Path.posix(...).expand("/")`, compare as `Path` — so this fires when
      # and only when stdlib would have.
      private def noncanonical_target(path : String) : String?
        # Never canonicalise a path the server refuses to serve. Independently
        # of handler order this keeps two promises: an unservable path is
        # 404'd by UnservablePathHandler rather than redirected, and nothing
        # here raises — `Path.posix` throws on a NUL and the decode below can
        # yield invalid UTF-8, either of which would escape as a 500.
        return if DevPath.unservable?(path)

        decoded = URI.decode(path)
        return unless decoded.valid_encoding?

        request_path = Path.posix(decoded)
        expanded = request_path.expand("/")
        return if request_path == expanded
        URI.encode_path(expanded.to_s)
      end

      private def redirect(context, location : String)
        # 302, matching IndexRewriteHandler: a permanent redirect would stick
        # in the browser cache long after the prefix changes.
        context.response.status_code = 302
        if (query = context.request.query) && !query.empty?
          location = "#{location}?#{query}"
        end
        context.response.headers["Location"] = location
      end
    end

    # Dev-only on-demand OG image generation for `[og.auto_image]
    # lazy_generate = true` under `hwaro serve`.
    #
    # Lazy serve builds assign each eligible page its predicted og:image URL
    # without rendering the file (OgImage.assign_lazy_urls) — this handler
    # fulfills the promised "generated on first request" contract that
    # previously didn't exist (the URLs 404'd all session). A request for a
    # path under the OG output directory generates the owning page's image,
    # then falls through to the static file handler to serve it from disk.
    #
    # Only ever mounted in the dev handler chain; a no-op unless the current
    # config enables auto-OG with lazy_generate.
    class OgLazyImageHandler
      include HTTP::Handler

      def initialize(@builder : Core::Build::Builder, @output_dir : String)
        @mutex = Mutex.new
      end

      def call(context)
        method = context.request.method
        return call_next(context) unless method == "GET" || method == "HEAD"

        config = @builder.config
        site = @builder.site
        return call_next(context) unless config && site
        ai = config.og.auto_image
        return call_next(context) unless ai.enabled && ai.lazy_generate

        sanitized = DevPath.safe_relative(context.request.path)
        return call_next(context) if sanitized.nil? || sanitized.empty?
        return call_next(context) unless sanitized.starts_with?("#{ai.output_dir.strip("/")}/")
        return call_next(context) unless sanitized.ends_with?(".png") || sanitized.ends_with?(".svg")

        url_path = "/#{sanitized}"
        page = site.pages.find { |p| p.image == url_path } ||
               site.sections.find { |s| s.image == url_path }
        return call_next(context) unless page

        # Serialize generation: the og:image and twitter:image fetches of one
        # link preview land together and must not render the file twice.
        # generate() is manifest-cached — when the file exists and the page
        # hash matches, a repeat request costs a hash + stat, so no extra
        # freshness bookkeeping is needed here. `partial: true`: a
        # single-page call must not truncate every other page's manifest
        # entry.
        # The advertised URL carries the collision-disambiguated slug that
        # assign_lazy_urls computed against the FULL page set — pass it
        # through, because a single-page generate() call would recompute
        # the slug with fresh collision state and collapse colliding pages
        # (/posts/foo/ vs /posts-foo/) onto the same unsuffixed file.
        slug = File.basename(sanitized, File.extname(sanitized))
        @mutex.synchronize do
          Content::Seo::OgImage.generate([page], config, @output_dir, partial: true, parallel: false, forced_slug: slug)
        rescue ex
          Logger.warn "On-demand OG image generation failed for #{url_path}: #{ex.message}"
        end

        # PNG rendering can fall back to SVG (no usable font). The advertised
        # .png path then has no backing file, but the page's updated image
        # URL does — serve those bytes under the requested path (dev-only
        # pragmatism: the preview still shows an image).
        requested = File.join(@output_dir, sanitized)
        if !File.exists?(requested) && (fallback = page.image) && fallback != url_path
          fallback_path = File.join(@output_dir, fallback.lchop('/'))
          if File.exists?(fallback_path) && Utils::OutputGuard.within_output_dir?(fallback_path, @output_dir)
            data = File.read(fallback_path)
            context.response.content_type = fallback.ends_with?(".svg") ? "image/svg+xml" : "image/png"
            context.response.content_length = data.bytesize
            context.response.print(data) unless method == "HEAD"
            return
          end
        end

        call_next(context)
      end
    end

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

    # Categorised set of file-system changes detected by the watcher.
    #
    # Changes are split into five buckets so the server can pick the
    # cheapest rebuild strategy.
    struct ChangeSet
      # Content files (.md under content/) that were *modified* (not added/deleted)
      getter modified_content : Array(String)
      # Non-Markdown files under content/ (images and other assets published
      # via `[content.files] allow_extensions`) that were *modified*. These
      # are not pages — they're copied 1:1 to the output dir on rebuild, so
      # they can't ride the incremental page pipeline.
      getter modified_content_files : Array(String)
      # Template files that were *modified*
      getter modified_templates : Array(String)
      # Static files that were *modified*
      getter modified_static : Array(String)
      # Data / i18n files (data/**, i18n/**) that were *modified*. Templates
      # read `site.data` and translations feed every localized string, so any
      # page may depend on these — a change here forces a full rebuild.
      getter modified_data : Array(String)
      # Files that were added (new) – present in current scan but not previous
      getter added_files : Array(String)
      # Files that were removed – present in previous scan but not current
      getter removed_files : Array(String)
      # Whether config.toml itself changed
      getter config_changed : Bool

      def initialize(
        @modified_content : Array(String),
        @modified_templates : Array(String),
        @modified_static : Array(String),
        @added_files : Array(String),
        @removed_files : Array(String),
        @config_changed : Bool,
        @modified_content_files : Array(String) = [] of String,
        @modified_data : Array(String) = [] of String,
      )
      end

      # True when the change set is empty (nothing actually changed)
      def empty? : Bool
        @modified_content.empty? &&
          @modified_content_files.empty? &&
          @modified_templates.empty? &&
          @modified_static.empty? &&
          @modified_data.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when a full rebuild is unavoidable:
      # config changed, data/i18n changed (any page may read them), or files
      # were added / deleted (which affects section lists, navigation,
      # taxonomy indices, etc.)
      def needs_full_rebuild? : Bool
        @config_changed || !@added_files.empty? || !@removed_files.empty? ||
          !@modified_data.empty?
      end

      # True when only template files were modified (no content / static / structural changes)
      def templates_only? : Bool
        !@modified_templates.empty? &&
          @modified_content.empty? &&
          @modified_content_files.empty? &&
          @modified_static.empty? &&
          @modified_data.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when only static files were modified
      def static_only? : Bool
        !@modified_static.empty? &&
          @modified_content.empty? &&
          @modified_content_files.empty? &&
          @modified_templates.empty? &&
          @modified_data.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when only non-Markdown content files were modified — just
      # republish them, no markdown re-parsing, no template re-render.
      def content_files_only? : Bool
        !@modified_content_files.empty? &&
          @modified_content.empty? &&
          @modified_templates.empty? &&
          @modified_static.empty? &&
          @modified_data.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when content and templates changed together (no structural changes)
      def content_and_template_only? : Bool
        !@modified_content.empty? &&
          !@modified_templates.empty? &&
          @modified_data.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when content was modified (possibly alongside static changes)
      # but no structural / config / template changes occurred.
      def content_incremental? : Bool
        !@modified_content.empty? &&
          @modified_templates.empty? &&
          @modified_data.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # Merge another ChangeSet into this one, combining all buckets.
      # Used during debounce to batch rapid successive changes.
      #
      # Order-aware semantics (self happens first, then other):
      # - add→remove cancels out (file created then deleted = no-op)
      # - remove→add keeps the add (file deleted then recreated = net add,
      #   e.g. atomic save via delete+move)
      def merge(other : ChangeSet) : ChangeSet
        self_only_added = @added_files - other.removed_files
        self_only_removed = @removed_files - other.added_files
        other_only_added = other.added_files - @removed_files
        other_only_removed = other.removed_files - @added_files

        # remove→add: file existed, was removed in self, re-added in other.
        # Treat as net add so we don't skip a rebuild.
        revived = @removed_files & other.added_files

        net_added = (self_only_added + other_only_added + revived).uniq
        net_removed = (self_only_removed + other_only_removed).uniq

        ChangeSet.new(
          modified_content: (@modified_content + other.modified_content).uniq,
          modified_content_files: (@modified_content_files + other.modified_content_files).uniq,
          modified_templates: (@modified_templates + other.modified_templates).uniq,
          modified_static: (@modified_static + other.modified_static).uniq,
          modified_data: (@modified_data + other.modified_data).uniq,
          added_files: net_added,
          removed_files: net_removed,
          config_changed: @config_changed || other.config_changed,
        )
      end

      # Determine the optimal rebuild strategy for this changeset.
      def rebuild_strategy : Symbol
        if needs_full_rebuild?
          :full
        elsif templates_only?
          :templates
        elsif content_and_template_only?
          :content_and_template
        elsif content_incremental?
          :incremental
        elsif static_only?
          :static
        elsif content_files_only?
          :content_files
        else
          :full
        end
      end

      # Human-readable description of the change for logging. The trailing
      # noun is pluralized by the total file count; a config change is named
      # separately since it is one specific file, not a category count.
      def description : String
        parts = [] of String
        total = 0
        {
          "content"       => @modified_content,
          "content-asset" => @modified_content_files,
          "template"      => @modified_templates,
          "static"        => @modified_static,
          "data"          => @modified_data,
          "added"         => @added_files,
          "removed"       => @removed_files,
        }.each do |label, list|
          next if list.empty?
          parts << "#{list.size} #{label}"
          total += list.size
        end
        desc = parts.empty? ? "" : "#{parts.join(", ")} #{total == 1 ? "file" : "files"}"
        if @config_changed
          desc = desc.empty? ? "config" : "#{desc}, config"
        end
        desc
      end

      # What the watch timeline prints: the path itself when exactly one file
      # changed (the common save-one-file loop), the category summary above
      # otherwise.
      def display : String
        return "config.toml" if @config_changed && all_changed_files.empty?
        files = all_changed_files
        files.size == 1 && !@config_changed ? files.first : description
      end

      private def all_changed_files : Array(String)
        @modified_content + @modified_content_files + @modified_templates +
          @modified_static + @modified_data + @added_files + @removed_files
      end
    end

    class Server
      # What the watcher records per file: mtime plus size. Size catches
      # same-tick rewrites on coarse-mtime filesystems (Docker bind mounts,
      # NFS/SMB shares, exFAT) where two quick saves can share a timestamp —
      # an mtime-only comparison would permanently miss the second save.
      alias FileStamp = {Time, Int64}

      @builder : Core::Build::Builder
      @live_reload_handler : LiveReloadHandler?
      # True after a watch rebuild raised. A failed rebuild can leave the
      # builder's in-memory state (reloaded templates, partially updated
      # site relationships) ahead of what's on disk, and the pages that
      # failed to render are not re-selected when the NEXT event touches an
      # unrelated file — so the next changeset escalates to a full rebuild
      # to guarantee convergence, whatever the user saves.
      @rebuild_failed : Bool = false
      # "config.<env>.toml" when serve runs with --env/HWARO_ENV, nil
      # otherwise. Watched alongside config.toml (both force full rebuilds).
      @env_config_file : String? = nil
      # [serve] table captured at startup — the baseline for warning that a
      # config edit changed restart-only settings (headers, fast).
      @startup_serve_config : Models::ServeConfig? = nil
      # Mirrors --no-error-overlay. The flag used to reach only BuildOptions
      # (where it governs the per-page render-error HTML), so the full-screen
      # overlay the live-reload client draws from an `error:` push kept
      # appearing for users who had explicitly turned overlays off.
      @error_overlay : Bool = true
      # Watcher baseline captured BEFORE the initial build (and before any
      # --fast-start deferred render). The watcher used to take its first
      # snapshot only when its loop started — after both — so any edit made
      # during that window was absorbed into the baseline and never rebuilt.
      # Consumed once by the watch loop; nil afterwards.
      @watch_baseline : Hash(String, FileStamp)? = nil

      # Extensions whose served bytes are UTF-8 text, each with the base type to
      # assume when the platform's MIME database has no opinion.
      #
      # Registering the charset in the MIME table makes `HTTP::StaticFileHandler`
      # emit it directly, which is the only thing that works for responses past
      # the response output buffer (`IO::DEFAULT_BUFFER_SIZE`, 32 KiB) — a
      # post-`call_next` header edit is too late there, so a 40 KB
      # `search.json` used to lose its charset entirely. `.html`/`.htm` matter
      # most: HTML is the site's primary content type and with
      # `--no-live-reload` (or any page the injector doesn't match) it goes out
      # through StaticFileHandler like any other file, so a 60 KB CJK page
      # rendered as mojibake.
      #
      # One list with one rule — deliberately NOT split on "does stdlib map
      # this extension?". That question has a platform-dependent answer:
      # Crystal seeds `MIME::DEFAULT_TYPES` (which already carries charsets)
      # and then lets the OS database override it, so macOS reads
      # `/etc/apache2/mime.types` and reports `.md` as nil while Linux reads
      # `/etc/mime.types` and reports `text/markdown`. Keying behaviour on that
      # split left these extensions with no charset at all on Linux — the very
      # bug the fallback existed to fix, invisible on macOS.
      UTF8_MIME_TYPES = {
        ".html"        => "text/html",
        ".htm"         => "text/html",
        ".txt"         => "text/plain",
        ".json"        => "application/json",
        ".xml"         => "application/xml",
        ".js"          => "text/javascript",
        ".mjs"         => "text/javascript",
        ".css"         => "text/css",
        ".svg"         => "image/svg+xml",
        ".csv"         => "text/csv",
        ".md"          => "text/markdown",
        ".webmanifest" => "application/manifest+json",
        ".map"         => "application/json",
      }

      # Ensure every listed extension carries `charset=utf-8` whatever the
      # platform's database says: append to the system's base type when it has
      # one, use ours when it does not. Never overrides a system type beyond
      # adding the charset, never double-appends, and is idempotent — a second
      # pass sees the charset already there and skips.
      #
      # Only ever called from the dev server, so the built output and every
      # other command keep stdlib's MIME table untouched.
      def self.register_utf8_mime_types
        UTF8_MIME_TYPES.each do |ext, assumed|
          base = MIME.from_extension?(ext) || assumed
          next if base.includes?("charset=")
          MIME.register(ext, "#{base}; charset=utf-8")
        end
      end

      # Debounce interval: after detecting changes, wait this long for
      # additional changes to settle before triggering a rebuild.
      DEBOUNCE_INTERVAL = 300.milliseconds

      # Maximum number of debounce iterations before forcing a rebuild.
      # Prevents indefinite blocking when files are being written continuously.
      MAX_DEBOUNCE_ITERATIONS = 10

      # Polling interval for the file watcher.
      POLL_INTERVAL = 500.milliseconds

      # Cap on the build-failure text that reaches the terminal and the browser
      # overlay. Crinja quotes the offending source lines in its message, so a
      # single very long line near a syntax error (a minified vendor bundle
      # inlined in a template, a generated data blob) produces a multi-megabyte
      # message: the watcher repainted the console with it on every save — one
      # broken template grew a serve log to 12 MB — and pushed the same payload
      # over the live-reload socket. A few thousand characters is far more than
      # the overlay can usefully show and still carries the error type, file
      # and position, which is what the developer actually reads.
      MAX_BUILD_ERROR_CHARS = 4000

      def initialize
        @builder = Core::Build::Builder.new

        # Register content hooks with lifecycle (same as build command)
        Content::Hooks.all.each do |hookable|
          @builder.register(hookable)
        end
      end

      def run(options : Config::Options::ServeOptions)
        build_options = options.to_build_options
        build_options.serve_mode = true
        # The dev server derives its document root from `build_options.output_dir`
        # (see `sanitize_output_dir` call sites), so `[build]` has to be merged
        # here as well as in the Builder: BuildOptions is a struct, and the copy
        # the Builder mutates is not this one. Without this, `[build] output_dir`
        # would have serve building into one directory and serving another.
        #
        # A missing or invalid config is not fatal here — serve deliberately
        # starts on a broken site, and the Builder reports the error on the
        # initial build.
        begin
          build_options.apply_build_config!(Hwaro::Models::Config.load(env: build_options.env).build)
        rescue Hwaro::HwaroError
        end
        run_with_options(options.host, options.port, options.open_browser, options.access_log, options.live_reload, build_options, options.json, options.headers)
      end

      private def run_with_options(host : String, port : Int32, open_browser : Bool, access_log : Bool, live_reload : Bool, build_options : Config::Options::BuildOptions, json_output : Bool = false, headers : Hash(String, String) = {} of String => String)
        # The env-specific config overlay (config.<env>.toml) feeds every
        # rebuild via Models::Config.load, so the watcher must see its edits
        # — scan_mtimes stats it alongside config.toml.
        @env_config_file = build_options.env.try { |e| "config.#{e}.toml" }
        @error_overlay = build_options.error_overlay
        # Must happen before any handler is built so StaticFileHandler picks
        # the charset-bearing types up.
        Server.register_utf8_mime_types

        # The initial build prints its own receipt; no preamble needed.
        #
        # A broken site at startup (template syntax error, failing hook)
        # used to kill serve before the server or watcher existed — the user
        # had to fix blind and rerun, while the very same error during a
        # running session gets the fix-and-save loop plus a browser overlay.
        # Start anyway: @rebuild_failed forces the first watch rebuild to be
        # a full one, and the error is replayed to the first live-reload
        # client so the browser shows the overlay instead of a bare 404.
        # Snapshot the watcher baseline BEFORE the initial build: edits saved
        # while the build (or the fast-start deferred render) runs must land
        # in the watcher's first diff instead of vanishing into it.
        capture_watch_baseline

        initial_error : String? = nil
        begin
          unless @builder.run(build_options)
            initial_error = "Initial build failed — check the terminal, fix the error, and save to rebuild."
          end
        rescue ex : Hwaro::HwaroError
          initial_error = ex.message || "Initial build failed"
          Logger.error "Initial build failed: #{truncate_build_error(initial_error)}"
          ex.hint.try { |hint| Logger.info "  Hint: #{hint}" }
        end
        if initial_error
          @rebuild_failed = true
          Logger.warn "Serving the previous output (if any) — the watcher will rebuild on your next save."
        end

        # Watch-triggered rebuilds should preserve the already-built output
        # so per-image mtime-skip (and any future incremental hook logic)
        # can short-circuit. Cold start still wipes — see above — to keep
        # serve honest about fresh state.
        watch_options = build_options.dup
        watch_options.preserve_output = true
        # Once the deferred pages have been rendered we don't want subsequent
        # watch-triggered rebuilds to also defer — that would re-stash the
        # same pages on every file save. Fast-start is a cold-start only
        # optimisation.
        watch_options.fast_start = false

        output_dir = sanitize_output_dir(build_options.output_dir)
        # The static handler needs an existing root even when the initial
        # build failed before creating one.
        Hwaro::Utils::FileSafe.mkdir_p(output_dir)

        # Baseline for the restart-only [serve.*] warning after config edits.
        # Nil when the initial build never loaded a config; established lazily
        # by the first successful config-changed rebuild in that case.
        @startup_serve_config = @builder.config.try(&.serve)

        # Path component of base_url, when the user pointed --base-url at a
        # subpath. "" for the normal host:port-derived base_url.
        #
        # Derived from the options, NOT from `@builder.config`: a startup build
        # that fails to load config (a TOML syntax error, say) leaves config
        # nil, and the handler chain is assembled exactly once — so reading it
        # there dropped the mount point for the whole session, and a later
        # successful rebuild emitting `/prefix/`-linked pages could never get it
        # back without a restart.
        base_path = base_path_for(build_options.base_url)

        handlers = build_handlers(output_dir, host, access_log, live_reload, headers, base_path)

        # Replay a startup failure to the first live-reload client(s) so the
        # browser shows the overlay instead of a bare 404/stale page.
        if msg = initial_error
          push_build_error(msg)
        end

        # DevHTTPServer, not HTTP::Server: see the class comment — a malformed
        # Content-Length must answer 400 instead of killing the connection
        # fiber with a raw backtrace on the developer's terminal.
        server = DevHTTPServer.new(handlers)

        # Bind BEFORE emitting any "Serving site at …" / "Live reload
        # enabled" / "Watching for changes …" banners. Previously those
        # lines printed first and the watcher fiber was already spawned,
        # so a port-conflict error produced misleading output that looked
        # like the server was running before the final `Error: Could not
        # bind …` line.
        begin
          server.bind_tcp host, port
        rescue ex : Socket::BindError
          # Socket::BindError#message already includes the address, so
          # use it verbatim rather than re-prefixing.
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: ex.message || "Could not bind to '#{host}:#{port}'",
            hint: "Is another process already listening on this port? Try -p/--port with a different value.",
          )
        end

        url = serve_url(host, port, base_path)
        # Calm serve receipt: where it's live, reload state, what's watched,
        # then the ember "ready" beat. `emit_ready_signal` publishes the very
        # same URL, so a script that blocks on the machine line and a human
        # reading the receipt can never be sent to different places.
        serve_receipt = Logger::Receipt.new("serve")
        serve_receipt.row("url", url, Logger::Role::Accent)
        serve_receipt.row("reload", live_reload ? "enabled" : "disabled")
        serve_receipt.row("watch", "content · templates · static · data · i18n · config")
        serve_receipt.outcome("ready", "Ctrl+C to stop")
        # Blank line separates the serve block from the initial build's
        # receipt above it (TTY rhythm only; plain output stays byte-stable).
        Logger.info "" if Logger.color_enabled?
        serve_receipt.emit

        if open_browser
          spawn do
            sleep 0.5.seconds
            open_browser_url(url)
          end
        end

        # If fast-start stashed pages on the builder, render them in the
        # background so the dev server can start serving the priority
        # subset immediately. Notify the browser via live-reload when the
        # background pass finishes so any tab parked on a not-yet-rendered
        # URL automatically refreshes once its HTML is on disk.
        #
        # `deferred_done` gates the file watcher: starting the watcher
        # before the deferred fiber returns would let a save-triggered
        # incremental rebuild race with the deferred render, both fibers
        # mutating shared Builder state (`@pages_by_path`,
        # `@page_crinja_value_cache`, `@cache`, …) at IO yield points.
        # The channel is closed once the deferred pass finishes (or
        # immediately if there's nothing to defer), at which point the
        # watcher proceeds.
        deferred_done = Channel(Nil).new
        fast_start_pending = build_options.fast_start && @builder.has_deferred_pages?

        # Run `server.listen` in its own fiber so the accept loop is
        # already established before we kick off the heavy deferred
        # render. With fast-start the deferred fiber does ~20s of mostly
        # pure-CPU work (PNG OG image encoding + image resize); if we
        # spawned it first and only then called `server.listen` from the
        # main fiber, the cooperative scheduler would pick the deferred
        # fiber at the first yield and the accept loop would never get
        # to run — TCP connects succeeded (OS-level backlog) but HTTP
        # responses sat indefinitely.
        listen_done = Channel(Nil).new
        # Captured from the listen fiber so a crashed accept loop can't turn
        # into a clean exit: `ensure` alone closed the channel and the main
        # fiber returned normally — exit 0 — with the server dead.
        listen_error : Exception? = nil
        spawn do
          server.listen
        rescue error
          listen_error = error
        ensure
          listen_done.close
        end

        if fast_start_pending
          deferred_options = build_options.dup
          deferred_options.preserve_output = true
          deferred_options.fast_start = false
          spawn do
            # Block until the listen fiber has actually entered the
            # accept loop. `HTTP::Server#listening?` flips to true
            # synchronously inside `#listen`, just before the accept
            # fiber is spawned, so once we observe it the accept path
            # is guaranteed to be live. Polling with `Fiber.yield` (not
            # `sleep`) keeps the wait sub-microsecond on a quiet
            # scheduler. A single `Fiber.yield` was *probabilistically*
            # enough in practice but offered no ordering guarantee
            # under `-Dpreview_mt` work-stealing.
            until server.listening?
              Fiber.yield
            end
            begin
              @builder.render_deferred(deferred_options)
              @live_reload_handler.try(&.notify_reload)
            rescue ex
              # Deferred pages have no HTML on disk yet and incremental
              # strategies will never render them — flag the failure so the
              # first watch rebuild escalates to a full one (the watcher only
              # starts after this fiber signals done, so no race on the flag).
              @rebuild_failed = true
              Logger.error "[Fast-start] Background render failed: #{truncate_build_error(ex.message || "")}"
              Logger.debug "[Fast-start] Backtrace: #{ex.backtrace?.try(&.first(5).join("\n    ")) || "unavailable"}"
              push_build_error(ex.message || "Background render failed")
            ensure
              deferred_done.close
            end
          end
        else
          deferred_done.close
        end

        spawn do
          # Block here — not in a sleep loop — until the deferred fiber
          # signals completion. `receive?` on a closed channel returns
          # `nil` without blocking.
          deferred_done.receive?
          watch_for_changes(watch_options)
        end

        emit_ready_signal(host, port, json_output, base_path)
        # Block the main fiber on the listen fiber's completion so the
        # process stays alive for the lifetime of the server.
        listen_done.receive?

        # The listen fiber died with an exception — serve must exit nonzero,
        # matching how a bind failure is reported (a classified HwaroError
        # that the CLI runner maps to a failure exit code).
        if failure = listen_error
          classified = failure.as?(Hwaro::HwaroError) || Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: "Dev server stopped unexpectedly: #{failure.message}",
            hint: "This is likely a bug or an OS-level socket failure — rerun `hwaro serve` and report the error if it persists.",
          )
          raise classified
        end
      end

      # Path component of `base_url`, mirroring `Models::Config#base_path`
      # (trailing slashes stripped, domain-root deploys yield ""). Kept here so
      # the mount point never depends on a config load that may have failed.
      protected def base_path_for(base_url : String?) : String
        return "" unless base_url
        path = begin
          URI.parse(base_url).path
        rescue URI::Error
          return ""
        end
        # A mount point is an absolute path component. `URI.parse` happily
        # returns an opaque path for junk like "::::" — mounting the site under
        # that would break every route, so only "/"-rooted paths count.
        return "" unless path.starts_with?("/")
        path = path.rstrip("/")
        path == "/" ? "" : path
      end

      # Assemble the dev server's handler chain. Extracted from
      # `run_with_options` so specs can drive the real chain over a fixture
      # directory instead of re-deriving (and drifting from) the order here.
      #
      # Order matters:
      # - NoCache / Charset / CustomHeaders sit outermost so their headers
      #   also reach DevCors' 204 preflight, which short-circuits the chain.
      # - CustomHeaders wraps everything below, so user values win on the way
      #   back out.
      # - BasePath sits above LiveReload so the WebSocket endpoint keeps its
      #   unprefixed path, and above IndexRewrite so redirects are computed on
      #   the stripped path and re-prefixed on the way out.
      protected def build_handlers(
        output_dir : String,
        host : String,
        access_log : Bool,
        live_reload : Bool,
        headers : Hash(String, String),
        base_path : String,
      ) : Array(HTTP::Handler)
        # Loopback literals plus the concrete bound host (a 0.0.0.0/:: wildcard
        # bind has no single host, so it contributes nothing here). The
        # DevCorsHandler reflects a request Origin only when its host is in
        # this set.
        cors_hosts = Set{"localhost", "127.0.0.1", "::1"}
        cors_hosts << host unless host.empty? || host == "0.0.0.0" || host == "::"

        handlers = [] of HTTP::Handler
        handlers << HTTP::LogHandler.new if access_log
        # Dev cache-busting (see NoCacheHandler). A user-supplied
        # Cache-Control from [serve.headers]/--header wins outright.
        handlers << NoCacheHandler.new unless headers.keys.any? { |k| k.downcase == "cache-control" }
        # Runs before StaticFileHandler so it can append `; charset=utf-8` to
        # text-shaped Content-Type headers the static handler sets. See the
        # class comment for why MIME registration, not this, is the primary
        # mechanism.
        handlers << CharsetHandler.new
        handlers << CustomHeadersHandler.new(headers) unless headers.empty?
        handlers << DevCorsHandler.new(cors_hosts)

        # Built up front so UnservablePathHandler can delegate to it and reuse
        # the real 404 body; it is still appended last as the fallthrough.
        inject_handler = live_reload ? LiveReloadInjectHandler.new(output_dir) : nil
        not_found = NotFoundHandler.new(output_dir, inject_handler)

        # FIRST among the routing handlers, above BasePathHandler: the hard
        # refusal has to win in both shapes. When it sat below the mount point,
        # BasePathHandler's canonicalising pre-empt reached an unservable path
        # first and answered `/myblog/%2Fguide%2Findex.html` with a 302 (404
        # without a mount) and `/myblog/index%00.html` with a 500 — `Path.posix`
        # raises on a NUL. Nothing here inspects or strips the prefix, so
        # running before the mount is safe.
        handlers << UnservablePathHandler.new(not_found)
        handlers << BasePathHandler.new(base_path) unless base_path.empty?
        if live_reload
          lr_handler = LiveReloadHandler.new
          @live_reload_handler = lr_handler
          handlers << lr_handler
        end
        handlers << IndexRewriteHandler.new(output_dir)
        handlers << inject_handler if inject_handler
        # Just above the static handler: generates a lazily-deferred OG image
        # on first request, then lets StaticFileHandler serve it from disk.
        # A no-op unless [og.auto_image] lazy_generate is enabled.
        handlers << OgLazyImageHandler.new(@builder, output_dir)
        handlers << HTTP::StaticFileHandler.new(output_dir, directory_listing: false, fallthrough: true)
        handlers << not_found
        handlers
      end

      # Push a build failure to connected browsers so the live-reload client
      # can draw its overlay. Silent under --no-error-overlay: that flag used
      # to reach only the per-page render fallback, leaving the full-screen
      # overlay in place for users who had asked for no overlays at all.
      private def push_build_error(message : String)
        return unless @error_overlay
        @live_reload_handler.try(&.notify_build_error(truncate_build_error(message)))
      end

      # Clamp a build-failure message to MAX_BUILD_ERROR_CHARS. Counted in
      # characters, not bytes: the message is rendered as text in the overlay
      # and printed to the terminal, and a byte slice can split a UTF-8
      # sequence.
      private def truncate_build_error(message : String) : String
        Hwaro::Utils::TextUtils.truncate_error(message, MAX_BUILD_ERROR_CHARS)
      end

      # Emit a single deterministic, machine-parseable line indicating the
      # server is bound and ready to accept connections. Scripts and agents
      # can block on this line to know when `hwaro serve` is ready.
      #
      # Emitted AFTER `bind_tcp` succeeds (so the OS-level listening socket
      # already accepts connections) and BEFORE `listen` starts the blocking
      # accept loop. Written directly to STDOUT (no log prefix; dimmed on an
      # interactive TTY, raw bytes everywhere else) and flushed immediately so
      # subprocess consumers see it without buffering delay.
      #
      # Coexists with the pretty "Serving site at …" banner logged earlier —
      # this is an additional single line, not a replacement.
      #
      # With `json: true` (the `--json` flag), the emitted line is a
      # compact JSON document matching the schema from issue #356:
      #   {"event":"ready","url":"...","host":"...","port":N,"pid":P}
      # Otherwise the human-readable `hwaro serve: ready url=... pid=...`
      # line from issue #360 is emitted.
      private def emit_ready_signal(host : String, port : Int32, json : Bool = false, base_path : String = "")
        line = json ? ready_signal_json(host, port, base_path) : ready_signal_line(host, port, base_path)
        # On an interactive colored TTY the machine line is dimmed so it reads
        # as a footnote under the serve receipt; the bytes inside the escapes
        # are unchanged. Pipes and CI (non-TTY) get the raw line exactly as
        # documented — that is where machine consumers live.
        line = Logger.paint(line, Logger::Role::Dim) if !json && Logger.color_enabled?
        STDOUT.puts(line)
        STDOUT.flush
      end

      # The URL the site is actually reachable at. Single source of truth for
      # the serve receipt and both ready signals: they used to compose it
      # independently, and only the receipt learned about `base_path` — so a
      # script blocking on the ready line fetched the bare origin and got a
      # 302 it may not follow.
      protected def serve_url(host : String, port : Int32, base_path : String = "") : String
        origin = "http://#{Config::Options::ServeOptions.url_host(host)}:#{port}"
        base_path.empty? ? origin : "#{origin}#{base_path}/"
      end

      # Build the deterministic ready-signal line. Kept separate from
      # `emit_ready_signal` so specs can assert on the format without
      # capturing stdout.
      protected def ready_signal_line(host : String, port : Int32, base_path : String = "") : String
        "hwaro serve: ready url=#{serve_url(host, port, base_path)} pid=#{Process.pid}"
      end

      # JSON variant of the ready signal — single-line document on stdout so
      # CI scripts and agents can parse it with `jq` / `JSON.parse`.
      protected def ready_signal_json(host : String, port : Int32, base_path : String = "") : String
        {
          "event" => "ready",
          "url"   => serve_url(host, port, base_path),
          "host"  => host,
          "port"  => port,
          "pid"   => Process.pid,
        }.to_json
      end

      private def sanitize_output_dir(dir : String) : String
        normalized = Path[dir].normalize.to_s
        if normalized.starts_with?("..") || normalized.starts_with?("/")
          Logger.warn "Invalid output directory: #{dir}. Using 'public' instead."
          return "public"
        end
        normalized
      end

      # Snapshot the watcher baseline. Called by run_with_options BEFORE the
      # initial build so files edited while it runs still diff as changed.
      private def capture_watch_baseline
        @watch_baseline = scan_mtimes
      end

      # The mtime snapshot the watch loop starts from: the pre-build baseline
      # when one was captured (consumed here — it is only valid once), a
      # fresh scan otherwise.
      private def initial_watch_mtimes : Hash(String, FileStamp)
        baseline = @watch_baseline
        @watch_baseline = nil
        baseline || scan_mtimes
      end

      private def watch_for_changes(build_options : Config::Options::BuildOptions)
        # Watched roots are shown in the serve receipt's "watch" row.
        last_mtimes = initial_watch_mtimes

        loop do
          sleep POLL_INTERVAL

          # The scan/diff/debounce steps run outside the build rescue below;
          # an exception there (filesystem churn, permission flips, …) would
          # otherwise kill this fiber and silently stop rebuilds for the rest
          # of the serve session while the HTTP server keeps running.
          begin
            current_mtimes = scan_mtimes
            if current_mtimes != last_mtimes
              changeset = detect_changes(last_mtimes, current_mtimes)
              last_mtimes = current_mtimes

              # Debounce: wait for changes to settle before rebuilding.
              # This batches rapid successive saves (e.g. multi-file save,
              # IDE format-on-save) into a single rebuild.
              unless changeset.empty?
                changeset, last_mtimes = debounce_changes(changeset, last_mtimes)

                begin
                  # apply_changeset owns the @rebuild_failed reset: it clears
                  # the flag only after a SUCCESSFUL rebuild. Resetting here
                  # unconditionally used to clobber the flag apply_changeset
                  # had just set for a Bool-failure build (pre-hook failure /
                  # phase abort return false without raising), breaking the
                  # full-rebuild-recovery contract for that path.
                  apply_changeset(changeset, build_options)
                rescue ex
                  # Surface the failure both in the terminal and the
                  # browser. Without the WS push the developer sees the
                  # stale page and keeps editing on top of a broken
                  # build until they happen to glance at the terminal.
                  @rebuild_failed = true
                  Logger.error "[Watch] Build failed: #{truncate_build_error(ex.message || "")}"
                  Logger.debug "[Watch] Backtrace: #{ex.backtrace?.try(&.first(5).join("\n    ")) || "unavailable"}"
                  push_build_error(ex.message || "Build failed")
                end
              end
            end
          rescue ex
            Logger.error "[Watch] Watcher iteration failed: #{ex.message} (retrying)"
            Logger.debug "[Watch] Backtrace: #{ex.backtrace?.try(&.first(5).join("\n    ")) || "unavailable"}"
          end
        end
      end

      # Wait for rapid successive changes to settle, merging all detected
      # changesets into one.  Returns the merged changeset.
      private def debounce_changes(initial : ChangeSet, last_mtimes : Hash(String, FileStamp)) : {ChangeSet, Hash(String, FileStamp)}
        merged = initial
        current_mtimes = last_mtimes
        iterations = 0

        loop do
          sleep DEBOUNCE_INTERVAL
          iterations += 1

          new_mtimes = scan_mtimes
          if new_mtimes != current_mtimes
            additional = detect_changes(current_mtimes, new_mtimes)
            current_mtimes = new_mtimes
            merged = merged.merge(additional) unless additional.empty?

            if iterations >= MAX_DEBOUNCE_ITERATIONS
              Logger.debug "[Watch] Debounce cap reached (#{MAX_DEBOUNCE_ITERATIONS} iterations). Proceeding with rebuild."
              break
            end
          else
            # No more changes — settled
            break
          end
        end

        {merged, current_mtimes}
      end

      # Diff two mtime snapshots and return a categorised ChangeSet.
      private def detect_changes(
        old_mtimes : Hash(String, FileStamp),
        new_mtimes : Hash(String, FileStamp),
      ) : ChangeSet
        modified_content = [] of String
        modified_content_files = [] of String
        modified_templates = [] of String
        modified_static = [] of String
        modified_data = [] of String
        added_files = [] of String
        removed_files = [] of String
        config_changed = false

        # --- Files that exist in both snapshots but with different mtime ---
        new_mtimes.each do |path, new_mtime|
          if old_mtime = old_mtimes[path]?
            next if old_mtime == new_mtime # unchanged

            if path == "config.toml" || path == @env_config_file
              config_changed = true
            else
              classify_modified(path, modified_content, modified_content_files, modified_templates, modified_static, modified_data)
            end
          else
            # New file (exists now, didn't before)
            added_files << path
          end
        end

        # --- Files that existed before but are now gone ---
        old_mtimes.each_key do |path|
          unless new_mtimes.has_key?(path)
            removed_files << path
          end
        end

        ChangeSet.new(
          modified_content: modified_content,
          modified_content_files: modified_content_files,
          modified_templates: modified_templates,
          modified_static: modified_static,
          modified_data: modified_data,
          added_files: added_files,
          removed_files: removed_files,
          config_changed: config_changed,
        )
      end

      # Put a modified path into the right bucket.
      #
      # Non-Markdown files under `content/` (images, PDFs, anything copied via
      # `[content.files] allow_extensions`) used to land in `content` and then
      # get silently dropped by `run_incremental` because they have no `Page`
      # entry. They now go into their own bucket and are republished verbatim.
      private def classify_modified(
        path : String,
        content : Array(String),
        content_files : Array(String),
        templates : Array(String),
        static : Array(String),
        data : Array(String),
      )
        if path.starts_with?("content/")
          if path.downcase.ends_with?(".md")
            content << path
          else
            content_files << path
          end
        elsif path.starts_with?("templates/")
          templates << path
        elsif path.starts_with?("static/")
          static << path
        elsif path.starts_with?("data/") || path.starts_with?("i18n/")
          data << path
        end
      end

      # The strategy the watcher will actually run: the changeset's own choice,
      # escalated to a full rebuild when the cheap paths can't be trusted.
      #
      # - Missing output root: `rm -rf public` (or a stray `hwaro build -o …`)
      #   mid-session used to poison the next save — the incremental
      #   strategies only rewrite the pages that changed and never recreate
      #   the directory tree around them, so every page raised "No such file
      #   or directory" on its temp file and only the @rebuild_failed-forced
      #   rebuild on the save AFTER that recovered.
      # - Previous failure: the pages a failed rebuild left stale are not
      #   re-selected when the next event touches an unrelated file.
      private def effective_strategy(changeset : ChangeSet, output_dir : String) : Symbol
        strategy = changeset.rebuild_strategy
        return strategy if strategy == :full

        unless Dir.exists?(output_dir)
          Logger.info "  Output directory was missing — running a full rebuild to recover."
          return :full
        end

        if @rebuild_failed
          Logger.info "  Previous rebuild failed — running a full rebuild to recover."
          return :full
        end

        strategy
      end

      # Choose the cheapest rebuild strategy for a given ChangeSet and execute it.
      private def apply_changeset(changeset : ChangeSet, build_options : Config::Options::BuildOptions)
        output_dir = sanitize_output_dir(build_options.output_dir)
        strategy = effective_strategy(changeset, output_dir)
        # Recreate a vanished output root before anything writes into it.
        Hwaro::Utils::FileSafe.mkdir_p(output_dir) unless Dir.exists?(output_dir)
        # Calm watch timeline: one "↻ <what> · time" event at column 0 (the ↻
        # glyph carries "changed"), then the rebuild's own spark "rebuilt …"
        # outcome line below it. The strategy is implied by that outcome
        # (incremental N/M, re-render, full).
        timestamp = Time.local.to_s("%H:%M:%S")
        if Logger.color_enabled?
          Logger.info "\n#{Logger.glyph(:watch)} #{changeset.display}" \
                      "#{Logger.paint(" · ", Logger::Role::Dim)}#{Logger.paint(timestamp, Logger::Role::Dim)}"
        else
          Logger.info "\n~ #{timestamp}  changed  #{changeset.display}"
        end

        # Resolve removed sources to their output files BEFORE the rebuild
        # swaps in a site that no longer knows the deleted page's URL.
        stale_outputs = if changeset.removed_files.empty?
                          [] of String
                        else
                          @builder.stale_outputs_for_removed(changeset.removed_files, output_dir)
                        end

        success = case strategy
                  when :full
                    @builder.run(build_options)
                  when :templates
                    @builder.run_rerender(build_options)
                  when :incremental
                    @builder.run_incremental(changeset.modified_content, build_options)
                  when :content_and_template
                    @builder.run_incremental_then_rerender(changeset.modified_content, build_options)
                  when :static
                    copy_static(changeset, build_options)
                  when :content_files
                    copy_content_files(changeset, build_options)
                    true
                  else
                    true
                  end

        # A build can fail WITHOUT raising: pre-hook failures and phase
        # aborts (non-classified exceptions become HookResult::Abort) return
        # false. Treat that exactly like the rescue path in the caller —
        # flag it so the next changeset escalates to a full rebuild, push
        # the overlay, and skip the reload so the browser doesn't refresh
        # onto a half-built site with no visible error.
        unless success
          @rebuild_failed = true
          push_build_error("Build failed — check the terminal for details.")
          return
        end

        # Clear the failure escalation HERE, where success is actually known.
        # The watch loop must not reset it — apply_changeset returns normally
        # after a Bool-failure build too (see the `unless success` guard).
        @rebuild_failed = false

        # A config edit rebuilt the site with the new values, but [serve.*]
        # keys were consumed at startup — warn instead of silently looking
        # like they applied.
        warn_restart_only_serve_settings if changeset.config_changed

        # Copy static files if they changed alongside content/template changes
        if strategy != :static && strategy != :full && !changeset.modified_static.empty?
          unless copy_static(changeset, build_options)
            @rebuild_failed = true
            push_build_error("Build failed — check the terminal for details.")
            return
          end
        end

        # Republish non-Markdown content assets whenever they accompany any
        # rebuild that wasn't a full one. A full build already re-copies them
        # via the ReadContent → Write raw-files path; for incremental,
        # templates-only, and static-only strategies, the watcher has to do
        # it explicitly or the served bytes stay stale (issue #530).
        if strategy != :content_files && strategy != :full && !changeset.modified_content_files.empty?
          copy_content_files(changeset, build_options)
        end

        # The stale list was mapped through the PRE-rebuild site, but a
        # single changeset can delete one source and re-create the same URL
        # from another (foo.md removed + foo/index.md added). The rebuild
        # just wrote that output for the NEW owner — deleting it here would
        # 404 the page until an unrelated rebuild. Skip anything the rebuilt
        # site still claims.
        unless stale_outputs.empty?
          owned = @builder.owned_output_paths(output_dir)
          stale_outputs = stale_outputs.reject { |path| owned.includes?(path) }
        end
        remove_stale_outputs(stale_outputs, output_dir)

        @live_reload_handler.try(&.notify_reload)
      end

      # [serve.*] keys are consumed once at startup (headers baked into the
      # handler chain, fast → skip flags in the frozen watch options). A
      # config edit triggers a full rebuild that LOOKS like it applied them —
      # say so instead of leaving the user chasing a phantom.
      private def warn_restart_only_serve_settings
        current = @builder.config.try(&.serve)
        return unless current
        unless startup = @startup_serve_config
          # Initial build never loaded a config (it failed) — this rebuild's
          # values become the baseline.
          @startup_serve_config = current
          return
        end
        if startup.headers != current.headers || startup.fast != current.fast
          Logger.warn "  [serve] settings changed in config — restart `hwaro serve` to apply them."
        end
      end

      # Delete output files orphaned by removed sources, pruning any
      # directories the deletion leaves empty (e.g. `public/guide/old-page/`).
      private def remove_stale_outputs(paths : Array(String), output_dir : String)
        paths.each do |path|
          next unless File.exists?(path)
          next unless Utils::OutputGuard.within_output_dir?(path, output_dir)
          File.delete(path)
          Logger.info "  Removed stale output: #{path}"

          dir = File.dirname(path)
          while dir != output_dir && Utils::OutputGuard.within_output_dir?(dir, output_dir) && Dir.exists?(dir) && Dir.empty?(dir)
            Dir.delete(dir)
            dir = File.dirname(dir)
          end
        rescue ex
          Logger.debug "  Could not remove stale output #{path}: #{ex.message}"
        end
      end

      # Returns false when an escalated re-render failed (bundle fingerprint
      # moved and the page re-render below reported failure); true otherwise.
      private def copy_static(changeset : ChangeSet, build_options : Config::Options::BuildOptions) : Bool
        output_dir = sanitize_output_dir(build_options.output_dir)
        @builder.copy_changed_static(changeset.modified_static, output_dir, build_options.verbose)
        # Changed image BYTES need their resized variants/LQIP regenerated
        # too — the resize hook only runs on full builds, so the copy above
        # alone left variants stale for the whole serve session (A12).
        unless build_options.skip_image_processing
          if config = @builder.config
            Hwaro::Content::Hooks::ImageHooks.reprocess_changed_images(changeset.modified_static, config, output_dir)
          end
        end
        # SCSS sources never publish verbatim — when one changed, recompile
        # the entries instead. A partial edit must rebuild every entry that
        # imports it, and there is no dependency graph, so the whole tree
        # recompiles (cheap at static-site scale). Compile errors raise and
        # reach the watcher rescue → browser overlay. The predicate is the
        # same one the copy paths use, so the gate can't drift.
        bundles_changed = false
        if (config = @builder.config) && changeset.modified_static.any? { |p| config.sass_source?(p) }
          bundles_changed = @builder.recompile_sass(output_dir)
        elsif changeset.modified_static.any? { |p| @builder.asset_bundle_source?(p) }
          # Plain (non-Sass) CSS/JS bundle sources only ever rebuilt inside
          # the full-build asset pipeline — a static-only save left the
          # fingerprinted bundle stale for the whole serve session.
          bundles_changed = @builder.reprocess_asset_bundles(output_dir)
        end

        # A changed fingerprint means every page referencing the bundle via
        # `asset()` still points at the OLD hash — rebuild so the HTML on
        # disk picks the new path up (covers the Sass path too). A full
        # rebuild, not run_rerender: templates are byte-identical here, so
        # the rerender's selective path would (correctly, by its own
        # contract) re-render nothing. Correctness over cleverness — the
        # rebuild reuses the same options the watcher's :full strategy runs.
        if bundles_changed
          Logger.info "  Asset bundle fingerprints changed — rebuilding pages to update references."
          return @builder.run(build_options)
        end
        true
      end

      private def copy_content_files(changeset : ChangeSet, build_options : Config::Options::BuildOptions)
        output_dir = sanitize_output_dir(build_options.output_dir)
        @builder.copy_changed_content_files(changeset.modified_content_files, output_dir, build_options.verbose)
        # Mirror copy_static: modified image bytes under content/ (published
        # via [content.files] or as page-bundle assets) must refresh their
        # resized variants/LQIP too (A12).
        unless build_options.skip_image_processing
          if config = @builder.config
            pages = @builder.site.try { |s| (s.pages + s.sections).as(Array(Models::Page)) }
            Hwaro::Content::Hooks::ImageHooks.reprocess_changed_images(changeset.modified_content_files, config, output_dir, pages: pages)
          end
        end
      end

      # Allowlist for URLs handed to the OS opener. Serve's own URLs can
      # carry bracketed IPv6 hosts (`http://[::1]:3000`, from `-b ::1`) and
      # percent-encoded path bytes (`/my%20blog/` base paths), so `[`, `]`
      # and `%` are part of the safe set alongside host/path characters.
      protected def url_openable?(url : String) : Bool
        (url.starts_with?("http://") || url.starts_with?("https://")) &&
          url.matches?(/\Ahttps?:\/\/[a-zA-Z0-9.:\/\-_\[\]%]+\z/)
      end

      private def open_browser_url(url : String)
        unless url_openable?(url)
          # Say why nothing opened instead of silently returning — the user
          # asked for --open and got no browser.
          Logger.debug "Not opening browser: URL contains characters outside the safe allowlist: #{url}"
          return
        end

        {% if flag?(:darwin) %}
          Process.run("open", [url])
        {% elsif flag?(:linux) %}
          Process.run("xdg-open", [url])
        {% elsif flag?(:windows) %}
          Process.run("cmd", ["/c", "start", url])
        {% end %}
      rescue ex
        Logger.debug "Failed to open browser: #{ex.message}"
      end

      # Paths matching these regexes are treated as editor byproducts
      # (backups, swap files, autosaves, OS metadata) and are excluded
      # from the watcher. Editors using `rename`-based atomic save or
      # keep-a-backup patterns (vim's default, `sed -i.bak`, emacs,
      # JetBrains, …) used to double-trigger rebuilds — once for the
      # real edit and once for the byproduct — and each event forced a
      # full rebuild (see server.cr `:full` strategy fallback).
      WATCHER_IGNORE_PATTERNS = [
        /\.bak$/,
        /~$/,
        /\.swp$/, /\.swo$/, /\.swx$/,
        /\.DS_Store$/,
        # emacs lock file:   .#filename
        # emacs autosave:    #filename#
        /(?:\A|\/)\.#[^\/]+$/,
        /(?:\A|\/)#[^\/]+#$/,
        # Atomic-save temp files: write-to-temp-then-rename editors create
        # these next to the target for a moment. Watching them turned every
        # such save into an add+remove pair — a needless FULL rebuild — and,
        # worse, could trigger a rebuild while the real file was still being
        # swapped in.
        /\.tmp$/,
        /\.crswap$/,                        # VS Code safe-write swap
        /___jb_tmp___$/,                    # JetBrains safe write
        /___jb_old___$/,                    # JetBrains safe-write backup
        /(?:\A|\/)\.goutputstream-[^\/]+$/, # GNOME (gedit) atomic save
        /(?:\A|\/)4913$/,                   # vim's write-permission probe
        # Hidden state directories editors/VCS maintain inside watched roots
        # (Obsidian vaults under content/ are common). The scan includes
        # dotfiles — publishable ones like static/.well-known/* must be
        # watched — so this churn has to be filtered by name.
        /(?:\A|\/)\.(?:git|obsidian|idea|vscode)\//,
      ]

      protected def self.watcher_ignored?(path : String) : Bool
        basename = File.basename(path)
        WATCHER_IGNORE_PATTERNS.any? { |re| re.matches?(path) || re.matches?(basename) }
      end

      # Is this watch root a directory we can actually walk?
      #
      # `Dir.exists?` answers `false` only for ENOENT/ENOTDIR — every other
      # stat failure raises. A root that is itself an unresolvable symlink
      # (a cycle, or a link whose target sits behind a directory we may not
      # traverse) therefore threw out of scan_mtimes and wedged the watcher
      # exactly as the per-file case below did. A root we cannot stat has
      # nothing watchable under it, so treat it like a missing one.
      private def watchable_root?(dir : String) : Bool
        Dir.exists?(dir)
      rescue ex : File::Error
        Logger.debug "Skipping unwatchable directory #{dir}: #{ex.message}"
        false
      end

      private def scan_mtimes : Hash(String, FileStamp)
        mtimes = {} of String => FileStamp
        dirs_to_watch = ["content", "templates", "static", "data", "i18n"]

        dirs_to_watch.each do |dir|
          next unless watchable_root?(dir)
          # DotFiles: the build publishes hidden files (static/.well-known/*,
          # see the equivalent build-side fix), so the watcher must see their
          # edits too — a default glob never descends into dot-directories,
          # leaving those files permanently stale during serve. Editor/VCS
          # noise stays filtered by watcher_ignored?.
          Dir.glob(File.join(dir, "**", "*"), match: File::MatchOptions.glob_default | File::MatchOptions::DotFiles) do |file|
            next if Server.watcher_ignored?(file)
            begin
              # Deciding whether an entry is watchable must NOT raise, and it
              # must happen inside this rescue. `File.directory?` used to stand
              # ahead of it: that call follows symlinks, and `File.info?` only
              # swallows ENOENT/ENOTDIR, so a symlink cycle under a watched
              # root (`ln -s a b; ln -s b a` in static/) threw ELOOP straight
              # out of scan_mtimes. One bad link then broke every scan for the
              # rest of the session — `hwaro serve` died at startup in
              # capture_watch_baseline, or, once watching, logged "[Watch]
              # Watcher iteration failed … (retrying)" on every poll with no
              # rebuild ever running again.
              #
              # lstat first, the same shape collect_static_files uses on the
              # build side so both agree on what a file is: it never follows,
              # so a cycle is just a symlink here, and only real symlinks pay
              # the extra target stat. Only regular files get stamped —
              # directories, dangling links and non-regular entries (FIFO,
              # socket, device node) carry nothing the build can read, and the
              # build skips them too. Failures stay at debug: this loop runs
              # every POLL_INTERVAL, so a warn would repeat forever.
              info = File.info?(file, follow_symlinks: false)
              next if info.nil?
              info = File.info?(file, follow_symlinks: true) if info.symlink?
              next if info.nil? || !info.type.file?
              mtimes[file] = {info.modification_time, info.size.to_i64}
            rescue ex
              Logger.debug "Failed to read file info for #{file}: #{ex.message}"
            end
          end
        end

        config_files = ["config.toml"]
        # The env overlay feeds every rebuild through Models::Config.load —
        # its edits were invisible to the watcher (silently ignored for the
        # whole session) before it was stat'ed here.
        @env_config_file.try { |ec| config_files << ec }
        config_files.each do |cfg|
          next unless File.exists?(cfg)
          begin
            info = File.info(cfg)
            mtimes[cfg] = {info.modification_time, info.size.to_i64}
          rescue ex
            Logger.debug "Failed to read #{cfg} info: #{ex.message}"
          end
        end

        mtimes
      end
    end
  end
end
