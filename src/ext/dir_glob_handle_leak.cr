# Patch for the stdlib globber — kept here with the other vendored fixes.
#
# `Dir.glob(pattern) { |path| … }` walks `**` with one open `Dir` per
# directory level and closes a level only once it has read its last entry.
# Nothing closes them when the block leaves early: a `raise`, `break` or
# `return` out of the block abandons every level the walk was inside, and
# `Dir` has no finalizer, so the descriptors stay open for the life of the
# process. `SassCompiler#compile_all` compiles inside such a block, so each
# failed `.scss` save leaked two descriptors in a `hwaro serve` session; at
# the fd limit (256 on macOS) Sass stopped compiling for good, `accept`
# failed, and the watcher saw every file as removed.
#
# The block form now collects the matches first — that block cannot leave
# early — and yields them afterwards. Same paths, same order; the caller's
# block just runs after the walk instead of in the middle of it.
class Dir
  def self.glob(patterns : Enumerable, match : File::MatchOptions = File::MatchOptions.glob_default, follow_symlinks : Bool = false, & : String -> _)
    paths = [] of String
    previous_def(patterns, match, follow_symlinks) { |path| paths << path }
    paths.each { |path| yield path }
    nil
  end
end
