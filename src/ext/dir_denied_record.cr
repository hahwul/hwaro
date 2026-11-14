# Patch for the stdlib globber — kept here with the other vendored fixes.
#
# `Dir.glob` with `**` opens each directory it descends into and, when the
# open fails (EACCES included), skips the subtree without a word — the same
# `rescue File::Error; next` that hides a missing directory. A `chmod 000
# content/posts` or `templates/` therefore built a site without those pages or
# templates and exited 0, with nothing naming the directory.
#
# Opening a directory is the one place that sees the error, so `Dir#initialize`
# notes every path it was denied; the build phases that discover sources ask
# `Dir.take_denied(root)` afterwards and warn (or fail) naming the directory.
# Nothing changes for the glob itself: it still skips the subtree.
class Dir
  # A set: a watcher polling an unreadable directory records it once, not
  # once per poll.
  @@denied = Set(String).new
  @@denied_mutex = Mutex.new

  def initialize(path : Path | String)
    previous_def
  rescue ex : File::AccessDeniedError
    @@denied_mutex.synchronize { @@denied << path.to_s }
    raise ex
  end

  # Remove and return the denied directories at or under `root`, sorted.
  def self.take_denied(root : String) : Array(String)
    prefix = root.chomp('/') + "/"
    @@denied_mutex.synchronize do
      taken = @@denied.select { |p| p == root || p.starts_with?(prefix) }
      @@denied.subtract(taken)
      taken.sort!
    end
  end
end

# A template FILE that cannot be read stays in the template set as a stub
# (`Utils::DeniedDirs.unreadable_template`), so page, section, taxonomy,
# shortcode, include/extends/import, render-hook and feed lookups pick it
# exactly where they would have picked the file. Every Crinja template is
# built here, so compiling the stub fails the build naming the file, and a
# site that never uses the file still builds.
class Crinja::Template
  def initialize(@source : String, @env : Crinja = Crinja.new, @name : String = "", @filename : String? = nil, run_parser = true)
    Hwaro::Utils::DeniedDirs.fail_if_unreadable_template(@source) if run_parser
    previous_def
  end
end
