# File operations safe to call from multiple fibers in MT mode.
#
# Crystal's stdlib `Dir.mkdir_p` is check-then-create, which races when
# `-Dpreview_mt` is enabled: two workers can both pass `Dir.exists?` and
# then both call `mkdir`, the second raising `File::AlreadyExistsError`.
# In single-threaded mode the race window is closed by cooperative
# scheduling (no preemption between `exists?` and `mkdir`), so this only
# became a real bug once MT was on the table.
#
# These wrappers are safe to call from any number of concurrent fibers —
# they treat "directory already exists" as success, which is what
# `mkdir -p` semantics promise anyway.

require "file_utils"
require "./errors"

module Hwaro
  module Utils
    module FileSafe
      # Equivalent to `FileUtils.mkdir_p` but tolerates concurrent creation
      # of any path component. Safe to call from MT workers without an
      # external mutex.
      #
      # We walk parents ourselves so EEXIST is absorbed *per component*.
      # Crystal's `Dir.mkdir_p` is `exists? → mkdir` for each parent and the
      # leaf, so two workers calling `mkdir_p("/out/a/b/x")` and
      # `mkdir_p("/out/a/b/y")` can race on every shared parent
      # (`/out`, `/out/a`, `/out/a/b`). A single retry of the whole call
      # isn't enough: the retry's parent walk can re-race on a *different*
      # shared parent, raise again, and a post-hoc `Dir.exists?(leaf)` check
      # is false because we never reached the leaf — so the EEXIST bubbles
      # out and a render fails ("Unable to create directory: '…': File
      # exists"). Tolerating EEXIST per component avoids the cascade.
      def self.mkdir_p(path : String | Path, mode : Int32 = 0o777) : Nil
        path = Path.new(path)
        return if Dir.exists?(path)

        path.each_parent do |parent|
          mkdir_tolerant(parent, mode)
        end
        mkdir_tolerant(path, mode)
      end

      # Create a single directory, treating "already exists as a directory"
      # as success. Anything else (including the path existing as a file)
      # propagates.
      private def self.mkdir_tolerant(path : Path, mode : Int32) : Nil
        return if Dir.exists?(path)
        Dir.mkdir(path, mode)
      rescue ex : File::AlreadyExistsError
        return if Dir.exists?(path)
        # `Dir.exists?` resolves symlinks, so a link whose target is missing
        # (or is not a directory) reads as "does not exist" while `mkdir` still
        # hits EEXIST on the link itself. `output_dir` pointing at a dangling
        # symlink (`public -> nowhere`) therefore reached here and re-raised a
        # bare `File::AlreadyExistsError` — an unclassified crash with no hint
        # about which path was at fault. Refuse with a classified error naming
        # the link instead. We deliberately do NOT create the link's target:
        # it can point anywhere on the filesystem, and a build must never
        # materialize (or disturb) directories outside the project on its own.
        # Only an already-failed `mkdir` reaches this rescue, so the extra
        # `symlink?` stat costs nothing on the hot path.
        raise dangling_symlink_error(path, ex) if File.symlink?(path)
        raise ex
      end

      # Classified error for `mkdir_p` running into a symlink that does not
      # resolve to a usable directory. Names the link *and* its target so the
      # user can tell which of the two is missing.
      private def self.dangling_symlink_error(path : Path, cause : Exception) : Hwaro::HwaroError
        target = File.readlink?(path)
        described = target ? "#{path} -> #{target}" : path.to_s
        Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_IO,
          message: "Cannot create directory '#{described}': the path is a symbolic link that does not point at an existing directory",
          hint: "Create the directory the link points at, repoint the link, or remove the link. Hwaro will not create or delete anything on the far side of it.",
          cause: cause
        )
      end

      # Write `content` to `path` atomically: write to a same-directory
      # temp file, then rename over the target. `hwaro serve` rewrites
      # output files while HTTP fibers stream them to the browser — a plain
      # `File.write` truncates first, so a request landing mid-rebuild could
      # read an empty or half-written page. Rename is atomic on the same
      # filesystem, so readers see either the old bytes or the new bytes.
      #
      # The temp name is unique per process AND fiber so parallel render
      # workers writing sibling outputs can't collide on it.
      def self.atomic_write(path : String | Path, content : String) : Nil
        target = path.to_s
        tmp = "#{target}.#{Process.pid}.#{Fiber.current.object_id}.tmp"
        begin
          File.write(tmp, content)
          File.rename(tmp, target)
        rescue ex
          # Never leave the temp file behind — a failed write must look
          # exactly like the old non-atomic failure (target unchanged).
          File.delete(tmp) if File.exists?(tmp)
          raise ex
        end
      end

      # Copy `src` onto `dest` atomically: copy into a same-directory temp
      # file, then rename it into place. Same invariant as `atomic_write`, for
      # the paths that publish bytes from a source file instead of a rendered
      # string.
      #
      # `FileUtils.cp` is `File.copy`, which opens the destination with
      # O_TRUNC and then streams — so while a copy runs the destination is
      # observably 0 bytes and then every intermediate size. `hwaro serve`
      # answers HTTP requests for those very paths from fibers of the same
      # process, so a request landing in that window gets a truncated body
      # whose header agrees with the short length, which means nothing
      # retries. `rename` is atomic within a filesystem, so a reader sees
      # either the old bytes or the new ones.
      #
      # Permissions carry over from the source exactly as with `FileUtils.cp`
      # (`File.copy` opens the destination with the source's mode); callers
      # that also want the source mtime keep stamping it after the copy.
      #
      # The temp name is unique per process AND fiber so parallel copies of
      # sibling files can't collide on it.
      def self.atomic_copy(src : String | Path, dest : String | Path) : Nil
        source = src.to_s
        target = dest.to_s

        # `FileUtils.cp` copies INTO a directory of that name; there is no
        # single file to replace atomically then, so keep the old behaviour
        # instead of failing the rename on it.
        if Dir.exists?(target)
          FileUtils.cp(source, target)
          return
        end

        tmp = "#{target}.#{Process.pid}.#{Fiber.current.object_id}.tmp"
        begin
          File.copy(source, tmp)
          File.rename(tmp, target)
        rescue ex
          # Never leave the temp file behind — a failed copy must look exactly
          # like the old non-atomic failure (destination unchanged).
          File.delete(tmp) if File.exists?(tmp)
          raise ex
        end
      end
    end
  end
end
