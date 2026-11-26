# Markdown extensions — GitHub-style admonitions.
#
# One file per `# --- X ---` pass of the pre/post-processing pipeline; the
# pass ORDER is fixed in ../markdown_extensions.cr (`preprocess` /
# `postprocess`). Parts only reopen the module: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
        # --- GitHub-style Admonitions ---
        # Recognised types match GitHub's alert syntax.
        ADMONITION_TYPES = {"NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"}

        # Captures a blockquote whose first paragraph starts with `[!TYPE]`.
        # Non-void tags that markd's inline renderer can open on a title line.
        # Balanced when every opener on the line is closed on the line: a
        # `<strong>`/`<a>`/`<code>`… opened here and closed on a later line
        # of the same paragraph means the author wrapped one inline element
        # across the soft break, not that they wrote a title.
        INLINE_TAG_RE    = /<(\/?)([a-zA-Z][\w-]*)[^>]*>/
        VOID_INLINE_TAGS = Set{"br", "img", "wbr", "hr", "input"}

        def inline_html_balanced?(fragment : String) : Bool
          return true unless fragment.includes?('<')
          open = [] of String
          fragment.scan(INLINE_TAG_RE) do |m|
            name = m[2].downcase
            next if VOID_INLINE_TAGS.includes?(name) || m[0].ends_with?("/>")
            if m[1].empty?
              open << name
            else
              return false if open.empty? || open.pop != name
            end
          end
          open.empty?
        end

        # Group 1: type token (uppercased). Group 2: whatever else sat on the
        # marker's own line — the custom title (Obsidian / Hugo syntax:
        # `> [!NOTE] Custom Title`); empty for a bare marker. Group 3: the rest
        # of the blockquote body, possibly starting with `</p>` (when the
        # marker line was a paragraph of its own) or with the inline body
        # content (when body text followed the marker via a soft break).
        #
        # Group 2 stops at the line break, so a same-line title can never be
        # confused with a soft-broken body. It used to be `\s*(.*?)`, which
        # swallowed the title into the first body paragraph — `Custom Title`
        # rendered as body text under the default "Note" heading. Obsidian's
        # optional fold marker (`[!NOTE]+` / `[!NOTE]-`, group 4) is dropped,
        # unless `foldable` (`[markdown] wikilinks`) renders it as <details>.
        #
        # The rest runs to the `</blockquote>` that closes THIS blockquote
        # (`matching_blockquote_close`): a lazy match to the first one ended
        # the admonition inside a nested quote (`> > quoted`), emitting its
        # `</div>` before the inner `</blockquote>` — mis-nested tags that
        # left a stray `</blockquote>` after the admonition.
        ADMONITION_OPEN_RE = /<blockquote>\s*<p>\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\](?<fold>[+-]?)([^\n]*?)(?:\n|(?=<\/p>))\s*/i
        BLOCKQUOTE_TAG_RE  = /<(\/?)blockquote(?=[\s>\/])[^>]*+>/i

        # Every blockquote tag on the page, paired once: `begins[i]` is the
        # i-th tag's offset, `closes[i]` the `</blockquote>` that returns a
        # quote whose content starts just before tag i to depth zero
        # (nested blockquotes counted, a render hook's
        # `<blockquote class=…>` included), and `firsts[i]` the first closer
        # at or after tag i. Unbalanced raw HTML that never returns to depth
        # zero falls back to that first closer, as the lazy match did; -1
        # when there is none. Scanning to the end of the page per admonition
        # instead was quadratic when every body held an unclosed raw
        # `<blockquote>`.
        private def pair_blockquote_tags(html : String, options : Regex::MatchOptions) : {Array(Int32), Array(Int32), Array(Int32)}
          begins = [] of Int32
          closing = [] of Bool
          pos = 0
          while m = BLOCKQUOTE_TAG_RE.match_at_byte_index(html, pos, options)
            begins << m.byte_begin(0)
            closing << !m[1].empty?
            pos = m.byte_end(0)
          end
          n = begins.size
          # level[k]: opens minus closes before tag k. A quote whose content
          # starts before tag i closes at the first k > i with
          # level[k] < level[i] (steps are ±1), i.e. at tag k - 1.
          level = Array(Int32).new(n + 1, 0)
          n.times { |k| level[k + 1] = level[k] + (closing[k] ? -1 : 1) }
          closes = Array(Int32).new(n + 1, -1)
          pending = [] of Int32
          (0..n).each do |k|
            while (top = pending.last?) && level[k] < level[top]
              closes[pending.pop] = begins[k - 1]
            end
            pending << k
          end
          firsts = Array(Int32).new(n + 1, -1)
          (n - 1).downto(0) { |k| firsts[k] = closing[k] ? begins[k] : firsts[k + 1] }
          {begins, closes, firsts}
        end

        # Byte offset of the `</blockquote>` closing the blockquote whose
        # content starts at `from` (see `pair_blockquote_tags`); nil when
        # there is no closer at all.
        private def matching_blockquote_close(tags : {Array(Int32), Array(Int32), Array(Int32)}, from : Int32) : Int32?
          begins, closes, firsts = tags
          i = begins.bsearch_index { |b| b >= from } || begins.size
          close = closes[i] >= 0 ? closes[i] : firsts[i]
          close >= 0 ? close : nil
        end

        # Post-processing: rewrite GitHub `> [!TYPE]` blockquotes as admonition
        # divs, including one nested in another (`> > [!TIP]`).
        #
        # Each nesting level rescans and copies its body, so the levels
        # rewritten are capped: a page nesting admonitions a thousand deep
        # (a megabyte of `> > > …`) took seconds. Deeper ones stay
        # blockquotes.
        MAX_ADMONITION_NESTING = 8

        def postprocess_admonitions(html : String, foldable : Bool = false, depth : Int32 = 0) : String
          return html unless Utils::ByteScan.includes?(html, "[!")
          # One UTF-8 check: PCRE2 otherwise revalidates the whole page on
          # every match, quadratic in the admonition count.
          options = html.valid_encoding? ? Regex::MatchOptions::NO_UTF_CHECK : Regex::MatchOptions::None
          return html unless m = ADMONITION_OPEN_RE.match_at_byte_index(html, 0, options)

          tags = pair_blockquote_tags(html, options)
          String.build(html.bytesize) do |io|
            pos = 0
            while m
              break unless close = matching_blockquote_close(tags, m.byte_end(0))
              io.write(html.to_slice[pos, m.byte_begin(0) - pos])
              body = html.byte_slice(m.byte_end(0), close - m.byte_end(0))
              body = postprocess_admonitions(body, foldable, depth + 1) if depth + 1 < MAX_ADMONITION_NESTING
              io << render_admonition(m[1], foldable ? m["fold"] : "", m[3], body)
              pos = close + "</blockquote>".bytesize
              m = ADMONITION_OPEN_RE.match_at_byte_index(html, pos, options)
            end
            io.write(html.to_slice[pos, html.bytesize - pos])
          end
        end

        private def render_admonition(type : String, fold : String, title_line : String, rest : String) : String
          # Two or more trailing spaces on the marker line become a hard
          # break in markd (`[!NOTE]  ` → `[!NOTE]<br />\n`), and the break
          # tag sits before the newline group 2 stops at — so it landed in
          # the title and a bare marker lost its "Note" heading to an empty
          # `<br />`. It is line-end residue, never title text.
          title_line = title_line.sub(/\s*<br\s*\/?>\s*\z/, "")
          # An inline element that wraps from the marker line onto the next
          # (`[!WARNING] see [the\n> docs](…)`) cannot be a title: cutting
          # it at the soft break split `<a>` between title and body. Treat
          # the whole paragraph as body, as before custom titles existed.
          unless inline_html_balanced?(title_line)
            rest = "#{title_line}\n#{rest}"
            title_line = ""
          end
          custom_title = title_line.strip
          type_lower = type.downcase
          # The custom title is already inline-rendered (and escaped) by
          # markd — it was part of the paragraph — so it is emitted as-is.
          type_title = custom_title.empty? ? type.capitalize : custom_title

          body = if rest.lstrip.starts_with?("</p>")
                   # Marker was alone on its paragraph; remaining content
                   # already consists of well-formed block elements.
                   rest.sub(/\A\s*<\/p>\s*/, "").strip
                 elsif rest.strip.empty?
                   # Title-only admonition with no body.
                   ""
                 else
                   # Body text shared the marker's paragraph (soft break).
                   # The closing </p> is already inside `rest`.
                   "<p>#{rest.lstrip}".strip
                 end

          String.build do |str|
            if fold.empty?
              str << %(<div class="admonition admonition-#{type_lower}">\n)
              str << %(<p class="admonition-title">#{type_title}</p>\n)
            else
              # Obsidian fold: `-` starts collapsed, `+` open.
              str << %(<details class="admonition admonition-#{type_lower}") << (fold == "+" ? " open>\n" : ">\n")
              str << %(<summary class="admonition-title">#{type_title}</summary>\n)
            end
            unless body.empty?
              str << body
              str << '\n'
            end
            str << (fold.empty? ? "</div>" : "</details>")
          end
        end
      end
    end
  end
end
