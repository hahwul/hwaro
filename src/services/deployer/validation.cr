# Deployer — target/source resolution, refusals, warnings and confirmation.
#
# Reopens `Services::Deployer`; deployer.cr keeps the result records, the
# three entry points (plan / run / deploy_structured) and per-target
# dispatch. Parts only reopen the class: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class Deployer
      # Resolve the deploy source directory from options/config (expanded).
      private def resolve_source_dir(options, deployment) : String
        expand_local_path(options.source_dir || deployment.source_dir)
      end

      # Expand a user-supplied local path. `home: true` matters: `path =
      # "~/public"` is the shape Hugo/Jekyll users reach for first, and
      # plain `File.expand_path` left the tilde literal, quietly creating a
      # directory named `~` inside the project instead of deploying home.
      private def expand_local_path(path : String) : String
        File.expand_path(path, home: true)
      end

      # Resolve which deploy target names to act on: explicit CLI targets, then
      # the configured default target, then the first configured target.
      # Duplicate CLI names are collapsed so `hwaro deploy prod prod` doesn't
      # deploy (and report) the same target twice.
      private def resolve_target_names(options, deployment) : Array(String)
        if options.targets.present?
          options.targets.uniq
        elsif default_target = deployment.target
          [default_target]
        elsif deployment.targets.size > 0
          [deployment.targets.first.name]
        else
          [] of String
        end
      end

      # Map target names to configured targets; unknown names raise
      # HWARO_E_USAGE with the configured-target list in the hint. Shared by
      # `#run` and `#plan` so dry-run and real deploys fail identically.
      private def resolve_targets!(
        target_names : Array(String),
        deployment : Models::DeploymentConfig,
      ) : Array(Models::DeploymentTarget)
        target_names.map do |name|
          target = deployment.target_named(name)
          unless target
            available = deployment.targets.map(&.name).join(", ")
            hint = if available.empty?
                     "No targets are configured. Add '[[deployment.targets]]' to config.toml."
                   else
                     "Configured targets: #{available}."
                   end
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "Unknown deploy target: #{name}",
              hint: hint,
            )
          end
          target
        end
      end

      private def raise_missing_url!(target : Models::DeploymentTarget) : NoReturn
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "Target '#{target.name}' is missing 'url' (or 'path' / 'command').",
          hint: "Set one of:\n" \
                "  path    = \"/abs/local/dir\"   # copy to a local directory\n" \
                "  url     = \"file:///abs/dir\"  # same, file:// scheme\n" \
                "  url     = \"s3://bucket\"      # auto-runs `aws s3 sync …`\n" \
                "  url     = \"gs://bucket\"      # auto-runs `gsutil rsync …`\n" \
                "  url     = \"az://container\"   # auto-runs `az storage blob sync …`\n" \
                "  command = \"rsync … {source} user@host:/var/www/\"  # arbitrary shell command",
        )
      end

      private def raise_unsupported_scheme!(target : Models::DeploymentTarget, url : String) : NoReturn
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "Unsupported deploy target URL scheme for '#{target.name}': #{url}",
          hint: "Set 'command' for this target to use external tools (rsync/aws/gsutil/etc). " \
                "Example: command = \"aws s3 sync {source}/ {url} --delete\"",
        )
      end

      # Refuse overlapping source/destination. Symlinks are resolved first so
      # a destination that is a symlink back into the source tree still trips
      # the refusal (a lexical-only comparison would let a strip_index_html
      # target mutate or delete the source).
      private def check_overlap!(source_dir : String, dest_dir : String)
        src = Hwaro::Utils::PathUtils.resolved_real_path(source_dir)
        dst = Hwaro::Utils::PathUtils.resolved_real_path(dest_dir)
        if nested_path?(src, dst) || nested_path?(dst, src)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_USAGE,
            message: "Refusing to deploy: source and destination overlap.",
            hint: "source: #{source_dir} / dest: #{dest_dir}",
          )
        end
      end

      # Enforce the delete safety cap. Any negative value disables the cap —
      # previously only exactly -1 did, so `--max-deletes -3` refused every
      # deploy with "Refusing to delete 0 files".
      private def check_max_deletes!(count : Int32, effective : EffectiveOptions)
        return if effective.max_deletes < 0
        return if count <= effective.max_deletes
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_USAGE,
          message: "Refusing to delete #{count} files (max_deletes: #{effective.max_deletes}).",
          hint: "Set deployment.maxDeletes = -1 (or pass --max-deletes -1) to disable the limit.",
        )
      end

      # The built-in sync only honors matcher `force`; header/compression
      # keys need an object-store/CDN API that hwaro's copy/exec deploys
      # don't speak. Warn instead of silently ignoring configured intent.
      private def warn_unapplied_matchers(deployment : Models::DeploymentConfig)
        return if deployment.matchers.none? { |m| m.cache_control || m.content_type || m.gzip }
        Logger.warn "deployment.matchers: cache_control/content_type/gzip are not applied by hwaro's built-in sync (only 'force' is). Configure headers/compression at your host or CDN."
      end

      # `include` / `exclude` / `strip_index_html` are applied by the built-in
      # file sync (`#build_desired_map`), which only runs for local `file://`
      # and `path` destinations. Command-driven targets — an explicit
      # `command`, or the auto-generated `aws s3 sync` / `gsutil rsync` /
      # `az storage blob sync` for `s3://`, `gs://`, `az://` — hand the whole
      # source tree to an external tool, so those keys have no effect there.
      # Silently dropping them uploaded files the author had explicitly
      # excluded; warn instead (same contract as `#warn_unapplied_matchers`).
      private def warn_unapplied_target_options(target : Models::DeploymentTarget)
        unapplied = [] of String
        unapplied << "include" if target.include
        unapplied << "exclude" if target.exclude
        unapplied << "strip_index_html" if target.strip_index_html
        return if unapplied.empty?

        Logger.warn "deployment target '#{target.name}': #{unapplied.join("/")} #{unapplied.size == 1 ? "is" : "are"} not applied to command-based targets (s3/gs/az/command) — express the filtering in the deploy command itself."
      end

      # Raise HWARO_E_CONFIG when the deploy source directory doesn't exist,
      # or when it is dev-server output (issue #756). The single choke point
      # for all three deploy paths (run / plan / deploy_structured), so
      # `--dry-run` and `--json` refuse exactly like a real deploy.
      private def require_source_dir!(source_dir : String)
        unless Dir.exists?(source_dir)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Source directory not found: #{source_dir}",
            hint: "Run 'hwaro build' first, or pass '--source DIR'.",
          )
        end

        # No override flag on purpose: pages under a dev marker carry the dev
        # server's base_url in every link, so deploying them is never what the
        # user wants. Deleting the marker by hand is the deliberate-enough
        # escape hatch.
        if Utils::DevMarker.present?(source_dir)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Refusing to deploy #{source_dir}: it is `hwaro serve` output (#{Utils::DevMarker::FILENAME} marker present), with dev URLs baked into its pages.",
            hint: "Run 'hwaro build' and deploy its output instead. If you are certain, delete #{File.join(source_dir, Utils::DevMarker::FILENAME)} to proceed.",
          )
        end
      end

      # An empty source is "the site was never built" (or was cleaned), and
      # every delete-capable backend would wipe the destination from it: the
      # built-in sync deletes every stale file, and the auto-generated
      # `aws s3 sync --delete` / `gsutil rsync -d` empty the bucket.
      #
      # Applied per target rather than once per run: a hand-written `command`
      # that never interpolates `{source}` (`netlify deploy --dir=dist`)
      # doesn't read the source at all, and failing it here would block a
      # perfectly valid deploy. `--force` is the documented way to clear a
      # destination deliberately.
      private def require_non_empty_source!(source_dir : String, effective : EffectiveOptions)
        return if effective.force
        return unless Dir.empty?(source_dir)
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "Source directory is empty: #{source_dir}",
          hint: "Run 'hwaro build' first, or pass '--source DIR' pointing at the built site. " \
                "Pass --force to deploy from it anyway.",
        )
      end

      # Clear any symlink standing between `dest_dir` and `dest_rel` — the
      # leaf itself and every intermediate directory segment. Copying through
      # a destination symlink writes *outside* the deploy root (a link at
      # `out/index.html` silently overwrote whatever it pointed at). Removing
      # the link and materialising a real file/directory in its place is what
      # `rsync` does by default, and keeps every write inside the destination.
      private def unlink_destination_symlinks!(dest_dir : String, dest_rel : String) : Nil
        parts = dest_rel.split('/')
        current = dest_dir
        parts.each do |part|
          next if part.empty?
          current = File.join(current, part)
          next unless symlink?(current)
          begin
            File.delete(current)
          rescue ex : File::Error | IO::Error
            # Swallowing this would hand the path straight to `FileUtils.cp`,
            # which follows the surviving link and writes outside the deploy
            # root — the exact failure this method exists to prevent. Fail
            # loudly instead.
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_IO,
              message: "Cannot replace symlink at destination: #{current} (#{ex.message})",
              hint: "Remove #{current} manually; deploying through it would write outside #{dest_dir}.",
            )
          end
        end
      end

      # Refuse a sync that would delete everything at the destination because
      # the source selected nothing. This is almost always `hwaro deploy`
      # before `hwaro build`, or an `include`/`exclude` typo — and the delete
      # cap (256 by default) is high enough to lose a small site silently.
      # `--force` is the documented escape hatch for deliberately clearing a
      # destination.
      private def check_empty_selection!(
        desired : Hash(String, String),
        to_delete : Array(String),
        target : Models::DeploymentTarget,
        effective : EffectiveOptions,
      )
        return unless desired.empty?
        return if to_delete.empty?
        return if effective.force

        filtered = target.include || target.exclude
        hint = if filtered
                 "Check 'include'/'exclude' for target '#{target.name}' — they matched no files. " \
                 "Pass --force to clear the destination anyway."
               else
                 "Run 'hwaro build' first, or pass '--source DIR'. " \
                 "Pass --force to clear the destination anyway."
               end

        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_USAGE,
          message: "Refusing to delete #{to_delete.size} files: target '#{target.name}' selected no files to deploy.",
          hint: hint,
        )
      end

      # Duplicate `name =` entries are a copy/paste slip: `target_named`
      # returns the first match, so every later definition is dead config
      # that looks live in `--list-targets`.
      private def warn_duplicate_targets(deployment : Models::DeploymentConfig)
        duplicates = deployment.targets.map(&.name).tally.select { |_, count| count > 1 }.keys
        return if duplicates.empty?
        Logger.warn "deployment.targets: duplicate target name(s) #{duplicates.sort!.join(", ")} — only the first definition of each is used."
      end

      # `deployment.workers` is parsed for forward compatibility but the
      # built-in sync copies serially and command targets manage their own
      # concurrency, so the value has no effect. Say so instead of letting a
      # tuned number look applied.
      private def warn_unapplied_workers(deployment : Models::DeploymentConfig)
        return if deployment.workers == Models::DeploymentConfig::DEFAULT_WORKERS
        Logger.warn "deployment.workers = #{deployment.workers} is not applied — hwaro's built-in sync copies serially, and command targets (s3/gs/az/command) manage their own concurrency."
      end

      # Raise HWARO_E_CONFIG when no deployment targets are configured.
      private def require_target_names!(target_names : Array(String))
        return unless target_names.empty?
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "No deployment targets configured.",
          hint: "Add '[[deployment.targets]]' to config.toml, or pass target names: hwaro deploy <targets>",
        )
      end

      private def validate_strip_index_html_for_filesystem(target : Models::DeploymentTarget, dest_paths : Array(String)) : Nil
        return unless target.strip_index_html
        # A conflict is a path that is BOTH a file and a directory prefix of
        # another path. The previous `dest_paths.any?(&.starts_with?)` made this
        # O(n^2) (millions of comparisons on a large site). Instead, for each
        # path walk its ancestor prefixes and check membership in a Set — the
        # same O(n) technique validate_destination_paths uses.
        dest_set = dest_paths.to_set
        dest_paths.each do |path|
          next if path.empty?
          parts = path.split('/')
          next if parts.size <= 1
          prefix = ""
          parts[0...-1].each do |part|
            prefix = prefix.empty? ? part : "#{prefix}/#{part}"
            if dest_set.includes?(prefix)
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_CONFIG,
                message: "stripIndexHTML cannot be used with file:// deployments when both '#{prefix}' and '#{prefix}/...' exist.",
                hint: "Disable stripIndexHTML for target '#{target.name}', or deploy via an object store.",
              )
            end
          end
        end
      end

      private def validate_destination_paths(dest_dir : String, dest_paths : Array(String)) : Nil
        dest_set = dest_paths.to_set

        dest_paths.each do |rel|
          next if rel.empty?
          parts = rel.split('/')
          if parts.size > 1
            prefix = ""
            parts[0...-1].each do |part|
              prefix = prefix.empty? ? part : "#{prefix}/#{part}"
              if dest_set.includes?(prefix)
                raise Hwaro::HwaroError.new(
                  code: Hwaro::Errors::HWARO_E_IO,
                  message: "Filesystem deploy conflict: both file '#{prefix}' and path '#{rel}' exist.",
                  hint: "Remove one or the other before deploying.",
                )
              end
            end
          end

          full_path = File.join(dest_dir, rel)
          # A *symlink* to a directory is replaced with a real file by the
          # copy pass (see `unlink_destination_symlinks!`), so only a real
          # directory is an unresolvable conflict here.
          if Dir.exists?(full_path) && !File.symlink?(full_path)
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_IO,
              message: "Destination path is a directory but needs a file: #{rel}",
              hint: "Remove the existing directory at #{full_path} or rename the source file.",
            )
          end

          current = dest_dir
          parts[0...-1].each do |part|
            current = File.join(current, part)
            # lstat, matching the leaf check above: a symlink standing where a
            # directory belongs is replaced by the copy pass, so reporting it
            # as an unresolvable conflict was a dead end for exactly the case
            # `unlink_destination_symlinks!` handles.
            info = begin
              File.info?(current, follow_symlinks: false)
            rescue File::Error | IO::Error
              nil
            end
            next unless info
            next if info.symlink?
            if info.file?
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_IO,
                message: "Destination path is a file but needs a directory: #{current}",
                hint: "Remove the existing file at #{current} or rename the source.",
              )
            end
          end
        end
      end

      private def confirm?(prompt : String) : Bool
        # `--json` promises a single machine-readable document on stdout;
        # a prompt written there corrupts it even on a TTY, so JSON mode is
        # treated as non-interactive and fails loudly instead.
        if !CLI::Prompt.interactive? || CLI::Runner.json_mode?
          # Note: `--force` does NOT bypass an explicit `--confirm` — it only
          # skips the automatic confirmation added for dangerous shell
          # commands. The old hint claimed otherwise and sent script authors
          # down a dead end.
          reason = CLI::Runner.json_mode? ? "--json output must stay machine-readable" : "stdin is not a TTY"
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_USAGE,
            message: "Cannot prompt for confirmation: #{reason}.",
            hint: "Drop --confirm (or confirm = true in config.toml) for non-interactive deploys. " \
                  "If this prompt came from a deploy command with shell metacharacters, --force skips that check.",
          )
        end
        CLI::Prompt.confirm?(prompt, default: false) == true
      end
    end
  end
end
