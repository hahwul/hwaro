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
      module Loader
        abstract def read(path : String) : String?
        abstract def exists?(path : String) : Bool
      end

      class FileLoader
        include Loader

        def read(path : String) : String?
          return nil unless File.file?(path)
          File.read(path)
        end

        def exists?(path : String) : Bool
          File.file?(path)
        end
      end

      # In-memory loader for specs; keys are expanded so relative paths in
      # test sources resolve like real files.
      class MemoryLoader
        include Loader

        def initialize(files : Hash(String, String), root : String = Dir.current)
          @files = {} of String => String
          files.each do |path, content|
            @files[File.expand_path(path, root)] = content
          end
        end

        def read(path : String) : String?
          @files[path]?
        end

        def exists?(path : String) : Bool
          @files.has_key?(path)
        end
      end

      class Importer
        getter root : String

        def initialize(@loader : Loader, root : String = Dir.current)
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
          if canonical == @root
            canonical
          elsif canonical.starts_with?(@root + File::SEPARATOR)
            canonical[(@root.size + 1)..]
          else
            canonical
          end
        end

        private def join_url(dir : String, base : String) : String
          dir == "." ? base : File.join(dir, base)
        end

        private def resolve_pair(partial : String, plain : String, base_dir : String,
                                 url : String, path : String, line : Int32, column : Int32) : {String, String}?
          partial_path = guard(File.expand_path(partial, base_dir), url, path, line, column)
          plain_path = guard(File.expand_path(plain, base_dir), url, path, line, column)
          if @loader.exists?(partial_path) && @loader.exists?(plain_path)
            raise SyntaxError.new(
              "ambiguous import \"#{url}\": both #{display_path(partial_path)} and #{display_path(plain_path)} exist",
              path, line, column)
          end
          if src = @loader.read(partial_path)
            return {partial_path, src}
          end
          if src = @loader.read(plain_path)
            return {plain_path, src}
          end
          nil
        end

        private def guard(expanded : String, url : String, path : String, line : Int32, column : Int32) : String
          unless expanded == @root || expanded.starts_with?(@root + File::SEPARATOR)
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
