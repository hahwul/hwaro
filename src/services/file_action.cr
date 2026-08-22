# Per-file manifest row shared by the import and export services.

require "json"

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
  end
end
