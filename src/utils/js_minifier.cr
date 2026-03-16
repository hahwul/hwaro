# JS minification utilities
#
# Provides conservative JS minification that removes comments and
# unnecessary whitespace. Does NOT rename variables or perform
# AST-level optimization.
#
# Operations:
# - Remove single-line comments (// ...) outside strings
# - Remove multi-line comments (/* ... */)
# - Collapse excessive whitespace
# - Remove leading/trailing whitespace on lines

module Hwaro
  module Utils
    module JsMinifier
      extend self

      # Perform conservative JS minification
      def minify(js : String) : String
        result = String.build do |io|
          i = 0
          len = js.size
          chars = js

          while i < len
            c = chars[i]

            # String literals — pass through unchanged
            if c == '"' || c == '\''
              quote = c
              io << c
              i += 1
              while i < len
                sc = chars[i]
                io << sc
                if sc == '\\' && i + 1 < len
                  i += 1
                  io << chars[i]
                elsif sc == quote
                  break
                end
                i += 1
              end
              i += 1
              next
            end

            # Template literals — track ${...} nesting depth
            if c == '`'
              io << c
              i += 1
              depth = 0
              while i < len
                sc = chars[i]
                io << sc
                if sc == '\\' && i + 1 < len
                  i += 1
                  io << chars[i]
                elsif sc == '$' && i + 1 < len && chars[i + 1] == '{'
                  io << chars[i + 1]
                  i += 1
                  depth += 1
                elsif sc == '{' && depth > 0
                  # Nested brace inside ${...}
                elsif sc == '}' && depth > 0
                  depth -= 1
                elsif sc == '`' && depth == 0
                  break
                end
                i += 1
              end
              i += 1
              next
            end

            # Single-line comment
            if c == '/' && i + 1 < len && chars[i + 1] == '/'
              # Skip until end of line
              i += 2
              while i < len && chars[i] != '\n'
                i += 1
              end
              next
            end

            # Multi-line comment
            if c == '/' && i + 1 < len && chars[i + 1] == '*'
              i += 2
              while i + 1 < len
                if chars[i] == '*' && chars[i + 1] == '/'
                  i += 2
                  break
                end
                i += 1
              end
              next
            end

            io << c
            i += 1
          end
        end

        # Collapse multiple blank lines
        lines = result.lines.map(&.rstrip)
        lines.reject! { |l| l.empty? }
        lines.join("\n").strip
      end
    end
  end
end
