# Shared helpers for locating non-regex frontmatter boundaries.
#
# TOML (`+++`) and YAML (`---`) use fixed line delimiters and are matched
# with regex at the call site. JSON frontmatter uses balanced braces — this
# module provides a brace-aware scanner that respects string literals.

module Hwaro
  module Utils
    module FrontmatterScanner
      extend self

      # Returns the end offset (exclusive) of the first balanced top-level JSON
      # object at byte 0 of `content`, or nil if the input does not start with
      # `{` or the braces never balance. Tracks string-literal state so braces
      # inside quoted strings are ignored.
      def find_json_end(content : String) : Int32?
        bytes = content.to_slice
        return nil if bytes.size == 0 || bytes[0] != '{'.ord.to_u8

        depth = 0
        in_string = false
        escaped = false
        i = 0

        while i < bytes.size
          c = bytes[i]
          if in_string
            if escaped
              escaped = false
            elsif c == '\\'.ord.to_u8
              escaped = true
            elsif c == '"'.ord.to_u8
              in_string = false
            end
          else
            case c
            when '"'.ord.to_u8
              in_string = true
            when '{'.ord.to_u8
              depth += 1
            when '}'.ord.to_u8
              depth -= 1
              return i + 1 if depth == 0
            end
          end
          i += 1
        end
        nil
      end
    end
  end
end
