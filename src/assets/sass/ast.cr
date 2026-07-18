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

        record Param, name : String, default : TextTemplate?, variadic : Bool = false

        class MixinDefNode < Node
          getter name : String
          getter params : Array(Param)
          getter body : Array(Node)

          def initialize(@name, @params, @body, line, column)
            super(line, column)
          end
        end

        record Arg, name : String?, value : TextTemplate, spread : Bool = false

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

        # One `$name: value` entry of `@use ... with (...)`.
        record UseConfig, name : String, value : TextTemplate, default : Bool

        # `@use "url"` / `@use "url" as ns` / `@use "url" as *`, with an
        # optional `with (...)` configuration.
        # namespace: nil = default (basename), "*" = merge into globals.
        class UseNode < Node
          getter url : String
          getter namespace : String?
          getter config : Array(UseConfig)

          def initialize(@url, @namespace, line, column, @config = [] of UseConfig)
            super(line, column)
          end
        end

        # `@forward "url"` with optional `show`/`hide` filters and an
        # `as prefix-*` member prefix. Visibility names keep their `$`
        # marker for variables ("$brand"), bare names cover mixins and
        # functions.
        class ForwardNode < Node
          getter url : String
          getter shown : Set(String)?
          getter hidden : Set(String)?
          getter prefix : String?

          def initialize(@url, @shown, @hidden, @prefix, line, column)
            super(line, column)
          end
        end

        # One branch of an @if/@else-if/@else chain; `condition` is nil
        # for the final @else.
        record IfBranch, condition : TextTemplate?, body : Array(Node)

        class IfNode < Node
          getter branches : Array(IfBranch)

          def initialize(@branches, line, column)
            super(line, column)
          end
        end

        class EachNode < Node
          getter vars : Array(String)
          getter list : TextTemplate
          getter body : Array(Node)

          def initialize(@vars, @list, @body, line, column)
            super(line, column)
          end
        end

        class ForNode < Node
          getter var : String
          getter from : TextTemplate
          getter to : TextTemplate
          # true for `to` (exclusive), false for `through` (inclusive).
          getter exclusive : Bool
          getter body : Array(Node)

          def initialize(@var, @from, @to, @exclusive, @body, line, column)
            super(line, column)
          end
        end

        class WhileNode < Node
          getter condition : TextTemplate
          getter body : Array(Node)

          def initialize(@condition, @body, line, column)
            super(line, column)
          end
        end

        class FunctionDefNode < Node
          getter name : String
          getter params : Array(Param)
          getter body : Array(Node)

          def initialize(@name, @params, @body, line, column)
            super(line, column)
          end
        end

        class ReturnNode < Node
          getter value : TextTemplate

          def initialize(@value, line, column)
            super(line, column)
          end
        end

        # @debug / @warn / @error.
        class MessageNode < Node
          getter kind : Symbol
          getter value : TextTemplate

          def initialize(@kind, @value, line, column)
            super(line, column)
          end
        end

        # `@at-root { ... }` / `@at-root .sel { ... }` — evaluates its
        # body outside the current style-rule nesting (but inside any
        # surrounding at-rule).
        class AtRootNode < Node
          getter selector : TextTemplate?
          getter children : Array(Node)

          def initialize(@selector, @children, line, column)
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
