# Config section — [deployment] loaders (the model lives in models/deployment.cr).
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    class Config
      # Point `hwaro deploy` at whatever `[build] output_dir` made the build
      # write, unless the user named a source explicitly. `[build] output_dir`
      # and `[deployment] source_dir` default to "public" independently, so
      # without this a site that builds to `dist/` would have deploy reading a
      # stale (or absent) `public/` — uploading nothing, or deleting the
      # remote's files when max_deletes allows it.
      #
      # Runs at the call site rather than inside `load_deployment` because the
      # common shape is a `[build] output_dir` with no `[deployment]` section
      # at all, which `load_deployment` returns early on.
      private def self.resolve_deployment_source_dir(config : Config)
        return unless build_output = config.build.output_dir
        explicit = config.raw["deployment"]?.try(&.as_h?).try { |s| s["source_dir"]? || s["source"]? }
        return if explicit.try(&.as_s?)
        config.deployment.source_dir = build_output
      end

      private def self.load_deployment(config : Config)
        return unless s = config.raw["deployment"]?.try(&.as_h?)

        config.deployment.target = s["target"]?.try(&.as_s?)
        config.deployment.confirm = bool_value(s["confirm"]?, config.deployment.confirm)

        dry_any = s["dryRun"]? || s["dry_run"]?
        if dry_val = dry_any.try(&.as_bool?)
          config.deployment.dry_run = dry_val
        end

        if force_val = s["force"]?.try(&.as_bool?)
          config.deployment.force = force_val
        end

        max_deletes_any = s["maxDeletes"]? || s["max_deletes"]?
        if max_deletes_val = max_deletes_any.try { |v| int_or_nil(v) }
          config.deployment.max_deletes = max_deletes_val
        end

        if workers_val = s["workers"]?.try { |v| int_or_nil(v) }
          config.deployment.workers = workers_val
        end

        source_any = s["source_dir"]? || s["source"]?
        if source_val = source_any.try(&.as_s?)
          config.deployment.source_dir = source_val
        end

        load_deployment_targets(config, s)
        load_deployment_matchers(config, s)
      end

      private def self.load_deployment_targets(config : Config, s : Hash(String, TOML::Any))
        return unless targets_any = s["targets"]?.try(&.as_a?)

        config.deployment.targets = targets_any.compact_map do |target_any|
          next unless target_h = target_any.as_h?

          name = target_h["name"]?.try(&.as_s?)
          next unless name

          target = DeploymentTarget.new
          target.name = name
          # `path = "/tmp/out"` is the obvious shape for the
          # local-filesystem case and matches what Hugo / Jekyll users
          # try first. Treat it as an alias for `url`; the deployer
          # already routes bare local paths to its native copy
          # implementation (gh#529).
          target.url = target_h["URL"]?.try(&.as_s?) || target_h["url"]?.try(&.as_s?) || target_h["path"]?.try(&.as_s?) || ""
          target.command = target_h["command"]?.try(&.as_s?)
          target.include = target_h["include"]?.try(&.as_s?)
          target.exclude = target_h["exclude"]?.try(&.as_s?)

          strip_any = target_h["stripIndexHTML"]? || target_h["strip_index_html"]?
          if strip_val = strip_any.try(&.as_bool?)
            target.strip_index_html = strip_val
          end

          target
        end
      end

      private def self.load_deployment_matchers(config : Config, s : Hash(String, TOML::Any))
        return unless matchers_any = s["matchers"]?.try(&.as_a?)

        config.deployment.matchers = matchers_any.compact_map do |matcher_any|
          next unless matcher_h = matcher_any.as_h?

          pattern = matcher_h["pattern"]?.try(&.as_s?)
          next unless pattern

          matcher = DeploymentMatcher.new
          matcher.pattern = pattern
          matcher.cache_control = matcher_h["cacheControl"]?.try(&.as_s?) || matcher_h["cache_control"]?.try(&.as_s?)
          matcher.content_type = matcher_h["contentType"]?.try(&.as_s?) || matcher_h["content_type"]?.try(&.as_s?)
          if gzip_val = matcher_h["gzip"]?.try(&.as_bool?)
            matcher.gzip = gzip_val
          end
          if force_val = matcher_h["force"]?.try(&.as_bool?)
            matcher.force = force_val
          end
          matcher
        end
      end
    end
  end
end
