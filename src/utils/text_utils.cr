# Text utility functions for common string operations
#
# Provides reusable text processing utilities:
# - slugify: Convert text to URL-friendly slugs
# - escape_xml: Escape XML special characters

require "uri"

module Hwaro
  module Utils
    module TextUtils
      extend self

      # Convert text to a URL-friendly slug
      #
      # Supports Unicode characters (CJK, Hangul, etc.) in addition to ASCII.
      #
      # Examples:
      #   slugify("Hello World!")  # => "hello-world"
      #   slugify("My Blog Post")  # => "my-blog-post"
      #   slugify("한글 제목")      # => "한글-제목"
      #   slugify("CJK 테스트!")   # => "cjk-테스트"
      #
      def slugify(text : String) : String
        # Single-pass: directly emit hyphens for separators, collapsing runs.
        # Avoids intermediate String allocation + regex gsub.
        String.build(text.bytesize) do |io|
          last_was_sep = true # suppress leading hyphen
          text.each_char do |char|
            if char.ascii_letter? || char.ascii_number?
              io << char.downcase
              last_was_sep = false
            elsif char.ascii_whitespace? || char == '-' || char == '_'
              unless last_was_sep
                io << '-'
                last_was_sep = true
              end
            elsif cjk_char?(char) || unicode_letter?(char)
              io << char.downcase
              last_was_sep = false
            end
            # All other characters (punctuation, symbols) are dropped
          end
        end.rstrip('-')
      end

      # Like `slugify` but never returns "". An all-symbol/emoji input (e.g. a
      # tag of "!!!" or "🎉") slugifies to "", which would make distinct terms
      # collide onto the same URL/output path and create a `//` path segment.
      # Falls back to a deterministic, stable token derived from the input's
      # UTF-8 bytes so distinct inputs stay distinct and the slug is identical
      # across builds (unlike `String#hash`, which is per-process seeded).
      def safe_slugify(text : String) : String
        s = slugify(text)
        s.empty? ? "term-#{text.to_slice.hexstring}" : s
      end

      # Map a set of terms to UNIQUE slugs. Distinct terms can slugify to the
      # same value ("C++"/"C#" → "c", "Hello World"/"hello-world" → "hello-world");
      # on a clash the later term (in sorted order) gets a numeric suffix, and the
      # candidate is re-checked so it never collides with another generated slug or
      # a real term whose base slug already ends in "-2". Sorting makes the result
      # deterministic across builds regardless of input order.
      #
      # This is the single source of truth for taxonomy term slugs: the taxonomy
      # generator (term-page paths + index links) and the `get_taxonomy` /
      # `get_taxonomy_url` template helpers must all run terms through here so the
      # links they emit point at the pages that were actually written.
      def disambiguated_slugs(terms : Array(String)) : Hash(String, String)
        slug_map = {} of String => String
        used = Set(String).new
        terms.sort.each do |term|
          base = safe_slugify(term)
          slug = base
          n = 2
          while used.includes?(slug)
            slug = "#{base}-#{n}"
            n += 1
          end
          used << slug
          slug_map[term] = slug
        end
        slug_map
      end

      # Check if a character is a Unicode letter (non-ASCII)
      private def unicode_letter?(char : Char) : Bool
        !char.ascii? && char.letter?
      end

      # Escape XML special characters
      #
      # Escapes: & < > " '
      #
      # Example:
      #   escape_xml("Tom & Jerry")  # => "Tom &amp; Jerry"
      #   escape_xml("<script>")     # => "&lt;script&gt;"
      #
      def escape_xml(text : String) : String
        # Fast path: most inputs (URLs, slug-like titles, dates) contain none
        # of the XML special chars, so the loop below would just copy bytes
        # into a fresh String.build. Bailing out here saves an allocation
        # per call — this function is on the per-page hot path for sitemaps,
        # feeds, and llms.txt, so the savings stack up on large builds.
        return text unless contains_xml_special?(text)
        String.build(text.bytesize) do |io|
          text.each_char do |char|
            case char
            when '&'  then io << "&amp;"
            when '<'  then io << "&lt;"
            when '>'  then io << "&gt;"
            when '"'  then io << "&quot;"
            when '\'' then io << "&apos;"
            when .ascii_control?
              # XML 1.0 forbids C0 control chars except tab/LF/CR. A stray
              # control byte (e.g. \f or \v sneaked in via JSON/quoted-YAML
              # frontmatter) would otherwise make the whole feed/sitemap
              # unparseable — drop those. DEL (0x7F) is a legal XML char, so
              # keep it; this also matches contains_xml_special?'s gate exactly.
              o = char.ord
              io << char unless o < 0x20 && o != 0x09 && o != 0x0A && o != 0x0D
            else io << char
            end
          end
        end
      end

      # Percent-encode the path component of a URL for spec-strict XML
      # outputs (sitemap `<loc>`, RSS/Atom `<link>`/`<id>`): the sitemap
      # protocol and RSS require RFC 3986 URIs, so non-ASCII paths like
      # `/posts/한글/` must become `/posts/%ED%95%9C%EA%B8%80/`.
      #
      # The scheme/host prefix (if any) is left untouched, and paths that
      # already contain a percent-escape are passed through unchanged so
      # pre-encoded URLs don't get double-encoded.
      def encode_url_path(url : String) : String
        return url if url.ascii_only? && !url.includes?(' ')
        return url if url.matches?(/%[0-9A-Fa-f]{2}/)

        if scheme_end = url.index("://")
          host_end = url.index('/', scheme_end + 3)
          return url unless host_end
          prefix = url[0...host_end]
          path = url[host_end..]
          prefix + URI.encode_path(path)
        else
          URI.encode_path(url)
        end
      end

      # Byte-level scan for the five XML special chars plus XML-illegal C0
      # control bytes (so the fast path doesn't skip the control-char cleanup).
      # Avoids the regex engine and Unicode decoding — all targets are 7-bit
      # ASCII so the byte view is exact even for UTF-8 input.
      private def contains_xml_special?(text : String) : Bool
        text.each_byte do |b|
          case b
          when 0x26, 0x3C, 0x3E, 0x22, 0x27 # & < > " '
            return true
          when 0x00..0x08, 0x0B, 0x0C, 0x0E..0x1F # XML-illegal C0 controls
            return true
          end
        end
        false
      end

      # Raw-text HTML elements whose *content* is code, not display text.
      # `<style>`/`<script>` bodies must be dropped along with their tags;
      # otherwise the CSS/JS source survives tag-stripping and pollutes
      # search indexes, feed summaries, and excerpts (a page with an inline
      # `<style>` gallery block had its whole search entry replaced by CSS).
      # `[\s\S]` matches across newlines (CSS/JS span multiple lines) without
      # relying on a dotall flag; `\1` ties the close tag to the open tag.
      # A self-closing or unterminated tag won't match and is left to the
      # tag stripper below.
      RAW_TEXT_ELEMENT = /<(script|style)(?:\s[^>]*)?>[\s\S]*?<\/\1\s*>/i

      # Strip HTML tags from text (single-pass)
      #
      # Example:
      #   strip_html("<p>Hello <b>World</b></p>")  # => "Hello World"
      #
      def strip_html(text : String) : String
        # Remove raw-text element bodies (<style>/<script>) before stripping
        # tags so their CSS/JS contents don't leak through as "text".
        text = text.gsub(RAW_TEXT_ELEMENT, " ")
        String.build(text.bytesize) do |io|
          in_tag = false
          last_was_space = true # suppress leading space
          pending_space = false # deferred space from tag boundary
          text.each_char do |char|
            if char == '<'
              in_tag = true
              # Mark that we might need a space (tag boundary)
              pending_space = true unless last_was_space
            elsif char == '>'
              in_tag = false
            elsif !in_tag
              if char.ascii_whitespace?
                unless last_was_space
                  io << ' '
                  last_was_space = true
                  pending_space = false
                end
              else
                # Emit deferred space only if the next char is alphanumeric
                # (avoids "World !" from "</b>!")
                if pending_space && char.alphanumeric?
                  io << ' '
                end
                pending_space = false
                io << char
                last_was_space = false
              end
            end
          end
        end.strip
      end

      # Check if a character is in a CJK Unicode range
      def cjk_char?(char : Char) : Bool
        code = char.ord
        (code >= 0x4E00 && code <= 0x9FFF) ||   # CJK Unified Ideographs
          (code >= 0x3040 && code <= 0x309F) || # Hiragana
          (code >= 0x30A0 && code <= 0x30FF) || # Katakana
          (code >= 0xAC00 && code <= 0xD7AF) || # Hangul Syllables
          (code >= 0x1100 && code <= 0x11FF) || # Hangul Jamo
          (code >= 0x3400 && code <= 0x4DBF) || # CJK Extension A
          (code >= 0x3300 && code <= 0x33FF) || # CJK Compatibility
          (code >= 0xFE30 && code <= 0xFE4F)    # CJK Compatibility Forms
      end

      # Tokenize CJK text into overlapping bigrams for search indexing
      #
      # CJK languages (Chinese, Japanese, Korean) often lack spaces between words.
      # This splits CJK character runs into overlapping 2-character pairs (bigrams)
      # so search libraries can match substrings.
      #
      # Example:
      #   tokenize_cjk("검색엔진")  # => "검색 색엔 엔진"
      #   tokenize_cjk("hello世界测试")  # => "hello世界 界测 测试"
      #
      def tokenize_cjk(text : String) : String
        builder = String::Builder.new(text.bytesize * 2)
        cjk_run = [] of Char

        text.each_char do |char|
          if cjk_char?(char)
            cjk_run << char
          else
            unless cjk_run.empty?
              flush_cjk_run(builder, cjk_run)
              cjk_run.clear
            end
            builder << char
          end
        end

        unless cjk_run.empty?
          flush_cjk_run(builder, cjk_run)
        end

        builder.to_s
      end

      private def flush_cjk_run(builder : String::Builder, run : Array(Char)) : Nil
        if run.size == 1
          builder << run[0]
          return
        end

        (run.size - 1).times do |i|
          builder << ' ' if i > 0
          builder << run[i]
          builder << run[i + 1]
        end
      end
    end
  end
end
