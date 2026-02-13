require "file_utils"
require "digest/md5"
require "set"
require "uri"

require "../models/config"
require "../utils/command_runner"
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

      def run(options : Config::Options::DeployOptions, config : Models::Config? = nil) : Bool
        config ||= Models::Config.load
        deployment = config.deployment

        source_dir = options.source_dir || deployment.source_dir
        source_dir = File.expand_path(source_dir)

        unless Dir.exists?(source_dir)
          Logger.error "Source directory not found: #{source_dir}"
          Logger.info "Run 'hwaro build' first, or pass '--source DIR'."
          return false
        end

        target_names =
          if options.targets.any?
            options.targets
          elsif deployment.target
            [deployment.target.not_nil!]
          elsif deployment.targets.size > 0
            [deployment.targets.first.name]
          else
            [] of String
          end

        if target_names.empty?
          Logger.error "No deployment targets configured."
          Logger.info "Add '[[deployment.targets]]' to config.toml, or pass target names: hwaro deploy <targets>"
          return false
        end

        targets = target_names.compact_map do |name|
          target = deployment.target_named(name)
          unless target
            Logger.error "Unknown deploy target: #{name}"
            nil
          else
            target
          end
        end

        return false if targets.empty?

        effective = EffectiveOptions.new(deployment, options)

        targets.each do |target|
          ok = deploy_target(target, source_dir, effective, deployment)
          return false unless ok
        end

        true
      end

      private class EffectiveOptions
        getter confirm : Bool
        getter dry_run : Bool
        getter force : Bool
        getter max_deletes : Int32

        def initialize(deployment : Models::DeploymentConfig, options : Config::Options::DeployOptions)
          @confirm = options.confirm.nil? ? deployment.confirm : options.confirm.not_nil!
          @dry_run = options.dry_run.nil? ? deployment.dry_run : options.dry_run.not_nil!
          @force = options.force.nil? ? deployment.force : options.force.not_nil!
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
          Logger.error "Target '#{target.name}' is missing 'url' (or 'command')."
          return false
        end

        if directory_destination = local_directory_destination(url)
          return deploy_to_directory(target, source_dir, directory_destination, effective)
        end

        Logger.error "Unsupported deploy target URL scheme for '#{target.name}': #{url}"
        Logger.info "Set 'command' for this target to use external tools (rsync/aws/gsutil/etc)."
        Logger.info "Example:"
        Logger.info "  [[deployment.targets]]"
        Logger.info "  name = \"prod\""
        Logger.info "  url = \"s3://my-bucket\""
        Logger.info "  command = \"aws s3 sync {source}/ {url} --delete\""
        false
      end

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

        if effective.confirm && !confirm?("Run deploy command for '#{target.name}'?")
          Logger.warn "Cancelled."
          return true
        end

        result = Utils::CommandRunner.run(expanded, env: env)
        unless result.output.empty?
          result.output.each_line { |line| Logger.info "  #{line}" }
        end
        unless result.success
          Logger.error "Deploy command failed (exit #{result.exit_code})."
          unless result.error.empty?
            result.error.each_line { |line| Logger.error "  #{line}" }
          end
          return false
        end

        Logger.success "Deploy command completed."
        true
      end

      private def deploy_to_directory(
        target : Models::DeploymentTarget,
        source_dir : String,
        dest_dir : String,
        effective : EffectiveOptions,
      ) : Bool
        dest_dir = File.expand_path(dest_dir)

        if nested_path?(source_dir, dest_dir) || nested_path?(dest_dir, source_dir)
          Logger.error "Refusing to deploy: source and destination overlap."
          Logger.info "source: #{source_dir}"
          Logger.info "dest:   #{dest_dir}"
          return false
        end

        FileUtils.mkdir_p(dest_dir)

        desired = build_desired_map(source_dir, target)
        existing = list_existing_files(dest_dir)

        return false unless validate_strip_index_html_for_filesystem(target, desired.keys)
        return false unless validate_destination_paths(dest_dir, desired.keys)

        to_delete = compute_deletes(existing, desired.keys, target)
        if effective.max_deletes != -1 && to_delete.size > effective.max_deletes
          Logger.error "Refusing to delete #{to_delete.size} files (max_deletes: #{effective.max_deletes})."
          Logger.info "Set deployment.maxDeletes = -1 (or pass --max-deletes -1) to disable the limit."
          return false
        end

        to_copy, skipped = compute_copies(desired, dest_dir, effective.force)

        Logger.info "Plan: copy #{to_copy.size}, delete #{to_delete.size}, skip #{skipped}"

        if effective.confirm && !confirm?("Proceed with deploy to #{dest_dir}?")
          Logger.warn "Cancelled."
          return true
        end

        if effective.dry_run
          log_plan(to_copy, to_delete)
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
        normalized = rel.gsub('\\', '/')
        if inc = target.include
          return false unless File.match?(inc, normalized)
        end
        if exc = target.exclude
          return false if File.match?(exc, normalized)
        end
        true
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

      private def validate_strip_index_html_for_filesystem(target : Models::DeploymentTarget, dest_paths : Array(String)) : Bool
        return true unless target.strip_index_html
        dest_paths.each do |path|
          next if path.empty?
          prefix = "#{path}/"
          if dest_paths.any? { |p| p.starts_with?(prefix) }
            Logger.error "stripIndexHTML cannot be used with file:// deployments when both '#{path}' and '#{prefix}...' exist."
            Logger.info "Disable stripIndexHTML for target '#{target.name}', or deploy via an object store."
            return false
          end
        end
        true
      end

      private def validate_destination_paths(dest_dir : String, dest_paths : Array(String)) : Bool
        dest_set = dest_paths.to_set

        dest_paths.each do |rel|
          next if rel.empty?
          parts = rel.split('/')
          if parts.size > 1
            prefix = ""
            parts[0...-1].each do |part|
              prefix = prefix.empty? ? part : "#{prefix}/#{part}"
              if dest_set.includes?(prefix)
                Logger.error "Filesystem deploy conflict: both file '#{prefix}' and path '#{rel}' exist."
                return false
              end
            end
          end

          full_path = File.join(dest_dir, rel)
          if Dir.exists?(full_path)
            Logger.error "Destination path is a directory but needs a file: #{rel}"
            return false
          end

          current = dest_dir
          parts[0...-1].each do |part|
            current = File.join(current, part)
            if File.file?(current)
              Logger.error "Destination path is a file but needs a directory: #{current}"
              return false
            end
          end
        end

        true
      end

      private def same_file?(a : String, b : String) : Bool
        return false unless File.exists?(a) && File.exists?(b)
        a_info = File.info(a)
        b_info = File.info(b)
        return false unless a_info.size == b_info.size
        Digest::MD5.hexdigest(File.read(a)) == Digest::MD5.hexdigest(File.read(b))
      rescue
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
        rel.starts_with?("/") ? rel[1..] : rel
      end

      private def nested_path?(a : String, b : String) : Bool
        a = a.gsub(/\/+\z/, "")
        b = b.gsub(/\/+\z/, "")
        return false if a.empty? || b.empty?
        b.starts_with?(a + "/")
      end

      private def log_plan(to_copy : Array({String, String}), to_delete : Array(String))
        if to_copy.any?
          Logger.info "Copy:"
          to_copy.first(50).each { |(dest_rel, _)| Logger.info "  + #{dest_rel}" }
          Logger.info "  ... (#{to_copy.size - 50} more)" if to_copy.size > 50
        end
        if to_delete.any?
          Logger.info "Delete:"
          to_delete.first(50).each { |rel| Logger.info "  - #{rel}" }
          Logger.info "  ... (#{to_delete.size - 50} more)" if to_delete.size > 50
        end
      end

      private def confirm?(prompt : String) : Bool
        raise "Cannot prompt for confirmation (stdin is not a TTY)." unless STDIN.tty?
        Logger.warn "#{prompt} [y/N]"
        input = STDIN.gets
        (input.try(&.strip.downcase) == "y")
      end

      private def expand_placeholders(command : String, source_dir : String, target : Models::DeploymentTarget) : String
        command
          .gsub("{source}", source_dir)
          .gsub("{url}", target.url)
          .gsub("{target}", target.name)
      end

      private def local_directory_destination(url : String) : String?
        if url.includes?("://")
          uri = URI.parse(url)
          return nil unless uri.scheme == "file"
          # Allow both file:///abs/path and file://relative/path forms.
          path = uri.path
          if path.empty?
            if host = uri.host
              path = host unless host.empty?
            end
          end
          return nil if path.empty?
          return path
        end

        # No scheme: treat as local path
        url
      rescue
        nil
      end
    end
  end
end
