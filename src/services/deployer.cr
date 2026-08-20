require "file_utils"
require "digest/sha256"
require "json"
require "set"
require "uri"

require "../cli/prompt"
require "../cli/runner"
require "../models/config"
require "../utils/command_runner"
require "../utils/errors"
require "../utils/file_safe"
require "../utils/logger"

module Hwaro
  module Services
    class Deployer
      struct Summary
        property copied : Int32
        property deleted : Int32
        property skipped : Int32

        def initialize(@copied : Int32 = 0, @deleted : Int32 = 0, @skipped : Int32 = 0)
        end
      end

      # A single planned deployment operation produced by `#plan`. Used by
      # `hwaro deploy --dry-run --json` so agents/CI can parse the list of
      # files that would be copied, updated, or deleted for each target.
      record PlannedOp,
        target : String,
        action : String,
        path : String,
        source : String?,
        destination : String? do
        include JSON::Serializable
      end

      # Per-target summary emitted by `#deploy_structured` for
      # `hwaro deploy --json` (non dry-run). Shape is part of the stable
      # JSON schema per issue #374 — agents/CI consume these fields.
      #
      # `error` is nil when `status == "ok"`. When set, it mirrors the
      # classified `HwaroError` payload (`code`, `category`, `message`,
      # `hint`) so the shape lines up with top-level error payloads.
      record DeployResult,
        name : String,
        status : String,
        created : Int32,
        updated : Int32,
        deleted : Int32,
        duration_ms : Float64,
        error : Hash(String, String?)? = nil do
        include JSON::Serializable
      end

      # Counts collected while deploying a single target. Command-based
      # targets report zeros since we can't introspect what the external
      # tool did.
      private struct TargetCounts
        property created : Int32
        property updated : Int32
        property deleted : Int32

        def initialize(@created : Int32 = 0, @updated : Int32 = 0, @deleted : Int32 = 0)
        end
      end

      # Build a list of planned operations across all configured (or explicitly
      # requested) targets without performing any filesystem writes or external
      # commands. Raises the same classified errors as `#run` (missing source,
      # no/unknown targets, bad target config, overlap, delete cap) so
      # `hwaro deploy --dry-run --json` fails the same way a real deploy
      # would instead of reporting an empty plan.
      def plan(options : Config::Options::DeployOptions, config : Models::Config? = nil) : Array(PlannedOp)
        ops = [] of PlannedOp
        config ||= Models::Config.load(env: options.env)
        deployment = config.deployment

        source_dir = resolve_source_dir(options, deployment)
        require_source_dir!(source_dir)

        target_names = resolve_target_names(options, deployment)
        require_target_names!(target_names)

        targets = resolve_targets!(target_names, deployment)
        require_non_empty_source!(source_dir)
        warn_duplicate_targets(deployment)
        warn_unapplied_matchers(deployment)
        warn_unapplied_workers(deployment)
        effective = EffectiveOptions.new(deployment, options)
        force_patterns = force_matcher_patterns(deployment)

        targets.each do |target|
          if command = target.command
            warn_unapplied_target_options(target)
            ops << PlannedOp.new(
              target: target.name,
              action: "command",
              path: expand_placeholders(command, source_dir, target),
              source: source_dir,
              destination: target.url,
            )
            next
          end

          url = target.url
          raise_missing_url!(target) if url.empty?

          if directory_destination = local_directory_destination(url)
            dest_dir = expand_local_path(directory_destination)
            check_overlap!(source_dir, dest_dir)

            desired = build_desired_map(source_dir, target)
            existing = list_existing_files(dest_dir)

            # `--dry-run` is only useful if it fails the way the real deploy
            # would. Skipping these left `--dry-run --json` reporting a clean
            # plan for a destination that a real deploy refuses (e.g. a
            # directory sitting where a file has to go).
            validate_strip_index_html_for_filesystem(target, desired.keys)
            validate_destination_paths(dest_dir, desired.keys)

            to_delete = compute_deletes(existing, desired.keys, target)
            check_empty_selection!(desired, to_delete, target, effective)
            check_max_deletes!(to_delete.size, effective)

            desired.each do |dest_rel, src_path|
              dest_path = File.join(dest_dir, dest_rel)
              if File.exists?(dest_path)
                next if !effective.force && !force_match?(dest_rel, force_patterns) && same_file?(src_path, dest_path)
                ops << PlannedOp.new(target: target.name, action: "update", path: dest_rel, source: src_path, destination: dest_path)
              else
                ops << PlannedOp.new(target: target.name, action: "create", path: dest_rel, source: src_path, destination: dest_path)
              end
            end

            to_delete.each do |rel|
              ops << PlannedOp.new(target: target.name, action: "delete", path: rel, source: nil, destination: File.join(dest_dir, rel))
            end
          elsif auto_command = auto_command_for_url(url, source_dir)
            warn_unapplied_target_options(target)
            ops << PlannedOp.new(
              target: target.name,
              action: "command",
              path: expand_placeholders(auto_command, source_dir, target),
              source: source_dir,
              destination: url,
            )
          else
            raise_unsupported_scheme!(target, url)
          end
        end

        ops
      end

      # Run a real deploy and return a per-target summary suitable for
      # `hwaro deploy --json` (no `--dry-run`). Each target is deployed
      # independently — an exception in one target is captured in its
      # `DeployResult.error` and does NOT abort the remaining targets,
      # so partial failures are visible to agents/CI.
      #
      # Config-load errors intentionally propagate as `HwaroError` so the
      # caller can emit a top-level error payload (shape unchanged).
      def deploy_structured(options : Config::Options::DeployOptions, config : Models::Config? = nil) : Array(DeployResult)
        results = [] of DeployResult
        config ||= Models::Config.load(env: options.env)
        deployment = config.deployment

        source_dir = resolve_source_dir(options, deployment)
        require_source_dir!(source_dir)

        target_names = resolve_target_names(options, deployment)
        require_target_names!(target_names)

        require_non_empty_source!(source_dir)
        warn_duplicate_targets(deployment)
        warn_unapplied_matchers(deployment)
        warn_unapplied_workers(deployment)

        targets = target_names.compact_map do |name|
          target = deployment.target_named(name)
          if target
            target
          else
            available = deployment.targets.map(&.name).join(", ")
            hint = available.empty? ? nil.as(String?) : "Configured targets: #{available}."
            results << DeployResult.new(
              name: name,
              status: "error",
              created: 0, updated: 0, deleted: 0,
              duration_ms: 0.0,
              error: {
                "code"     => Hwaro::Errors::HWARO_E_USAGE,
                "category" => Hwaro::Errors.category_for(Hwaro::Errors::HWARO_E_USAGE).to_s,
                "message"  => "Unknown deploy target: #{name}",
                "hint"     => hint,
              } of String => String?,
            )
            nil
          end
        end

        effective = EffectiveOptions.new(deployment, options)

        targets.each do |target|
          results << deploy_target_structured(target, source_dir, effective, deployment)
        end

        results
      end

      # Deploy a single target while capturing counts, timing, and any
      # classified error. Exceptions raised below are caught here rather
      # than propagating so one failing target doesn't abort the run.
      private def deploy_target_structured(
        target : Models::DeploymentTarget,
        source_dir : String,
        effective : EffectiveOptions,
        deployment : Models::DeploymentConfig,
      ) : DeployResult
        started = Time.instant
        counts = TargetCounts.new
        ok = false
        error : Hwaro::HwaroError? = nil

        begin
          ok, counts = deploy_target_with_counts(target, source_dir, effective, deployment)
        rescue ex : Hwaro::HwaroError
          error = ex
        rescue ex
          # Any non-`HwaroError` reaching here is an unexpected defect,
          # not a network problem. Classifying as HWARO_E_INTERNAL avoids
          # the older blanket-`HWARO_E_NETWORK` that made bugs masquerade
          # as connectivity issues and hid the original message behind a
          # generic "Deploy target 'X' failed" line.
          error = Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_INTERNAL,
            message: ex.message || "Deploy target '#{target.name}' failed with #{ex.class}",
          )
        end

        duration_ms = ((Time.instant - started).total_milliseconds * 100).round / 100

        if err = error
          return DeployResult.new(
            name: target.name,
            status: "error",
            created: counts.created,
            updated: counts.updated,
            deleted: counts.deleted,
            duration_ms: duration_ms,
            error: {
              "code"     => err.code,
              "category" => err.category.to_s,
              "message"  => err.message || "",
              "hint"     => err.hint,
            } of String => String?,
          )
        end

        unless ok
          return DeployResult.new(
            name: target.name,
            status: "error",
            created: counts.created,
            updated: counts.updated,
            deleted: counts.deleted,
            duration_ms: duration_ms,
            error: {
              "code"     => Hwaro::Errors::HWARO_E_NETWORK,
              "category" => Hwaro::Errors.category_for(Hwaro::Errors::HWARO_E_NETWORK).to_s,
              "message"  => "Deploy target '#{target.name}' failed",
              "hint"     => nil.as(String?),
            } of String => String?,
          )
        end

        DeployResult.new(
          name: target.name,
          status: "ok",
          created: counts.created,
          updated: counts.updated,
          deleted: counts.deleted,
          duration_ms: duration_ms,
          error: nil,
        )
      end

      # Deploy a single target, returning both success and the collected
      # counts so `#deploy_structured` can surface file-level stats.
      private def deploy_target_with_counts(
        target : Models::DeploymentTarget,
        source_dir : String,
        effective : EffectiveOptions,
        deployment : Models::DeploymentConfig,
      ) : {Bool, TargetCounts}
        if command = target.command
          ok = deploy_via_command(target, source_dir, command, effective)
          return {ok, TargetCounts.new}
        end

        url = target.url
        raise_missing_url!(target) if url.empty?

        if directory_destination = local_directory_destination(url)
          return deploy_to_directory_with_counts(target, source_dir, directory_destination, effective, deployment)
        end

        if auto_command = auto_command_for_url(url, source_dir)
          Logger.debug "  Auto-generated command for #{url}"
          ok = deploy_via_command(target, source_dir, auto_command, effective)
          return {ok, TargetCounts.new}
        end

        raise_unsupported_scheme!(target, url)
      end

      def run(options : Config::Options::DeployOptions, config : Models::Config? = nil) : Bool
        config ||= Models::Config.load(env: options.env)
        deployment = config.deployment

        source_dir = resolve_source_dir(options, deployment)
        require_source_dir!(source_dir)

        target_names = resolve_target_names(options, deployment)
        require_target_names!(target_names)

        targets = resolve_targets!(target_names, deployment)
        require_non_empty_source!(source_dir)
        warn_duplicate_targets(deployment)
        warn_unapplied_matchers(deployment)
        warn_unapplied_workers(deployment)

        effective = EffectiveOptions.new(deployment, options)

        # All failure paths inside deploy_target now raise HwaroError, so
        # the loop body either completes or the error propagates up to
        # the Runner which renders the classified error + exit code. The
        # Bool return is kept for backwards compatibility with callers
        # that only care about success/skip.
        targets.each do |target|
          deploy_target(target, source_dir, effective, deployment)
        end

        true
      end

      private class EffectiveOptions
        getter confirm : Bool
        getter dry_run : Bool
        getter force : Bool
        getter max_deletes : Int32

        def initialize(deployment : Models::DeploymentConfig, options : Config::Options::DeployOptions)
          @confirm = options.confirm.nil? ? deployment.confirm : options.confirm.as(Bool)
          @dry_run = options.dry_run.nil? ? deployment.dry_run : options.dry_run.as(Bool)
          @force = options.force.nil? ? deployment.force : options.force.as(Bool)
          @max_deletes = options.max_deletes || deployment.max_deletes
        end
      end

      private def deploy_target(
        target : Models::DeploymentTarget,
        source_dir : String,
        effective : EffectiveOptions,
        deployment : Models::DeploymentConfig,
      ) : Bool
        if command = target.command
          return deploy_via_command(target, source_dir, command, effective)
        end

        url = target.url
        raise_missing_url!(target) if url.empty?

        if directory_destination = local_directory_destination(url)
          return deploy_to_directory(target, source_dir, directory_destination, effective, deployment)
        end

        if auto_command = auto_command_for_url(url, source_dir)
          Logger.debug "  Auto-generated command for #{url}"
          return deploy_via_command(target, source_dir, auto_command, effective)
        end

        raise_unsupported_scheme!(target, url)
      end

      # Shell metacharacters that indicate potentially dangerous commands.
      # These are not inherently bad but warrant user attention when present
      # in deploy commands, especially from remote scaffolds.
      DANGEROUS_SHELL_PATTERNS = /[|;&`$]|\bsudo\b|\brm\s+-rf\b/

      private def deploy_via_command(
        target : Models::DeploymentTarget,
        source_dir : String,
        command : String,
        effective : EffectiveOptions,
      ) : Bool
        Logger.heading("deploy", target.name)
        warn_unapplied_target_options(target)
        expanded = expand_placeholders(command, source_dir, target)
        env = {
          "HWARO_DEPLOY_TARGET" => target.name,
          "HWARO_DEPLOY_URL"    => target.url,
          "HWARO_DEPLOY_SOURCE" => source_dir,
        }

        if effective.dry_run
          Logger.info "Dry run: would run command:"
          Logger.info "  #{expanded}"
          return true
        end

        # Always show the command that will be executed
        Logger.info "  Command: #{expanded}"

        # Warn and require confirmation for commands with shell metacharacters
        needs_confirm = effective.confirm
        if !effective.force && DANGEROUS_SHELL_PATTERNS.matches?(expanded)
          Logger.warn "Deploy command contains shell metacharacters (pipes, redirects, subshells, etc.)."
          needs_confirm = true
        end

        if needs_confirm && !confirm?("Run deploy command for '#{target.name}'?")
          Logger.warn "Cancelled."
          return true
        end

        result = Utils::CommandRunner.run(expanded, env: env)
        unless result.output.empty?
          result.output.each_line { |line| Logger.info "  #{line}" }
        end
        unless result.success
          # Surface stderr from the subprocess before raising so the user
          # sees the tool-specific failure detail; the classified error
          # itself carries only the summary exit-code info.
          unless result.error.empty?
            result.error.each_line { |line| Logger.error "  #{line}" }
          end
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: "Deploy command failed (exit #{result.exit_code}): #{expanded}",
            hint: "Inspect the stderr above for details from the deploy tool.",
          )
        end

        Logger.info "" if Logger.color_enabled?
        Logger.outcome("deployed", target.name)
        true
      end

      # Variant of `#deploy_to_directory` that also returns per-action
      # counts (created/updated/deleted) for JSON summary output.
      private def deploy_to_directory_with_counts(
        target : Models::DeploymentTarget,
        source_dir : String,
        dest_dir : String,
        effective : EffectiveOptions,
        deployment : Models::DeploymentConfig,
      ) : {Bool, TargetCounts}
        Logger.heading("deploy", target.name)
        counts = TargetCounts.new
        dest_dir_expanded = expand_local_path(dest_dir)

        check_overlap!(source_dir, dest_dir_expanded)

        Hwaro::Utils::FileSafe.mkdir_p(dest_dir_expanded)

        desired = build_desired_map(source_dir, target)
        existing = list_existing_files(dest_dir_expanded)

        validate_strip_index_html_for_filesystem(target, desired.keys)
        validate_destination_paths(dest_dir_expanded, desired.keys)

        to_delete = compute_deletes(existing, desired.keys, target)
        check_empty_selection!(desired, to_delete, target, effective)
        check_max_deletes!(to_delete.size, effective)

        to_copy, _skipped = compute_copies(desired, dest_dir_expanded, effective.force, force_matcher_patterns(deployment))

        if effective.dry_run
          return {true, counts}
        end

        if effective.confirm && !confirm?("Proceed with deploy to #{dest_dir_expanded}?")
          Logger.warn "Cancelled."
          return {true, counts}
        end

        to_copy.each_with_index do |(dest_rel, src_path), idx|
          Logger.progress(idx + 1, to_copy.size, "Copying ")
          dest_path = File.join(dest_dir_expanded, dest_rel)
          # `existed_before` is sampled after the symlink is cleared: a link
          # replaced by a real file is a create, not an update.
          unlink_destination_symlinks!(dest_dir_expanded, dest_rel)
          existed_before = File.exists?(dest_path)
          Hwaro::Utils::FileSafe.mkdir_p(File.dirname(dest_path))
          FileUtils.cp(src_path, dest_path)
          if existed_before
            counts.updated += 1
          else
            counts.created += 1
          end
        end

        to_delete.each_with_index do |rel, idx|
          Logger.progress(idx + 1, to_delete.size, "Deleting ")
          FileUtils.rm(File.join(dest_dir_expanded, rel))
          counts.deleted += 1
        end

        remove_empty_directories(dest_dir_expanded)
        Logger.info "" if Logger.color_enabled?
        Logger.outcome("deployed", "#{dest_dir_expanded} · #{counts.created} created · #{counts.updated} updated · #{counts.deleted} deleted")
        {true, counts}
      end

      private def deploy_to_directory(
        target : Models::DeploymentTarget,
        source_dir : String,
        dest_dir : String,
        effective : EffectiveOptions,
        deployment : Models::DeploymentConfig,
      ) : Bool
        dest_dir = expand_local_path(dest_dir)

        check_overlap!(source_dir, dest_dir)

        Hwaro::Utils::FileSafe.mkdir_p(dest_dir)

        desired = build_desired_map(source_dir, target)
        existing = list_existing_files(dest_dir)

        validate_strip_index_html_for_filesystem(target, desired.keys)
        validate_destination_paths(dest_dir, desired.keys)

        to_delete = compute_deletes(existing, desired.keys, target)
        check_empty_selection!(desired, to_delete, target, effective)
        check_max_deletes!(to_delete.size, effective)

        to_copy, skipped = compute_copies(desired, dest_dir, effective.force, force_matcher_patterns(deployment))

        Logger::Receipt.new("deploy", target.name)
          .row("source", source_dir)
          .row("dest", dest_dir)
          .row("plan", "copy #{to_copy.size} · delete #{to_delete.size} · skip #{skipped}")
          .emit

        if effective.dry_run
          log_plan(to_copy, to_delete)
          return true
        end

        if effective.confirm && !confirm?("Proceed with deploy to #{dest_dir}?")
          Logger.warn "Cancelled."
          return true
        end

        summary = Summary.new(copied: 0, deleted: 0, skipped: skipped)

        to_copy.each_with_index do |(dest_rel, src_path), idx|
          Logger.progress(idx + 1, to_copy.size, "Copying ")
          dest_path = File.join(dest_dir, dest_rel)
          unlink_destination_symlinks!(dest_dir, dest_rel)
          Hwaro::Utils::FileSafe.mkdir_p(File.dirname(dest_path))
          FileUtils.cp(src_path, dest_path)
          summary.copied += 1
        end

        to_delete.each_with_index do |rel, idx|
          Logger.progress(idx + 1, to_delete.size, "Deleting ")
          FileUtils.rm(File.join(dest_dir, rel))
          summary.deleted += 1
        end

        remove_empty_directories(dest_dir)
        Logger.info "" if Logger.color_enabled?
        Logger.outcome("deployed", "#{dest_dir} · #{summary.copied} copied · #{summary.deleted} deleted · #{summary.skipped} skipped")
        true
      end

      private def build_desired_map(source_dir : String, target : Models::DeploymentTarget) : Hash(String, String)
        desired = {} of String => String

        each_project_file(source_dir) do |path|
          rel = relative_to(path, source_dir)
          next if rel.empty?
          next if ignored_file?(rel)
          next unless included_by_target?(rel, target)

          dest_rel = target.strip_index_html ? strip_index_html(rel) : rel
          desired[dest_rel] = path
        end

        # Deterministic order: plan JSON, progress lines, and copy order must
        # not depend on the OS directory-read order.
        desired.to_a.sort_by!(&.[0]).to_h
      end

      private def compute_copies(
        desired : Hash(String, String),
        dest_dir : String,
        force : Bool,
        force_patterns : Array(Regex) = [] of Regex,
      ) : {Array({String, String}), Int32}
        to_copy = [] of {String, String}
        skipped = 0

        desired.each do |dest_rel, src_path|
          dest_path = File.join(dest_dir, dest_rel)
          if !force && !force_match?(dest_rel, force_patterns) && File.exists?(dest_path) && same_file?(src_path, dest_path)
            skipped += 1
            next
          end
          to_copy << {dest_rel, src_path}
        end

        {to_copy, skipped}
      end

      private def compute_deletes(
        existing : Array(String),
        desired_paths : Array(String),
        target : Models::DeploymentTarget,
      ) : Array(String)
        desired_set = desired_paths.to_set
        # Directory prefixes of desired paths are never stale. A destination
        # symlink is listed as a leaf entry (see `#list_existing_files`), so
        # `out/sub -> …` with a desired `sub/index.html` looked like a stale
        # `sub` — but the copy pass replaces that link with the real directory
        # holding the new file, and deleting it afterwards failed with EPERM.
        ancestors = desired_ancestors(desired_paths)

        existing.select do |rel|
          next false if ignored_file?(rel)
          next false if ancestors.includes?(rel)
          next false unless delete_candidate?(rel, target)
          !desired_set.includes?(rel)
        end
      end

      private def desired_ancestors(desired_paths : Array(String)) : Set(String)
        ancestors = Set(String).new
        desired_paths.each do |path|
          parts = path.split('/')
          next if parts.size <= 1
          prefix = ""
          parts[0...-1].each do |part|
            prefix = prefix.empty? ? part : "#{prefix}/#{part}"
            ancestors << prefix
          end
        end
        ancestors
      end

      private def delete_candidate?(rel : String, target : Models::DeploymentTarget) : Bool
        return true if included_by_target?(rel, target)
        # With strip_index_html the on-disk name for `foo/index.html` is just
        # `foo`, so include/exclude globs written against source paths (e.g.
        # include = "**/*.html") never match the stored name and stale pages
        # would survive every sync. Consider the un-stripped form too.
        target.strip_index_html && included_by_target?("#{rel}/index.html", target)
      end

      private def list_existing_files(dest_dir : String) : Array(String)
        files = [] of String
        return files unless Dir.exists?(dest_dir)

        # `follow_symlinks: false` is load-bearing. Descending into a
        # symlinked directory at the destination made every file *behind*
        # the link a delete candidate, so a stale `out/sub -> /data/sub`
        # link let `hwaro deploy` unlink files outside the deploy root.
        # A link is now a leaf entry: stale ones are removed as links, and
        # their targets are never read or touched.
        each_project_file(dest_dir, follow_symlinks: false) do |path|
          rel = relative_to(path, dest_dir)
          next if rel.empty?
          next if ignored_file?(rel)
          files << rel
        end

        files.sort!
      end

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
        src = existing_real_path(source_dir)
        dst = existing_real_path(dest_dir)
        if nested_path?(src, dst) || nested_path?(dst, src)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_USAGE,
            message: "Refusing to deploy: source and destination overlap.",
            hint: "source: #{source_dir} / dest: #{dest_dir}",
          )
        end
      end

      # Resolve symlinks for the deepest existing ancestor and re-append the
      # not-yet-created remainder. Resolving only the paths that fully exist
      # would compare a resolved source against a lexical destination (e.g.
      # /private/var vs /var on macOS) and miss real overlaps.
      private def existing_real_path(path : String) : String
        suffix = [] of String
        current = path
        until File.exists?(current)
          parent = File.dirname(current)
          return path if parent == current
          suffix << File.basename(current)
          current = parent
        end
        real = File.realpath(current)
        suffix.reverse_each { |part| real = File.join(real, part) }
        real
      rescue File::Error | IO::Error
        path
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

      # Compile `force = true` matcher patterns (regex, per the deploy docs).
      # An invalid pattern warns and is skipped instead of crashing the deploy.
      private def force_matcher_patterns(deployment : Models::DeploymentConfig) : Array(Regex)
        deployment.matchers.select(&.force).compact_map do |matcher|
          Regex.new(matcher.pattern)
        rescue ex : ArgumentError
          Logger.warn "Ignoring invalid deployment matcher pattern #{matcher.pattern.inspect}: #{ex.message}"
          nil
        end
      end

      private def force_match?(rel : String, patterns : Array(Regex)) : Bool
        return false if patterns.empty?
        normalized = rel.gsub('\\', '/')
        patterns.any?(&.matches?(normalized))
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

      # Raise HWARO_E_CONFIG when the deploy source directory doesn't exist.
      private def require_source_dir!(source_dir : String)
        return if Dir.exists?(source_dir)
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "Source directory not found: #{source_dir}",
          hint: "Run 'hwaro build' first, or pass '--source DIR'.",
        )
      end

      # An empty source is "the site was never built" (or was cleaned), and
      # every delete-capable backend would wipe the destination from it: the
      # built-in sync deletes every stale file, and the auto-generated
      # `aws s3 sync --delete` / `gsutil rsync -d` empty the bucket. Checked
      # after target resolution so an unknown-target error still wins.
      private def require_non_empty_source!(source_dir : String)
        return unless Dir.empty?(source_dir)
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "Source directory is empty: #{source_dir}",
          hint: "Run 'hwaro build' first, or pass '--source DIR' pointing at the built site.",
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
          next unless File.symlink?(current)
          begin
            File.delete(current)
          rescue File::Error | IO::Error
            next
          end
        end
      rescue File::Error | IO::Error
        nil
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

      private def included_by_target?(rel : String, target : Models::DeploymentTarget) : Bool
        normalized = rel.gsub('\\', '/')
        # A malformed include/exclude glob raises File::BadPatternError. Treat a
        # bad `include` as not-matching (file excluded) and a bad `exclude` as
        # not-matching (file kept), so a config typo doesn't crash the deploy.
        if inc = target.include
          return false unless Utils::PathUtils.glob_match?(inc, normalized)
        end
        if exc = target.exclude
          return false if Utils::PathUtils.glob_match?(exc, normalized)
        end
        true
      end

      private def ignored_file?(rel : String) : Bool
        normalized = rel.gsub('\\', '/')
        return true if normalized.ends_with?("/.DS_Store") || normalized == ".DS_Store"
        false
      end

      private def strip_index_html(rel : String) : String
        normalized = rel.gsub('\\', '/')
        return normalized if normalized == "index.html"
        if normalized.ends_with?("/index.html")
          return normalized.rchop("/index.html")
        end
        normalized
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
            if File.file?(current)
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_IO,
                message: "Destination path is a file but needs a directory: #{current}",
                hint: "Remove the existing file at #{current} or rename the source.",
              )
            end
          end
        end
      end

      # Compare two files for identical content. Uses size check first,
      # then reads in 8 KiB chunks to avoid loading large files entirely
      # into memory for the common case where files differ early.
      private def same_file?(a : String, b : String) : Bool
        return false unless File.exists?(a) && File.exists?(b)
        return false unless File.info(a).size == File.info(b).size

        File.open(a, "rb") do |fa|
          File.open(b, "rb") do |fb|
            buf_a = Bytes.new(8192)
            buf_b = Bytes.new(8192)
            loop do
              # IO#read may return fewer bytes than requested without being at
              # EOF; fill each buffer fully so a short read on one side isn't
              # mistaken for a content difference.
              read_a = read_fully(fa, buf_a)
              read_b = read_fully(fb, buf_b)
              return false unless read_a == read_b
              return true if read_a == 0
              return false unless buf_a[0, read_a] == buf_b[0, read_b]
            end
          end
        end
      rescue ex : IO::Error | File::Error
        Logger.debug "File comparison failed for #{a} vs #{b}: #{ex.message}"
        false
      rescue ex
        Logger.debug "File comparison failed: #{ex.message}"
        false
      end

      # Read until `slice` is full or EOF; returns the byte count (< slice
      # size only at EOF).
      private def read_fully(io : IO, slice : Bytes) : Int32
        total = 0
        while total < slice.size
          read = io.read(slice[total, slice.size - total])
          break if read == 0
          total += read
        end
        total
      end

      # Prune directories the delete pass emptied. Walks depth-first with
      # lstat instead of `Dir.glob`: glob expands `**` *through* symlinked
      # directories, so the old sweep could delete empty directories that
      # live outside the deploy root entirely. Dot-entries are left alone
      # (glob skipped them too, and the deploy never creates them).
      private def remove_empty_directories(root : String)
        prune_empty_directories(root)
      end

      private def prune_empty_directories(dir : String) : Nil
        Dir.each_child(dir) do |entry|
          next if entry.starts_with?(".")
          full = File.join(dir, entry)
          next if File.symlink?(full)
          next unless Dir.exists?(full)
          prune_empty_directories(full)
          begin
            Dir.delete(full) if Dir.empty?(full)
          rescue File::Error | IO::Error
            next
          end
        end
      rescue File::Error | IO::Error
        nil
      end

      private def each_project_file(root : String, follow_symlinks : Bool = true, &block : String ->)
        visited = Set(String).new
        visited << existing_real_path(root)
        walk_project_files(root, visited, follow_symlinks, &block)
      end

      private def walk_project_files(dir : String, visited : Set(String), follow_symlinks : Bool, &block : String ->)
        Dir.each_child(dir) do |entry|
          next if entry == ".DS_Store"
          full = File.join(dir, entry)
          # info? follows symlinks; broken links and ELOOP entries are
          # skipped instead of crashing the deploy mid-walk.
          info = begin
            File.info?(full, follow_symlinks: follow_symlinks)
          rescue File::Error | IO::Error
            nil
          end
          next unless info
          if !follow_symlinks && info.symlink?
            # Report the link itself so the delete pass can unlink a stale
            # one, without ever reading through it.
            block.call(full)
            next
          end
          if info.directory?
            if entry.starts_with?(".") && entry != ".well-known"
              next
            end
            # Track resolved paths so symlink cycles (public/a → public) and
            # multiple links to the same directory are walked at most once.
            real = begin
              File.realpath(full)
            rescue File::Error | IO::Error
              next
            end
            next if visited.includes?(real)
            visited << real
            walk_project_files(full, visited, follow_symlinks, &block)
          elsif info.file?
            block.call(full)
          end
        end
      end

      private def relative_to(path : String, root : String) : String
        normalized_root = root.gsub('\\', '/')
        normalized_root += "/" unless normalized_root.ends_with?("/")
        normalized_path = path.gsub('\\', '/')
        rel =
          if normalized_path.starts_with?(normalized_root)
            normalized_path[normalized_root.size, normalized_path.size - normalized_root.size]
          else
            normalized_path
          end
        rel.starts_with?("/") ? rel.lchop('/') : rel
      end

      private def nested_path?(a : String, b : String) : Bool
        a = a.rstrip('/')
        b = b.rstrip('/')
        return false if a.empty? || b.empty?
        # Identical directories also count as overlap — otherwise a
        # source == destination config slips past the overlap refusal and a
        # strip_index_html target can mutate/delete the source tree.
        return true if a == b
        b.starts_with?(a + "/")
      end

      private def log_plan(to_copy : Array({String, String}), to_delete : Array(String))
        if to_copy.present?
          Logger.section("copy")
          to_copy.first(50).each { |(dest_rel, _)| Logger.item("+ #{dest_rel}", glyph: :bullet) }
          Logger.item("… and #{to_copy.size - 50} more", glyph: :bullet) if to_copy.size > 50
        end
        if to_delete.present?
          Logger.section("delete")
          to_delete.first(50).each { |rel| Logger.item("- #{rel}", glyph: :bullet) }
          Logger.item("… and #{to_delete.size - 50} more", glyph: :bullet) if to_delete.size > 50
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

      # Supported placeholders in `command = "..."` templates. Listed
      # here so `expand_placeholders` can produce a helpful error message
      # when an unknown `{foo}` slips through (typo, forward-looking
      # name, etc.) instead of sending the literal to the shell.
      COMMAND_PLACEHOLDERS = {"source", "url", "target"}

      # Pattern for `{name}` placeholder tokens in command templates.
      private COMMAND_PLACEHOLDER_RE = /\{([a-zA-Z_][\w-]*)\}/

      private def expand_placeholders(command : String, source_dir : String, target : Models::DeploymentTarget) : String
        # Validate the ORIGINAL template, then substitute in a single pass:
        # expanded values (paths, urls) may legitimately contain `{...}` text
        # and must be neither re-validated nor re-expanded. The previous
        # sequential gsub let a source path containing a literal `{url}` get
        # substituted a second time, corrupting the command and splicing the
        # shell quoting.
        validate_no_unexpanded_placeholders!(command, target)

        command.gsub(COMMAND_PLACEHOLDER_RE) do |token|
          case $~[1]
          when "source" then shell_escape(source_dir)
          when "url"    then shell_escape(target.url)
          when "target" then shell_escape(target.name)
          else               token
          end
        end
      end

      # Raise HWARO_E_CONFIG if the command template contains any unknown
      # `{name}` tokens — catches typos like `{srouce}` and forward-
      # looking placeholders (`{bucket}`, `{region}`) before the literal
      # reaches the underlying deploy tool and produces a confusing
      # downstream error.
      private def validate_no_unexpanded_placeholders!(
        command : String,
        target : Models::DeploymentTarget,
      ) : Nil
        unresolved = command.scan(COMMAND_PLACEHOLDER_RE)
          .map { |m| m[1] }
          .uniq!
          .reject { |name| COMMAND_PLACEHOLDERS.includes?(name) }

        return if unresolved.empty?

        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "Unknown placeholder(s) in 'command' for target '#{target.name}': " \
                   "#{unresolved.map { |n| "{#{n}}" }.join(", ")}",
          hint: "Supported placeholders: #{COMMAND_PLACEHOLDERS.to_a.sort.map { |n| "{#{n}}" }.join(", ")}.",
        )
      end

      # Escape a string for safe interpolation into a shell command.
      # Wraps the value in single quotes and escapes any embedded single quotes.
      # Strips null bytes which can bypass shell escaping.
      private def shell_escape(value : String) : String
        sanitized = value.gsub("\0", "")
        "'" + sanitized.gsub("'", "'\\''") + "'"
      end

      # Auto-generate a deploy command for known cloud URL schemes.
      # Returns nil if the scheme is not recognized.
      private def auto_command_for_url(url : String, source_dir : String) : String?
        uri = begin
          URI.parse(url)
        rescue URI::Error
          return
        end
        # A missing authority means the URL has no bucket — `s3:/bucket`
        # (one slash) parses as scheme `s3` with path `/bucket`. Handing that
        # to `aws s3 sync` produces an opaque CLI error; returning nil routes
        # it to the unsupported-scheme message that names the target.
        case uri.scheme
        when "s3"
          return if uri.host.nil? || uri.host.try(&.empty?)
          "aws s3 sync {source}/ {url} --delete"
        when "gs"
          return if uri.host.nil? || uri.host.try(&.empty?)
          "gsutil -m rsync -r -d {source}/ {url}"
        when "az"
          # az://container → Azure Blob Storage. Inline the container name
          # (uri.host), shell-escaped — `{url}` would expand to the full
          # `az://container` URL, which the az CLI rejects as a container name.
          container = uri.host
          return if container.nil? || container.empty?
          command = "az storage blob sync --source {source} --container #{shell_escape(container)}"
          # az://container/sub/dir → sync under the sub/dir prefix; dropping
          # the path silently deployed to the container root.
          prefix = uri.path.lchop('/')
          command += " --destination #{shell_escape(URI.decode(prefix))}" unless prefix.empty?
          command
        end
      end

      # Any `scheme:` prefix marks the value as a URL rather than a path. The
      # second character class requires at least two scheme characters so a
      # Windows drive letter (`C:\\out`) stays a local path. Matching on
      # `://` alone let a single-slash typo like `s3:/bucket` fall through to
      # the local-copy branch and create a directory literally named `s3:`.
      private URL_SCHEME_RE = /\A[A-Za-z][A-Za-z0-9+.\-]+:/

      private def local_directory_destination(url : String) : String?
        if url.matches?(URL_SCHEME_RE)
          uri = URI.parse(url)
          return unless uri.scheme.try(&.downcase) == "file"
          # Allow both file:///abs/path and file://relative/path forms.
          # For a relative form (file://./out, file://relative/path) URI puts the
          # first segment in `host`; prepend it so the path isn't silently
          # rooted at the filesystem root (file://./out must be ./out, not /out).
          path = uri.path
          if host = uri.host
            path = host + path unless host.empty?
          end
          return if path.empty?
          # URI components stay percent-encoded (a space is `%20`); decode so
          # `file:///var/www/my%20site` deploys to the real directory instead
          # of creating a literal `my%20site` one.
          return URI.decode(path)
        end

        # No scheme: treat as local path
        url
      rescue ex
        Logger.debug "Failed to parse deploy URL '#{url}': #{ex.message}"
        nil
      end
    end
  end
end
