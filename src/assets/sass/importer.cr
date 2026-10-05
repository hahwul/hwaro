# @use/@import resolution for the SCSS compiler.
#
# Probe order for `@use "u"` / `@import "u"` (relative to the importing
# file's directory): `_u.scss`, `u.scss`, `u/_index.scss`, `u/index.scss`;
# an explicit `.scss` extension probes only the exact name and its `_`
# partial variant. Both a partial and a non-partial matching the same url
# is an ambiguity error (dart-sass behavior). Resolved paths must stay
# inside the project root.

require "./errors"
require "../../utils/path_utils"

module Hwaro
  module Assets
    module Sass
      class Importer
        getter root : String

        def initialize(root : String = Dir.current)
          @root = File.expand_path(root)
        end

        # Resolves `url` from `from_file` and returns {canonical_path,
        # source}. Raises SyntaxError (located at the directive) when the
        # target is missing, ambiguous, or escapes the project root.
        def load(url : String, from_file : String, path : String, line : Int32, column : Int32) : {String, String}
          base_dir = File.dirname(File.expand_path(from_file, @root))
          dir = File.dirname(url)
          base = File.basename(url)

          candidates =
            if base.ends_with?(".scss")
              [join_url(dir, "_#{base}"), join_url(dir, base)]
            else
              [join_url(dir, "_#{base}.scss"), join_url(dir, "#{base}.scss")]
            end

          found = resolve_pair(candidates[0], candidates[1], base_dir, url, path, line, column)
          if found.nil? && !base.ends_with?(".scss")
            found = resolve_pair(join_url(url, "_index.scss"), join_url(url, "index.scss"),
              base_dir, url, path, line, column)
          end

          unless found
            raise SyntaxError.new("can't find stylesheet to import: \"#{url}\"", path, line, column)
          end
          found
        end

        # Path shown in error messages / parsed module ASTs — project-
        # relative when possible.
        def display_path(canonical : String) : String
          relative = Hwaro::Utils::PathUtils.relative_path(canonical, @root)
          relative && !relative.empty? ? relative : canonical
        end

        private def join_url(dir : String, base : String) : String
          dir == "." ? base : File.join(dir, base)
        end

        private def resolve_pair(partial : String, plain : String, base_dir : String,
                                 url : String, path : String, line : Int32, column : Int32) : {String, String}?
          partial_path = guard(File.expand_path(partial, base_dir), url, path, line, column)
          plain_path = guard(File.expand_path(plain, base_dir), url, path, line, column)
          if File.file?(partial_path) && File.file?(plain_path)
            raise SyntaxError.new(
              "ambiguous import \"#{url}\": both #{display_path(partial_path)} and #{display_path(plain_path)} exist",
              path, line, column)
          end
          return {partial_path, File.read(partial_path)} if File.file?(partial_path)
          return {plain_path, File.read(plain_path)} if File.file?(plain_path)
          nil
        end

        private def guard(expanded : String, url : String, path : String, line : Int32, column : Int32) : String
          unless Hwaro::Utils::PathUtils.within?(expanded, @root)
            raise SyntaxError.new("import \"#{url}\" resolves outside the project directory", path, line, column)
          end
          # A symlinked source whose target escapes the project would leak
          # outside content into compiled CSS — same policy as the static
          # copy's symlink guard.
          if File.exists?(expanded) && !Hwaro::Utils::PathUtils.resolves_within?(expanded, @root)
            raise SyntaxError.new("import \"#{url}\" resolves outside the project directory", path, line, column)
          end
          expanded
        end
      end
    end
  end
end
