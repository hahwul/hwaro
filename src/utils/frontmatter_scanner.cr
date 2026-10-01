# Shared helpers for locating frontmatter boundaries.
#
# TOML (`+++`) and YAML (`---`) use fixed line delimiters and are matched
# with the regexes below. JSON frontmatter uses balanced braces — this
# module provides a brace-aware scanner that respects string literals.

require "yaml"

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
        elsif json_start?(content) && (end_idx = find_json_end(content))
          # find_json_end returns a BYTE offset; byte_slice keeps multibyte
          # JSON front matter intact.
          {:json, content.byte_slice(0, end_idx)}
        end
      end

      # True when `content` opens the way JSON front matter does: a `{` at
      # byte 0 followed (after optional whitespace) by `"` (the first key) or
      # `}` (an empty object). This is the build's own test
      # (`Processors::Markdown#json_front_matter_start?`): a `{` also opens
      # shortcodes (`{{ … }}`), Jinja tags (`{% … %}`) and attribute lists
      # (`{:.class}`), which the build renders as body text. Treating those
      # as front matter made the read-only tools disagree with the build —
      # `tool validate` failed such a page with a JSON parse error.
      def json_start?(content : String) : Bool
        return false unless content.starts_with?('{')
        reader = Char::Reader.new(content)
        reader.next_char # skip the leading '{'
        while reader.has_next?
          ch = reader.current_char
          return true if ch == '"' || ch == '}'
          return false unless ch.whitespace?
          reader.next_char
        end
        false
      end

      # Strip front matter, if any. The TOML and YAML strips are mutually
      # exclusive: chaining them would let the `\A`-anchored YAML pattern
      # eat a *body* that opens with a thematic break (`---\n…\n---`) once
      # the TOML front matter had already been removed, silently dropping
      # the first block of the document.
      #
      # A leading `---` pair is only stripped when the build reads it as
      # front matter (see `yaml_front_matter?`); a thematic break around
      # prose stays part of the body, as it does in the build.
      def strip_frontmatter(content : String) : String
        if json_start?(content) && (end_idx = find_json_end(content))
          content.byte_slice(end_idx)
        elsif content.matches?(TOML_FRONTMATTER_RE)
          content.sub(TOML_FRONTMATTER_RE, "")
        elsif (match = content.match(YAML_FRONTMATTER_RE)) && yaml_front_matter?(match[1])
          match.post_match
        else
          content
        end
      end

      # A top-level `key:` line — what separates broken YAML front matter
      # from prose between two thematic breaks. Same pattern as
      # `Processors::Markdown::YAML_KEY_LINE_RE`.
      YAML_KEY_LINE_RE = /^[\p{L}_][\p{L}\p{N}_.-]*\s*:(\s|$)/

      # Whether the build treats the text between a leading `---` pair as
      # front matter (`Processors::Markdown#parse`): a mapping, an empty or
      # comment-only block, or a block that fails to parse but carries a
      # `key:` line (the build reports that as invalid front matter). Any
      # other block — a list, a scalar, prose that is not valid YAML — is
      # body text opening with a thematic break, and the build renders it.
      def yaml_front_matter?(block : String) : Bool
        parsed = begin
          YAML.parse(block)
        rescue
          return yaml_front_matter_like?(block)
        end
        return true if parsed.as_h?
        return false unless parsed.raw.nil?
        block.each_line.all? do |line|
          stripped = line.strip
          stripped.empty? || stripped.starts_with?('#')
        end
      end

      # True when a block that failed to parse as YAML still looks like front
      # matter, so the failure is the author's broken front matter rather
      # than prose after a thematic break.
      def yaml_front_matter_like?(block : String) : Bool
        block.each_line.any?(&.matches?(YAML_KEY_LINE_RE))
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
