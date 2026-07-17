# Compiler-internal error type for the built-in SCSS compiler.
#
# Raised for lexing, parsing, evaluation, and import-resolution failures.
# Carries a 1-based line/column and the path of the file that failed so
# the build boundary (SassCompiler / asset pipeline) can convert it into
# a classified `HwaroError` with a precise `path:line:col` location.

module Hwaro
  module Assets
    module Sass
      class SyntaxError < Exception
        getter path : String
        getter line : Int32
        getter column : Int32

        def initialize(message : String, @path : String, @line : Int32, @column : Int32)
          super(message)
        end

        # "css/style.scss:14:3"
        def location : String
          "#{@path}:#{@line}:#{@column}"
        end
      end
    end
  end
end
