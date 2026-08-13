# Shortcode processing module extracted from Builder
#
# Handles Jinja2/Crinja-style shortcode expansion in content:
# - Block shortcodes:  {% name(args) %}body{% end %}   or   {% name(args) %}body{% endname %}
# - Explicit calls:    {{ shortcode("name", args) }}
# - Direct calls:      {{ name(args) }}
#
# Both bare {% end %} and named {% endNAME %} closers are supported (localized normalization).
#
# Shortcodes inside fenced code blocks (``` / ~~~) are left untouched
# so documentation can show literal `{{ ... }}` examples safely.

require "crinja"
require "../../utils/logger"
require "../../content/processors/fence_tracker"
require "../../content/processors/inline_markdown"
require "./builtin_shortcodes"

module Hwaro
  module Core
    module Build
      module ShortcodeProcessor
        # Quoted values accept backslash escapes (`\"`, `\'`, `\\`) so a caption
        # or title can contain the same quote character that delimits it. Without
        # `(?:[^"\\]|\\.)*`, `caption="The \"big\" reveal"` matched only up to the
        # first escaped quote: the value silently became `The \` and the rest of
        # the argument list was mis-split.
        SHORTCODE_ARGS_REGEX  = /(\w+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|([^,\s]+))/
        MAX_SHORTCODE_NESTING = 5
        BLOCK_OPEN_RE         = /\{\%\s*([a-zA-Z_][\w\-]*)\s*(?:\((.*?)\)|((?:\w+\s*=\s*(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[^,%\s]+)\s*,?\s*)*))\s*\%\}/
        # Support both bare {% end %} and named {% endNAME %}.
        BLOCK_CLOSE_RE = /\{\%\s*end(?:\s+[a-zA-Z_][\w\-]*)?\s*\%\}/i
        # Broader close matcher for the outer fence loop's block pairing: it
        # must recognize every closer the normalization step collapses to
        # `{% end %}` — bare `{% end %}` and named `{% endNAME %}` / `{% end NAME %}`
        # with OR without a space — so it stays balanced against BLOCK_OPEN_RE
        # (which also matches `{% endalert %}` as an opener). Without the no-space
        # form, openers would never pair off and fence protection would
        # silently break for the rest of the document.
        BLOCK_ANY_CLOSE_RE = /\{\%\s*end[\s\w\-]*\%\}/i

        # Placeholder left in the content stream for each rendered shortcode
        # before Markdown runs. HTML-comment form so CommonMark treats it as
        # an HTML block (type 2) when on its own line — otherwise block-level
        # shortcode output ends up wrapped in a stray <p>. Inline usage still
        # works because comments are preserved verbatim inside paragraphs.
        # The %d is substituted with the placeholder index at emit time, and
        # the regex is used by `replace_shortcode_placeholders` after Markdown.
        SHORTCODE_PLACEHOLDER_PREFIX = "<!--HWARO-SHORTCODE-PLACEHOLDER-"
        SHORTCODE_PLACEHOLDER_SUFFIX = "-->"
        # The matching regex lives in InlineMarkdown, which must stash the
        # comment before its HTML.escape pass (a spec pins the alias against
        # PREFIX/SUFFIX so the two can't drift).
        SHORTCODE_PLACEHOLDER_RE = Content::Processors::InlineMarkdown::SHORTCODE_PLACEHOLDER_RE

        # Matches CommonMark-style inline code spans on a single line
        # (1 to 3 leading backticks; the same count must close the span).
        # Multi-line inline spans are rare and intentionally not handled —
        # those are usually fenced blocks, which the line-based outer
        # loop in `process_shortcodes_jinja` already skips.
        INLINE_CODE_RE = /(`{1,3})((?:(?!\1)[^\n])+?)\1/

        # Fast pre-filter used by the render hot path (see render.cr).
        # Returns true only when {{ or {% appear *outside* fenced code blocks
        # (``` / ~~~) and *outside* inline code spans. This lets us skip the
        # expensive build_template_variables + full shortcode processing for
        # the very common case of documentation pages that only show literal
        # shortcode examples inside code regions.
        def content_may_contain_shortcodes?(content : String) : Bool
          return false unless content.includes?("{{") || content.includes?("{%")

          # FenceTracker (shared with the table/definition/math walkers and,
          # critically, process_shortcodes_jinja below) so the skip decision
          # and the actual expansion can never disagree about what's fenced.
          tracker = Content::Processors::FenceTracker.new

          content.each_line(chomp: false) do |line|
            next if tracker.fence_line?(line)

            # Outside fence: check whether any {{ or {% survives inline-code stripping
            if line.includes?("{{") || line.includes?("{%")
              if has_shortcode_token_outside_inline_code?(line)
                return true
              end
            end
          end

          false
        end

        private def has_shortcode_token_outside_inline_code?(line : String) : Bool
          pos = 0
          while match = INLINE_CODE_RE.match(line, pos)
            before = line[pos...match.begin]
            return true if before.includes?("{{") || before.includes?("{%")

            pos = match.begin + match[0].size
          end

          tail = line[pos..]
          tail.includes?("{{") || tail.includes?("{%")
        end

        # Process shortcodes in content (Jinja2/Crinja style)
        # Supports two syntax patterns:
        # 1. Explicit: {{ shortcode("name", arg1="value1", arg2="value2") }}
        # 2. Direct:   {{ name(arg1="value1", arg2="value2") }}
        private def process_shortcodes_jinja(content : String, templates : Hash(String, String), context : Hash(String, Crinja::Value), shortcode_results : Hash(String, String)? = nil, crinja_env_override : Crinja? = nil, template_cache_override : Hash(UInt64, Crinja::Template)? = nil, warnings : Array(String)? = nil) : String
          # Avoid processing shortcodes inside fenced code blocks (``` / ~~~),
          # so documentation can show literal `{{ ... }}` examples safely.
          # Fence semantics come from the shared CommonMark-faithful
          # FenceTracker (indent rules, closer-length rule, backtick-in-info
          # rule) — the previous ad-hoc regex opened on indented ``` (literal
          # text in CommonMark) and never closed on a longer closer run,
          # desyncing fence state for the rest of the document.
          String.build do |io|
            tracker = Content::Processors::FenceTracker.new
            buffer = String::Builder.new
            # Lines that live inside a block-shortcode body. While inside one
            # we must NOT treat a fence line as a buffer boundary, otherwise a
            # block shortcode whose body contains a fenced code block gets
            # split across chunks and its `{% name %}` / `{% end %}` tags leak
            # as literal text.
            #
            # The map is computed up front because the answer needs
            # look-ahead: only a MATCHED opener/closer pair opens a body. The
            # running depth counter this replaced had no way to know, so an
            # opener the author never closed pinned the depth above zero for
            # the rest of the page — the tracker was never fed again, every
            # later fenced `{{ … }}` example expanded, and Markd escaped the
            # resulting placeholder comment inside `<pre><code>` where the
            # post-Markdown restore pass can no longer find it (the raw
            # HWARO-SHORTCODE-PLACEHOLDER token then shipped in the HTML,
            # the feed and the search index).
            body_lines = block_body_lines(content)
            line_no = 0

            content.each_line(chomp: false) do |line|
              in_body = body_lines[line_no]? || false
              line_no += 1

              # Fence lines flush the pending chunk and pass through
              # verbatim. The tracker is only fed outside block-shortcode
              # bodies: a fence inside a block body is part of the body, not
              # a chunk boundary (block_body_lines already guarantees the
              # fences inside a body are balanced, so the tracker resumes in
              # the same state on the far side).
              if !in_body && tracker.fence_line?(line)
                io << process_shortcodes_in_text(buffer.to_s, templates, context, shortcode_results, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, warnings: warnings)
                buffer = String::Builder.new
                io << line
                next
              end

              buffer << line
            end

            io << process_shortcodes_in_text(buffer.to_s, templates, context, shortcode_results, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, warnings: warnings)
          end
        end

        # Line map for the fence loop above: `true` for every line inside a
        # MATCHED `{% name %}` … `{% end %}` body — the opener's own line is
        # false and the closer's line is true, the same window the running
        # depth counter used to cover. Empty when the content carries no
        # block tags at all (the common case; the whole scan is skipped).
        #
        # Pairing is a stack, exactly like the block parser: openers push,
        # closers pop, and any opener still on the stack at EOF is UNMATCHED.
        # `process_block_shortcodes` emits an unmatched opener as literal
        # text, so it must not open a body here either — otherwise one
        # forgotten `{% end %}` turns off fenced-code protection for the rest
        # of the page.
        #
        # Lines the shared FenceTracker calls fenced-code content are never
        # scanned: a `{% end %}` shown inside a ``` example is documentation,
        # not a closer. (The old loop honored that only at depth 0, which is
        # exactly how a fenced example came to close a real opener.)
        private def block_body_lines(content : String) : Array(Bool)
          return [] of Bool unless content.includes?("{%")

          tracker = Content::Processors::FenceTracker.new
          open_lines = [] of Int32
          pairs = [] of Tuple(Int32, Int32)
          line_count = 0

          content.each_line(chomp: false) do |line|
            line_no = line_count
            line_count += 1
            next if tracker.fence_line?(line)

            # Inline code spans are masked first: a literal `{% alert %}` in
            # backticks must not count as an opener.
            scan_line = line.includes?('`') ? mask_inline_code(line)[0] : line

            # Crinja control tags (`{% set %}`, `{% if %}`/`{% endif %}`, …)
            # are ignored — pairing them would desync the map (an unbalanced
            # `{% set %}` would swallow a later `{% end %}`). Classification
            # is EXACT-keyword (control_tag_open? / shortcode_closer?), the
            # same rules as the block parser below — the prefix regex once
            # used here treated `-`/`(` as word boundaries, so a shortcode
            # named `include-code` counted as a control tag and its fenced
            # body split at the fence line.
            scan_line.scan(BLOCK_OPEN_RE) do |m|
              next if control_tag_open?(m) || BLOCK_ANY_CLOSE_RE.matches?(m[0])
              open_lines << line_no
            end
            scan_line.scan(BLOCK_ANY_CLOSE_RE) do |m|
              next unless shortcode_closer?(m[0])
              # A closer with nothing open is stray — the block parser emits
              # it as literal text too.
              if opened = open_lines.pop?
                pairs << {opened, line_no} if line_no > opened
              end
            end
          end

          return [] of Bool if pairs.empty?

          # Difference array, one slot past the last line so a closer on the
          # final line still has somewhere to decrement. Prefix-summing it
          # marks every covered line in one pass, nesting included.
          deltas = Array(Int32).new(line_count + 1, 0)
          pairs.each do |(opened, closed)|
            deltas[opened + 1] += 1
            deltas[closed + 1] -= 1
          end

          depth = 0
          body_map = Array(Bool).new(line_count, false)
          line_count.times do |i|
            depth += deltas[i]
            body_map[i] = depth > 0
          end
          body_map
        end

        private def process_shortcodes_in_text(content : String, templates : Hash(String, String), context : Hash(String, Crinja::Value), shortcode_results : Hash(String, String)? = nil, crinja_env_override : Crinja? = nil, template_cache_override : Hash(UInt64, Crinja::Template)? = nil, depth : Int32 = 0, warnings : Array(String)? = nil) : String
          # Inline code spans (`…`, ``…``) are opaque to the shortcode
          # processor — running shortcodes inside `<code>` would both
          # change the visible source the author meant to display and
          # leak placeholder comments into the rendered HTML / search
          # index after Markdown HTML-escapes them inside `<code>`.
          # Mirror the protection that fenced code blocks already get
          # in `process_shortcodes_jinja`.
          #
          # The spans are MASKED (swapped for opaque tokens), not split out
          # into separate chunks: splitting broke any block shortcode whose
          # body contained a code span, because `{% name %}` and `{% end %}`
          # landed in different chunks and both leaked as literal text.
          # Tokens are restored on the shortcode body/args right before
          # rendering and on the final text before returning.
          masked, spans = mask_inline_code(content)
          # `{% raw %}` regions get the same treatment, for the same reason:
          # they are the construct an author uses to SHOW shortcode syntax
          # outside a code fence (see `mask_raw_blocks`).
          masked = mask_raw_blocks(masked, spans)
          processed = process_shortcodes_in_chunk(masked, templates, context, shortcode_results, crinja_env_override, template_cache_override, depth, spans, warnings)
          unmask_inline_code(processed, spans)
        end

        # Token format for masked inline code spans. NUL bytes cannot appear
        # in markdown source, so the token can never collide with real text.
        INLINE_CODE_MASK_RE = /\x00HWARO-INLINE-CODE-(\d+)\x00/

        private def mask_inline_code(content : String) : {String, Array(String)}
          spans = [] of String
          return {content, spans} unless content.includes?('`')
          masked = content.gsub(INLINE_CODE_RE) do |span|
            spans << span
            "\x00HWARO-INLINE-CODE-#{spans.size - 1}\x00"
          end
          {masked, spans}
        end

        private def unmask_inline_code(text : String, spans : Array(String)) : String
          return text if spans.empty?
          return text unless text.includes?('\u{0}')
          # to_i? (not to_i): a counterfeit token whose digit run overflows
          # Int32 would otherwise raise ArgumentError and abort the render.
          text.gsub(INLINE_CODE_MASK_RE) { |tok| $1.to_i?.try { |i| spans[i]? } || tok }
        end

        # A `{% raw %}` … `{% endraw %}` region. Accepts the whitespace-control
        # forms (`{%- raw -%}`) and the spaced closer (`{% end raw %}`) Crinja
        # itself accepts, and spans lines.
        #
        # Single source of truth for both shortcode entry points: the template
        # path hides these regions in `mask_template_literals`
        # (phases/render.cr) before Crinja parses a template, and the content
        # path hides them in `mask_raw_blocks` below. The same example written
        # in a template and in a markdown body has to survive identically, so
        # the two must never disagree about where a raw block starts and ends.
        RAW_BLOCK_RE = /\{\%-?\s*raw\s*-?\%\}.*?\{\%-?\s*end\s*raw\s*-?\%\}/m

        # Hide `{% raw %}` regions from the shortcode passes.
        #
        # A raw block is how an author shows shortcode syntax outside a code
        # fence, and the shortcode passes had no notion of it: only the TAGS
        # were classified as Crinja control keywords, nothing suppressed the
        # region BETWEEN them. `{% raw %}{{ youtube("x") }}{% endraw %}` in a
        # markdown body shipped a rendered iframe instead of the example, and a
        # raw block naming a shortcode hwaro doesn't know shipped
        # `<!-- hwaro: missing shortcode 'x' -->` plus a bogus build warning —
        # the documented construct destroying the very text it exists to
        # protect. Markdown content is never rendered through Crinja, so the
        # tags themselves stay literal text exactly as they do today (that is
        # already what a non-call-shaped `{% raw %}Use {{ page.title }}{% endraw %}`
        # produces); what changes is only that the region between them is no
        # longer expanded.
        #
        # Regions ride the SAME span array as inline code so that every restore
        # point already in place covers them: this method's caller unmasks the
        # final text, and `process_block_shortcodes` unmasks a block's body and
        # args before rendering it. Without that second one, a raw block inside
        # a block-shortcode body would leak its mask token into the rendered
        # HTML — which is stashed in `shortcode_results` and never flows back
        # through the caller's unmask.
        #
        # Scanned AFTER inline-code masking, so a backticked `{% raw %}` in
        # prose cannot open a region, and each region is stored with its inner
        # code spans already restored so no token ever nests inside another
        # (unmasking is a single gsub pass).
        #
        # Known limit: a raw region straddling a fenced code block is split
        # across chunks by the fence loop in `process_shortcodes_jinja` and
        # stays unmasked — the fenced half is protected by the fence itself,
        # and the rest behaves exactly as it did before.
        private def mask_raw_blocks(content : String, spans : Array(String)) : String
          # Substring probe first: raw blocks are rare and this runs on every
          # chunk of every page.
          return content unless content.includes?("raw")
          content.gsub(RAW_BLOCK_RE) do |region|
            # Same token shape `mask_inline_code` emits, so INLINE_CODE_MASK_RE
            # restores both kinds through `unmask_inline_code`.
            spans << unmask_inline_code(region, spans)
            "\x00HWARO-INLINE-CODE-#{spans.size - 1}\x00"
          end
        end

        # Every `{% end<name> %}` / `{% end <name> %}` closer. Whether a given
        # match is a Jinja control tag (`{% endif %}`) or a shortcode's named
        # closer (`{% endcallout %}`) is decided in code, against
        # CRINJA_CONTROL_KEYWORDS — a regex lookahead cannot do it:
        #
        #   * `(?!if|for|set|call|block|raw|filter|comment|…)` has no word
        #     boundary, so it also rejected every shortcode whose name merely
        #     *starts* with a keyword — `callout`, `iframe`, `setup`, `format`,
        #     `blockquote`, `rawdata`, `withdraw`, … Those closers were never
        #     normalized, the block parser never found a `{% end %}`, and the
        #     raw `{% callout(...) %}…{% endcallout %}` source leaked verbatim
        #     into the published page.
        #   * adding `\b` fixes those but breaks hyphenated names instead
        #     (`{% endinclude-code %}`), since `-` is a word boundary.
        #
        # Shared with `shortcode_scan_needed?` (via `named_closer?`) so the
        # skip decision and the rewrite can never drift apart.
        NAMED_CLOSER_RE = /\{\%\s*end\s*([a-zA-Z_][\w\-]*)\s*\%\}/i

        # Rewrite shortcode named closers to the canonical `{% end %}`, leaving
        # real Jinja/Crinja control closers (`{% endif %}`, `{% endfor %}`, …)
        # untouched.
        private def normalize_named_closers(content : String) : String
          content.gsub(NAMED_CLOSER_RE) do |match|
            CRINJA_CONTROL_KEYWORDS.includes?($1.downcase) ? match : "{% end %}"
          end
        end

        # True when a BLOCK_ANY_CLOSE_RE match closes a shortcode block rather
        # than a Jinja control structure (`{% endif %}`, `{% endfor %}`, …).
        # Bare `{% end %}` is always a shortcode closer; named closers are
        # classified against CRINJA_CONTROL_KEYWORDS exactly, mirroring
        # normalize_named_closers.
        private def shortcode_closer?(tag : String) : Bool
          if m = NAMED_CLOSER_RE.match(tag)
            !CRINJA_CONTROL_KEYWORDS.includes?(m[1].downcase)
          else
            true
          end
        end

        # True when `text` carries at least one shortcode named closer (i.e.
        # one that `normalize_named_closers` would actually rewrite).
        private def named_closer?(text : String) : Bool
          pos = 0
          while m = NAMED_CLOSER_RE.match_at_byte_index(text, pos)
            return true unless CRINJA_CONTROL_KEYWORDS.includes?(m[1].downcase)
            pos = m.byte_begin + m[0].bytesize
          end
          false
        end

        # Matches both shortcode invocation forms handled by
        # process_shortcodes_in_chunk: `{{ shortcode("name", …) }}` and the
        # direct `{{ name(…) }}` call (`shortcode` is itself a name followed
        # by `(`). Used only for the conservative skip pre-check below.
        SHORTCODE_CALL_SCAN_RE = /\{\{\s*[a-zA-Z_][\w\-]*\s*\(/

        # True when `process_shortcodes_in_text(text)` could be anything other
        # than the identity transform. Over-approximates on purpose: a false
        # positive only costs the normal (current) processing pass, while a
        # false negative would skip a real rewrite — so every rewrite the
        # processor can perform must be covered by one of these checks:
        # named-closer normalization, an explicit/direct `{{ name(...) }}`
        # call, or a non-control `{% name %}` block opener.
        def shortcode_scan_needed?(text : String) : Bool
          return false unless text.includes?("{{") || text.includes?("{%")
          return true if named_closer?(text)
          return true if SHORTCODE_CALL_SCAN_RE.matches?(text)

          pos = 0
          while m = BLOCK_OPEN_RE.match_at_byte_index(text, pos)
            return true unless control_tag_open?(m)
            pos = m.byte_begin + m[0].bytesize
          end
          false
        end

        private def process_shortcodes_in_chunk(content : String, templates : Hash(String, String), context : Hash(String, Crinja::Value), shortcode_results : Hash(String, String)?, crinja_env_override : Crinja?, template_cache_override : Hash(UInt64, Crinja::Template)?, depth : Int32, spans : Array(String) = [] of String, warnings : Array(String)? = nil) : String
          # Localized normalization for named closers (only affects shortcode block content).
          # Avoid touching real Jinja/Crinja control tags (endif, endfor, etc.).
          normalized = normalize_named_closers(content)

          # 1. Block shortcodes
          processed = process_block_shortcodes(normalized, templates, context, shortcode_results, crinja_env_override, template_cache_override, depth, spans, warnings)

          # 2. Explicit call: {{ shortcode("name", args) }} — the name accepts
          # either quote style, matching the argument syntax docs; the
          # single-quoted form previously fell through to the direct-call pass
          # as a shortcode literally named "shortcode" and was warned+dropped.
          processed = processed.gsub(/\{\{\s*shortcode\s*\(\s*(?:"([^"]+)"|'([^']+)')(?:\s*,\s*(.*?))?\s*\)\s*\}\}/) do |match|
            name = $1? || $2? || ""
            args = $3?.try { |a| unmask_inline_code(a, spans) }
            render_shortcode_result(name, args, templates, context, shortcode_results, match, warn_missing: true, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, warnings: warnings)
          end

          # 3. Direct call: {{ name(args) }}
          # Direct calls are also valid Crinja/Jinja function-call syntax
          # ({{ env("FOO") }}, {{ asset(name="x") }}, …), so we warn only when
          # the name resolves to neither a shortcode template nor a registered
          # Crinja function — that way real typos surface while legitimate
          # template-function calls in content pass through silently.
          processed.gsub(/\{\{\s*([a-zA-Z_][\w\-]*)\s*\((.*?)\)\s*\}\}/) do |match|
            render_shortcode_result($1, unmask_inline_code($2, spans), templates, context, shortcode_results, match, warn_missing: true, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, warnings: warnings)
          end
        end

        # Jinja/Crinja control keywords, for exact-name matching everywhere a
        # tag must be classified (block parser AND the outer fence-loop depth
        # scan). Deliberately not a prefix regex with `\b`: a word boundary at
        # a hyphen means a user shortcode named `include-code` (or
        # `if-banner`, `do-not-translate`, …) would be misclassified as a
        # control tag and silently stop expanding.
        CRINJA_CONTROL_KEYWORDS = Set{
          "if", "elif", "else", "endif", "for", "endfor", "set", "endset",
          "with", "endwith", "raw", "endraw", "filter", "endfilter",
          "block", "endblock", "macro", "endmacro", "call", "endcall",
          "autoescape", "endautoescape", "trans", "endtrans", "pluralize",
          "comment", "endcomment", "include", "import", "from", "extends", "do",
        }

        # True when a BLOCK_OPEN_RE match is really a Jinja control tag, not a
        # shortcode opener. Parenthesized args are decisive: no Jinja control
        # form matching BLOCK_OPEN_RE carries `name(...)` (Jinja's own
        # `{% include "x.html" %}` / `{% call(u) m(l) %}` don't match the
        # regex at all), so `{% include(name="promo") %}` is a user shortcode
        # named `include` and must keep expanding.
        private def control_tag_open?(m : Regex::MatchData) : Bool
          return false if m[2]? # `name(...)` form — unambiguously a shortcode call
          CRINJA_CONTROL_KEYWORDS.includes?(m[1].downcase)
        end

        # Next BLOCK_OPEN_RE match at or after byte offset `from` that is a
        # real shortcode opener, skipping Crinja/Jinja control tags. Bare
        # keyword tags (`{% endif %}`, `{% else %}`, `{% raw %}`) and
        # assignment tags (`{% set x = 1 %}`) match BLOCK_OPEN_RE too;
        # counting them as block openers desynced the nesting scan — a block
        # shortcode whose body contained `{% if %}…{% endif %}` never found
        # its `{% end %}` and leaked its opening tag as literal text.
        private def next_block_open(content : String, from : Int32) : Regex::MatchData?
          pos = from
          while m = BLOCK_OPEN_RE.match_at_byte_index(content, pos)
            return m unless control_tag_open?(m)
            pos = m.byte_begin + m[0].bytesize
          end
          nil
        end

        # Stack-based block shortcode parser that correctly handles nested
        # block shortcodes of the same type. Scans for opening tags {% name(...) %}
        # and closing tags {% end %}, tracking nesting depth to pair them correctly.
        #
        # The scan works in BYTE offsets (match_at_byte_index / byte_begin /
        # byte_slice): char-position `Regex#match(str, pos)` converts the char
        # index to a byte index — O(pos) on non-ASCII strings — and
        # `MatchData#begin` converts back, so every tag scanned on a CJK page
        # cost O(document). All offsets come from regex matches, so slices
        # always land on character boundaries.
        private def process_block_shortcodes(content : String, templates : Hash(String, String), context : Hash(String, Crinja::Value), shortcode_results : Hash(String, String)?, crinja_env_override : Crinja?, template_cache_override : Hash(UInt64, Crinja::Template)?, depth : Int32, spans : Array(String) = [] of String, warnings : Array(String)? = nil) : String
          # An author's markdown can already contain the placeholder comment
          # we emit for rendered shortcodes — an imported WordPress/Jekyll
          # post, or a page documenting hwaro itself. It is byte-identical to
          # a token we emitted (unlike the inline-code mask, which uses NUL
          # delimiters source can never carry), so the post-Markdown restore
          # pass would swap it for an UNRELATED shortcode's rendered HTML.
          # Drop it here, the one pass every chunk of prose goes through.
          # Fenced blocks never reach this method (the fence loop passes them
          # through) and inline code spans arrive masked, so a placeholder
          # the author is deliberately DISPLAYING still renders literally;
          # what's dropped is only an invisible HTML comment.
          if content.includes?(SHORTCODE_PLACEHOLDER_PREFIX)
            stripped = content.gsub(SHORTCODE_PLACEHOLDER_RE, "")
            # Dropping it is the cheap correct fix for the injection, but it is
            # still a silent mutation of the author's text — the exact class of
            # bug this pass exists to stop. Say so, so nobody spends an
            # afternoon wondering where their comment went.
            if stripped != content
              Logger.warn "Removed a literal #{SHORTCODE_PLACEHOLDER_PREFIX}N#{SHORTCODE_PLACEHOLDER_SUFFIX} comment from content: it is reserved for hwaro's shortcode pass and would otherwise be replaced by an unrelated shortcode's output."
            end
            content = stripped
          end

          close_re = BLOCK_CLOSE_RE

          result = String::Builder.new
          pos = 0
          content_bytesize = content.bytesize

          # Memoized scans: a match found ahead of the cursor stays the next
          # match until the cursor passes it, so re-running the regex from
          # every new position is pure waste — consuming each stray
          # `{% end %}` used to rescan every control tag ahead of it,
          # quadratic on keyword-dense pages (Jinja documentation).
          cached_open : Regex::MatchData? = nil
          cached_close : Regex::MatchData? = nil

          while pos < content_bytesize
            # Find next opening tag (control tags skipped)
            open_match = if (c = cached_open) && c.byte_begin >= pos
                           c
                         else
                           cached_open = next_block_open(content, pos)
                         end
            # Find next closing tag (to handle stray {% end %} gracefully)
            close_match = if (c = cached_close) && c.byte_begin >= pos
                            c
                          else
                            cached_close = close_re.match_at_byte_index(content, pos)
                          end

            # No more opening tags — append rest and done
            unless open_match
              result << content.byte_slice(pos)
              break
            end

            open_start = open_match.byte_begin

            # If a close tag appears before the next open tag, it's unmatched — emit as-is
            if close_match
              close_start = close_match.byte_begin
              if close_start < open_start
                close_end = close_start + close_match[0].bytesize
                result << content.byte_slice(pos, close_end - pos)
                pos = close_end
                next
              end
            end

            # Emit text before the opening tag
            result << content.byte_slice(pos, open_start - pos)

            name = open_match[1]
            args_str = open_match[2]? || open_match[3]?
            body_start = open_start + open_match[0].bytesize

            # `{% end %}` is the closing-tag literal; BLOCK_OPEN_RE happens to
            # match it too (since `end` is a valid identifier), but treating
            # it as an opening tag would silently consume a stray close. Emit
            # it as-is so unmatched `{% end %}` reads as plain text.
            if name == "end"
              result << open_match[0]
              pos = body_start
              next
            end

            # Find the matching {% end %} by tracking nesting depth. Same
            # memoization as the outer loop: matches ahead of scan_pos stay
            # valid until the scan passes them.
            nesting = 1
            scan_pos = body_start
            body_end = nil
            nest_open : Regex::MatchData? = nil
            nest_close : Regex::MatchData? = nil

            while nesting > 0 && scan_pos < content_bytesize
              next_open = if (c = nest_open) && c.byte_begin >= scan_pos
                            c
                          else
                            nest_open = next_block_open(content, scan_pos)
                          end
              next_close = if (c = nest_close) && c.byte_begin >= scan_pos
                             c
                           else
                             nest_close = close_re.match_at_byte_index(content, scan_pos)
                           end

              break unless next_close
              next_close_start = next_close.byte_begin

              if next_open
                next_open_start = next_open.byte_begin
                if next_open_start < next_close_start
                  nesting += 1
                  scan_pos = next_open_start + next_open[0].bytesize
                  next
                end
              end

              nesting -= 1
              if nesting == 0
                body_end = next_close_start
                pos = next_close_start + next_close[0].bytesize
              else
                scan_pos = next_close_start + next_close[0].bytesize
              end
            end

            unless body_end
              # No matching {% end %} found — emit the opening tag as literal text
              result << open_match[0]
              pos = body_start
              next
            end

            body = content.byte_slice(body_start, body_end - body_start).strip

            # Recursively process nested shortcodes in body (with depth limit).
            # The body is already masked by the caller, so recurse through the
            # chunk processor directly — re-masking via _in_text would assign
            # fresh span indexes that collide with the outer `spans` tokens.
            if depth < MAX_SHORTCODE_NESTING && (body.includes?("{{") || body.includes?("{%"))
              body = process_shortcodes_in_chunk(body, templates, context, shortcode_results, crinja_env_override, template_cache_override, depth + 1, spans, warnings)
            end

            # Restore inline code spans before rendering: the rendered HTML is
            # stashed in shortcode_results and never flows back through the
            # caller's final unmask, so masked tokens would otherwise leak
            # into the output verbatim.
            body = unmask_inline_code(body, spans)
            unmasked_args = args_str.try { |a| unmask_inline_code(a, spans) }

            extra_args = {"body" => body}
            original_text = content.byte_slice(open_start, pos - open_start)
            result << render_shortcode_result(name, unmasked_args, templates, context, shortcode_results, original_text, warn_missing: true, extra_args: extra_args, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, warnings: warnings)
          end

          result.to_s
        end

        # Shared helper: look up a shortcode template, render it, and either
        # return the HTML directly or store it behind a placeholder so that
        # Markdown processing doesn't mangle it.
        private def render_shortcode_result(
          name : String,
          args_str : String?,
          templates : Hash(String, String),
          context : Hash(String, Crinja::Value),
          shortcode_results : Hash(String, String)?,
          fallback : String,
          warn_missing : Bool = true,
          extra_args : Hash(String, String)? = nil,
          crinja_env_override : Crinja? = nil,
          template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
          warnings : Array(String)? = nil,
        ) : String
          template_key = "shortcodes/#{name}"
          template = templates[template_key]? || BuiltinShortcodes.templates[template_key]?

          unless template
            # Direct-call syntax (`{{ name(args) }}`) doubles as Crinja's
            # function-call syntax — `env`, `asset`, `url_for`, …, are
            # legitimate references that the page-template engine will
            # resolve later. Pass those through untouched.
            return fallback if crinja_function?(name, crinja_env_override)

            warn_missing_shortcode(template_key) if warn_missing

            # Drop the call instead of leaking `{{ name(args) }}` into the
            # rendered HTML and search index. Use the placeholder pipeline
            # so block-level missing calls don't get wrapped in a stray
            # `<p>`, mirroring how rendered shortcodes are handled.
            placeholder_html = "<!-- hwaro: missing shortcode '#{name}' -->"
            if results = shortcode_results
              placeholder = "#{SHORTCODE_PLACEHOLDER_PREFIX}#{results.size}#{SHORTCODE_PLACEHOLDER_SUFFIX}"
              results[placeholder] = placeholder_html
              return placeholder
            end
            return placeholder_html
          end

          args = parse_shortcode_args_jinja(args_str)
          extra_args.try &.each { |k, v| args[k] = v }

          # Built-in shortcodes read named slots (`{{ id }}`, `{{ src }}`, ...),
          # so the documented positional form (`{{ youtube("ID") }}`) only
          # reaches them after we alias each `_N` to a named parameter from
          # `BuiltinShortcodes::POSITIONAL_PARAMS`. Positional values fill the
          # declared slots IN ORDER, skipping slots the caller already
          # provided by name — `{{ gist(user="u", "abc") }}` maps "abc" to
          # `id`, not to the named-consumed `user` slot (indexing purely by
          # positional order silently dropped such values).
          if positional = BuiltinShortcodes.positional_params(template_key)
            pos_idx = 0
            positional.each do |param_name|
              next if args.has_key?(param_name)
              break unless value = args["_#{pos_idx}"]?
              args[param_name] = value
              pos_idx += 1
            end
          end

          html = render_shortcode_jinja(template, args, context, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, shortcode_name: name, warnings: warnings)

          if results = shortcode_results
            placeholder = "#{SHORTCODE_PLACEHOLDER_PREFIX}#{results.size}#{SHORTCODE_PLACEHOLDER_SUFFIX}"
            results[placeholder] = html
            placeholder
          else
            html
          end
        end

        # A token that starts as `identifier =` is a named argument; anything
        # else (quoted strings, bare values, URLs whose query carries `=`) is
        # positional.
        NAMED_TOKEN_RE = /\A[A-Za-z_]\w*\s*=/

        # Parse shortcode arguments — supports named, positional, and MIXED
        # Named:      key="value", key='value', key=value
        # Positional: "value", 'value', value (assigned as _0, _1, ...)
        # Mixed:      "value", key="v"  — positional slots fill in order
        #
        # Single pass: tokenize once on top-level commas (quote-aware, so
        # `figure("/i.png", "a, b")` keeps the comma inside the caption),
        # then classify each token. Named tokens are scanned with
        # SHORTCODE_ARGS_REGEX so space-separated pairs in one token
        # (`key1="a" key2="b"`) keep working; everything else is positional.
        # Scanning per-token (not whole-string) also stops the named-arg
        # regex from extracting phantom keys out of a quoted positional
        # (`{{ youtube("…?v=abc", width="560") }}` used to yield v="abc").
        # Previously positionals were parsed only when NO named arg was
        # present, so the documented mixed form silently dropped them.
        private def parse_shortcode_args_jinja(args_str : String?) : Hash(String, String)
          args = {} of String => String
          return args unless args_str
          return args if args_str.strip.empty?

          idx = 0
          split_shortcode_args(args_str).each do |part|
            token = part.strip
            next if token.empty?

            if token.matches?(NAMED_TOKEN_RE)
              token.scan(SHORTCODE_ARGS_REGEX) do |match|
                key = match[1]
                # Only the quoted alternatives carry escapes; an unquoted value
                # (match[4]) is taken verbatim so a Windows path stays intact.
                args[key] = if quoted = match[2]? || match[3]?
                              unescape_shortcode_arg(quoted)
                            else
                              match[4]? || ""
                            end
              end
            else
              value = unquote_shortcode_arg(token)
              next if value.empty?
              args["_#{idx}"] = value
              idx += 1
            end
          end

          args
        end

        # Split an argument string on top-level commas; commas inside single-
        # or double-quoted values belong to the value. A backslash inside a
        # quoted run escapes the next character, so `label="a\"b,c"` stays one
        # token instead of splitting at the comma and dropping the args after it.
        private def split_shortcode_args(args_str : String) : Array(String)
          parts = [] of String
          current = String::Builder.new
          quote : Char? = nil
          escaped = false
          args_str.each_char do |ch|
            if q = quote
              current << ch
              if escaped
                escaped = false
              elsif ch == '\\'
                escaped = true
              elsif ch == q
                quote = nil
              end
            elsif ch == '"' || ch == '\''
              quote = ch
              current << ch
            elsif ch == ','
              parts << current.to_s
              current = String::Builder.new
            else
              current << ch
            end
          end
          parts << current.to_s
          parts
        end

        # Strip one layer of surrounding quotes from an argument value, and
        # resolve the escapes inside it (positional args go through here).
        private def unquote_shortcode_arg(value : String) : String
          if value.size >= 2 && ((value.starts_with?('"') && value.ends_with?('"')) ||
             (value.starts_with?('\'') && value.ends_with?('\'')))
            unescape_shortcode_arg(value[1..-2])
          else
            value
          end
        end

        # Resolve backslash escapes in a quoted argument value. Only `\`, `"`
        # and `'` are special; every other backslash is kept verbatim so a
        # literal `C:\new` or a LaTeX-ish `\alpha` survives unchanged.
        private def unescape_shortcode_arg(value : String) : String
          return value unless value.includes?('\\')

          String.build(value.bytesize) do |io|
            escaped = false
            value.each_char do |ch|
              if escaped
                io << '\\' unless ch == '\\' || ch == '"' || ch == '\''
                io << ch
                escaped = false
              elsif ch == '\\'
                escaped = true
              else
                io << ch
              end
            end
            io << '\\' if escaped
          end
        end

        # Render a shortcode template with Crinja
        private def render_shortcode_jinja(template : String, args : Hash(String, String), context : Hash(String, Crinja::Value), crinja_env_override : Crinja? = nil, template_cache_override : Hash(UInt64, Crinja::Template)? = nil, shortcode_name : String? = nil, warnings : Array(String)? = nil) : String
          env = crinja_env_override || crinja_env

          # Inject the shortcode args into the caller's context and restore
          # them after the render. The context hash is built fresh per page
          # and owned by a single fiber (see the `build_template_variables`
          # calls in render.cr / parse_content.cr), so in-place mutation is
          # safe here — and it avoids duplicating the ~75-entry hash on
          # every shortcode invocation, the densest allocation site in the
          # parallel render fan-out. `saved` keeps any pre-existing values
          # for colliding keys so nested/subsequent invocations see the
          # exact original context.
          saved : Hash(String, Crinja::Value)? = nil
          begin
            args.each do |key, value|
              if context.has_key?(key)
                (saved ||= {} of String => Crinja::Value)[key] = context[key]
              end
              context[key] = Crinja::Value.new(value)
            end

            # Cache compiled shortcode templates by content hash to avoid
            # re-parsing the template AST on every shortcode invocation.
            # XOR with a salt to avoid collisions with page template cache entries
            # that share the same cache map.
            #
            # A `Crinja::Template` is permanently bound to the env it was parsed
            # with (`Template#render` swaps `@context` on *that* env), so a
            # cached template MUST only ever be rendered on the env that
            # compiled it. In the parallel path each worker passes its own env
            # AND its own cache (`template_cache_override`); using that
            # worker-local cache keeps every template bound to, and rendered on,
            # the worker's own env — no cross-worker env mutation, and no mutex
            # needed since a single fiber owns the cache. Only the shared
            # fallback cache (sequential path) needs the reentrant mutex.
            cache_key = template.hash ^ 0x5C0DE_CAFE_u64
            # User shortcodes live at templates/shortcodes/<name>.html; resolving
            # that key through compile_template attaches the filename so errors
            # point at the file. Builtins aren't on disk and stay anonymous.
            template_key = shortcode_name.try { |n| "shortcodes/#{n}" }
            crinja_template = if wcache = template_cache_override
                                wcache[cache_key]? || begin
                                  compiled = compile_template(env, template, template_key)
                                  wcache[cache_key] = compiled
                                  compiled
                                end
                              else
                                @crinja_cache_mutex.synchronize do
                                  @compiled_templates_cache[cache_key]? || begin
                                    compiled = compile_template(env, template, template_key)
                                    @compiled_templates_cache[cache_key] = compiled
                                    compiled
                                  end
                                end
                              end
            crinja_template.render(context)
          rescue ex : Crinja::TemplateError
            label = shortcode_name ? "shortcode '#{shortcode_name}'" : "shortcode"
            Logger.warn "Template error in #{label}: #{ex.message}"
            # Record the failure on the page (drives the serve error overlay —
            # a mid-edit syntax error used to make the shortcode output
            # silently vanish with a "successful" rebuild) and leave a visible
            # trace in the HTML instead of an empty string.
            warnings.try(&.<< "Template error in #{label}: #{ex.message}")
            "<!-- hwaro: template error in #{label.gsub("--", "‐‐")} -->"
          ensure
            args.each_key { |key| context.delete(key) }
            saved.try &.each { |k, v| context[k] = v }
          end
        end

        # Replace shortcode placeholders with their rendered HTML content.
        #
        # Block shortcodes can nest, and the inner placeholder gets baked
        # into the outer template's `{{ body }}` before either of them
        # actually lands in the rendered HTML. A single gsub pass would
        # only resolve the outermost placeholder, leaving an
        # `<!--HWARO-SHORTCODE-PLACEHOLDER-N-->` artifact one level
        # inwards. Loop until the result stops changing (or until we hit
        # the same depth limit the recursive renderer uses) so every
        # nested level resolves.
        private def replace_shortcode_placeholders(html : String, shortcode_results : Hash(String, String)) : String
          return html if shortcode_results.empty?
          result = html
          (MAX_SHORTCODE_NESTING + 1).times do
            # Substring probe before the regex pass: the typical page pays
            # one confirming scan per nesting level otherwise, over the
            # whole rendered HTML.
            return result unless result.includes?(SHORTCODE_PLACEHOLDER_PREFIX)
            replaced = result.gsub(SHORTCODE_PLACEHOLDER_RE) do |match|
              shortcode_results[match]? || match
            end
            return replaced if replaced == result
            result = replaced
          end
          result
        end

        # True when `name` is a registered Crinja function in the env used
        # for template rendering. Direct shortcode calls ({{ name(args) }})
        # and template function calls share syntax, so this check lets the
        # shortcode processor silent-pass-through legitimate function calls
        # like `env`, `asset`, `url_for`, `get_url`, … while still warning
        # on names that aren't registered anywhere.
        private def crinja_function?(name : String, crinja_env_override : Crinja?) : Bool
          env = crinja_env_override || crinja_env
          env.functions.has_key?(name)
        rescue Exception
          false
        end

        # Emit a "shortcode template not found" warning at most once per
        # template key per build to avoid spamming the log when the same
        # typo appears on many pages.
        #
        # MT note: `Set#includes?` + `Set#<<` is a check-then-write race
        # under `-Dpreview_mt`. Two workers hitting the same missing
        # shortcode could each emit one warning before the other had a
        # chance to record it. Cheap to guard with the shared crinja mutex.
        private def warn_missing_shortcode(template_key : String) : Nil
          should_warn = @crinja_cache_mutex.synchronize do
            seen = (@shortcode_warnings_seen ||= Set(String).new)
            seen.add?(template_key)
          end
          return unless should_warn
          Logger.warn "Shortcode template '#{template_key}' not found."
        end
      end
    end
  end
end
