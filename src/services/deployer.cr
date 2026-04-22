require "file_utils"
require "digest/sha256"
require "json"
require "set"
require "uri"

require "../models/config"
require "../utils/command_runner"
require "../utils/errors"
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
      # commands. Returns an empty array when no targets resolve (caller is
      # responsible for surfacing that as a friendly message or JSON error).
      def plan(options : Config::Options::DeployOptions, config : Models::Config? = nil) : Array(PlannedOp)
        ops = [] of PlannedOp
        config ||= Models::Config.load(env: options.env)
        deployment = config.deployment

        source_dir = options.source_dir || deployment.source_dir
        source_dir = File.expand_path(source_dir)
        return ops unless Dir.exists?(source_dir)

        target_names =
          if options.targets.present?
            options.targets
          elsif default_target = deployment.target
            [default_target]
          elsif deployment.targets.size > 0
            [deployment.targets.first.name]
          else
            [] of String
          end
        return ops if target_names.empty?

        targets = target_names.compact_map { |name| deployment.target_named(name) }
        return ops if targets.empty?

        targets.each do |target|
          if command = target.command
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
          next if url.empty?

          if directory_destination = local_directory_destination(url)
            dest_dir = File.expand_path(directory_destination)
            desired = build_desired_map(source_dir, target)
            existing = list_existing_files(dest_dir)

            desired.each do |dest_rel, src_path|
              dest_path = File.join(dest_dir, dest_rel)
              if File.exists?(dest_path)
                next if same_file?(src_path, dest_path)
                ops << PlannedOp.new(target: target.name, action: "update", path: dest_rel, source: src_path, destination: dest_path)
              else
                ops << PlannedOp.new(target: target.name, action: "create", path: dest_rel, source: src_path, destination: dest_path)
              end
            end

            desired_set = desired.keys.to_set
            existing.each do |rel|
              next if desired_set.includes?(rel)
              next unless delete_candidate?(rel, target)
              ops << PlannedOp.new(target: target.name, action: "delete", path: rel, source: nil, destination: File.join(dest_dir, rel))
            end
          elsif auto_command = auto_command_for_url(url, source_dir)
            ops << PlannedOp.new(
              target: target.name,
              action: "command",
              path: expand_placeholders(auto_command, source_dir, target),
              source: source_dir,
              destination: url,
            )
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

        source_dir = options.source_dir || deployment.source_dir
        source_dir = File.expand_path(source_dir)

        unless Dir.exists?(source_dir)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Source directory not found: #{source_dir}",
            hint: "Run 'hwaro build' first, or pass '--source DIR'.",
          )
        end

        target_names =
          if options.targets.present?
            options.targets
          elsif default_target = deployment.target
            [default_target]
          elsif deployment.targets.size > 0
            [deployment.targets.first.name]
          else
            [] of String
          end

        if target_names.empty?
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "No deployment targets configured.",
            hint: "Add '[[deployment.targets]]' to config.toml, or pass target names: hwaro deploy <targets>",
          )
        end

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
        Logger.action(:Deploy, "Target: #{target.name}")

        if command = target.command
          ok = deploy_via_command(target, source_dir, command, effective)
          return {ok, TargetCounts.new}
        end

        url = target.url
        if url.empty?
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Target '#{target.name}' is missing 'url' (or 'command').",
            hint: "Set either 'url' or 'command' in [[deployment.targets]].",
          )
        end

        if directory_destination = local_directory_destination(url)
          return deploy_to_directory_with_counts(target, source_dir, directory_destination, effective)
        end

        if auto_command = auto_command_for_url(url, source_dir)
          Logger.debug "  Auto-generated command for #{url}"
          ok = deploy_via_command(target, source_dir, auto_command, effective)
          return {ok, TargetCounts.new}
        end

        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "Unsupported deploy target URL scheme for '#{target.name}': #{url}",
          hint: "Set 'command' for this target to use external tools (rsync/aws/gsutil/etc). " \
                "Example: command = \"aws s3 sync {source}/ {url} --delete\"",
        )
      end

      def run(options : Config::Options::DeployOptions, config : Models::Config? = nil) : Bool
        config ||= Models::Config.load(env: options.env)
        deployment = config.deployment

        source_dir = options.source_dir || deployment.source_dir
        source_dir = File.expand_path(source_dir)

        unless Dir.exists?(source_dir)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Source directory not found: #{source_dir}",
            hint: "Run 'hwaro build' first, or pass '--source DIR'.",
          )
        end

        target_names =
          if options.targets.present?
            options.targets
          elsif default_target = deployment.target
            [default_target]
          elsif deployment.targets.size > 0
            [deployment.targets.first.name]
          else
            [] of String
          end

        if target_names.empty?
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "No deployment targets configured.",
            hint: "Add '[[deployment.targets]]' to config.toml, or pass target names: hwaro deploy <targets>",
          )
        end

        targets = target_names.map do |name|
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
        Logger.action(:Deploy, "Target: #{target.name}")

        if command = target.command
          return deploy_via_command(target, source_dir, command, effective)
        end

        url = target.url
        if url.empty?
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Target '#{target.name}' is missing 'url' (or 'command').",
            hint: "Set either 'url' or 'command' in [[deployment.targets]].",
          )
        end

        if directory_destination = local_directory_destination(url)
          return deploy_to_directory(target, source_dir, directory_destination, effective)
        end

        if auto_command = auto_command_for_url(url, source_dir)
          Logger.debug "  Auto-generated command for #{url}"
          return deploy_via_command(target, source_dir, auto_command, effective)
        end

        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "Unsupported deploy target URL scheme for '#{target.name}': #{url}",
          hint: "Set 'command' for this target to use external tools (rsync/aws/gsutil/etc). " \
                "Example: command = \"aws s3 sync {source}/ {url} --delete\"",
        )
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

        Logger.success "Deploy command completed."
        true
      end

      # Variant of `#deploy_to_directory` that also returns per-action
      # counts (created/updated/deleted) for JSON summary output.
      private def deploy_to_directory_with_counts(
        target : Models::DeploymentTarget,
        source_dir : String,
        dest_dir : String,
        effective : EffectiveOptions,
      ) : {Bool, TargetCounts}
        counts = TargetCounts.new
        dest_dir_expanded = File.expand_path(dest_dir)

        if nested_path?(source_dir, dest_dir_expanded) || nested_path?(dest_dir_expanded, source_dir)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_USAGE,
            message: "Refusing to deploy: source and destination overlap.",
            hint: "source: #{source_dir} / dest: #{dest_dir_expanded}",
          )
        end

        FileUtils.mkdir_p(dest_dir_expanded)

        desired = build_desired_map(source_dir, target)
        existing = list_existing_files(dest_dir_expanded)

        validate_strip_index_html_for_filesystem(target, desired.keys)
        validate_destination_paths(dest_dir_expanded, desired.keys)

        to_delete = compute_deletes(existing, desired.keys, target)
        if effective.max_deletes != -1 && to_delete.size > effective.max_deletes
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_USAGE,
            message: "Refusing to delete #{to_delete.size} files (max_deletes: #{effective.max_deletes}).",
            hint: "Set deployment.maxDeletes = -1 (or pass --max-deletes -1) to disable the limit.",
          )
        end

        to_copy, _skipped = compute_copies(desired, dest_dir_expanded, effective.force)

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
          existed_before = File.exists?(dest_path)
          FileUtils.mkdir_p(File.dirname(dest_path))
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
        Logger.success "Deployed to #{dest_dir_expanded} (created #{counts.created}, updated #{counts.updated}, deleted #{counts.deleted})"
        {true, counts}
      end

      private def deploy_to_directory(
        target : Models::DeploymentTarget,
        source_dir : String,
        dest_dir : String,
        effective : EffectiveOptions,
      ) : Bool
        dest_dir = File.expand_path(dest_dir)

        if nested_path?(source_dir, dest_dir) || nested_path?(dest_dir, source_dir)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_USAGE,
            message: "Refusing to deploy: source and destination overlap.",
            hint: "source: #{source_dir} / dest: #{dest_dir}",
          )
        end

        FileUtils.mkdir_p(dest_dir)

        desired = build_desired_map(source_dir, target)
        existing = list_existing_files(dest_dir)

        validate_strip_index_html_for_filesystem(target, desired.keys)
        validate_destination_paths(dest_dir, desired.keys)

        to_delete = compute_deletes(existing, desired.keys, target)
        if effective.max_deletes != -1 && to_delete.size > effective.max_deletes
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_USAGE,
            message: "Refusing to delete #{to_delete.size} files (max_deletes: #{effective.max_deletes}).",
            hint: "Set deployment.maxDeletes = -1 (or pass --max-deletes -1) to disable the limit.",
          )
        end

        to_copy, skipped = compute_copies(desired, dest_dir, effective.force)

        Logger.info "Plan: copy #{to_copy.size}, delete #{to_delete.size}, skip #{skipped}"

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
          FileUtils.mkdir_p(File.dirname(dest_path))
          FileUtils.cp(src_path, dest_path)
          summary.copied += 1
        end

        to_delete.each_with_index do |rel, idx|
          Logger.progress(idx + 1, to_delete.size, "Deleting ")
          FileUtils.rm(File.join(dest_dir, rel))
          summary.deleted += 1
        end

        remove_empty_directories(dest_dir)
        Logger.success "Deployed to #{dest_dir} (copied #{summary.copied}, deleted #{summary.deleted}, skipped #{summary.skipped})"
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

        desired
      end

      private def compute_copies(
        desired : Hash(String, String),
        dest_dir : String,
        force : Bool,
      ) : {Array({String, String}), Int32}
        to_copy = [] of {String, String}
        skipped = 0

        desired.each do |dest_rel, src_path|
          dest_path = File.join(dest_dir, dest_rel)
          if !force && File.exists?(dest_path) && same_file?(src_path, dest_path)
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

        existing.select do |rel|
          next false if ignored_file?(rel)
          next false unless delete_candidate?(rel, target)
          !desired_set.includes?(rel)
        end
      end

      private def delete_candidate?(rel : String, target : Models::DeploymentTarget) : Bool
        included_by_target?(rel, target)
      end

      private def list_existing_files(dest_dir : String) : Array(String)
        files = [] of String
        return files unless Dir.exists?(dest_dir)

        each_project_file(dest_dir) do |path|
          rel = relative_to(path, dest_dir)
          next if rel.empty?
          next if ignored_file?(rel)
          files << rel
        end

        files
      end

      private def included_by_target?(rel : String, target : Models::DeploymentTarget) : Bool
        normalized = rel.gsub('\\', '/')
        if inc = target.include
          return false unless File.match?(inc, normalized)
        end
        if exc = target.exclude
          return false if File.match?(exc, normalized)
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
        dest_paths.each do |path|
          next if path.empty?
          prefix = "#{path}/"
          if dest_paths.any?(&.starts_with?(prefix))
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONFIG,
              message: "stripIndexHTML cannot be used with file:// deployments when both '#{path}' and '#{prefix}...' exist.",
              hint: "Disable stripIndexHTML for target '#{target.name}', or deploy via an object store.",
            )
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
          if Dir.exists?(full_path)
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
              read_a = fa.read(buf_a)
              read_b = fb.read(buf_b)
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

      private def remove_empty_directories(root : String)
        dirs = Dir.glob(File.join(root, "**", "*")).select { |p| Dir.exists?(p) }
        dirs.sort_by! { |p| -p.count('/') }
        dirs.each do |dir|
          next if dir == root
          next unless Dir.exists?(dir)
          next unless Dir.empty?(dir)
          Dir.delete(dir)
        end
      end

      private def each_project_file(root : String, &block : String ->)
        walk_project_files(root, &block)
      end

      private def walk_project_files(dir : String, &block : String ->)
        Dir.each_child(dir) do |entry|
          next if entry == ".DS_Store"
          full = File.join(dir, entry)
          if Dir.exists?(full)
            if entry.starts_with?(".") && entry != ".well-known"
              next
            end
            walk_project_files(full, &block)
          elsif File.file?(full)
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
        b.starts_with?(a + "/")
      end

      private def log_plan(to_copy : Array({String, String}), to_delete : Array(String))
        if to_copy.present?
          Logger.info "Copy:"
          to_copy.first(50).each { |(dest_rel, _)| Logger.info "  + #{dest_rel}" }
          Logger.info "  ... (#{to_copy.size - 50} more)" if to_copy.size > 50
        end
        if to_delete.present?
          Logger.info "Delete:"
          to_delete.first(50).each { |rel| Logger.info "  - #{rel}" }
          Logger.info "  ... (#{to_delete.size - 50} more)" if to_delete.size > 50
        end
      end

      private def confirm?(prompt : String) : Bool
        unless STDIN.tty?
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_USAGE,
            message: "Cannot prompt for confirmation: stdin is not a TTY.",
            hint: "Pass --force to skip confirmation prompts in non-interactive environments.",
          )
        end
        Logger.warn "#{prompt} [y/N]"
        input = STDIN.gets
        (input.try(&.strip.downcase) == "y")
      end

      # Supported placeholders in `command = "..."` templates. Listed
      # here so `expand_placeholders` can produce a helpful error message
      # when an unknown `{foo}` slips through (typo, forward-looking
      # name, etc.) instead of sending the literal to the shell.
      COMMAND_PLACEHOLDERS = {"source", "url", "target"}

      # Pattern used to detect *remaining* placeholders after expansion.
      # Anything that still matches is unknown and rejected.
      private COMMAND_PLACEHOLDER_RE = /\{([a-zA-Z_][\w-]*)\}/

      private def expand_placeholders(command : String, source_dir : String, target : Models::DeploymentTarget) : String
        expanded = command
          .gsub("{source}", shell_escape(source_dir))
          .gsub("{url}", shell_escape(target.url))
          .gsub("{target}", shell_escape(target.name))

        validate_no_unexpanded_placeholders!(command, expanded, target)
        expanded
      end

      # Raise HWARO_E_CONFIG if the expanded command still contains any
      # `{name}` tokens — catches typos like `{srouce}` and forward-
      # looking placeholders (`{bucket}`, `{region}`) before the literal
      # reaches the underlying deploy tool and produces a confusing
      # downstream error.
      private def validate_no_unexpanded_placeholders!(
        original : String,
        expanded : String,
        target : Models::DeploymentTarget,
      ) : Nil
        unresolved = expanded.scan(COMMAND_PLACEHOLDER_RE)
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
        uri = URI.parse(url) rescue return
        case uri.scheme
        when "s3"
          "aws s3 sync {source}/ {url} --delete"
        when "gs"
          "gsutil -m rsync -r -d {source}/ {url}"
        when "az"
          # az://container → Azure Blob Storage
          "az storage blob sync --source {source} --container {url}"
        end
      end

      private def local_directory_destination(url : String) : String?
        if url.includes?("://")
          uri = URI.parse(url)
          return unless uri.scheme == "file"
          # Allow both file:///abs/path and file://relative/path forms.
          path = uri.path
          if path.empty?
            if host = uri.host
              path = host unless host.empty?
            end
          end
          return if path.empty?
          return path
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
