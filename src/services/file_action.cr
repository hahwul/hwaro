# Per-file manifest row and page-bundle asset walk shared by the import and
# export services.

require "json"
require "../utils/logger"
require "../utils/output_guard"
require "../utils/path_utils"

module Hwaro
  module Services
    # One row of a per-file manifest: the destination a source resolved to
    # and what happened there (`imported` / `exported` / `overwritten` /
    # `skipped`). Import and export surface these through `--json`, so
    # scripts get a source-of-truth file list instead of re-deriving it
    # from log lines.
    record FileAction, path : String, action : String do
      include JSON::Serializable
    end

    module BundleAssets
      # Walk a page bundle's co-located assets — every non-Markdown, non-
      # symlink regular file beside its `index.md` — yielding `{src, dest}`
      # for each destination that stays inside `output_dir`. The block
      # performs the copy and returns whether it did; the count of `true`s is
      # returned. A failure on one asset is warned as "Could not `verb`
      # bundle asset" and the walk moves on.
      #
      # `recursive` also walks subdirectories (a leaf bundle's `images/`),
      # stopping at one with its own `index`/`_index` page, which is another
      # bundle (as `Page#collect_assets` does). Every destination directory
      # passes the same output-dir checks as `dest_dir`.
      def self.copy(source_dir : String, dest_dir : String, output_dir : String, dry_run : Bool, verb : String, recursive : Bool = false, & : String, String -> Bool) : Int32
        copied = 0
        dirs = [{source_dir, dest_dir}]
        while pair = dirs.shift?
          from, to = pair
          # A subdirectory's destination may not exist yet; its parent passed
          # this check, so only an existing one (a symlink?) is resolved.
          next unless Dir.exists?(from) && dest_dir_ok?(to, output_dir, dry_run || to != dest_dir)
          Dir.children(from).sort!.each do |entry|
            src = File.join(from, entry)
            next if File.symlink?(src)
            if File.directory?(src)
              dirs << {src, File.join(to, entry)} if recursive && !bundle_dir?(src)
              next
            end
            next if entry.ends_with?(".md") || entry.ends_with?(".markdown")

            # `entry` is a single directory component — it can never contain
            # `/`, `.` or `..`, so the guard below is the real protection.
            # Running it through a filename sanitizer that split on `\` renamed
            # a legitimate `C:\photo.png` to `photo.png` and left the
            # `![](C:\photo.png)` reference this copy exists to repair broken.
            dest = File.join(to, entry)
            next unless Utils::OutputGuard.within_output_dir?(dest, output_dir)
            copied += 1 if yield src, dest
          rescue ex
            Logger.warn "Could not #{verb} bundle asset #{src}: #{ex.message}"
          end
        end
        copied
      end

      private def self.dest_dir_ok?(dest_dir : String, output_dir : String, may_be_missing : Bool) : Bool
        return false unless Utils::OutputGuard.within_output_dir?(dest_dir, output_dir)
        # `within_output_dir?` is lexical. If the destination directory —
        # or any ancestor — is a symlink out of the tree, `Dir.exists?`
        # follows it and `File.copy` would write straight through it.
        # A dry run never created `dest_dir`, so it can only apply the
        # resolved check to a directory that already exists — the same
        # pre-existing-symlink case the real run refuses.
        return !Dir.exists?(dest_dir) || Utils::PathUtils.resolves_within?(dest_dir, output_dir) if may_be_missing
        Utils::PathUtils.resolves_within?(dest_dir, output_dir)
      end

      private def self.bundle_dir?(dir : String) : Bool
        Dir.children(dir).any? do |entry|
          (entry.starts_with?("index.") || entry.starts_with?("_index.")) && (entry.ends_with?(".md") || entry.ends_with?(".markdown"))
        end
      end
    end
  end
end
