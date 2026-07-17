# AST for the SCSS subset.
#
# Values, selectors, property names, and at-rule preludes are represented
# as `TextTemplate`s — verbatim source text runs with embedded dynamic
# pieces (`$var` references and `#{...}` interpolation). Keeping unparsed
# CSS verbatim is what guarantees plain-CSS passthrough; richer expression
# parsing (arithmetic, functions) slots in later by deepening how a
# template's string pieces are parsed, without changing statement nodes.

module Hwaro
  module Assets
    module Sass
      module Ast
        # A `$name` / `ns.$name` reference. `lexeme` preserves the original
        # spelling so contexts that must not substitute variables (custom
        # property values) can restore the literal text.
        class VarRef
          getter name : String
          getter namespace : String?
          getter line : Int32
          getter column : Int32

          def initialize(@name, @namespace, @line, @column)
          end

          def lexeme : String
            ns = @namespace
            ns ? "#{ns}.$#{@name}" : "$#{@name}"
          end
        end

        # `#{ ... }` — the inner content is itself a template (text and
        # variable references in v1).
        class Interp
          getter inner : TextTemplate
          getter line : Int32
          getter column : Int32

          def initialize(@inner, @line, @column)
          end
        end

        alias Piece = String | VarRef | Interp

        class TextTemplate
          getter pieces : Array(Piece)
          getter line : Int32
          getter column : Int32

          def initialize(@pieces : Array(Piece), @line : Int32, @column : Int32)
          end

          def empty? : Bool
            @pieces.all? { |p| p.is_a?(String) && p.blank? }
          end
        end

        abstract class Node
          getter line : Int32
          getter column : Int32

          def initialize(@line : Int32, @column : Int32)
          end
        end

        class Stylesheet < Node
          getter children : Array(Node)

          def initialize(@children, line = 1, column = 1)
            super(line, column)
          end
        end

        class RuleNode < Node
          getter selector : TextTemplate
          getter children : Array(Node)

          def initialize(@selector, @children, line, column)
            super(line, column)
          end
        end

        class DeclarationNode < Node
          getter name : TextTemplate
          getter value : TextTemplate
          getter important : Bool
          getter custom_property : Bool

          def initialize(@name, @value, @important, @custom_property, line, column)
            super(line, column)
          end
        end

        class VarDeclNode < Node
          getter name : String
          getter value : TextTemplate
          getter default : Bool
          getter global : Bool

          def initialize(@name, @value, @default, @global, line, column)
            super(line, column)
          end
        end

        record Param, name : String, default : TextTemplate?

        class MixinDefNode < Node
          getter name : String
          getter params : Array(Param)
          getter body : Array(Node)

          def initialize(@name, @params, @body, line, column)
            super(line, column)
          end
        end

        record Arg, name : String?, value : TextTemplate

        class IncludeNode < Node
          getter name : String
          getter namespace : String?
          getter args : Array(Arg)
          getter body : Array(Node)?

          def initialize(@name, @namespace, @args, @body, line, column)
            super(line, column)
          end
        end

        class ContentNode < Node
        end

        # `@use "url"` / `@use "url" as ns` / `@use "url" as *`.
        # namespace: nil = default (basename), "*" = merge into globals.
        class UseNode < Node
          getter url : String
          getter namespace : String?

          def initialize(@url, @namespace, line, column)
            super(line, column)
          end
        end

        # Sass `@import "local"` (classic global-merge semantics).
        class ImportNode < Node
          getter url : String

          def initialize(@url, line, column)
            super(line, column)
          end
        end

        # Any other at-rule. `children` is nil for the statement form
        # (`@charset "utf-8";`, plain-CSS `@import url(...);`); bodied
        # forms (@media, @supports, @keyframes, @font-face, unknown) carry
        # their block statements.
        class RawAtRuleNode < Node
          getter name : String
          getter prelude : TextTemplate
          getter children : Array(Node)?

          def initialize(@name, @prelude, @children, line, column)
            super(line, column)
          end
        end

        # Loud comment kept at statement position.
        class CommentNode < Node
          getter text : String

          def initialize(@text, line, column)
            super(line, column)
          end
        end
      end
    end
  end
end
