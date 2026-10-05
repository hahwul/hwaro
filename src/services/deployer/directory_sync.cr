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
        skipped : Int32,
        clear_first : Array(String),
        to_gzip : Array(String)

      # Validate and select files for syncing `source_dir` into the local
      # directory `dest_dir`. Nothing here writes: a missing destination is
      # only created by `#write_directory_sync`, so a dry run — or a deploy the
      # user then declines at the `--confirm` prompt — leaves no trace.
      #
      # `matchers` lets the plan compile (and warn about) the matcher
      # patterns once for the whole run; the deploy paths compile them per
      # target, as they always did.
      private def prepare_directory_sync(
        target : Models::DeploymentTarget,
        source_dir : String,
        dest_dir : String,
        effective : EffectiveOptions,
        deployment : Models::DeploymentConfig,
        matchers : Array(CompiledMatcher)? = nil,
      ) : DirectorySync
        require_non_empty_source!(source_dir, effective)
        matchers ||= compile_matchers(deployment)
        warn_local_header_matchers(target, deployment)
        dest_dir = expand_local_path(dest_dir)

        check_overlap!(source_dir, dest_dir)
        require_directory_destination!(target, dest_dir)

        desired = build_desired_map(source_dir, target)
        existing = list_existing_files(dest_dir)

        validate_strip_index_html_for_filesystem(target, desired.keys)

        stems = gzip_stems(desired, source_dir, matchers)
        to_delete = compute_deletes(existing, desired.keys, target, dest_dir, stems.map { |rel| "#{rel}.gz" }.to_set)
        clear_first = validate_destination_paths(dest_dir, desired.keys, to_delete.to_set)
        check_empty_selection!(desired, to_delete, target, effective)
        check_max_deletes!(to_delete.size - stale_gzip_siblings(to_delete, existing, desired, matchers), effective)

        to_copy, skipped = compute_copies(desired, source_dir, dest_dir, effective.force, force_patterns(matchers))
        copied = to_copy.map(&.[0]).to_set
        to_gzip = stems.select { |rel| copied.includes?(rel) || gzip_sibling_stale?(File.join(dest_dir, rel)) }

        DirectorySync.new(dest_dir, desired, to_copy, to_delete, skipped, clear_first, to_gzip)
      end

      # Apply a prepared sync: clear stale entries standing where the new
      # tree needs the opposite kind of entry, copy, delete the rest, prune
      # empty directories. Returns the per-action counts (a link or stale
      # directory replaced by a real file is a create, not an update —
      # `existed_before` is sampled after the obstacle is cleared).
      #
      # `counts` is filled in as the sync goes, so a caller still holds what
      # was already written when a later copy or delete raises.
      private def write_directory_sync(sync : DirectorySync, counts : TargetCounts = TargetCounts.new) : TargetCounts
        dest_dir = sync.dest_dir

        Hwaro::Utils::FileSafe.mkdir_p(dest_dir)

        # Deletes normally run after the copies so a live destination never
        # loses a page before its replacement lands. The exception is a stale
        # entry in the way of a new one — `foo/` (a directory of old
        # `foo/index.html`) where `strip_index_html` now writes a file `foo`,
        # or the reverse — which has to go first or the copy cannot happen.
        early = Set(String).new
        unless sync.clear_first.empty?
          clear_set = sync.clear_first.to_set
          sync.to_delete.each do |rel|
            next unless at_or_under?(rel, clear_set)
            FileUtils.rm(File.join(dest_dir, rel))
            early << rel
            counts.deleted += 1
          end
          sync.clear_first.each do |rel|
            full = File.join(dest_dir, rel)
            remove_cleared_directory(full) if File.info?(full, follow_symlinks: false).try(&.directory?)
          end
        end

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

        # Precompressed siblings, once the files they compress are in place.
        sync.to_gzip.each do |rel|
          unlink_destination_symlinks!(dest_dir, "#{rel}.gz")
          gzip_file(File.join(dest_dir, rel), File.join(dest_dir, "#{rel}.gz"))
        end

        remaining = early.empty? ? sync.to_delete : sync.to_delete.reject { |rel| early.includes?(rel) }
        remaining.each_with_index do |rel, idx|
          Logger.progress(idx + 1, remaining.size, "Deleting ")
          FileUtils.rm(File.join(dest_dir, rel))
          counts.deleted += 1
        end

        prune_emptied_directories(dest_dir, sync.to_delete)
        counts
      end

      # True when `rel` or one of its ancestor directories is in `set`.
      private def at_or_under?(rel : String, set : Set(String)) : Bool
        return true if set.includes?(rel)
        idx = rel.size
        while idx = rel.rindex('/', idx - 1)
          return true if set.includes?(rel[0, idx])
          break if idx == 0
        end
        false
      end

      # Remove a stale directory whose files the early deletes just took.
      # What is left should be empty directories and Finder litter; only
      # those are removed. Anything else — say, a file that appeared while a
      # `--confirm` prompt waited — makes `Dir.delete` fail (reported as
      # HWARO_E_IO) instead of being swept away unplanned, as `rm_r` would.
      private def remove_cleared_directory(dir : String) : Nil
        Dir.children(dir).each do |entry|
          full = File.join(dir, entry)
          info = File.info?(full, follow_symlinks: false)
          next unless info
          if info.directory?
            remove_cleared_directory(full)
          elsif entry == ".DS_Store"
            File.delete(full)
          end
        end
        Dir.delete(dir)
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
        counts : TargetCounts = TargetCounts.new,
      ) : {Bool, TargetCounts}
        Logger.heading("deploy", target.name)
        sync = prepare_directory_sync(target, source_dir, dest_dir, effective, deployment)

        return {true, counts} if effective.dry_run
        return {true, counts} unless sync_confirmed?(sync.dest_dir, effective)

        write_directory_sync(sync, counts)
        Logger.info "" if Logger.color_enabled?
        Logger.outcome("deployed", "#{sync.dest_dir} · #{counts.created} created · #{counts.updated} updated · #{counts.deleted} deleted#{gzipped_note(sync)}")
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
        sync = prepare_directory_sync(target, source_dir, dest_dir, effective, deployment)
        dest_dir = sync.dest_dir

        Logger::Receipt.new("deploy", target.name)
          .row("source", source_dir)
          .row("dest", dest_dir)
          .row("plan", "copy #{sync.to_copy.size} · delete #{sync.to_delete.size} · skip #{sync.skipped}#{" · gzip #{sync.to_gzip.size}" unless sync.to_gzip.empty?}")
          .emit

        if effective.dry_run
          log_plan(sync.to_copy, sync.to_delete, sync.to_gzip)
          return true
        end

        return true unless sync_confirmed?(dest_dir, effective)

        counts = write_directory_sync(sync)
        Logger.info "" if Logger.color_enabled?
        Logger.outcome("deployed", "#{dest_dir} · #{counts.created + counts.updated} copied · #{counts.deleted} deleted · #{sync.skipped} skipped#{gzipped_note(sync)}")
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
        source_dir : String,
        dest_dir : String,
        force : Bool,
        force_patterns : Array(Regex) = [] of Regex,
      ) : {Array({String, String}), Int32}
        to_copy = [] of {String, String}
        skipped = 0
        symlink_memo = {} of String => Bool

        desired.each do |dest_rel, src_path|
          dest_path = File.join(dest_dir, dest_rel)
          # Matchers see the source path as well as the destination name, the
          # way include/exclude do: under strip_index_html the documented
          # `^.+\.html$` never matched the stripped `foo`, so every page but
          # the root silently lost its `force`.
          forced = force || force_match?(dest_rel, force_patterns) ||
                   force_match?(relative_to(src_path, source_dir), force_patterns)
          if !forced &&
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

      # True when copying `dest_rel` overwrites a regular file already at the
      # destination — the "update" side of the plan and write counts. A path
      # that crosses a destination symlink is a create (the link is cleared
      # first), and so is one where a stale directory stands.
      private def replaces_existing_file?(dest_dir : String, dest_rel : String, memo : Hash(String, Bool)) : Bool
        !traverses_symlink?(dest_dir, dest_rel, memo) && File.file?(File.join(dest_dir, dest_rel))
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
        dest_dir : String,
        keep : Set(String) = Set(String).new,
      ) : Array(String)
        desired_set = desired_paths.to_set
        # A destination symlink at a directory prefix of a desired path is
        # never stale. Links are listed as leaf entries (see
        # `#list_existing_files`), so `out/sub -> …` with a desired
        # `sub/index.html` looked like a stale `sub` — but the copy pass
        # replaces that link with the real directory holding the new file, and
        # deleting it afterwards failed with EPERM. A real *file* there (the
        # `foo` a `strip_index_html` deploy wrote, now wanted as
        # `foo/index.html`) is stale, and is cleared before the copy pass.
        ancestors = desired_ancestors(desired_paths)

        existing.select do |rel|
          next false if ignored_file?(rel)
          next false if keep.includes?(rel)
          next false if ancestors.includes?(rel) && symlink?(File.join(dest_dir, rel))
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
        # With strip_index_html the on-disk name for `foo/index.html` is just
        # `foo`, and include/exclude globs are written against source paths.
        # Judge both spellings: either may be what `include` names (else
        # stale pages survive every sync), and *neither* may be excluded —
        # `exclude = "foo/index.html"` never matched the stored `foo`, so the
        # remote page the author excluded was deleted as stale.
        #
        # Only an extensionless name can be a stripped page. Reading
        # `img/logo.png` as `img/logo.png/index.html` made
        # `include = "**/index.html"` delete every stale asset outside it.
        unless target.strip_index_html && File.extname(rel).empty?
          return included_by_target?(rel, target)
        end
        unstripped = "#{rel}/index.html"
        (target_include_match?(rel, target) || target_include_match?(unstripped, target)) &&
          !target_exclude_match?(rel, target) && !target_exclude_match?(unstripped, target)
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
        each_project_file(dest_dir, follow_symlinks: false, dot_dirs: false) do |path|
          rel = relative_to(path, dest_dir)
          next if rel.empty?
          next if ignored_file?(rel)
          files << rel
        end

        files.sort!
      end

      private def force_match?(rel : String, patterns : Array(Regex)) : Bool
        return false if patterns.empty?
        normalized = rel.gsub('\\', '/')
        patterns.any?(&.matches?(normalized))
      end

      private def included_by_target?(rel : String, target : Models::DeploymentTarget) : Bool
        target_include_match?(rel, target) && !target_exclude_match?(rel, target)
      end

      # A malformed include/exclude glob raises File::BadPatternError. Treat a
      # bad `include` as not-matching (file excluded) and a bad `exclude` as
      # not-matching (file kept), so a config typo doesn't crash the deploy.
      private def target_include_match?(rel : String, target : Models::DeploymentTarget) : Bool
        return true unless inc = target.include
        Utils::PathUtils.glob_match?(inc, rel.gsub('\\', '/'))
      end

      private def target_exclude_match?(rel : String, target : Models::DeploymentTarget) : Bool
        return false unless exc = target.exclude
        Utils::PathUtils.glob_match?(exc, rel.gsub('\\', '/'))
      end

      # Entries the sync neither copies nor deletes. `.git` covers the
      # gh-pages shape: a destination that is a `git worktree` or submodule
      # checkout holds a `.git` *file* (dot-directories are already skipped
      # by the walk), and deleting it as "stale" silently detached the
      # checkout from its repository.
      private def ignored_file?(rel : String) : Bool
        normalized = rel.gsub('\\', '/')
        name = normalized.rpartition('/')[2]
        name == ".DS_Store" || name == ".git"
      end

      private def strip_index_html(rel : String) : String
        normalized = rel.gsub('\\', '/')
        return normalized if normalized == "index.html"
        if normalized.ends_with?("/index.html")
          return normalized.rchop("/index.html")
        end
        normalized
      end

      private def log_plan(to_copy : Array({String, String}), to_delete : Array(String), to_gzip : Array(String))
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
        if to_gzip.present?
          Logger.section("gzip")
          to_gzip.first(50).each { |rel| Logger.item("+ #{rel}.gz", glyph: :bullet) }
          Logger.item("… and #{to_gzip.size - 50} more", glyph: :bullet) if to_gzip.size > 50
        end
      end
    end
  end
end
