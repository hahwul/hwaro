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
        STRIKETHROUGH_RE          = InlineMarkdown::INLINE_STRIKETHROUGH_RE
        STRIKETHROUGH_CODE_RE     = /`[^`]+`/
        LINK_DEFINITION_PREFIX_RE = /\A(?: {0,3}>[ \t]?)* {0,3}\[[^\]]+\]:[ \t]*/
        LINK_DEST_TOKEN_RE        = /\x00LD(\d+)\x00/
        HTML_TAG_RE               = /<\/?[a-z][\w:-]*(?:[^>"']|"[^"]*"|'[^']*')*>/i
        HTML_TAG_TOKEN_RE         = /\x00HT(\d+)\x00/

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
        private def stash_markdown_link_destinations(text : String, store : Array(String)) : String
          slice = text.to_slice
          return text if slice.size < 3

          # A reference-definition destination and optional title occupy the
          # remainder of their line; neither is inline Markdown text.
          if definition = text.match(LINK_DEFINITION_PREFIX_RE)
            start = definition.end
            return text if start >= slice.size

            return String.build(text.bytesize) do |io|
              io.write(slice[0, start])
              store << text.byte_slice(start, slice.size - start)
              io << "\x00LD#{store.size - 1}\x00"
            end
          end

          String.build(text.bytesize) do |io|
            copied_until = 0
            search_from = 0

            while close_bracket = text.byte_index(']', search_from)
              if close_bracket + 1 < slice.size && slice[close_bracket + 1] === '(' &&
                 !escaped_markdown_delimiter?(slice, close_bracket) && has_matching_link_label?(slice, close_bracket)
                destination_start = close_bracket + 2
                if close_paren = find_link_destination_end(slice, destination_start)
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

        private def has_matching_link_label?(slice : Bytes, close_bracket : Int32) : Bool
          depth = 1
          pos = close_bracket - 1
          while pos >= 0
            char = slice[pos]
            if (char === '[' || char === ']') && !escaped_markdown_delimiter?(slice, pos)
              if char === ']'
                depth += 1
              else
                depth -= 1
                return true if depth.zero?
              end
            end
            pos -= 1
          end
          false
        end

        private def escaped_markdown_delimiter?(slice : Bytes, pos : Int32) : Bool
          slashes = 0
          cursor = pos - 1
          while cursor >= 0 && slice[cursor] === '\\'
            slashes += 1
            cursor -= 1
          end
          slashes.odd?
        end

        # Returns the outer `)` for one inline link, counting balanced
        # parentheses in an unquoted destination/title and ignoring escaped
        # delimiters, angle-bracket destinations, and quoted titles.
        private def find_link_destination_end(slice : Bytes, start : Int32) : Int32?
          nested = 0
          angle_destination = false
          quote = 0_u8
          pos = start

          while pos < slice.size
            char = slice[pos]
            if char === '\\'
              pos += 2
              next
            end

            if quote != 0
              quote = 0_u8 if char == quote
            elsif angle_destination
              angle_destination = false if char === '>'
            else
              case char
              when '<'
                angle_destination = true
              when '"', '\''
                quote = char
              when '('
                nested += 1
              when ')'
                return pos if nested.zero?
                nested -= 1
              end
            end

            pos += 1
          end

          nil
        end
      end
    end
  end
end
