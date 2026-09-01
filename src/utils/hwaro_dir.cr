# The `.hwaro/` workspace directory
#
# `.hwaro/` at the project root is hwaro's own scratch space: `hwaro serve`
# builds into `.hwaro/serve/` (issue #756) and remote data sources cache
# under `.hwaro/remote_data/` (issue #753). None of it is source, and a serve
# tree carries dev base_urls that must never be committed or deployed — yet
# in a repository whose top-level .gitignore predates the directory, all of
# it lands in `git status` as hundreds of untracked files.
#
# git honors nested .gitignore files, so the directory ignores itself: a
# one-line `*` in `.hwaro/.gitignore` keeps the whole tree invisible to git
# without touching the user's own .gitignore (the same trick Cargo uses for
# `target/`). Every code path that creates a directory under `.hwaro/` calls
# `ensure_self_ignore` right after, so existing projects pick the ignore up
# the first time serve or a remote-data build runs — no migration needed.
#
# Note `.hwaro_cache.json` lives NEXT TO `.hwaro/`, not inside it, and is not
# covered here; the .gitignore scaffolded by `hwaro init` lists it.

module Hwaro
  module Utils
    module HwaroDir
      extend self

      DIR = ".hwaro"

      # `*` un-ignores nothing, so it also hides this .gitignore itself —
      # exactly right for a directory that should not exist in the index.
      GITIGNORE_CONTENT = "*\n"

      # Drop a self-ignoring .gitignore into `dir` (the `.hwaro` directory
      # itself, never a subdirectory of it) unless one already exists.
      #
      # Guarded by basename so a caller passing a spec tmp dir or a custom
      # cache location can never sprinkle .gitignore files around the user's
      # tree. Best-effort: git hygiene must never fail a build or a serve
      # session, so filesystem errors (read-only checkout, permissions) are
      # swallowed. Never overwrites — a user who deliberately un-ignored
      # parts of `.hwaro/` keeps their file.
      def ensure_self_ignore(dir : String = DIR) : Nil
        return unless File.basename(dir) == DIR
        return unless Dir.exists?(dir)
        path = File.join(dir, ".gitignore")
        return if File.exists?(path)
        File.write(path, GITIGNORE_CONTENT)
      rescue IO::Error
        nil
      end
    end
  end
end
