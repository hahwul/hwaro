# Built-in pure-Crystal SCSS compiler (practical subset).
#
# Supported: `$variables` (with !default/!global), nested rules with `&`,
# partials via @use (namespaces) / @import (classic merge), @mixin /
# @include with defaults, keyword args and @content, `#{...}`
# interpolation, and @media/@supports bubbling through nesting. Valid
# plain CSS compiles to itself (whitespace-normalized). Unsupported Sass
# directives (@if/@each/@function/@extend/...) fail loudly with a located
# error — never silent garbage output.
#
# See docs/content/features/sass.md for the full support matrix and the
# documented deviations from dart-sass.

require "./sass/errors"
require "./sass/scanner"
require "./sass/ast"
require "./sass/parser"
require "./sass/environment"
require "./sass/css"
require "./sass/importer"
require "./sass/evaluator"

module Hwaro
  module Assets
    module Sass
      # Compiles SCSS source to expanded CSS. `path` is used for error
      # locations and as the base for @use/@import resolution; `root`
      # bounds import resolution to the project directory. Raises
      # `Sass::SyntaxError` — build-facing callers convert it to a
      # classified `HwaroError`.
      def self.compile(source : String, path : String = "(inline)",
                       loader : Loader = FileLoader.new, root : String = Dir.current) : String
        sheet = Parser.parse(source, path)
        importer = Importer.new(loader, root)
        evaluator = Evaluator.new(importer, path)
        evaluator.seed_load_stack(File.expand_path(path, importer.root)) unless path == "(inline)"
        nodes = evaluator.evaluate(sheet)
        Css::Serializer.serialize(nodes)
      end
    end
  end
end
