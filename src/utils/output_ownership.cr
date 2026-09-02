require "./hwaro_dir"
require "./file_safe"
require "./logger"

# Which output directories a cold `hwaro build` may clear.
#
# A cold build starts from an empty output directory, and until now it got
# one by `rm_rf`-ing whatever `-o`/`[build] output_dir` named. The guard in
# the Initialize phase refuses the obviously catastrophic targets (`/`, the
# home directory, the project and its input directories), but any OTHER
# pre-existing directory — `-o ~/Documents/site`, a `dist/` shared with a
# bundler — was emptied silently, exit 0, with every unrelated file in it
# gone.
#
# The rule now: hwaro clears a directory only when it can be sure the
# contents are its own —
#
#   * the conventional `public/` next to the project (the documented default,
#     and what every existing site relies on), judged lexically so a
#     `public -> /var/www/site` symlink keeps its publish-through-the-link
#     clearing;
#   * a directory `hwaro serve` wrote (it carries the `.hwaro-dev` marker);
#   * a directory hwaro created, or found empty, on an earlier build — those
#     are recorded here, under the project's self-ignored `.hwaro/`.
#
# Anything else that already holds files is kept as-is: the build still
# writes into it (overwriting the paths it owns) and warns that files from an
# earlier build may linger — the same contract `--cache` builds already have.
# Emptying the directory once is what hands it over.
module Hwaro
  module Utils
    module OutputOwnership
      extend self

      # One resolved absolute path per line.
      FILE = File.join(HwaroDir::DIR, "owned_outputs")

      # `true` when a cold build may clear `resolved` (a symlink-resolved
      # absolute path) before writing. `output_dir` is the path as given, for
      # the lexical `public/` rule; `project_root` is the resolved project
      # directory the `.hwaro/` record lives under.
      def clearable?(output_dir : String, resolved : String, project_root : String) : Bool
        return true if conventional?(output_dir)
        # `.hwaro/` is hwaro's own workspace (`hwaro serve` builds into
        # `.hwaro/serve`); nothing in there is a user's file.
        return true if resolved.starts_with?(File.join(project_root, HwaroDir::DIR) + File::SEPARATOR)
        return true if DevMarker.present?(resolved)
        recorded?(resolved, project_root)
      end

      # The documented default output directory, next to the project. Judged
      # on the UNRESOLVED path on purpose: a `public` symlink resolves to the
      # tree behind it, and publishing through such a link is a deliberate
      # setup whose clearing the cold build must keep.
      def conventional?(output_dir : String) : Bool
        expanded = File.expand_path(output_dir)
        expanded = expanded.rstrip(File::SEPARATOR) unless expanded == File::SEPARATOR_STRING
        expanded == File.join(File.expand_path(Dir.current), "public")
      end

      def recorded?(resolved : String, project_root : String) : Bool
        path = File.join(project_root, FILE)
        return false unless File.file?(path)
        File.each_line(path) do |line|
          return true if line.strip == resolved
        end
        false
      rescue File::Error
        false
      end

      # Remember that hwaro owns `resolved` from now on. Best effort: a
      # read-only project directory must not fail the build over bookkeeping.
      def record(resolved : String, project_root : String) : Nil
        return if recorded?(resolved, project_root)
        dir = File.join(project_root, HwaroDir::DIR)
        FileSafe.mkdir_p(dir)
        HwaroDir.ensure_self_ignore(dir)
        File.open(File.join(project_root, FILE), "a") { |f| f.puts resolved }
      rescue ex : File::Error
        Logger.debug "Could not record output directory ownership for #{resolved}: #{ex.message}"
      end
    end
  end
end
