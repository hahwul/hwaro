# Markdown extensions — GFM strikethrough.
#
# One file per `# --- X ---` pass of the pre/post-processing pipeline; the
# pass ORDER is fixed in ../markdown_extensions.cr (`preprocess` /
# `postprocess`). Parts only reopen the module: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
        # --- Strikethrough (GFM) ---
        # `~~text~~` → `<del>text</del>`. Markd doesn't ship a GFM strikethrough
        # parser, so we apply this pre-Markd. The walk is fence-aware so
        # examples inside fenced code blocks (` ``` ` / `~~~`) render verbatim,
        # and inline `` `code` `` runs on the same line are skipped via a
        # placeholder pass so e.g. `` `~~not strike~~` `` stays as code.
        #
        # When math is also enabled, `preprocess` stashes `$…$`/`$$…$$`
        # spans into opaque placeholders before this pass runs, so `$~~x~~$`
        # reaches KaTeX verbatim instead of being rewritten here.
        STRIKETHROUGH_RE      = InlineMarkdown::INLINE_STRIKETHROUGH_RE
        STRIKETHROUGH_CODE_RE = /`[^`]+`/
        LINK_DEST_TOKEN_RE    = /\x00LD(\d+)\x00/
        HTML_TAG_TOKEN_RE     = /\x00HT(\d+)\x00/

        # A whole-line reference definition: `[label]:`, a destination
        # (`<…>` or a non-space run), an optional title after whitespace, and
        # nothing else. Group 1 ends where the destination starts. A line
        # with trailing text is a paragraph to Markd, not a definition.
        LINK_DEFINITION_RE = /\A((?: {0,3}>[ \t]?)*+ {0,3}\[[^\]]++\]:[ \t]*+)(?:<[^<>\n\\]*+(?:\\.[^<>\n\\]*+)*+>|[^<\s]\S*+)(?:[ \t]++(?:"[^"\\]*+(?:\\.[^"\\]*+)*+"|'[^'\\]*+(?:\\.[^'\\]*+)*+'|\([^()\\]*+(?:\\.[^()\\]*+)*+\)))?[ \t]*\r?\n?\z/

        # Raw inline HTML tags as Markd recognizes them (Markd::Rule::OPEN_TAG
        # and CLOSE_TAG: tag name, attributes with optional unquoted/quoted
        # values, `/>` or `>`), so text that merely starts with `<` —
        # `<b ~~x~~ y>` — stays Markdown. Possessive quantifiers give the
        # same matches without backtracking frames, so a tag with thousands
        # of attributes cannot exhaust the PCRE JIT stack.
        HTML_TAG_RE = /<[A-Za-z][A-Za-z0-9-]*+(?:\s++[a-zA-Z_:][a-zA-Z0-9:._-]*+(?:\s*+=\s*+(?:[^"'=<>`\x00-\x20]++|'[^']*+'|"[^"]*+"))?+)*+\s*+\/?>|<\/[A-Za-z][A-Za-z0-9-]*+\s*+>/

        def preprocess_strikethrough(content : String) : String
          return content unless content.includes?("~~")

          process_lines_fence_aware(content) do |line, _in_fence|
            if line.includes?("~~")
              rewrite_strikethrough_line(line)
            else
              line
            end
          end
        end

        private def rewrite_strikethrough_line(line : String) : String
          # Stash inline code spans so a `~~` inside backticks is not rewritten.
          transform_outside_code_spans(line) do |stashed|
            stashed.gsub(STRIKETHROUGH_RE) { "<del>#{$1}</del>" }
          end
        end

        # Stash inline code spans — backtick spans AND `<code>` HTML spans —
        # transform the rest through the block, then restore the spans: so
        # literals like `` `~~x~~` ``, `` `[^1]` ``, and `` `$x$` `` survive
        # the HTML-injecting passes, including after a table cell or
        # definition body has already been rendered to `<code>…</code>`.
        # Multi-line chunks pass SINGLE_LINE_CODE_SPAN_RE so a stray lone
        # backtick in one paragraph can't absorb text from another.
        private def transform_outside_code_spans(text : String, code_span_re : Regex = STRIKETHROUGH_CODE_RE, & : String -> String) : String
          has_backticks = text.includes?('`')
          has_html_code = text.includes?("<code")
          has_link_destinations = text.includes?("](") || text.includes?("]:")
          has_html_tags = text.includes?('<') && text.matches?(HTML_TAG_RE)
          return yield text unless has_backticks || has_html_code || has_link_destinations || has_html_tags

          code_spans = [] of String
          stashed = text
          if has_backticks
            stashed = stashed.gsub(code_span_re) do |match|
              code_spans << match
              "\x00CS#{code_spans.size - 1}\x00"
            end
          end
          if has_html_code
            stashed = stashed.gsub(HTML_CODE_SPAN_RE) do |match|
              code_spans << match
              "\x00CS#{code_spans.size - 1}\x00"
            end
          end

          link_destinations = [] of String
          stashed = stash_markdown_link_destinations(stashed, link_destinations) if has_link_destinations

          html_tags = [] of String
          stashed = stashed.gsub(HTML_TAG_RE) do |tag|
            html_tags << tag
            "\x00HT#{html_tags.size - 1}\x00"
          end if has_html_tags

          rewritten = yield stashed

          unless link_destinations.empty?
            rewritten = rewritten.gsub(LINK_DEST_TOKEN_RE) do |match|
              link_destinations[$1.to_i]?.try(&.itself) || match
            end
          end
          unless html_tags.empty?
            rewritten = rewritten.gsub(HTML_TAG_TOKEN_RE) do |match|
              html_tags[$1.to_i]?.try(&.itself) || match
            end
          end

          # Single-pass restore per nesting level (the per-index `sub` loop
          # rescanned the line once per span). An HTML code span stashed
          # second can contain a backtick-span placeholder stashed first
          # (`<code>` + "`x`" on one line); gsub does not rescan injected
          # content, so a second pass picks those up. The pass count is a
          # HARD cap of 2, matching the two stash passes above — a span
          # whose own content forges a valid token (raw NULs in the source
          # file) would otherwise re-expand itself every pass and hang the
          # build. An out-of-range counterfeit restores nothing and exits
          # via the no-change check.
          2.times do
            break unless rewritten.includes?("\x00CS")
            replaced = rewritten.gsub(CODE_SPAN_TOKEN_RE) do |match|
              idx = $1.to_i?
              idx && idx < code_spans.size ? code_spans[idx] : match
            end
            break if replaced == rewritten
            rewritten = replaced
          end
          rewritten
        end

        # Inline extensions act on Markdown text, but a delimiter inside
        # `](destination "title")` is URL/title data. Stash that part while
        # the caller rewrites emphasis-like syntax, then restore it before
        # Markd parses the link. Code spans have already been stashed by the
        # caller, so their brackets cannot be mistaken for a real link.
        #
        # Linear in the line length: bracket and parenthesis matches come
        # from one forward pass each, the destination scan jumps straight to
        # the precomputed `)` or whitespace, and each title is scanned once.
        private def stash_markdown_link_destinations(text : String, store : Array(String)) : String
          slice = text.to_slice
          return text if slice.size < 3

          # A reference-definition destination and optional title occupy the
          # remainder of their line; neither is inline Markdown text.
          if text.includes?("]:") && (definition = text.match(LINK_DEFINITION_RE))
            start = definition.byte_end(1)

            return String.build(text.bytesize) do |io|
              io.write(slice[0, start])
              store << text.byte_slice(start, slice.size - start)
              io << "\x00LD#{store.size - 1}\x00"
            end
          end

          label_close, paren_match, next_space, next_paren_stop = link_syntax_tables(slice)
          title_ends = {} of Int32 => Int32
          String.build(text.bytesize) do |io|
            copied_until = 0
            search_from = 0

            while close_bracket = text.byte_index(']', search_from)
              if close_bracket + 1 < slice.size && slice[close_bracket + 1] === '(' && label_close[close_bracket]
                destination_start = close_bracket + 2
                if close_paren = inline_link_end(slice, destination_start, paren_match, next_space, next_paren_stop, title_ends)
                  io.write(slice[copied_until, destination_start - copied_until])
                  store << text.byte_slice(destination_start, close_paren - destination_start)
                  io << "\x00LD#{store.size - 1}\x00"
                  copied_until = close_paren
                  search_from = close_paren + 1
                else
                  search_from = close_bracket + 1
                end
              else
                search_from = close_bracket + 1
              end
            end

            io.write(slice[copied_until, slice.size - copied_until])
          end
        end

        # One forward pass over the line: which `]` closes an earlier
        # unescaped `[`, the `)` balancing each unescaped `(`, and (filled
        # backward) the next ASCII whitespace and the next unescaped `)` or
        # NUL at or after every offset. A backslash escapes the next ASCII
        # punctuation character, as in CommonMark, so an escaped bracket or
        # paren never pairs.
        private def link_syntax_tables(slice : Bytes) : {Array(Bool), Array(Int32), Array(Int32), Array(Int32)}
          size = slice.size
          label_close = Array(Bool).new(size, false)
          paren_match = Array(Int32).new(size, -1)
          next_space = Array(Int32).new(size + 1, size)
          next_paren_stop = Array(Int32).new(size + 1, size)

          brackets = [] of Int32
          parens = [] of Int32
          pos = 0
          while pos < size
            char = slice[pos]
            if char === '\\'
              pos += pos + 1 < size && link_punctuation?(slice[pos + 1]) ? 2 : 1
              next
            end
            case char
            when '['
              brackets << pos
            when ']'
              label_close[pos] = true if brackets.pop?
            when '('
              parens << pos
            when ')'
              next_paren_stop[pos] = pos
              if open = parens.pop?
                paren_match[open] = pos
              end
            when 0
              next_paren_stop[pos] = pos
            end
            pos += 1
          end

          (size - 1).downto(0) do |i|
            next_space[i] = link_space?(slice[i]) ? i : next_space[i + 1]
            next_paren_stop[i] = next_paren_stop[i + 1] unless next_paren_stop[i] == i
          end

          {label_close, paren_match, next_space, next_paren_stop}
        end

        # Mirrors Markd's inline-link parse after `](` (`start` is the offset
        # after the `(`): spaces, a destination (`<…>`, or everything up to
        # whitespace or the `)` balancing the opening paren), spaces, an
        # optional title that must follow whitespace, spaces, and the closing
        # `)`. Returns that `)`'s offset, or nil when the text is not an
        # inline link. The destination and `(…)` title scans jump through the
        # precomputed tables, and a quoted title is scanned once per opening
        # quote (`title_ends`) — a quoted scan stops at the next same quote,
        # so those scans never overlap — keeping a line full of `[x](` linear.
        private def inline_link_end(slice : Bytes, start : Int32, paren_match : Array(Int32), next_space : Array(Int32), next_paren_stop : Array(Int32), title_ends : Hash(Int32, Int32)) : Int32?
          size = slice.size
          pos = skip_link_spaces(slice, start)
          return if pos >= size

          if slice[pos] === '<'
            pos += 1
            while pos < size
              char = slice[pos]
              if char === '\\'
                return unless pos + 1 < size && link_punctuation?(slice[pos + 1])
                pos += 2
                next
              end
              break if char === '>' || char === '<' || char === '\t' || char === '\n' || char == 0
              pos += 1
            end
            return unless pos < size && slice[pos] === '>'
            pos += 1
          else
            close = paren_match[start - 1]
            space = next_space[pos]
            pos = close >= 0 && close < space ? close : space
          end

          pos = skip_link_spaces(slice, pos)
          if pos < size && link_space?(slice[pos - 1]) && (slice[pos] === '"' || slice[pos] === '\'' || slice[pos] === '(')
            title_close = if slice[pos] === '('
                            stop = next_paren_stop[pos + 1]
                            stop < size && slice[stop] === ')' ? stop : -1
                          else
                            title_ends[pos] ||= link_title_end(slice, pos)
                          end
            pos = skip_link_spaces(slice, title_close + 1) if title_close >= 0
          end

          pos < size && slice[pos] === ')' ? pos : nil
        end

        # Offset of the quote closing the link title opened by the `"` or `'`
        # at `open`, or -1 when it never closes.
        private def link_title_end(slice : Bytes, open : Int32) : Int32
          closer = slice[open]
          pos = open + 1
          while pos < slice.size
            char = slice[pos]
            if char === '\\' && pos + 1 < slice.size && link_punctuation?(slice[pos + 1])
              pos += 2
              next
            end
            return -1 if char == 0
            return pos if char == closer
            pos += 1
          end
          -1
        end

        private def skip_link_spaces(slice : Bytes, pos : Int32) : Int32
          while pos < slice.size && slice[pos] === ' '
            pos += 1
          end
          pos
        end

        private def link_space?(byte : UInt8) : Bool
          byte === ' ' || byte === '\t' || byte === '\n' || byte === '\r' || byte == 0x0b || byte == 0x0c
        end

        private def link_punctuation?(byte : UInt8) : Bool
          (0x21 <= byte <= 0x2f) || (0x3a <= byte <= 0x40) || (0x5b <= byte <= 0x60) || (0x7b <= byte <= 0x7e)
        end
      end
    end
  end
end
