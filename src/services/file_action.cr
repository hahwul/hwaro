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
      def self.copy(source_dir : String, dest_dir : String, output_dir : String, dry_run : Bool, verb : String, & : String, String -> Bool) : Int32
        return 0 unless Dir.exists?(source_dir)
        return 0 unless Utils::OutputGuard.within_output_dir?(dest_dir, output_dir)
        # `within_output_dir?` is lexical. If the destination directory —
        # or any ancestor — is a symlink out of the tree, `Dir.exists?`
        # follows it and `File.copy` would write straight through it.
        # A dry run never created `dest_dir`, so it can only apply the
        # resolved check to a directory that already exists — the same
        # pre-existing-symlink case the real run refuses.
        if dry_run
          return 0 if Dir.exists?(dest_dir) && !Utils::PathUtils.resolves_within?(dest_dir, output_dir)
        else
          return 0 unless Utils::PathUtils.resolves_within?(dest_dir, output_dir)
        end

        copied = 0
        Dir.children(source_dir).sort!.each do |entry|
          src = File.join(source_dir, entry)
          next if File.directory?(src) || File.symlink?(src)
          next if entry.ends_with?(".md") || entry.ends_with?(".markdown")

          # `entry` is a single directory component — it can never contain
          # `/`, `.` or `..`, so the guard below is the real protection.
          # Running it through a filename sanitizer that split on `\` renamed
          # a legitimate `C:\photo.png` to `photo.png` and left the
          # `![](C:\photo.png)` reference this copy exists to repair broken.
          dest = File.join(dest_dir, entry)
          next unless Utils::OutputGuard.within_output_dir?(dest, output_dir)
          copied += 1 if yield src, dest
        rescue ex
          Logger.warn "Could not #{verb} bundle asset #{src}: #{ex.message}"
        end
        copied
      end
    end
  end
end
