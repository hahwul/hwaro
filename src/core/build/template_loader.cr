# Snapshot-consistent Crinja template loader.
#
# Entry templates render from the in-memory hash `load_templates` built, but
# `{% include %}` / `{% extends %}` / `{% import %}` / `{% from %}` resolve
# through the Crinja environment's loader at render time. With a plain
# `FileSystemLoader` that meant partials were re-read from DISK on every
# render — so an editor (or agent) rewriting template files while a serve
# rebuild was in flight could feed half-written or momentarily-missing
# sources into the very rebuild that was meant to pick them up cleanly,
# producing broken pages or spurious template errors.
#
# This loader serves references from the same snapshot the entry templates
# come from, making every rebuild internally consistent: one template state
# in, one site state out. References the snapshot can't answer fall back to
# the filesystem loader so behavior outside the snapshot (extension-less
# names, extension variants shadowed by load priority, exotic files) is
# unchanged.

require "crinja"

module Hwaro
  module Core
    module Build
      class SnapshotTemplateLoader < Crinja::Loader
        # `templates` is keyed by extension-stripped name ("partials/nav"),
        # `template_paths` maps that name to the source file the snapshot
        # actually loaded ("templates/partials/nav.html"). Both hashes are
        # treated as read-only; `load_templates` swaps in fresh hashes on
        # reload rather than mutating these.
        def initialize(
          @templates : Hash(String, String),
          @template_paths : Hash(String, String),
          @fallback : Crinja::Loader,
        )
        end

        def get_source(env : Crinja, template : String) : {String, String?}
          name = template.sub(Builder::TEMPLATE_EXTENSION_REGEX, "")

          # Only claim references that name the exact file the snapshot
          # loaded (extension included). This keeps two behaviors identical
          # to the filesystem loader: an extension-less reference still
          # resolves (or fails) against the literal file, and a reference to
          # a lower-priority extension variant (`foo.j2` while `foo.html`
          # won the snapshot slot) still reads its own file.
          if name != template && (source = @templates[name]?)
            path = @template_paths[name]?
            return {source, path} if path && path == File.join("templates", template)
          end

          @fallback.get_source(env, template)
        end
      end
    end
  end
end
