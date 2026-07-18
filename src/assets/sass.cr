# Built-in pure-Crystal SCSS compiler (practical subset).
#
# Supported: `$variables` (with !default/!global), nested rules with `&`,
# partials via @use (namespaces, `with (...)` configuration) / @forward /
# @import (classic merge), @mixin / @include with defaults, keyword and
# variadic args and @content, @function / @return, control flow
# (@if/@else/@each/@for/@while), @debug/@warn/@error, @at-root, `#{...}`
# interpolation, @media/@supports bubbling through nesting, SassScript
# expressions (arithmetic, comparisons, string/list/map values), and a
# curated built-in function set (`sass:math`, `sass:string`, `sass:list`,
# `sass:map`, `sass:meta` + the legacy global names).
#
# Two invariants shape the design:
# - Valid plain CSS compiles to itself (whitespace-normalized): value
#   contexts are *lenient* — expressions only evaluate when they visibly
#   compute something, and any failure falls back to verbatim text.
# - New syntax fails loudly: control-flow headers, @return, and
#   @use ... with surface every problem as a located error.
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
