# CSS minification utilities
#
# Provides conservative CSS minification that removes unnecessary
# whitespace and comments while preserving functional correctness.
#
# Operations:
# - Remove CSS comments (/* ... */)
# - Collapse whitespace
# - Remove whitespace around structural characters
# - Strip trailing semicolons before }
# - Preserve url() contents and string literals
#
# Processing order is critical: strings and urls are extracted first
# so that comment removal and whitespace rules cannot damage their
# contents (e.g. "/* not a comment */" or url(http://example.com)).

module Hwaro
  module Utils
    module CssMinifier
      extend self

      # Perform conservative CSS minification
      def minify(css : String) : String
        result = css
        preserves = [] of String
        placeholder_prefix = "\x00PRESERVE_"

        # ── Step 1: Extract url() contents FIRST ─────────────────────────
        # Must run before string extraction, because url('...') contains
        # quotes that would otherwise be captured as standalone strings.
        result = result.gsub(/url\(\s*(['"]?)(.+?)\1\s*\)/m) do |_match|
          quote = $1
          inner = $2
          idx = preserves.size
          preserves << "url(#{quote}#{inner}#{quote})"
          "#{placeholder_prefix}#{idx}\x00"
        end

        # ── Step 2: Extract remaining string literals ─────────────────────
        # Prevents comment-like patterns inside strings from being stripped.
        # e.g. content: "/* not a comment */"
        result = result.gsub(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/m) do |match|
          idx = preserves.size
          preserves << match
          "#{placeholder_prefix}#{idx}\x00"
        end

        # ── Step 3: Remove comments (safe now — strings/urls are protected) ─
        result = result.gsub(/\/\*.*?\*\//m, "")

        # ── Step 4: Collapse whitespace ───────────────────────────────────
        result = result.gsub(/\s+/, " ")

        # ── Step 5: Remove space around structural characters ─────────────
        result = result.gsub(/\s*\{\s*/, "{")
        result = result.gsub(/\s*\}\s*/, "}")
        result = result.gsub(/\s*:\s*/, ":")
        result = result.gsub(/\s*;\s*/, ";")
        result = result.gsub(/\s*,\s*/, ",")

        # ── Step 6: Strip trailing semicolons before } ────────────────────
        result = result.gsub(/;\}/, "}")

        # ── Step 7: Restore preserved tokens (single-pass) ─────────────────
        result = result.gsub(/\x00PRESERVE_(\d+)\x00/) do
          idx = $1.to_i
          idx < preserves.size ? preserves[idx] : $0
        end

        result.strip
      end
    end
  end
end
