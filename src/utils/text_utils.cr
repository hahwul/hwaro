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

      # Strip a leading UTF-8 byte order mark.
      #
      # Windows editors (Notepad, PowerShell `>` redirection, "UTF-8 with BOM"
      # in VS Code) prepend U+FEFF. Every parser hwaro hands file text to
      # anchors on the first character — the front matter fences (`\A\+\+\+`,
      # `\A---`, a leading `{`), TOML's first token, JSON's first token — so a
      # BOM silently turns front matter into body text and makes config.toml
      # and data files unparseable. Strip it once at the point of read.
      def strip_bom(content : String) : String
        content.lchop('\uFEFF')
      end

      # Remove terminal control characters (ANSI escapes, CR, BEL, \u2026) plus the
      # Unicode line/paragraph separators.
      #
      # Titles, tags and link targets come from semi-trusted content \u2014 a docs
      # or blog PR \u2014 and end up printed to a maintainer's terminal by the
      # `tool` reports. Raw escape bytes there can repaint or spoof the
      # console, and they wreck column alignment even when benign.
      #
      # Scope is deliberately Cc only. `Char#control?` is ALSO true for the Cf
      # format category, and stripping that mangles real words: U+200C ZWNJ
      # turns Persian `\u0645\u06cc\u200c\u0631\u0648\u062f` into the different word `\u0645\u06cc\u0631\u0648\u062f`, U+200D ZWJ
      # splits `\ud83d\udc68\u200d\ud83d\udc69\u200d\ud83d\udc67` into three separate people, and dropping U+200F RLM
      # flips where punctuation lands in a Hebrew line. Those codepoints are
      # invisible, not dangerous \u2014 they carry no cursor movement \u2014 so they
      # stay. Apply this at the RENDER layer only; a model or JSON payload
      # must keep the author's bytes intact.
      def strip_control(s : String) : String
        return s unless s.each_char.any? { |c| strippable_control?(c) }
        s.gsub { |c| strippable_control?(c) ? "" : c }
      end

      # C0 (U+0000\u2013001F), DEL + C1 (U+007F\u2013009F), and the LINE/PARAGRAPH
      # SEPARATORs, which terminals treat as line breaks.
      private def strippable_control?(c : Char) : Bool
        ord = c.ord
        ord <= 0x1F || (0x7F <= ord <= 0x9F) || ord == 0x2028 || ord == 0x2029
      end

      # Codepoint ranges that occupy two terminal columns: East Asian Wide (W)
      # and Fullwidth (F) per UAX #11, plus the emoji blocks terminals render
      # double-width. Ascending and non-overlapping, so `wide_char?` can stop
      # as soon as a range starts past the codepoint. Anything outside is one
      # column.
      WIDE_RANGES = [
        0x1100..0x115F,   # Hangul Jamo initial consonants
        0x231A..0x231B,   # ⌚ ⌛
        0x2329..0x232A,   # 〈 〉
        0x23E9..0x23EC,   # ⏩–⏬
        0x23F0..0x23F0,   # ⏰
        0x23F3..0x23F3,   # ⏳
        0x25FD..0x25FE,   # ◽ ◾
        0x2614..0x2615,   # ☔ ☕
        0x2648..0x2653,   # zodiac
        0x267F..0x267F,   # ♿
        0x2693..0x2693,   # ⚓
        0x26A1..0x26A1,   # ⚡
        0x26AA..0x26AB,   # ⚪ ⚫
        0x26BD..0x26BE,   # ⚽ ⚾
        0x26C4..0x26C5,   # ⛄ ⛅
        0x26CE..0x26CE,   # ⛎
        0x26D4..0x26D4,   # ⛔
        0x26EA..0x26EA,   # ⛪
        0x26F2..0x26F3,   # ⛲ ⛳
        0x26F5..0x26F5,   # ⛵
        0x26FA..0x26FA,   # ⛺
        0x26FD..0x26FD,   # ⛽
        0x2705..0x2705,   # ✅
        0x270A..0x270B,   # ✊ ✋
        0x2728..0x2728,   # ✨
        0x274C..0x274C,   # ❌
        0x274E..0x274E,   # ❎
        0x2753..0x2755,   # ❓–❕
        0x2757..0x2757,   # ❗
        0x2795..0x2797,   # ➕–➗
        0x27B0..0x27B0,   # ➰
        0x27BF..0x27BF,   # ➿
        0x2B1B..0x2B1C,   # ⬛ ⬜
        0x2B50..0x2B50,   # ⭐
        0x2B55..0x2B55,   # ⭕
        0x2E80..0x303E,   # CJK radicals, Kangxi, CJK symbols & punctuation
        0x3041..0x33FF,   # Hiragana, Katakana, Bopomofo, Hangul compat, CJK compat
        0x3400..0x4DBF,   # CJK unified ideographs extension A
        0x4E00..0x9FFF,   # CJK unified ideographs
        0xA000..0xA4CF,   # Yi syllables & radicals
        0xA960..0xA97F,   # Hangul Jamo extended-A
        0xAC00..0xD7A3,   # Hangul syllables
        0xD7B0..0xD7C6,   # Hangul Jamo extended-B (vowels)
        0xD7CB..0xD7FB,   # Hangul Jamo extended-B (trailing consonants)
        0xF900..0xFAFF,   # CJK compatibility ideographs
        0xFE10..0xFE19,   # Vertical forms
        0xFE30..0xFE6F,   # CJK compatibility & small form variants
        0xFF00..0xFF60,   # Fullwidth ASCII variants
        0xFFE0..0xFFE6,   # Fullwidth signs
        0x16FE0..0x16FE4, # Tangut/Nushu marks
        0x17000..0x18AFF, # Tangut
        0x1B000..0x1B12F, # Kana supplement / extended
        0x1F004..0x1F004, # 🀄
        0x1F0CF..0x1F0CF, # 🃏
        0x1F18E..0x1F18E, # 🆎
        0x1F191..0x1F19A, # 🆑–🆚
        0x1F200..0x1F2FF, # Enclosed ideographic supplement (🈚 …)
        0x1F300..0x1F64F, # Misc symbols & pictographs, emoticons
        0x1F680..0x1F6FF, # Transport & map symbols
        0x1F7E0..0x1F7EB, # 🟠–🟫 coloured shapes
        0x1F900..0x1F9FF, # Supplemental symbols & pictographs
        0x1FA70..0x1FAFF, # Symbols & pictographs extended-A (🩴 …)
        0x20000..0x2FFFD, # CJK extension B and beyond
        0x30000..0x3FFFD,
      ]

      # Emoji modifiers (Fitzpatrick skin tones). They are category So, not a
      # combining mark, but they recolour the preceding emoji rather than
      # adding a cell: `👍🏽` renders in two columns, not four.
      SKIN_TONE_RANGE = 0x1F3FB..0x1F3FF

      # Zero-width joiner. `👨‍👩‍👧` is three wide emoji plus two joiners but
      # renders as a single two-column glyph, so a joiner makes the codepoint
      # that follows it contribute nothing.
      ZWJ = 0x200D

      # How many terminal columns a string occupies.
      #
      # `String#size` counts codepoints, which is the wrong unit for padding a
      # column: a Hangul or CJK title renders twice as wide as its codepoint
      # count, a combining mark renders in the previous cell, and a control
      # byte renders as nothing — so `ljust` left every table row after a
      # non-ASCII cell visibly misaligned.
      #
      # Printable ASCII returns exactly `size`, so ASCII-only output — every
      # existing table — is unchanged. A TAB is deliberately counted as one
      # column (what `ljust` charged it) rather than zero: its real width
      # depends on the terminal's tab stops, and one keeps the "ASCII measures
      # like `String#size`" invariant total rather than only-for-printable.
      def display_width(s : String) : Int32
        return s.bytesize if printable_ascii?(s)

        width = 0
        joined = false
        s.each_char do |c|
          ord = c.ord

          if ord == ZWJ
            joined = true
            next
          end

          next if SKIN_TONE_RANGE.includes?(ord)
          # `Char#control?` covers Cc *and* Cf, so ZWSP / RLM / BOM are zero
          # too; `mark?` covers combining marks and variation selectors. Both
          # are correct for WIDTH even though `strip_control` deliberately
          # keeps Cf — an invisible character occupies no column either way.
          next if ord == 0x2028 || ord == 0x2029
          next if (c.control? && ord != 0x09) || c.mark?

          wide = wide_char?(c)
          # A joiner merges the following EMOJI into the preceding glyph
          # (`👨‍👩‍👧` is one two-column cluster). It does not merge ordinary
          # letters: `a‍b` still renders as two characters, so only a wide
          # codepoint is absorbed.
          if joined
            joined = false
            next if wide
          end

          width += wide ? 2 : 1
        end
        width
      end

      # Left-align `s` in a field `width` terminal columns across. The
      # display-width counterpart of `String#ljust`; identical to it for
      # ASCII-only input.
      def pad_display(s : String, width : Int32) : String
        pad = width - display_width(s)
        pad > 0 ? "#{s}#{" " * pad}" : s
      end

      # Space through `~`: one byte, one codepoint, one column each — the
      # overwhelmingly common case, and the one that must stay exact.
      private def printable_ascii?(s : String) : Bool
        s.each_byte { |b| return false if b < 0x20 || b > 0x7E }
        true
      end

      # `WIDE_RANGES` is ascending and disjoint, so the scan can stop at the
      # first range that begins past `ord` instead of testing all of them.
      private def wide_char?(c : Char) : Bool
        ord = c.ord
        return false if ord < 0x1100
        WIDE_RANGES.each do |range|
          return false if range.begin > ord
          return true if range.includes?(ord)
        end
        false
      end

      # Count words the way the build does.
      #
      # Single pass: skip HTML tags, and treat Markdown punctuation as a
      # separator rather than a word so `## Heading` counts one word and a
      # table row's pipes count none. This is the single source of truth
      # behind both `page.word_count` / `page.reading_time` and
      # `hwaro tool stats`, which previously split on whitespace alone and
      # reported ~30% more words than the site itself rendered.
      def count_words(text : String) : Int32
        in_tag = false
        in_word = false
        count = 0

        reader = Char::Reader.new(text)
        while reader.has_next?
          char = reader.current_char
          if char == '<'
            # Only enter tag mode for a real HTML tag start (`<a`, `</p`, `<!--`).
            # A bare `<` in prose/math ("n < 1000", "if 0 < x") is a literal
            # less-than, not a tag \u2014 treating it as one set in_tag with no closing
            # `>` and swallowed the rest of the document, collapsing the count.
            nxt = reader.peek_next_char
            in_tag = true if nxt.ascii_letter? || nxt == '/' || nxt == '!'
            in_word = false
          elsif char == '>'
            in_tag = false
          elsif !in_tag
            is_word_char = !char.ascii_whitespace? && !char.in?('#', '*', '_', '`', '[', ']', '(', ')', '~', '>', '<', '|')
            if is_word_char
              count += 1 unless in_word
              in_word = true
            else
              in_word = false
            end
          end
          reader.next_char
        end

        count
      end

      # Convert text to a URL-friendly slug
      #
      # Supports Unicode characters (CJK, Hangul, etc.) in addition to ASCII.
      #
      # Examples:
      #   slugify("Hello World!")  # => "hello-world"
      #   slugify("My Blog Post")  # => "my-blog-post"
      #   slugify("한글 제목")      # => "한글-제목"
      #   slugify("CJK 테스트!")   # => "cjk-테스트"
      #   slugify("日本語　テスト") # => "日本語-テスト"  (U+3000)
      #
      def slugify(text : String) : String
        # Single-pass: directly emit hyphens for separators, collapsing runs.
        # Avoids intermediate String allocation + regex gsub.
        String.build(text.bytesize) do |io|
          last_was_sep = true # suppress leading hyphen
          # Separator test is `whitespace?`, not `ascii_whitespace?`: the
          # ideographic space U+3000 is the ordinary word separator in CJK
          # titles, and an `&nbsp;` in a title decodes to U+00A0. Neither is
          # a letter, so the old test dropped them entirely and welded the
          # surrounding words together ("日本語　テスト" → "日本語テスト").
          text.each_char do |char|
            if char.ascii_letter? || char.ascii_number?
              io << char.downcase
              last_was_sep = false
            elsif char.whitespace? || char == '-' || char == '_'
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
