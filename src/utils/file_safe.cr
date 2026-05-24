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
        raise ex unless Dir.exists?(path)
      end
    end
  end
end
