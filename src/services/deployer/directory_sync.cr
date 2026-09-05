# Deployer — local-directory sync (file selection, copy/delete pass, both reporting styles).
#
# Reopens `Services::Deployer`; deployer.cr keeps the result records, the
# three entry points (plan / run / deploy_structured) and per-target
# dispatch. Parts only reopen the class: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class Deployer
      # Everything a local-directory deploy decides before it writes: the
      # expanded destination, the desired file map, and the copy/delete lists.
      # Shared by the dry-run plan and both deploy reporting styles, so the
      # three can't drift in what they validate or select.
      private record DirectorySync,
        dest_dir : String,
        desired : Hash(String, String),
        to_copy : Array({String, String}),
        to_delete : Array(String),
        skipped : Int32

      # Validate and select files for syncing `source_dir` into the local
      # directory `dest_dir`. `create_dest: false` (the plan) leaves a missing
      # destination uncreated — a dry run must not write anything.
      private def prepare_directory_sync(
        target : Models::DeploymentTarget,
        source_dir : String,
        dest_dir : String,
        effective : EffectiveOptions,
        deployment : Models::DeploymentConfig,
        create_dest : Bool,
      ) : DirectorySync
        require_non_empty_source!(source_dir, effective)
        dest_dir = expand_local_path(dest_dir)

        check_overlap!(source_dir, dest_dir)

        Hwaro::Utils::FileSafe.mkdir_p(dest_dir) if create_dest

        desired = build_desired_map(source_dir, target)
        existing = list_existing_files(dest_dir)

        validate_strip_index_html_for_filesystem(target, desired.keys)
        validate_destination_paths(dest_dir, desired.keys)

        to_delete = compute_deletes(existing, desired.keys, target)
        check_empty_selection!(desired, to_delete, target, effective)
        check_max_deletes!(to_delete.size, effective)

        to_copy, skipped = compute_copies(desired, dest_dir, effective.force, force_matcher_patterns(deployment))

        DirectorySync.new(dest_dir, desired, to_copy, to_delete, skipped)
      end

      # Apply a prepared sync: copy, delete, prune empty directories. Returns
      # the per-action counts (a link replaced by a real file is a create,
      # not an update — `existed_before` is sampled after the link is cleared).
      private def write_directory_sync(sync : DirectorySync) : TargetCounts
        counts = TargetCounts.new
        dest_dir = sync.dest_dir

        sync.to_copy.each_with_index do |(dest_rel, src_path), idx|
          Logger.progress(idx + 1, sync.to_copy.size, "Copying ")
          dest_path = File.join(dest_dir, dest_rel)
          unlink_destination_symlinks!(dest_dir, dest_rel)
          existed_before = File.exists?(dest_path)
          Hwaro::Utils::FileSafe.mkdir_p(File.dirname(dest_path))
          FileUtils.cp(src_path, dest_path)
          if existed_before
            counts.updated += 1
          else
            counts.created += 1
          end
        end

        sync.to_delete.each_with_index do |rel, idx|
          Logger.progress(idx + 1, sync.to_delete.size, "Deleting ")
          FileUtils.rm(File.join(dest_dir, rel))
          counts.deleted += 1
        end

        remove_empty_directories(dest_dir)
        counts
      end

      # Ask before writing when `--confirm` is on; false means the user
      # declined (the deploy is then reported as completed, not failed).
      private def sync_confirmed?(dest_dir : String, effective : EffectiveOptions) : Bool
        return true unless effective.confirm
        return true if confirm?("Proceed with deploy to #{dest_dir}?")
        Logger.warn "Cancelled."
        false
      end

      # Local-directory deploy with the compact reporting of `deploy --json`,
      # returning per-action counts (created/updated/deleted) for the summary.
      private def deploy_to_directory_with_counts(
        target : Models::DeploymentTarget,
        source_dir : String,
        dest_dir : String,
        effective : EffectiveOptions,
        deployment : Models::DeploymentConfig,
      ) : {Bool, TargetCounts}
        Logger.heading("deploy", target.name)
        sync = prepare_directory_sync(target, source_dir, dest_dir, effective, deployment, create_dest: true)

        return {true, TargetCounts.new} if effective.dry_run
        return {true, TargetCounts.new} unless sync_confirmed?(sync.dest_dir, effective)

        counts = write_directory_sync(sync)
        Logger.info "" if Logger.color_enabled?
        Logger.outcome("deployed", "#{sync.dest_dir} · #{counts.created} created · #{counts.updated} updated · #{counts.deleted} deleted")
        {true, counts}
      end

      # Local-directory deploy with the human reporting of a plain
      # `hwaro deploy`: a receipt up front, the plan listing on --dry-run, and
      # a copied/deleted/skipped outcome.
      private def deploy_to_directory(
        target : Models::DeploymentTarget,
        source_dir : String,
        dest_dir : String,
        effective : EffectiveOptions,
        deployment : Models::DeploymentConfig,
      ) : Bool
        sync = prepare_directory_sync(target, source_dir, dest_dir, effective, deployment, create_dest: true)
        dest_dir = sync.dest_dir

        Logger::Receipt.new("deploy", target.name)
          .row("source", source_dir)
          .row("dest", dest_dir)
          .row("plan", "copy #{sync.to_copy.size} · delete #{sync.to_delete.size} · skip #{sync.skipped}")
          .emit

        if effective.dry_run
          log_plan(sync.to_copy, sync.to_delete)
          return true
        end

        return true unless sync_confirmed?(dest_dir, effective)

        counts = write_directory_sync(sync)
        Logger.info "" if Logger.color_enabled?
        Logger.outcome("deployed", "#{dest_dir} · #{counts.created + counts.updated} copied · #{counts.deleted} deleted · #{sync.skipped} skipped")
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
        symlink_memo = {} of String => Bool

        desired.each do |dest_rel, src_path|
          dest_path = File.join(dest_dir, dest_rel)
          if !force && !force_match?(dest_rel, force_patterns) &&
             File.exists?(dest_path) &&
             !traverses_symlink?(dest_dir, dest_rel, symlink_memo) &&
             same_file?(src_path, dest_path)
            skipped += 1
            next
          end
          to_copy << {dest_rel, src_path}
        end

        {to_copy, skipped}
      end

      # True when any component of `dest_rel` under `dest_dir` is a symlink.
      #
      # `File.exists?`/`same_file?` both follow links, so a file whose content
      # matched the one *behind* a destination link looked identical and was
      # skipped — and then the copy pass replaced the link with a real
      # directory, leaving the skipped file absent from the destination
      # entirely. Forcing a copy for every path that crosses a link also
      # guarantees the link is cleared even when everything behind it is
      # byte-identical (otherwise the escaping link survived the sync).
      #
      # Directory components are memoised: `desired` is sorted, so the same
      # prefixes repeat across every file in a directory.
      private def traverses_symlink?(dest_dir : String, dest_rel : String, memo : Hash(String, Bool)) : Bool
        parts = dest_rel.split('/')
        current = dest_dir
        last = parts.size - 1
        parts.each_with_index do |part, idx|
          next if part.empty?
          current = File.join(current, part)
          if idx == last
            return true if symlink?(current)
          else
            cached = memo[current]?
            if cached.nil?
              cached = symlink?(current)
              memo[current] = cached
            end
            return true if cached
          end
        end
        false
      end

      private def symlink?(path : String) : Bool
        File.symlink?(path)
      rescue File::Error | IO::Error
        false
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
    end
  end
end
