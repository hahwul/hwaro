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
require "socket"
require "../../core/build/builder"
require "../../content/hooks"
require "../../utils/errors"
require "../../utils/logger"
require "../../utils/path_utils"
require "../../config/options/serve_options"
require "../../config/options/build_options"
require "../../utils/command_runner"
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
        elsif File.extname(path).empty?
          # Sanitize to prevent directory traversal before filesystem access
          sanitized = Utils::PathUtils.sanitize_path(path)
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
            context.response.status_code = 301
            # Use the already-sanitized path for the Location header to prevent
            # CRLF injection and path traversal in the redirect target.
            context.response.headers["Location"] = "/" + sanitized + "/"
            return
          end
        end

        call_next(context)
      end
    end

    class NotFoundHandler
      include HTTP::Handler

      def initialize(@public_dir : String)
      end

      def call(context)
        context.response.status_code = 404
        context.response.content_type = "text/html; charset=utf-8"

        path_404 = File.join(@public_dir, "404.html")
        if File.exists?(path_404)
          context.response.print File.read(path_404)
        else
          context.response.print "404 Not Found"
        end
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

      def call(context)
        context.response.headers["Access-Control-Allow-Origin"] = "*"

        if context.request.method == "OPTIONS"
          requested_headers = context.request.headers["Access-Control-Request-Headers"]?
          context.response.headers["Access-Control-Allow-Methods"] = "GET, HEAD, OPTIONS"
          context.response.headers["Access-Control-Allow-Headers"] = requested_headers || "*"
          context.response.headers["Access-Control-Max-Age"] = "86400"
          context.response.status_code = 204
          return
        end

        call_next(context)
      end
    end

    # `HTTP::StaticFileHandler` derives `Content-Type` from the file
    # extension via `MIME.from_extension` and writes it without a
    # charset parameter — so `robots.txt` / `llms.txt` / sitemap and
    # search index responses all advertise no charset, leaving UTF-8
    # bytes (e.g. Korean LLM-instructions) at the mercy of client-side
    # heuristics. This handler runs after the static handler and
    # appends `; charset=utf-8` to text-shaped responses.
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
        call_next(context)

        # Apply after all other handlers so user values override built-ins
        # (including Content-Type adjustments and dev CORS headers).
        @headers.each do |name, value|
          # Final guard: never emit control characters in headers even if they
          # somehow made it through config/CLI validation.
          next if name.each_char.any?(&.ascii_control?) || value.each_char.any?(&.ascii_control?)
          context.response.headers[name] = value
        end
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
      )
      end

      # True when the change set is empty (nothing actually changed)
      def empty? : Bool
        @modified_content.empty? &&
          @modified_content_files.empty? &&
          @modified_templates.empty? &&
          @modified_static.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when a full rebuild is unavoidable:
      # config changed, or files were added / deleted (which affects
      # section lists, navigation, taxonomy indices, etc.)
      def needs_full_rebuild? : Bool
        @config_changed || !@added_files.empty? || !@removed_files.empty?
      end

      # True when only template files were modified (no content / static / structural changes)
      def templates_only? : Bool
        !@modified_templates.empty? &&
          @modified_content.empty? &&
          @modified_content_files.empty? &&
          @modified_static.empty? &&
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
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when content and templates changed together (no structural changes)
      def content_and_template_only? : Bool
        !@modified_content.empty? &&
          !@modified_templates.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when content was modified (possibly alongside static changes)
      # but no structural / config / template changes occurred.
      def content_incremental? : Bool
        !@modified_content.empty? &&
          @modified_templates.empty? &&
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

      # Human-readable description of the change for logging.
      def description : String
        parts = [] of String
        parts << "#{@modified_content.size} content" unless @modified_content.empty?
        parts << "#{@modified_content_files.size} content-asset" unless @modified_content_files.empty?
        parts << "#{@modified_templates.size} template" unless @modified_templates.empty?
        parts << "#{@modified_static.size} static" unless @modified_static.empty?
        parts << "#{@added_files.size} added" unless @added_files.empty?
        parts << "#{@removed_files.size} removed" unless @removed_files.empty?
        parts << "config" if @config_changed
        parts.join(", ") + " file(s)"
      end
    end

    class Server
      @builder : Core::Build::Builder
      @live_reload_handler : LiveReloadHandler?

      # Debounce interval: after detecting changes, wait this long for
      # additional changes to settle before triggering a rebuild.
      DEBOUNCE_INTERVAL = 300.milliseconds

      # Maximum number of debounce iterations before forcing a rebuild.
      # Prevents indefinite blocking when files are being written continuously.
      MAX_DEBOUNCE_ITERATIONS = 10

      # Polling interval for the file watcher.
      POLL_INTERVAL = 500.milliseconds

      def initialize
        @builder = Core::Build::Builder.new

        # Register content hooks with lifecycle (same as build command)
        Content::Hooks.all.each do |hookable|
          @builder.register(hookable)
        end
      end

      def run(options : Config::Options::ServeOptions)
        build_options = options.to_build_options
        run_with_options(options.host, options.port, options.open_browser, options.access_log, options.live_reload, build_options, options.json, options.headers)
      end

      def run(host : String = "127.0.0.1", port : Int32 = 3000, drafts : Bool = false)
        build_options = Config::Options::BuildOptions.new(drafts: drafts)
        run_with_options(host, port, false, false, false, build_options, false, {} of String => String)
      end

      private def run_with_options(host : String, port : Int32, open_browser : Bool, access_log : Bool, live_reload : Bool, build_options : Config::Options::BuildOptions, json_output : Bool = false, headers : Hash(String, String) = {} of String => String)
        if build_options.fast_start
          Logger.info "Performing fast-start initial build (priority pages only)..."
        else
          Logger.info "Performing initial build..."
        end
        @builder.run(build_options)

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

        handlers = [] of HTTP::Handler
        handlers << HTTP::LogHandler.new if access_log
        # Set CORS headers first so they apply to every downstream response,
        # including 301 redirects from IndexRewriteHandler and 404s from
        # NotFoundHandler. Without this, opening the site via `localhost`
        # while base_url is baked as `127.0.0.1` (or vice versa) makes
        # browser fetch() calls fail same-origin checks.
        handlers << DevCorsHandler.new
        # Run before StaticFileHandler so we can append `; charset=utf-8`
        # to text-shaped Content-Type headers after the static handler
        # sets them — Crystal's `HTTP::Server::Response` buffers the
        # response until first flush, so post-call_next header edits
        # take effect for typical dev-site responses.
        handlers << CharsetHandler.new
        # User-provided headers (from config + CLI). Placed here so:
        # - it wraps IndexRewrite / LiveReloadInject (catches their early returns)
        # - it runs after DevCors + Charset on the return path (user values win)
        handlers << CustomHeadersHandler.new(headers) unless headers.empty?
        if live_reload
          lr_handler = LiveReloadHandler.new
          @live_reload_handler = lr_handler
          handlers << lr_handler
          handlers << IndexRewriteHandler.new(output_dir)
          handlers << LiveReloadInjectHandler.new(output_dir)
        else
          handlers << IndexRewriteHandler.new(output_dir)
        end
        handlers << HTTP::StaticFileHandler.new(output_dir, directory_listing: false, fallthrough: true)
        handlers << NotFoundHandler.new(output_dir)

        server = HTTP::Server.new(handlers)

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

        url = "http://#{host}:#{port}"
        Logger.success "Serving site at #{url}"
        Logger.info "Press Ctrl+C to stop."
        Logger.info "Live reload enabled" if live_reload

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
        spawn do
          begin
            server.listen
          ensure
            listen_done.close
          end
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
              Logger.error "[Fast-start] Background render failed: #{ex.message}"
              Logger.debug "[Fast-start] Backtrace: #{ex.backtrace?.try(&.first(5).join("\n    ")) || "unavailable"}"
              @live_reload_handler.try(&.notify_build_error(ex.message || "Background render failed"))
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

        emit_ready_signal(host, port, json_output)
        # Block the main fiber on the listen fiber's completion so the
        # process stays alive for the lifetime of the server.
        listen_done.receive?
      end

      # Emit a single deterministic, machine-parseable line indicating the
      # server is bound and ready to accept connections. Scripts and agents
      # can block on this line to know when `hwaro serve` is ready.
      #
      # Emitted AFTER `bind_tcp` succeeds (so the OS-level listening socket
      # already accepts connections) and BEFORE `listen` starts the blocking
      # accept loop. Written directly to STDOUT (no color, no log prefix) and
      # flushed immediately so subprocess consumers see it without buffering
      # delay.
      #
      # Coexists with the pretty "Serving site at …" banner logged earlier —
      # this is an additional single line, not a replacement.
      #
      # With `json: true` (the `--json` flag), the emitted line is a
      # compact JSON document matching the schema from issue #356:
      #   {"event":"ready","url":"...","host":"...","port":N,"pid":P}
      # Otherwise the human-readable `hwaro serve: ready url=... pid=...`
      # line from issue #360 is emitted.
      private def emit_ready_signal(host : String, port : Int32, json : Bool = false)
        STDOUT.puts(json ? ready_signal_json(host, port) : ready_signal_line(host, port))
        STDOUT.flush
      end

      # Build the deterministic ready-signal line. Kept separate from
      # `emit_ready_signal` so specs can assert on the format without
      # capturing stdout.
      protected def ready_signal_line(host : String, port : Int32) : String
        "hwaro serve: ready url=http://#{host}:#{port} pid=#{Process.pid}"
      end

      # JSON variant of the ready signal — single-line document on stdout so
      # CI scripts and agents can parse it with `jq` / `JSON.parse`.
      protected def ready_signal_json(host : String, port : Int32) : String
        {
          "event" => "ready",
          "url"   => "http://#{host}:#{port}",
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

      private def watch_for_changes(build_options : Config::Options::BuildOptions)
        Logger.info "Watching for changes in content/, templates/, static/ and config.toml..."
        last_mtimes = scan_mtimes

        loop do
          sleep POLL_INTERVAL

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
                apply_changeset(changeset, build_options)
              rescue ex
                # Surface the failure both in the terminal and the
                # browser. Without the WS push the developer sees the
                # stale page and keeps editing on top of a broken
                # build until they happen to glance at the terminal.
                Logger.error "[Watch] Build failed: #{ex.message}"
                Logger.debug "[Watch] Backtrace: #{ex.backtrace?.try(&.first(5).join("\n    ")) || "unavailable"}"
                @live_reload_handler.try(&.notify_build_error(ex.message || "Build failed"))
              end
            end
          end
        end
      end

      # Wait for rapid successive changes to settle, merging all detected
      # changesets into one.  Returns the merged changeset.
      private def debounce_changes(initial : ChangeSet, last_mtimes : Hash(String, Time)) : {ChangeSet, Hash(String, Time)}
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
        old_mtimes : Hash(String, Time),
        new_mtimes : Hash(String, Time),
      ) : ChangeSet
        modified_content = [] of String
        modified_content_files = [] of String
        modified_templates = [] of String
        modified_static = [] of String
        added_files = [] of String
        removed_files = [] of String
        config_changed = false

        # --- Files that exist in both snapshots but with different mtime ---
        new_mtimes.each do |path, new_mtime|
          if old_mtime = old_mtimes[path]?
            next if old_mtime == new_mtime # unchanged

            if path == "config.toml"
              config_changed = true
            else
              classify_modified(path, modified_content, modified_content_files, modified_templates, modified_static)
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
        end
      end

      # Choose the cheapest rebuild strategy for a given ChangeSet and execute it.
      private def apply_changeset(changeset : ChangeSet, build_options : Config::Options::BuildOptions)
        strategy = changeset.rebuild_strategy
        Logger.info "\n[Watch] Change detected (#{changeset.description}). Strategy: #{strategy}..."

        case strategy
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
        end

        # Copy static files if they changed alongside content/template changes
        if strategy != :static && strategy != :full && !changeset.modified_static.empty?
          copy_static(changeset, build_options)
        end

        # Republish non-Markdown content assets whenever they accompany any
        # rebuild that wasn't a full one. A full build already re-copies them
        # via the ReadContent → Write raw-files path; for incremental,
        # templates-only, and static-only strategies, the watcher has to do
        # it explicitly or the served bytes stay stale (issue #530).
        if strategy != :content_files && strategy != :full && !changeset.modified_content_files.empty?
          copy_content_files(changeset, build_options)
        end

        @live_reload_handler.try(&.notify_reload)
      end

      private def copy_static(changeset : ChangeSet, build_options : Config::Options::BuildOptions)
        output_dir = sanitize_output_dir(build_options.output_dir)
        @builder.copy_changed_static(changeset.modified_static, output_dir, build_options.verbose)
      end

      private def copy_content_files(changeset : ChangeSet, build_options : Config::Options::BuildOptions)
        output_dir = sanitize_output_dir(build_options.output_dir)
        @builder.copy_changed_content_files(changeset.modified_content_files, output_dir, build_options.verbose)
      end

      private def open_browser_url(url : String)
        unless url.starts_with?("http://") || url.starts_with?("https://")
          return
        end

        unless url.matches?(/\Ahttps?:\/\/[a-zA-Z0-9.:\/\-_]+\z/)
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
      ]

      protected def self.watcher_ignored?(path : String) : Bool
        basename = File.basename(path)
        WATCHER_IGNORE_PATTERNS.any? { |re| re.matches?(path) || re.matches?(basename) }
      end

      private def scan_mtimes : Hash(String, Time)
        mtimes = {} of String => Time
        dirs_to_watch = ["content", "templates", "static"]

        dirs_to_watch.each do |dir|
          next unless Dir.exists?(dir)
          Dir.glob(File.join(dir, "**", "*")) do |file|
            next if File.directory?(file)
            next if Server.watcher_ignored?(file)
            begin
              mtimes[file] = File.info(file).modification_time
            rescue ex
              Logger.debug "Failed to read file info for #{file}: #{ex.message}"
            end
          end
        end

        if File.exists?("config.toml")
          begin
            mtimes["config.toml"] = File.info("config.toml").modification_time
          rescue ex
            Logger.debug "Failed to read config.toml info: #{ex.message}"
          end
        end

        mtimes
      end
    end
  end
end
