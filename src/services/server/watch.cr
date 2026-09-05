# Dev server — file watcher (mtime/digest scanning, debouncing, change classification).
#
# Split out of server.cr, which keeps the require order, the Server ivars
# and the boot sequence. Parts only define or reopen types: no requires, no
# load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class Server
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
            current_mtimes = scan_mtimes(last_mtimes)
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

          new_mtimes = scan_mtimes(current_mtimes)
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

        # --- Files that exist in both snapshots but with different stamps ---
        new_mtimes.each do |path, new_stamp|
          if old_stamp = old_mtimes[path]?
            next if old_stamp == new_stamp # unchanged

            if watched_config_file?(path)
              # A config stamp that moved only because OUR OWN last build
              # rewrote it byte-identically is the #760 config loop:
              # config_changed forces a full rebuild, the full rebuild
              # re-runs build.hooks.pre, the hook rewrites config.toml again,
              # forever. Drop it — but only when the stamp is exactly the one
              # that build left behind, so a developer's `touch config.toml`
              # (the documented force-a-full-rebuild escape hatch) still
              # rebuilds.
              next if built_config_rewrite?(path, new_stamp)
              config_changed = true
            elsif identical_rewrite?(path, old_stamp, new_stamp)
              # A data/i18n stamp that moved without a byte changing — the
              # #755 hook loop: reporting it would force a full rebuild,
              # which re-runs build.hooks.pre, which rewrites the file
              # again. Dropping it lets the changeset settle to empty.
              next
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

      # `prev` is the previous snapshot, used only to carry data/i18n digests
      # forward without re-reading files whose stamps are unchanged (see
      # watch_digest). Passing nil — the baseline scan, or a caller without a
      # previous snapshot — computes them fresh.
      private def scan_mtimes(prev : Hash(String, FileStamp)? = nil) : Hash(String, FileStamp)
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
              mtimes[file] = {info.modification_time, info.size.to_i64, watch_digest(file, info, prev)}
            rescue ex
              Logger.debug "Failed to read file info for #{file}: #{ex.message}"
            end
          end
        end

        # The env overlay feeds every rebuild through Models::Config.load —
        # its edits were invisible to the watcher (silently ignored for the
        # whole session) before it was stat'ed here.
        watched_config_files.each do |cfg|
          next unless File.exists?(cfg)
          begin
            info = File.info(cfg)
            mtimes[cfg] = {info.modification_time, info.size.to_i64, nil}
          rescue ex
            Logger.debug "Failed to read #{cfg} info: #{ex.message}"
          end
        end

        mtimes
      end

      # config.toml plus the env overlay (`config.<env>.toml` under
      # --env / HWARO_ENV): the files whose edits force a full rebuild.
      private def watched_config_files : Array(String)
        files = ["config.toml"]
        @env_config_file.try { |ec| files << ec }
        files
      end

      private def watched_config_file?(path : String) : Bool
        path == "config.toml" || path == @env_config_file
      end

      # Stamp + content digest of each watched config file, taken either side
      # of a hook-running build. These always carry a digest, unlike the
      # watcher's own config stamps (scan_mtimes leaves that slot nil): this
      # reads one or two small files once per full build, not a whole tree on
      # every poll.
      private def config_stamps : Hash(String, FileStamp)
        stamps = {} of String => FileStamp
        watched_config_files.each do |cfg|
          info = File.info?(cfg)
          next if info.nil? || !info.type.file?
          stamps[cfg] = {info.modification_time, info.size.to_i64, file_digest(cfg)}
        rescue ex
          Logger.debug "Failed to stamp #{cfg}: #{ex.message}"
        end
        stamps
      end

      private def note_config_rewrites(before : Hash(String, FileStamp))
        rewritten = {} of String => FileStamp
        config_stamps.each do |path, stamp|
          old = before[path]?
          next if old.nil? || old == stamp
          # Same size and same non-nil digest means the bytes the build read
          # are still the bytes on disk. A hook that genuinely changed the
          # config — or one whose file could not be hashed (nil digest) — is
          # NOT recorded, so the next poll reports it and the site rebuilds
          # with the new values.
          next unless old[1] == stamp[1]
          old_digest = old[2]
          next if old_digest.nil? || old_digest != stamp[2]
          rewritten[path] = stamp
        end
        @config_rewritten_by_build = rewritten
      end

      # True when `new_stamp` is precisely the stamp the last hook-running
      # build left on a config file it rewrote byte-identically — which makes
      # it a stamp whose BYTES that build already read (it loads the config
      # before running a single hook, and the entry exists only because the
      # bytes never moved after that). Nothing is owed a rebuild, so the
      # event is dropped even if the developer edited the config in between:
      # the build that followed the edit read it.
      #
      # Comparing
      # the STAMP, not just the bytes, is what keeps `touch config.toml`
      # alive: a touch after the build moves the mtime off the recorded one
      # and is reported as a config change, exactly as documented. (On a
      # filesystem with 1-second mtime granularity a touch landing in the
      # same second as the build's own rewrite is indistinguishable from it
      # and gets absorbed; touching again a moment later forces the rebuild.)
      #
      # Only mtime and size are compared because the watcher's config stamps
      # carry no digest — byte-identity was already established, against the
      # pre-build bytes, when the entry was recorded.
      private def built_config_rewrite?(path : String, new_stamp : FileStamp) : Bool
        built = @config_rewritten_by_build[path]?
        return false if built.nil?
        built[0] == new_stamp[0] && built[1] == new_stamp[1]
      end

      # data/** and i18n/** are the only buckets whose FileStamp carries a
      # content digest. They are the buckets #755 reported: a full rebuild is
      # the only thing that re-runs build.hooks.pre, and a hook rewriting
      # data/ byte-identically then looped forever on its own stamp.
      #
      # content/, templates/ and static/ stay stamp-only because hashing them
      # would tax every save of every page for a rarer case: each has its own
      # hook-free rebuild path (:incremental, :templates, :static copy), and a
      # static file's only full rebuild is the one-time added-file case.
      #
      # That is a cost trade, not a proof of no-loop — it is only the reason
      # THESE buckets are hashed. The two routes that used to bypass it (#760)
      # are closed without hashing anything else: `rebuild_strategy` no longer
      # sends a mixed templates+static changeset to :full (so no hook re-runs
      # for it), and a config.toml that only our own hooks rewrote is dropped
      # by built_config_rewrite?.
      private def digest_watched?(path : String) : Bool
        path.starts_with?("data/") || path.starts_with?("i18n/")
      end

      # The digest slot for a scanned file: nil for stamp-only buckets. For
      # data/i18n, the previous scan's digest is carried forward when
      # mtime+size are unchanged — the bytes can't differ without moving one
      # of them, the same assumption the stamp comparison itself makes — so
      # steady-state polls never re-read content. A read happens only on the
      # poll that first sees a path or sees its stamp move; that includes
      # size-only changes (the change decision doesn't need the digest then,
      # but the next byte-identical hook rewrite does need a fresh baseline
      # to compare against, and the read is amortized against the full
      # rebuild the size change is about to trigger anyway).
      private def watch_digest(file : String, info : File::Info, prev : Hash(String, FileStamp)?) : String?
        return unless digest_watched?(file)

        if prev && (old = prev[file]?) && old[0] == info.modification_time && old[1] == info.size.to_i64
          return old[2]
        end

        file_digest(file)
      end

      # Streamed digest of a file's bytes, nil when it can't be read
      # (unreadable mid-rewrite, or vanished since the stat). Callers treat
      # nil as "no proof of identity", so an error always falls back to the
      # pre-digest behavior — rebuild — and never silently drops a change.
      private def file_digest(path : String) : String?
        digest = Digest::MD5.new
        buffer = Bytes.new(8192)
        File.open(path, "r") do |io|
          while (bytes_read = io.read(buffer)) > 0
            digest.update(buffer[0, bytes_read])
          end
        end
        digest.final.hexstring
      rescue ex
        Logger.debug "Failed to hash #{path}: #{ex.message}"
        nil
      end

      # True only when a data/i18n stamp difference is PROVABLY
      # byte-identical: equal sizes (a size change is always a real change —
      # no digest consulted) and equal non-nil digests. A nil digest — a
      # hash-read failure — never matches, so the event is reported and the
      # full rebuild runs, exactly as before the digests existed.
      private def identical_rewrite?(path : String, old_stamp : FileStamp, new_stamp : FileStamp) : Bool
        return false unless digest_watched?(path)
        return false unless old_stamp[1] == new_stamp[1]

        old_digest = old_stamp[2]
        !old_digest.nil? && old_digest == new_stamp[2]
      end
    end
  end
end
