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
        end

        record Decl, name : String, value : String, important : Bool

        class Comment < Node
          getter text : String

          def initialize(@text)
          end
        end

        class Rule < Node
          getter selectors : Array(String)
          getter items = [] of Decl | Comment

          def initialize(@selectors)
          end

          def decls? : Bool
            @items.any?(Decl)
          end
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
          getter text : String

          def initialize(@text)
          end
        end

        module Serializer
          extend self

          def serialize(nodes : Array(Node)) : String
            out = String.build do |io|
              write_nodes(io, hoist_statements(nodes), 0)
            end
            out.empty? ? out : out.chomp + "\n"
          end

          # Plain-CSS `@import` (and `@charset`) are only honoured before any
          # style rule — a browser ignores one that appears later. Partials
          # routinely put an `@import url(fonts…)` in a file pulled in after
          # other rules, which would silently never load. Lift them back to
          # the top, preserving relative order (a stable partition).
          private def hoist_statements(nodes : Array(Node)) : Array(Node)
            return nodes unless nodes.any? { |n| hoistable?(n) }
            hoisted = [] of Node
            rest = [] of Node
            nodes.each { |n| (hoistable?(n) ? hoisted : rest) << n }
            hoisted + rest
          end

          private def hoistable?(node : Node) : Bool
            return false unless node.is_a?(Raw)
            text = node.text.lstrip
            text.starts_with?("@import") || text.starts_with?("@charset")
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
            emitted = false
            nodes.each do |node|
              next unless emit?(node)
              io << "\n" if emitted
              write_node(io, node, indent)
              emitted = true
            end
          end

          private def write_node(io : IO, node : Node, indent : Int32) : Nil
            pad = "  " * indent
            case node
            when Rule
              io << pad << node.selectors.join(",\n#{pad}") << " {\n"
              write_items(io, node.items, indent + 1)
              io << pad << "}\n"
            when AtRule
              io << pad << "@" << node.name
              io << " " << node.prelude unless node.prelude.empty?
              io << " {\n"
              write_items(io, node.items, indent + 1)
              unless node.children.empty?
                io << "\n" unless node.items.empty?
                write_nodes(io, node.children, indent + 1)
              end
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
                io << pad << item.name << ": " << item.value
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
