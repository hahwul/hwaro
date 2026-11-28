# Flat CSS output tree + expanded-style serializer.
#
# The evaluator flattens SCSS nesting into this small model: style rules
# hold declarations (and passthrough comments); at-rules hold either
# declarations (@font-face), nested rules (@media after bubbling), or
# both. Minification is not a serializer concern — compiled output flows
# through the existing Utils::CssMinifier when [sass] minify is on.

module Hwaro
  module Assets
    module Sass
      module Css
        abstract class Node
          # True on the last root node produced by a top-level style rule:
          # the serializer separates such groups with a blank line
          # (dart-sass's `isGroupEnd`). At-rule statements never set it.
          property group_end : Bool = false
        end

        record Decl, name : String, value : String, important : Bool

        class Comment < Node
          getter text : String

          def initialize(@text)
          end
        end

        class Rule < Node
          getter selectors : Array(String)
          # Line-break flags parallel to `selectors`: true when the source
          # had a newline in the whitespace before that selector — the
          # serializer preserves the author's selector-list line structure
          # (dart-sass behavior). May be shorter than `selectors` (extend
          # appends without flags); a missing entry reads as false.
          getter breaks : Array(Bool)

          def initialize(@selectors, @breaks = [] of Bool)
          end

          getter items = [] of Decl | Comment
        end

        class AtRule < Node
          getter name : String
          getter prelude : String
          getter items = [] of Decl | Comment
          getter children = [] of Node

          def initialize(@name, @prelude)
          end
        end

        # Statement at-rule kept verbatim (@charset, plain-CSS @import, ...).
        class Raw < Node
          getter name : String
          getter text : String

          def initialize(@name, @text)
          end
        end

        module Serializer
          extend self

          def serialize(nodes : Array(Node)) : String
            # Source `@charset` declarations are dropped (a merged sheet
            # can carry one per imported file); the single output charset
            # is decided below from the bytes actually emitted.
            nodes = nodes.reject { |n| charset?(n) }
            text = String.build do |io|
              write_nodes(io, hoist_statements(nodes), 0)
            end
            return text if text.empty?
            text = text.chomp + "\n"
            # Non-ASCII output needs an encoding declaration or browsers
            # fall back to the response/platform charset and garble it
            # (dart-sass emits this too).
            text = "@charset \"UTF-8\";\n" + text unless text.ascii_only?
            text
          end

          private def charset?(node : Node) : Bool
            node.is_a?(Raw) && node.name == "charset"
          end

          # Move late CSS imports ahead of style rules, where browsers will
          # load them. Keep the legal prefix in place: a leading @layer
          # statement sets cascade priority before imports name any layers.
          private def hoist_statements(nodes : Array(Node)) : Array(Node)
            return nodes unless nodes.any? { |node| import_statement?(node) }
            boundary = nodes.index do |node|
              emit?(node) && !node.is_a?(Comment) && !(node.is_a?(Raw) && node.name.in?("import", "layer"))
            end
            return nodes unless boundary

            imports, rest = nodes[boundary..].partition { |node| import_statement?(node) }
            nodes.first(boundary) + imports + rest
          end

          private def import_statement?(node : Node) : Bool
            node.is_a?(Raw) && node.name == "import"
          end

          # Empty rules and empty at-rule blocks are omitted (dart-sass
          # behavior); comment-only rules still render.
          private def emit?(node : Node) : Bool
            case node
            when Rule
              !node.items.empty?
            when AtRule
              # An empty `@layer` block is not dead code: it declares
              # cascade order up front, which is the standard idiom.
              # Dropping it reorders layer precedence and silently changes
              # which rule wins.
              return true if node.name == "layer"
              !node.items.empty? || node.children.any? { |c| emit?(c) }
            else
              true
            end
          end

          private def write_nodes(io : IO, nodes : Array(Node), indent : Int32) : Nil
            previous = nil.as(Node?)
            nodes.each do |node|
              next unless emit?(node)
              # A blank line only after the output group of a top-level
              # style rule (dart-sass). Adjacent rules from one group, and
              # at-rule statements, join without one.
              io << "\n" if previous && previous.group_end
              write_node(io, node, indent)
              previous = node
            end
          end

          private def write_node(io : IO, node : Node, indent : Int32) : Nil
            pad = "  " * indent
            case node
            when Rule
              io << pad
              node.selectors.each_with_index do |selector, index|
                io << (node.breaks[index]? ? ",\n#{pad}" : ", ") unless index == 0
                io << selector
              end
              io << " {\n"
              write_items(io, node.items, indent + 1)
              io << pad << "}\n"
            when AtRule
              io << pad << "@" << node.name
              io << " " << node.prelude unless node.prelude.empty?
              io << " {\n"
              write_items(io, node.items, indent + 1)
              write_nodes(io, node.children, indent + 1)
              io << pad << "}\n"
            when Raw
              io << pad << node.text << "\n"
            when Comment
              io << pad << node.text << "\n"
            end
          end

          private def write_items(io : IO, items : Array(Decl | Comment), indent : Int32) : Nil
            pad = "  " * indent
            items.each do |item|
              case item
              in Decl
                io << pad << item.name << ":"
                # A null value kept alive by !important is empty — don't
                # print the value's leading space or the output carries a
                # double space (`y:  !important`); dart emits `y: !important`.
                # An empty value WITHOUT !important keeps the space: the
                # custom-property `--empty: ;` serializes with it (dart).
                io << " " unless item.value.empty? && item.important
                io << item.value
                io << " !important" if item.important
                io << ";\n"
              in Comment
                io << pad << item.text << "\n"
              end
            end
          end
        end
      end
    end
  end
end
