require "file_utils"
require "digest/sha256"
require "json"
require "set"
require "uri"

require "../cli/prompt"
require "../cli/runner"
require "../models/config"
require "../utils/dev_marker"
require "../utils/errors"
require "../utils/file_safe"
require "../utils/logger"

require "./deployer/directory_sync"
require "./deployer/command_target"
require "./deployer/validation"
require "./deployer/fs_utils"

module Hwaro
  module Services
    class Deployer
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

        # Every op carries every documented key: a delete has no source, and
        # dropping the key (JSON::Serializable's default for nil) broke
        # consumers that index `op["source"]`.
        @[JSON::Field(emit_null: true)]
        @source : String?
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
      # tool did. A class, so the counts filled in before a mid-sync failure
      # still reach the `deploy --json` error result.
      private class TargetCounts
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
        deployment, source_dir, target_names = load_deploy_inputs(options, config)
        targets = resolve_targets!(target_names, deployment)
        warn_deployment_config(deployment)
        effective = EffectiveOptions.new(deployment, options)
        force_patterns = force_matcher_patterns(deployment)

        targets.each do |target|
          if command = target.command
            warn_unapplied_target_options(target)
            classify_io_errors(target) { require_non_empty_source!(source_dir, effective) } if command_reads_source?(command)
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
            # `--dry-run` is only useful if it fails the way the real deploy
            # would, so the plan runs the exact preparation (overlap check,
            # destination validation, delete cap) a deploy does.
            classify_io_errors(target) do
              sync = prepare_directory_sync(target, source_dir, directory_destination, effective, deployment, force_patterns: force_patterns)
              dest_dir = sync.dest_dir
              symlink_memo = {} of String => Bool

              sync.to_copy.each do |dest_rel, src_path|
                dest_path = File.join(dest_dir, dest_rel)
                # Same rule the write pass counts by: a path reached through a
                # destination symlink, or standing where a stale directory is
                # cleared first, is created, not updated.
                action = replaces_existing_file?(dest_dir, dest_rel, symlink_memo) ? "update" : "create"
                ops << PlannedOp.new(target: target.name, action: action, path: dest_rel, source: src_path, destination: dest_path)
              end

              sync.to_delete.each do |rel|
                ops << PlannedOp.new(target: target.name, action: "delete", path: rel, source: nil, destination: File.join(dest_dir, rel))
              end
            end
          elsif auto_command = auto_command_for_url(url, source_dir)
            warn_unapplied_target_options(target)
            classify_io_errors(target) { require_non_empty_source!(source_dir, effective) } if command_reads_source?(auto_command)
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
        deployment, source_dir, target_names = load_deploy_inputs(options, config)
        warn_deployment_config(deployment)

        targets = target_names.compact_map do |name|
          target = deployment.target_named(name)
          if target
            target
          else
            available = deployment.targets.map(&.name).join(", ")
            hint = available.empty? ? nil : "Configured targets: #{available}."
            code = Hwaro::Errors::HWARO_E_USAGE
            results << deploy_result(name, TargetCounts.new, 0.0,
              error_payload(code, Hwaro::Errors.category_for(code).to_s, "Unknown deploy target: #{name}", hint))
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
          ok, counts = deploy_target_with_counts(target, source_dir, effective, deployment, counts: counts)
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

        payload = if err = error
                    error_payload(err.code, err.category.to_s, err.message || "", err.hint)
                  elsif !ok
                    code = Hwaro::Errors::HWARO_E_NETWORK
                    error_payload(code, Hwaro::Errors.category_for(code).to_s, "Deploy target '#{target.name}' failed", nil)
                  end
        deploy_result(target.name, counts, duration_ms, payload)
      end

      # `status` is "error" exactly when an error payload is present.
      private def deploy_result(name : String, counts : TargetCounts, duration_ms : Float64, error : Hash(String, String?)?) : DeployResult
        DeployResult.new(
          name: name,
          status: error ? "error" : "ok",
          created: counts.created,
          updated: counts.updated,
          deleted: counts.deleted,
          duration_ms: duration_ms,
          error: error,
        )
      end

      # The classified-error shape `DeployResult.error` mirrors (key order is
      # part of the JSON output).
      private def error_payload(code : String, category : String, message : String, hint : String?) : Hash(String, String?)
        {"code" => code, "category" => category, "message" => message, "hint" => hint} of String => String?
      end

      # Load the config and resolve the source directory and requested target
      # names — the shared opening of `#plan`, `#run` and
      # `#deploy_structured`, raising the same classified errors for each.
      private def load_deploy_inputs(options : Config::Options::DeployOptions, config : Models::Config?) : {Models::DeploymentConfig, String, Array(String)}
        config ||= Models::Config.load(env: options.env)
        deployment = config.deployment

        source_dir = resolve_source_dir(options, deployment)
        require_source_dir!(source_dir)

        target_names = resolve_target_names(options, deployment)
        require_target_names!(target_names)
        {deployment, source_dir, target_names}
      end

      private def warn_deployment_config(deployment : Models::DeploymentConfig) : Nil
        warn_duplicate_targets(deployment)
        warn_unapplied_matchers(deployment)
        warn_unapplied_workers(deployment)
      end

      # Deploy a single target, returning both success and the collected
      # counts so `#deploy_structured` can surface file-level stats.
      #
      # `structured` picks the local-directory reporting style: the compact
      # heading + created/updated/deleted outcome of `deploy --json`, or the
      # receipt + dry-run plan listing of a plain `hwaro deploy`. Everything
      # else — command targets, URL resolution, the sync itself — is the same
      # code path either way.
      private def deploy_target_with_counts(
        target : Models::DeploymentTarget,
        source_dir : String,
        effective : EffectiveOptions,
        deployment : Models::DeploymentConfig,
        structured : Bool = true,
        counts : TargetCounts = TargetCounts.new,
      ) : {Bool, TargetCounts}
        if command = target.command
          ok = deploy_via_command(target, source_dir, command, effective)
          return {ok, TargetCounts.new}
        end

        url = target.url
        raise_missing_url!(target) if url.empty?

        if directory_destination = local_directory_destination(url)
          outcome = classify_io_errors(target) do
            if structured
              deploy_to_directory_with_counts(target, source_dir, directory_destination, effective, deployment, counts)
            else
              {deploy_to_directory(target, source_dir, directory_destination, effective, deployment), TargetCounts.new}
            end
          end
          return outcome
        end

        if auto_command = auto_command_for_url(url, source_dir)
          Logger.debug "  Auto-generated command for #{url}"
          ok = deploy_via_command(target, source_dir, auto_command, effective)
          return {ok, TargetCounts.new}
        end

        raise_unsupported_scheme!(target, url)
      end

      def run(options : Config::Options::DeployOptions, config : Models::Config? = nil) : Bool
        deployment, source_dir, target_names = load_deploy_inputs(options, config)
        targets = resolve_targets!(target_names, deployment)
        warn_deployment_config(deployment)

        effective = EffectiveOptions.new(deployment, options)

        # All failure paths inside a target deploy raise HwaroError, so the
        # loop body either completes or the error propagates up to the
        # Runner which renders the classified error + exit code. The Bool
        # return is kept for backwards compatibility with callers that only
        # care about success/skip. `structured: false` picks the human
        # reporting style.
        targets.each do |target|
          deploy_target_with_counts(target, source_dir, effective, deployment, structured: false)
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
    end
  end
end
