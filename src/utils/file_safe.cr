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
      def self.mkdir_p(path : String | Path, mode : Int32 = 0o777) : Nil
        Dir.mkdir_p(path, mode)
      rescue ex : File::AlreadyExistsError
        # Two workers calling `mkdir_p("/out/posts/a")` and
        # `mkdir_p("/out/posts/b")` can race on the shared parent `/out/posts`:
        # both pass the `Dir.exists?` precondition (`/out/posts` is absent),
        # both descend, both call `mkdir("/out/posts")`, and the loser gets
        # EEXIST on the parent — even though its own leaf hasn't been created
        # yet. So a single retry is enough: on the second attempt `/out/posts`
        # now exists (whoever won the race created it), and `mkdir_p` skips
        # that step and only creates the leaf the caller actually asked for.
        begin
          Dir.mkdir_p(path, mode)
        rescue ex2 : File::AlreadyExistsError
          # Genuinely repeated EEXIST after retry: surface only when the
          # final target *still* isn't a directory. Otherwise the
          # post-condition `mkdir_p` promises ("path exists as a directory")
          # already holds and we treat as success.
          raise ex2 unless Dir.exists?(path)
        end
      end
    end
  end
end
