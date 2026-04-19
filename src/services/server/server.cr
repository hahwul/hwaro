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
require "../../core/build/builder"
require "../../content/hooks"
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
          public_real = File.realpath(@public_dir) rescue @public_dir
          resolved = if File.exists?(fs_path.to_s)
                       File.realpath(fs_path) rescue nil
                     else
                       nil
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
        context.response.content_type = "text/html"

        path_404 = File.join(@public_dir, "404.html")
        if File.exists?(path_404)
          context.response.print File.read(path_404)
        else
          context.response.print "404 Not Found"
        end
      end
    end

    # Categorised set of file-system changes detected by the watcher.
    #
    # Changes are split into four buckets so the server can pick the
    # cheapest rebuild strategy.
    struct ChangeSet
      # Content files (.md under content/) that were *modified* (not added/deleted)
      getter modified_content : Array(String)
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
      )
      end

      # True when the change set is empty (nothing actually changed)
      def empty? : Bool
        @modified_content.empty? &&
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
          @modified_static.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when only static files were modified
      def static_only? : Bool
        !@modified_static.empty? &&
          @modified_content.empty? &&
          @modified_templates.empty? &&
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
        else
          :full
        end
      end

      # Human-readable description of the change for logging.
      def description : String
        parts = [] of String
        parts << "#{@modified_content.size} content" unless @modified_content.empty?
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
        run_with_options(options.host, options.port, options.open_browser, options.access_log, options.live_reload, build_options, options.json)
      end

      def run(host : String = "127.0.0.1", port : Int32 = 3000, drafts : Bool = false)
        build_options = Config::Options::BuildOptions.new(drafts: drafts)
        run_with_options(host, port, false, false, false, build_options, false)
      end

      private def run_with_options(host : String, port : Int32, open_browser : Bool, access_log : Bool, live_reload : Bool, build_options : Config::Options::BuildOptions, json_output : Bool = false)
        Logger.info "Performing initial build..."
        @builder.run(build_options)

        # Watch-triggered rebuilds should preserve the already-built output
        # so per-image mtime-skip (and any future incremental hook logic)
        # can short-circuit. Cold start still wipes — see above — to keep
        # serve honest about fresh state.
        watch_options = build_options.dup
        watch_options.preserve_output = true

        spawn do
          watch_for_changes(watch_options)
        end

        url = "http://#{host}:#{port}"
        Logger.success "Serving site at #{url}"
        Logger.info "Press Ctrl+C to stop."

        if open_browser
          spawn do
            sleep 0.5.seconds
            open_browser_url(url)
          end
        end

        output_dir = sanitize_output_dir(build_options.output_dir)

        handlers = [] of HTTP::Handler
        handlers << HTTP::LogHandler.new if access_log
        if live_reload
          lr_handler = LiveReloadHandler.new
          @live_reload_handler = lr_handler
          handlers << lr_handler
          handlers << IndexRewriteHandler.new(output_dir)
          handlers << LiveReloadInjectHandler.new(output_dir)
          Logger.info "Live reload enabled"
        else
          handlers << IndexRewriteHandler.new(output_dir)
        end
        handlers << HTTP::StaticFileHandler.new(output_dir, directory_listing: false, fallthrough: true)
        handlers << NotFoundHandler.new(output_dir)

        server = HTTP::Server.new(handlers)

        address = server.bind_tcp host, port
        emit_ready_signal(host, port, json_output)
        server.listen
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
                Logger.error "[Watch] Build failed: #{ex.message}"
                Logger.debug "[Watch] Backtrace: #{ex.backtrace?.try(&.first(5).join("\n    ")) || "unavailable"}"
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
              classify_modified(path, modified_content, modified_templates, modified_static)
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
          modified_templates: modified_templates,
          modified_static: modified_static,
          added_files: added_files,
          removed_files: removed_files,
          config_changed: config_changed,
        )
      end

      # Put a modified path into the right bucket.
      private def classify_modified(
        path : String,
        content : Array(String),
        templates : Array(String),
        static : Array(String),
      )
        if path.starts_with?("content/")
          content << path
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
        end

        # Copy static files if they changed alongside content/template changes
        if strategy != :static && strategy != :full && !changeset.modified_static.empty?
          copy_static(changeset, build_options)
        end

        @live_reload_handler.try(&.notify_reload)
      end

      private def copy_static(changeset : ChangeSet, build_options : Config::Options::BuildOptions)
        output_dir = sanitize_output_dir(build_options.output_dir)
        @builder.copy_changed_static(changeset.modified_static, output_dir, build_options.verbose)
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

      private def scan_mtimes : Hash(String, Time)
        mtimes = {} of String => Time
        dirs_to_watch = ["content", "templates", "static"]

        dirs_to_watch.each do |dir|
          next unless Dir.exists?(dir)
          Dir.glob(File.join(dir, "**", "*")) do |file|
            next if File.directory?(file)
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
