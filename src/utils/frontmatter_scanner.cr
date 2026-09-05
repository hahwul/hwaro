# Shared helpers for locating frontmatter boundaries.
#
# TOML (`+++`) and YAML (`---`) use fixed line delimiters and are matched
# with the regexes below. JSON frontmatter uses balanced braces — this
# module provides a brace-aware scanner that respects string literals.

module Hwaro
  module Utils
    module FrontmatterScanner
      extend self

      # Front-matter block matchers shared by the read-only services
      # (stats, validator, exporters, lister). Both capture the block body
      # in group 1. The build's own parser (`Processors::Markdown`) uses
      # its own variants that additionally capture the body.
      TOML_FRONTMATTER_RE = /\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?/m
      YAML_FRONTMATTER_RE = /\A---\s*\n(.*?\n?)^---\s*$\n?/m

      # The front-matter block at the top of `content` as {dialect, source}:
      # `{:toml, body}` / `{:yaml, body}` (the text between the fences) or
      # `{:json, object}` (the balanced `{...}` at byte 0), or nil when the
      # file has none. Detection order TOML → YAML → JSON, the same as the
      # build's parser, so every read-only tool agrees with the build about
      # which dialect a file is in. Parsing (and its error policy) stays
      # with the caller.
      def detect(content : String) : {Symbol, String}?
        if match = content.match(TOML_FRONTMATTER_RE)
          {:toml, match[1]}
        elsif match = content.match(YAML_FRONTMATTER_RE)
          {:yaml, match[1]}
        elsif content.starts_with?('{') && (end_idx = find_json_end(content))
          # find_json_end returns a BYTE offset; byte_slice keeps multibyte
          # JSON front matter intact.
          {:json, content.byte_slice(0, end_idx)}
        end
      end

      # Strip front matter, if any. The TOML and YAML strips are mutually
      # exclusive: chaining them would let the `\A`-anchored YAML pattern
      # eat a *body* that opens with a thematic break (`---\n…\n---`) once
      # the TOML front matter had already been removed, silently dropping
      # the first block of the document.
      def strip_frontmatter(content : String) : String
        if content.starts_with?('{') && (end_idx = find_json_end(content))
          content.byte_slice(end_idx)
        elsif content.matches?(TOML_FRONTMATTER_RE)
          content.sub(TOML_FRONTMATTER_RE, "")
        else
          content.sub(YAML_FRONTMATTER_RE, "")
        end
      end

      # Returns the end offset (exclusive) of the first balanced top-level JSON
      # object at byte 0 of `content`, or nil if the input does not start with
      # `{` or the braces never balance. Tracks string-literal state so braces
      # inside quoted strings are ignored.
      def find_json_end(content : String) : Int32?
        bytes = content.to_slice
        return if bytes.size == 0 || bytes[0] != '{'.ord.to_u8

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
