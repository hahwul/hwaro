# Text utility functions for common string operations
#
# Provides reusable text processing utilities:
# - slugify: Convert text to URL-friendly slugs
# - escape_xml: Escape XML special characters

require "digest/sha1"
require "html"
require "uri"

module Hwaro
  module Utils
    module TextUtils
      extend self

      # Longest error message any console emitter prints on one line.
      #
      # A template error carries Crinja's source excerpt, so a single
      # minified/one-line template turns one failure into a multi-megabyte
      # console line: a 3 MB `{% if %}` line produced a 6 MB log, and in serve
      # mode every rebuild repeated it. The clamp has to be applied by each
      # emitter (rather than inside Logger) because the machine-readable
      # contracts hwaro prints elsewhere are byte-preserved.
      MAX_ERROR_CHARS = 4000

      # Clamp `message` to `max` CHARACTERS (not bytes — the count is what the
      # suffix reports, and slicing on a character boundary can never split a
      # codepoint in the terminal). Returns the message untouched when it fits,
      # which is every ordinary error.
      def truncate_error(message : String, max : Int32 = MAX_ERROR_CHARS) : String
        # A negative budget is nonsense, but `String#[0, negative]` answers it
        # with `ArgumentError: Negative count` — turning a caller's bad cap
        # into a crash while it was busy REPORTING another error, which is the
        # worst possible moment to raise. Clamp to "keep nothing" instead.
        max = 0 if max < 0
        return message if message.size <= max
        "#{message[0, max]}… (truncated, #{message.size} characters)"
      end

      # Display names for common language codes, used by scaffold configs
      # for `--include-multilingual`. Unknown codes fall back to upcase.
      LANGUAGE_DISPLAY_NAMES = {
        "en" => "English",
        "ko" => "한국어",
        "ja" => "日本語",
        "zh" => "中文",
        "es" => "Español",
        "fr" => "Français",
        "de" => "Deutsch",
        "pt" => "Português",
        "ru" => "Русский",
        "it" => "Italiano",
        "nl" => "Nederlands",
        "pl" => "Polski",
        "vi" => "Tiếng Việt",
        "th" => "ไทย",
        "ar" => "العربية",
        "hi" => "हिन्दी",
      }

      def language_display_name(code : String) : String
        LANGUAGE_DISPLAY_NAMES[code.downcase]? || code.upcase
      end

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

      # Widest padding run `pad_display` will emit. Far past any real terminal,
      # so alignment is unaffected; it only bounds a nonsense width.
      MAX_PAD_COLUMNS = 10_000

      # Left-align `s` in a field `width` terminal columns across. The
      # display-width counterpart of `String#ljust`; identical to it for
      # ASCII-only input.
      def pad_display(s : String, width : Int32) : String
        # Int64 subtraction: `width - display_width(s)` overflows Int32 for a
        # width near either extreme (a terminal width read as Int32::MIN, a
        # column computed from a pathological label), and `String#*` then gets
        # a negative or absurd count. Both raise out of a pure FORMATTING
        # helper. Cap the padding at a full screen's worth instead.
        pad = width.to_i64 - display_width(s).to_i64
        return s unless pad > 0
        "#{s}#{" " * pad.clamp(0_i64, MAX_PAD_COLUMNS.to_i64)}"
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
      #   slugify("CI/CD")         # => "ci-cd"
      #   slugify("보안—우회")      # => "보안-우회"  (em dash)
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
            elsif char.whitespace? || char == '-' || char == '_' || slug_separator?(char)
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

      # Punctuation that joins two words WITHOUT surrounding spaces and so
      # must become a hyphen rather than vanish. Dropping these welded the
      # words together: "CI/CD" → "cicd", "security/xss" → "securityxss",
      # "보안—우회" → "보안우회" — while every slug convention (and Hwaro's own
      # `Creator.slugify` for filenames) separates them ("ci-cd").
      # Deliberately narrow: slash, backslash, and the Unicode dash block
      # (hyphen U+2010 … horizontal bar U+2015) plus minus sign U+2212.
      # Other punctuation ('.', '&', apostrophes, …) keeps the historical
      # drop behavior so existing heading anchors and term URLs don't move.
      private def slug_separator?(char : Char) : Bool
        char == '/' || char == '\\' || char.in?('‐'..'―') || char == '−'
      end

      # Longest slug `safe_slugify` returns, in bytes.
      #
      # A taxonomy term becomes one path segment (`public/tags/<slug>/`), and
      # nothing bounded it: pasting a phrase into `tags` produced a 300-byte
      # directory name and the build died at the first mkdir with ENAMETOOLONG.
      # The two filesystem limits that matter disagree on their UNIT — ext4
      # caps a name at 255 bytes, APFS at 255 characters — which is why a
      # 264-byte / 88-character Korean tag builds on macOS but not on Linux. A
      # byte bound satisfies both, because a string's character count is never
      # greater than its byte count.
      #
      # The bound is set as close to 255 as the `-N` disambiguation suffix
      # `disambiguated_slugs` may append allows (10 bytes of headroom, enough
      # for `-999999999`), deliberately NOT lower: a slug of 201..245 bytes
      # publishes fine on every mainstream filesystem, so a tighter cap would
      # silently move the URL of a term that works today — `page.url`, the
      # sitemap `<loc>`, the feeds and every `get_taxonomy_url` link with it —
      # and 404 anything already indexed. Only terms that could not have been
      # written at all are rewritten.
      MAX_SLUG_BYTES = 245

      # Hex characters of the term digest appended to a truncated slug — enough
      # that two terms sharing a long prefix keep separate URLs.
      SLUG_DIGEST_CHARS = 8

      # Like `slugify` but never returns "" and never exceeds `MAX_SLUG_BYTES`.
      # An all-symbol/emoji input (e.g. a tag of "!!!" or "🎉") slugifies to "",
      # which would make distinct terms collide onto the same URL/output path
      # and create a `//` path segment. Falls back to a deterministic, stable
      # token derived from the input's UTF-8 bytes so distinct inputs stay
      # distinct and the slug is identical across builds (unlike `String#hash`,
      # which is per-process seeded).
      def safe_slugify(text : String) : String
        s = slugify(text)
        # Two hex characters per input byte, so this fallback is the *longer*
        # of the two paths for a long emoji-only term — it needs bounding too.
        s = "term-#{text.to_slice.hexstring}" if s.empty?
        bound_slug(s, text)
      end

      # Cap `slug` at `MAX_SLUG_BYTES`, keeping distinct terms on distinct URLs.
      #
      # Truncating alone would fold every term sharing a long prefix onto one
      # slug — two tags silently rendering as one page — so the kept head is
      # followed by a digest of the WHOLE source term. SHA-1 is an identifier
      # here, not a security primitive; what it buys is determinism across
      # runs, processes and platforms, which `String#hash` (per-process seeded)
      # does not give. That matters because this is the single source of truth
      # for term slugs: bounding here means the on-disk path, `page.url`, the
      # sitemap, the feeds and the `get_taxonomy_url` helper all shorten
      # together. Bounding at the filesystem layer instead would leave every
      # generated link pointing at the un-truncated path — a site of dead
      # links, worse than the crash.
      #
      # Slugs at or under the bound — every term on every existing site — are
      # returned untouched, so no published URL moves.
      # True when `safe_slugify(term)` had to shorten the term to fit
      # `MAX_SLUG_BYTES`, i.e. its published URL is not derived from the whole
      # term. `safe_slugify` itself is called many times per term (index links,
      # term pages, template helpers), so it must stay silent; callers that
      # enumerate the term set ONCE per build use this to warn exactly once.
      def slug_truncated?(term : String) : Bool
        s = slugify(term)
        s = "term-#{term.to_slice.hexstring}" if s.empty?
        s.bytesize > MAX_SLUG_BYTES
      end

      private def bound_slug(slug : String, source : String) : String
        return slug if slug.bytesize <= MAX_SLUG_BYTES

        suffix = "-#{Digest::SHA1.hexdigest(source)[0, SLUG_DIGEST_CHARS]}"
        head = truncate_bytes(slug, MAX_SLUG_BYTES - suffix.bytesize)
        # The cut can land right after a separator ("...-word-"); dropping it
        # keeps the result shaped like any other slug, which never ends in "-".
        "#{head.rstrip('-')}#{suffix}"
      end

      # Longest prefix of `s` that fits in `max_bytes`, cut on a character
      # boundary. Slicing UTF-8 at an arbitrary byte offset would leave half a
      # codepoint in a directory name and in every link that points at it, so
      # the width of each character is charged whole or not at all.
      private def truncate_bytes(s : String, max_bytes : Int32) : String
        kept = 0
        s.each_char do |char|
          width = char.bytesize
          break if kept + width > max_bytes
          kept += width
        end
        s.byte_slice(0, kept)
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
      #
      # Bases arrive already capped by `safe_slugify`; the few bytes a `-N`
      # suffix adds on top are what `MAX_SLUG_BYTES`' headroom under 255 is for.
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
      # The scheme/host prefix (if any) is left untouched, and escapes that are
      # already present are stepped over so pre-encoded URLs don't get
      # double-encoded.
      def encode_url_path(url : String) : String
        return url if url.ascii_only? && !url.includes?(' ')

        if scheme_end = url.index("://")
          host_end = url.index('/', scheme_end + 3)
          return url unless host_end
          prefix = url[0...host_end]
          path = url[host_end..]
          prefix + encode_path_preserving_escapes(path)
        else
          encode_path_preserving_escapes(url)
        end
      end

      # `URI.encode_path`, except that a `%XX` escape already in the input is
      # copied through instead of having its `%` escaped again.
      #
      # The old rule bailed out of encoding entirely at the first escape it
      # saw. That is right for a fully pre-encoded URL, but "contains an
      # escape" is not "is fully escaped": a page whose filename holds both a
      # non-ASCII word and a `#` reaches here as `/posts/한글%23x/`, and
      # passing that straight through emitted raw UTF-8 into a sitemap `<loc>`
      # and an RSS `<link>`, which the sitemap protocol and RFC 3986 forbid.
      # Same for a URL mixing a raw space with an escape (`/a b%20c/`).
      private def encode_path_preserving_escapes(path : String) : String
        return URI.encode_path(path) unless path.matches?(/%[0-9A-Fa-f]{2}/)

        bytes = path.to_slice
        String.build(path.bytesize + 8) do |io|
          index = 0
          run_start = 0
          while index < bytes.size
            # `%` + two hex digits: an escape to preserve verbatim. Encode the
            # run of ordinary bytes before it as one chunk so multi-byte UTF-8
            # characters are never split across two encode calls.
            if bytes[index] == 0x25 && index + 2 < bytes.size &&
               bytes[index + 1].unsafe_chr.hex? && bytes[index + 2].unsafe_chr.hex?
              URI.encode_path(io, String.new(bytes[run_start, index - run_start])) if index > run_start
              io.write(bytes[index, 3])
              index += 3
              run_start = index
            else
              index += 1
            end
          end
          URI.encode_path(io, String.new(bytes[run_start, bytes.size - run_start])) if run_start < bytes.size
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

      # Elements whose CONTENT is not prose and must not seed an automatic
      # summary: code (`<pre>`/`<code>`), raw-text elements, figures/images
      # (captions and alt text read badly out of context) and headings (a
      # summary that opens with the page's own title is noise). Matched
      # with a lazy `[\s\S]*?` so multi-line blocks are removed whole; a
      # nested `<code>` inside `<pre>` is consumed by the outer match.
      # Unterminated tags fall through to the generic tag stripper.
      EXCERPT_SKIP_ELEMENT = /<(pre|code|script|style|figure|h[1-6])(?:\s[^>]*)?>[\s\S]*?<\/\1\s*>/i
      EXCERPT_SKIP_VOID    = /<img(?:\s[^>]*)?\/?>/i
      # Markup the Markdown extensions emit whose text is not prose either:
      # math (`<span class="math …">\(x\)</span>` holds TeX source until
      # KaTeX/MathJax runs in the browser), footnote reference markers
      # (`[1]`) and the trailing footnotes section.
      EXCERPT_SKIP_CLASSED = /<(span|div|sup|section)\s+class="(?:math|footnote-ref|footnotes)[^"]*"[^>]*>[\s\S]*?<\/\1\s*>/i

      # Plain prose of a rendered HTML body, for the automatic summary:
      # code/figure/heading/math/footnote blocks dropped, tags stripped,
      # entities decoded
      # (after stripping, so `&lt;p&gt;` can never be read as markup), and
      # whitespace collapsed to single spaces. The result is TEXT — a
      # consumer that embeds it in HTML must escape it again.
      def excerpt_text(html : String) : String
        cleaned = html.gsub(EXCERPT_SKIP_ELEMENT, " ").gsub(EXCERPT_SKIP_CLASSED, " ").gsub(EXCERPT_SKIP_VOID, " ")
        text = HTML.unescape(strip_html(cleaned))
        collapse_whitespace(text)
      end

      # Trailing characters dropped before the ellipsis so a cut never ends
      # in `word,…` / `word;…`. Covers ASCII and the full-width CJK forms.
      EXCERPT_TRAILING_PUNCT = {',', ';', ':', '&', '\uFF0C', '\uFF1B', '\uFF1A', '\u3001', '(', '\uFF08', '[', '-', '\u2013', '\u2014'}

      # Truncate plain text for an automatic summary. Returns the excerpt
      # and whether anything was cut.
      #
      # Units: space-delimited text is measured in WORDS. Text whose
      # non-space characters are mostly CJK (Chinese/Japanese have no word
      # boundaries; Korean has them but sentences pack far more meaning
      # per word) is measured in CHARACTERS with the same numeric setting
      # scaled ×2, so `length = 70` reads as ~70 words or ~140 CJK
      # characters. The character cut is never placed inside a Latin word
      # embedded in CJK text (it backs up to the preceding boundary), and
      # every index is a Char index, so a multibyte sequence cannot be
      # split. Entities are not a concern: callers pass decoded text.
      # `length <= 0` means "no limit" — callers gate the feature on it.
      def truncate_excerpt(text : String, length : Int32, ellipsis : String) : {String, Bool}
        text = collapse_whitespace(text)
        return {text, false} if text.empty? || length <= 0

        cut = if cjk_dominant?(text)
                truncate_excerpt_chars(text, length * 2)
              else
                truncate_excerpt_words(text, length)
              end
        return {text, false} unless cut

        cut = cut.rstrip
        while (last = cut[-1]?) && (last.ascii_whitespace? || EXCERPT_TRAILING_PUNCT.includes?(last))
          cut = cut.rchop
        end
        # Degenerate input (all punctuation before the cut): keep the raw
        # cut rather than emitting a bare ellipsis.
        cut = text[0, length].rstrip if cut.empty?
        {"#{cut}#{ellipsis}", true}
      end

      # CJK-dominant: more than half of the non-whitespace characters are
      # CJK (same ranges `tokenize_cjk`/`slugify` use).
      def cjk_dominant?(text : String) : Bool
        cjk = 0
        total = 0
        text.each_char do |c|
          next if c.ascii_whitespace?
          total += 1
          cjk += 1 if cjk_char?(c)
        end
        total > 0 && cjk * 2 > total
      end

      private def truncate_excerpt_words(text : String, max_words : Int32) : String?
        words = text.split(' ')
        return if words.size <= max_words
        words[0, max_words].join(' ')
      end

      private def truncate_excerpt_chars(text : String, max_chars : Int32) : String?
        return if text.size <= max_chars
        chars = text.chars
        idx = max_chars
        # Inside a run of non-CJK, non-space characters (a Latin word or a
        # number embedded in CJK prose)? Back up to where that run started.
        if latin_word_char?(chars[idx]) && latin_word_char?(chars[idx - 1])
          back = idx
          while back > 0 && latin_word_char?(chars[back - 1])
            back -= 1
          end
          idx = back if back > 0
        end
        chars[0, idx].join
      end

      private def latin_word_char?(c : Char) : Bool
        !c.ascii_whitespace? && !cjk_char?(c) && (c.alphanumeric? || c == '\'' || c == '_')
      end

      private def collapse_whitespace(text : String) : String
        String.build(text.bytesize) do |io|
          pending = false
          started = false
          text.each_char do |c|
            if c.whitespace?
              pending = started
            else
              io << ' ' if pending
              pending = false
              started = true
              io << c
            end
          end
        end
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
