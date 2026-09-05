# Dev server — HTTP handler chain (index rewrite, 404, no-cache, CORS, charset, headers, base path, lazy OG images).
#
# Split out of server.cr, which keeps the require order, the Server ivars
# and the boot sequence. Parts only define or reopen types: no requires, no
# load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class IndexRewriteHandler
      include HTTP::Handler

      def initialize(@public_dir : String)
      end

      def call(context)
        path = context.request.path

        if path.ends_with?("/")
          context.request.path = path + "index.html"
          begin
            call_next(context)
          ensure
            # Put the request back the way it arrived. `HTTP::LogHandler` sits
            # outermost and reads `request.resource` AFTER call_next, so
            # leaving the rewrite in place made `--access-log` report
            # `GET /index.html` for a request to `/` (and
            # `GET /about/index.html` for `/about/`) — an access log that no
            # longer matches what the browser asked for is useless for
            # correlating with the browser's own network panel. BasePathHandler
            # already restores its own strip for exactly this reason; without a
            # mount point nothing was undoing this rewrite.
            context.request.path = path
          end
          return
        end

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
  end
end
