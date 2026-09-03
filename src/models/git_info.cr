module Hwaro
  module Models
    # Commit metadata for one content file, collected once per build by
    # `Core::Build::GitInfo` when `[git] enabled = true`.
    #
    # `hash`/`author_*`/`lastmod` describe the file's LATEST non-merge commit
    # (the first one `git log` lists); `first_commit` is the earliest author
    # date across every commit that touched the path. Renames are not
    # followed, so a renamed file's history restarts at the rename commit.
    # Times keep the author's UTC offset (`%aI`), matching how front-matter
    # dates are treated as local wall-clock values.
    record GitInfo,
      hash : String,
      lastmod : Time,
      first_commit : Time,
      author_name : String,
      author_email : String do
      # Abbreviated commit id (7 chars, git's default `--short` width).
      def short_hash : String
        hash[0, 7]
      end
    end
  end
end
