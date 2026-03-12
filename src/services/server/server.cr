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

          # Verify resolved path is within public_dir
          resolved = File.realpath(fs_path) rescue nil
          public_real = File.realpath(@public_dir) rescue @public_dir
          if resolved && resolved.starts_with?(public_real + "/") && Dir.exists?(resolved)
            context.response.status_code = 301
            context.response.headers["Location"] = path + "/"
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

      # True when content was modified (possibly alongside static changes)
      # but no structural / config / template changes occurred.
      def content_incremental? : Bool
        !@modified_content.empty? &&
          @modified_templates.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end
    end

    class Server
      @builder : Core::Build::Builder
      @live_reload_handler : LiveReloadHandler?

      def initialize
        @builder = Core::Build::Builder.new

        # Register content hooks with lifecycle (same as build command)
        Content::Hooks.all.each do |hookable|
          @builder.register(hookable)
        end
      end

      def run(options : Config::Options::ServeOptions)
        build_options = options.to_build_options
        run_with_options(options.host, options.port, options.open_browser, options.access_log, options.live_reload, build_options)
      end

      def run(host : String = "127.0.0.1", port : Int32 = 3000, drafts : Bool = false)
        build_options = Config::Options::BuildOptions.new(drafts: drafts)
        run_with_options(host, port, false, false, false, build_options)
      end

      private def run_with_options(host : String, port : Int32, open_browser : Bool, access_log : Bool, live_reload : Bool, build_options : Config::Options::BuildOptions)
        Logger.info "Performing initial build..."
        @builder.run(build_options)

        spawn do
          watch_for_changes(build_options)
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
        server.listen
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
          sleep 1.seconds

          current_mtimes = scan_mtimes
          if current_mtimes != last_mtimes
            changeset = detect_changes(last_mtimes, current_mtimes)

            unless changeset.empty?
              begin
                apply_changeset(changeset, build_options)
              rescue ex
                Logger.error "[Watch] Build failed: #{ex.message}"
              end
            end

            last_mtimes = current_mtimes
          end
        end
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

      # Choose the cheapest rebuild strategy for a given ChangeSet.
      private def apply_changeset(changeset : ChangeSet, build_options : Config::Options::BuildOptions)
        if changeset.needs_full_rebuild?
          reason = if changeset.config_changed
                     "config"
                   elsif !changeset.added_files.empty?
                     "new files"
                   else
                     "deleted files"
                   end
          Logger.info "\n[Watch] Structural change detected (#{reason}). Full rebuild..."
          @builder.run(build_options)
        elsif changeset.templates_only?
          Logger.info "\n[Watch] Template change detected (#{changeset.modified_templates.size} file(s)). Re-rendering..."
          @builder.run_rerender(build_options)
        elsif changeset.content_incremental?
          count = changeset.modified_content.size
          Logger.info "\n[Watch] Content change detected (#{count} file(s)). Incremental rebuild..."
          @builder.run_incremental(changeset.modified_content, build_options)

          # Also copy any static files that changed alongside content
          unless changeset.modified_static.empty?
            output_dir = sanitize_output_dir(build_options.output_dir)
            @builder.copy_changed_static(changeset.modified_static, output_dir, build_options.verbose)
          end
        elsif changeset.static_only?
          Logger.info "\n[Watch] Static file change detected (#{changeset.modified_static.size} file(s)). Copying..."
          output_dir = sanitize_output_dir(build_options.output_dir)
          @builder.copy_changed_static(changeset.modified_static, output_dir, build_options.verbose)
        else
          # Mixed changes that don't fit neatly into one category
          # (e.g. content + template changes simultaneously) → full rebuild
          Logger.info "\n[Watch] Multiple change types detected. Full rebuild..."
          @builder.run(build_options)
        end

        @live_reload_handler.try(&.notify_reload)
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
