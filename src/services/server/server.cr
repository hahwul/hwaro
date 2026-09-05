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
require "digest/md5"
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
require "../../utils/dev_marker"
require "../../utils/hwaro_dir"
require "./dev_path"
require "./live_reload_handler"

require "./handlers"
require "./dev_http_server"
require "./change_set"
require "./watch"
require "./rebuild"

module Hwaro
  module Services
    class Server
      # What the watcher records per file: mtime plus size. Size catches
      # same-tick rewrites on coarse-mtime filesystems (Docker bind mounts,
      # NFS/SMB shares, exFAT) where two quick saves can share a timestamp —
      # an mtime-only comparison would permanently miss the second save.
      #
      # The third slot is a content digest, carried ONLY for the full-rebuild
      # buckets (data/**, i18n/** — nil everywhere else). Those buckets force
      # a full rebuild, and a full rebuild re-runs `build.hooks.pre` — so a
      # hook that rewrites an identical payload into data/ (the pattern #752
      # documents) retriggered itself forever under a stamp-only comparison
      # (#755). The digest lets detect_changes drop stamp movement whose
      # bytes are unchanged. See watch_digest for when it is (re)computed.
      alias FileStamp = {Time, Int64, String?}

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
      # The stamps our own most recent hook-running build left on the watched
      # config files it rewrote WITHOUT changing a byte. Empty for the
      # overwhelmingly common build that touches no config at all. See
      # built_config_rewrite? for what it buys and what it deliberately does
      # not swallow.
      @config_rewritten_by_build = {} of String => FileStamp

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
        run_with_options(options.host, options.port, options.open_browser, options.access_log, options.live_reload, serve_build_options(options), options.json, options.headers)
      end

      # The effective BuildOptions a serve session runs with. Extracted so
      # specs can assert the serve/build output split (issue #756) without
      # binding a socket.
      #
      # `[build]` is merged here as well as in the Builder: BuildOptions is a
      # struct, and the copy the Builder mutates is not this one — without the
      # merge, `[build] drafts`/`cache` would apply to rebuilds but not to the
      # options the server derives its document root and mount point from.
      # `output_dir` is the exception: serve always builds into its own
      # `ServeOptions::DEV_OUTPUT_DIR` (never the configured output_dir, which
      # stays untouched for deploys), enforced by `output_dir_explicit` in
      # `to_build_options`.
      #
      # A missing or invalid config is not fatal here — serve deliberately
      # starts on a broken site, and the Builder reports the error on the
      # initial build.
      protected def serve_build_options(options : Config::Options::ServeOptions) : Config::Options::BuildOptions
        build_options = options.to_build_options
        build_options.serve_mode = true
        begin
          build_options.apply_build_config!(Hwaro::Models::Config.load(env: build_options.env).build)
        rescue Hwaro::HwaroError
        end
        build_options
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
          unless run_full_build(build_options)
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
        # Stamp the served root as dev output no matter how the initial build
        # went — a build that failed before its Initialize phase completed
        # (bad config.toml) never reached the builder-side stamp, and the
        # directory may still hold a previous session's dev pages.
        Hwaro::Utils::DevMarker.write(output_dir)
        # Keep the freshly created `.hwaro/` workspace out of `git status`
        # (the dev pages under it carry dev base_urls and must never be
        # committed). No-op when the guard sees anything but `.hwaro` itself.
        Hwaro::Utils::HwaroDir.ensure_self_ignore(File.dirname(output_dir))

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
        bind_dev_server(server, host, port)

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
        rescue error
          # `watch_for_changes` rescues every iteration of its poll loop, but
          # its one-time setup (`initial_watch_mtimes`, a full stat sweep of
          # the watched roots) runs before that loop and outside any handler.
          # An exception there does not kill the process — Crystal's
          # `Fiber#run` prints `Unhandled exception in spawn` and the server
          # keeps serving — which is precisely the bad outcome: a raw
          # backtrace scrolls past, and from then on saves silently stop
          # rebuilding for the rest of the session with nothing to say why.
          # Report it as what it is, and name the way out.
          Logger.error "[Watch] Watcher could not start: #{error.message}. File changes will not trigger rebuilds; restart 'hwaro serve' to retry."
          Logger.debug "[Watch] Backtrace: #{error.backtrace?.try(&.first(5).join("\n    ")) || "unavailable"}"
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

      # Bind the dev server's listening socket, classifying every way that can
      # fail. Extracted from `run_with_options` so specs can drive the real
      # bind without standing up a whole serve session.
      #
      # `bind_tcp` does TWO things: it resolves `host`, then binds. Only the
      # second half raises `Socket::BindError` — a `-b/--bind` value the
      # resolver cannot answer for (a typo'd hostname, `-b 300.1.1.1`) raises
      # `Socket::Addrinfo::Error`, which fell straight through the old
      # BindError-only rescue and reached the user as a bare, code-less
      # `Error: Hostname lookup for 300.1.1.1 failed: No address found` with no
      # hint and nothing naming the flag that produced it.
      #
      # Resolution is not the only `-b` mistake: an address that resolves but
      # this machine does not hold (`-b 10.255.255.1`) fails INSIDE bind with
      # EADDRNOTAVAIL, and a privileged port (`-p 80`) with EACCES — both
      # arrive as `Socket::BindError`, so both used to get the "another
      # process is listening, try -p/--port" hint, which is wrong for each.
      protected def bind_dev_server(server : HTTP::Server, host : String, port : Int32)
        server.bind_tcp host, port
      rescue ex : Socket::BindError
        # Socket::BindError#message already includes the address, so
        # use it verbatim rather than re-prefixing.
        message = ex.message || "Could not bind to '#{host}:#{port}'"
        case ex.os_error
        when Errno::EADDRNOTAVAIL
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_USAGE,
            message: message,
            hint: "Check -b/--bind: #{host} is not an address this machine holds. Use 127.0.0.1, 0.0.0.0, ::1, or one of its interface addresses.",
          )
        when Errno::EACCES
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: message,
            hint: "Port #{port} needs elevated privileges on this system. Try -p/--port with a value above 1023.",
          )
        else
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: message,
            hint: "Is another process already listening on this port? Try -p/--port with a different value.",
          )
        end
      rescue ex : Socket::Error
        # Resolution failures and anything else the socket layer reports.
        # `host` is only ever the `-b/--bind` value, so the hint can name it.
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_USAGE,
          message: "Could not bind to '#{host}:#{port}': #{ex.message}",
          hint: "Check -b/--bind: pass an address this machine holds (127.0.0.1, 0.0.0.0, ::1) or a hostname it can resolve.",
        )
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

      # An absolute path is allowed: `hwaro build -o /srv/site` and
      # `[build] output_dir = "/srv/site"` both write there, and rejecting it
      # here would leave serve building into that directory while serving an
      # empty `public/` — every request a 404 for the whole session. The build's
      # own `guard_output_dir!` is what refuses the genuinely dangerous roots.
      # A `..` path still falls back, and config-loaded values never reach here
      # with one (`Config::Loader.build_output_dir_value` drops those).
      private def sanitize_output_dir(dir : String) : String
        normalized = Path[dir].normalize.to_s
        if normalized.starts_with?("..")
          Logger.warn "Invalid output directory: #{dir}. Using 'public' instead."
          return "public"
        end
        normalized
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
    end
  end
end
