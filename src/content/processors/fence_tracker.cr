# Shared fenced-code-block tracker for line-by-line markdown walkers.
#
# `MarkdownExtensions.process_lines_fence_aware`, the math chunker, the
# definition-list detector, and `TableParser.process` all need the same
# answer to "is this line fenced-code content?". Keeping one implementation
# stops the walkers drifting from each other — and from Markd's block
# parser, which is what actually decides how the page renders.

module Hwaro
  module Content
    module Processors
      # CommonMark-faithful fence state machine:
      #
      # - An opener is a run of 3+ backticks or tildes indented at most 3
      #   spaces. A backtick fence's info string may not contain a backtick
      #   (CommonMark treats such a line as inline code, not a fence).
      # - The closer must use the same character, be at least as long as the
      #   opener, and carry nothing but whitespace after the run. A shorter
      #   run, the other character, or trailing text is fence *content* —
      #   this is what keeps ``` examples nested inside ```` fences (and
      #   "```ruby" lines inside an open fence) verbatim.
      # - Lines indented 4+ spaces (or starting with a tab) are indented-code
      #   context where ```/~~~ is literal text, never a delimiter. Whole
      #   indented-code *runs* are tracked as verbatim too: a 4+-indented
      #   non-blank line opens a run when nothing before it can absorb the
      #   indent — after a blank line, or directly after an ATX heading,
      #   which CommonMark (and Markd) let indented code follow with no
      #   blank line in between. Inside a list item the run opens only
      #   four columns beyond the item's content column (tabs expanded to
      #   4-column stops), and it survives blanks until the first non-blank
      #   line back under that column.
      # - List items are tracked as a stack of content columns, one entry
      #   per open item, at ANY indentation: a nested `- b` sits wherever
      #   its parent's content puts it, four spaces or a tab included. The
      #   stack errs toward keeping items open — a marker always pushes, an
      #   item is only popped by a marker left of its content or by a
      #   non-blank line left of its content after a blank line (the one
      #   case where Markd certainly closes it). A stale item can only make
      #   a line look *less* like code (today's under-protective
      #   behaviour); a missed one would make real list content look like
      #   code and silently skip every extension on it. Items are keyed by
      #   blockquote depth, so a quote inside an item never pops the item,
      #   while a `>` marker left of an item's content closes it.
      #   Column arithmetic mirrors Markd, including its quirks (tabs after
      #   a list marker and after `>` are measured from Markd's own column,
      #   not the true one). Lines inside a generic HTML block (`<div>` …
      #   blank line, `<!--` … `-->`) never open indented code, since Markd
      #   passes them through as raw HTML. Known limit: a fence closer
      #   followed directly by indented code opens no run.
      # - Fences inside blockquotes (`> ```) are tracked too: the leading
      #   `>` markers are stripped before the opener/closer rules apply, and
      #   the marker depth is remembered. Because CommonMark gives fenced
      #   code no lazy continuation, a line missing the fence's markers ends
      #   the quote — and the fence with it — and is re-evaluated as a
      #   potential new opener. Inside an open fence, only the fence's own
      #   marker depth is stripped, so a `> ```' line stays literal content
      #   of a top-level fence. Known limits: fences at 4+ absolute indent
      #   inside list items are still invisible, and tab-formed `>` markers
      #   (`>\t`) are not recognized.
      class FenceTracker
        # A bullet or ordered-list marker, matched after the line's leading
        # whitespace (so at any indentation — which list it belongs to is
        # decided by the item stack), followed by a space/tab or nothing
        # (CommonMark's empty item). Over-matching (a `* * *` thematic break,
        # a `2.` that cannot interrupt a paragraph) only pushes a stale item,
        # which errs toward "not code".
        LIST_MARKER_RE = /\A(?:[-*+]|\d{1,9}[.)])(?=[ \t]|\r?\n?\z)/

        # These CommonMark raw HTML blocks (type 1) leave their contents
        # uninterpreted. Preprocessors must treat them like code so math,
        # footnotes, and inline markup do not rewrite script/style or
        # preformatted text. The tag name must end at whitespace, `>` or the
        # line end — `<style-guide>` or `<pre-view>` is an ordinary element —
        # and the block ends at the first line containing ANY of the closing
        # tags, whichever element opened it.
        RAW_HTML_CODE_OPEN_RE  = /\A {0,3}<(?:pre|script|style|textarea)(?:[\s>]|\z)/i
        RAW_HTML_CODE_CLOSE_RE = /<\/(?:pre|script|style|textarea)\s*>/i

        # Starts of CommonMark HTML blocks that run to a blank line (Markd's
        # HTML_BLOCK_OPEN types 6 and 7, the latter with possessive
        # quantifiers so a long line cannot exhaust the PCRE JIT stack).
        HTML_BLOCK_TAG_RE      = /\A {0,3}<\/?(?:address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|section|source|title|summary|table|tbody|td|tfoot|th|thead|tr|track|ul)(?:\s|\/?>|\z)/i
        HTML_BLOCK_LONE_TAG_RE = /\A {0,3}(?:<[A-Za-z][A-Za-z0-9-]*+(?:\s++[a-zA-Z_:][a-zA-Z0-9:._-]*+(?:\s*+=\s*+(?:[^"'=<>`\x00-\x20]++|'[^']*+'|"[^"]*+"))?+)*+\s*+\/?>|<\/[A-Za-z][A-Za-z0-9-]*+\s*+>)\s*\z/

        # An ATX heading at up to 3 spaces indent: 1-6 `#` followed by a
        # space/tab or nothing but the line ending. Only used to let an
        # indented-code run open on the line right after a heading — the
        # blank line the run otherwise needs is what CommonMark requires to
        # keep indented code from interrupting a *paragraph*, and a heading
        # is not a paragraph. Markd opens the code block there, so without
        # this the walkers transformed lines Markd renders verbatim (a
        # shortcode expanded on such a line left an escaped placeholder
        # comment stranded inside `<pre><code>`). The other paragraph-ending
        # blocks (setext underlines, thematic breaks, HTML blocks) are not
        # recognized here: they are ambiguous line-locally, and missing them
        # only keeps today's under-protective behavior.
        ATX_HEADING_RE = /\A {0,3}\#{1,6}(?:[ \t]|\r?\n?\z)/

        @in_fence = false
        @fence_char = '`'
        @fence_len = 0
        @fence_bq_depth = 0
        @in_raw_html_code = false
        @raw_html_code_bq_depth = 0
        @in_indented_code = false
        @indented_code_column = 4
        @indented_code_bq_depth = 0
        # Open list items as {blockquote depth, content column}, outermost
        # first.
        @list_items = [] of {Int32, Int32}
        @prev_blank = true
        @prev_atx_heading = false
        # Deepest blockquote that may still hold an open paragraph: raised by
        # any line at a deeper quote, lowered only by a blank line (which
        # closes the paragraph and every quote deeper than its markers).
        @open_quote_depth = 0
        # The last line opened an empty list item (`-` alone). If the next
        # line is blank the item is over: an item may begin with at most
        # one blank line, and an empty one followed by a blank has none.
        @empty_item_open = false
        # An open generic HTML block (0 none, 1 ends at a blank line — the
        # CommonMark type 6/7 blocks, 2 an HTML comment ending at `-->`) and
        # the quote depth it lives in. Its lines are raw HTML to Markd, so
        # they never open indented code. Only that suppression is modelled:
        # a block tracked too long merely leaves lines unprotected.
        @html_block = 0
        @html_block_bq_depth = 0

        # True while inside an open fence: after the opener line was fed,
        # until (and excluding) the line after the closer. Lets callers
        # that need to route in-fence lines differently branch before
        # feeding the line.
        def in_fence? : Bool
          @in_fence
        end

        # `raw_html_code: false` turns off raw-HTML code-block tracking.
        # Only the Markdown-extension walkers treat `<pre>`/`<script>`/
        # `<style>`/`<textarea>` blocks as opaque; shortcode expansion (and
        # the checks that must agree with it) and definition-list
        # extraction keep their long-standing behaviour of seeing inside.
        def initialize(raw_html_code : Bool = true)
          @track_raw_html_code = raw_html_code
        end

        # Feed the next line (with or without its trailing newline).
        # Returns true when the line must pass through verbatim: a fence
        # delimiter or any line inside an open fence.
        def fence_line?(line : String) : Bool
          # Consumed and cleared up front so every early return below (fence
          # content, an ongoing indented-code run) leaves the flag false —
          # only the plain-text tail re-arms it.
          prev_atx_heading = @prev_atx_heading
          @prev_atx_heading = false

          if @in_fence
            content, depth = strip_blockquote_markers(line, @fence_bq_depth)
            if depth == @fence_bq_depth
              @in_fence = false if !indented?(content) && closes_fence?(content.lstrip)
              @prev_blank = false
              return true
            end
            # The fence's blockquote marker is gone: the quote ends here
            # and takes the fence with it (no lazy continuation for fenced
            # code). Fall through so this same line can open a new fence.
            @in_fence = false
          end

          content, depth = strip_blockquote_markers(line)
          blank = content.blank?

          # A line deeper than any quote still open starts a new blockquote,
          # which holds no paragraph yet — indented code may open at once.
          # A shallower line may be a lazy paragraph continuation, so the
          # open depth only drops at a blank line.
          #
          # Inside a generic HTML block every line is raw HTML — a `>` there
          # is text — so none of that applies.
          in_html_block = inside_html_block?(content, depth, blank)
          quote_opened = !in_html_block && depth > @open_quote_depth
          @open_quote_depth = depth if blank || quote_opened
          close_items_left_of_quote_markers(line, depth) unless depth.zero? || in_html_block
          if @empty_item_open
            @list_items.pop if blank
            @empty_item_open = false
          end

          if @track_raw_html_code
            if @in_raw_html_code
              if depth != @raw_html_code_bq_depth
                # Raw HTML blocks inside a blockquote end when the quote ends.
                @in_raw_html_code = false
              else
                @in_raw_html_code = false if RAW_HTML_CODE_CLOSE_RE.matches?(content)
                @prev_blank = false
                return true
              end
            end

            if content.includes?('<') && RAW_HTML_CODE_OPEN_RE.matches?(content)
              @in_raw_html_code = !RAW_HTML_CODE_CLOSE_RE.matches?(content)
              @raw_html_code_bq_depth = depth
              @prev_blank = false
              return true
            end
          end

          prefix, tab_consumed = depth.zero? ? {0, false} : blockquote_prefix_column(line, depth)
          column, text_start = leading_columns(content, prefix, tab_consumed)

          code_left_quote = false
          if @in_indented_code
            if blank
              @prev_blank = true
              return true
            elsif depth == @indented_code_bq_depth && column >= @indented_code_column
              @prev_blank = false
              return true
            end
            # First non-blank line back under the run's column ends the run
            # and is evaluated normally below. Code has no lazy
            # continuation, so a line at another quote depth closes the
            # quote (or opens one) with no paragraph for indented code to
            # interrupt.
            code_left_quote = depth != @indented_code_bq_depth
            @in_indented_code = false
          end

          if !blank && @prev_blank
            # After a blank line, a line left of an item's content column
            # closes that item; items of quotes that ended at the blank line
            # are dropped. (Items of an enclosing container are closed by
            # this line's `>` markers instead, above.)
            @list_items.reject! { |item| item[0] > depth || (item[0] == depth && item[1] > column) }
          end

          if !blank && !in_html_block && (@prev_blank || prev_atx_heading || quote_opened || code_left_quote)
            base = list_content_column(depth, column)
            if column - base >= 4
              @in_indented_code = true
              @indented_code_column = base + 4
              @indented_code_bq_depth = depth
              @prev_blank = false
              return true
            end
          end

          track_list_item(content, depth, column, text_start, prefix) unless blank
          open_html_block(content, depth) unless blank || in_html_block

          stripped = content.lstrip
          heading = !blank && ATX_HEADING_RE.matches?(content)
          fence_run = indented?(content) ? nil : opener_run(stripped)
          if heading || fence_run
            # Headings and fences are never lazy continuations: one left of
            # an item's content closes it, like a line after a blank.
            @list_items.reject! { |item| item[0] > depth || (item[0] == depth && item[1] > column) }
          end

          if run = fence_run
            @in_fence = true
            @fence_char = stripped[0]
            @fence_len = run
            @fence_bq_depth = depth
            @prev_blank = false
            true
          else
            @prev_blank = blank
            @prev_atx_heading = heading
            false
          end
        end

        private def indented?(content : String) : Bool
          content.starts_with?("    ") || content.starts_with?('\t')
        end

        # Consumes up to `max_depth` leading blockquote markers (each up to
        # 3 spaces, a `>`, and one optional space) and returns the remainder
        # plus the number of markers consumed. Byte scan: every byte that
        # can form a marker is ASCII, and ordinary lines exit on the first
        # byte — this runs several times per line across the walkers.
        private def strip_blockquote_markers(line : String, max_depth : Int32 = Int32::MAX) : {String, Int32}
          slice = line.to_slice
          pos = 0
          depth = 0
          while depth < max_depth
            start = pos
            spaces = 0
            while pos < slice.size && slice[pos] === ' ' && spaces < 3
              pos += 1
              spaces += 1
            end
            unless pos < slice.size && slice[pos] === '>'
              pos = start
              break
            end
            pos += 1
            pos += 1 if pos < slice.size && slice[pos] === ' '
            depth += 1
          end
          return {line, 0} if depth.zero?
          {line.byte_slice(pos, line.bytesize - pos), depth}
        end

        private def opener_run(stripped : String) : Int32?
          char = stripped[0]?
          return unless char
          return unless char == '`' || char == '~'
          run = run_length(stripped, char)
          return if run < 3
          return if char == '`' && stripped.index('`', run)
          run
        end

        private def closes_fence?(stripped : String) : Bool
          run = run_length(stripped, @fence_char)
          run >= @fence_len && stripped[run..].blank?
        end

        # The column Markd has reached after consuming `depth` blockquote
        # markers. Markd never advances its column over the up-to-3 spaces
        # before a `>` (`advance_next_nonspace` updates only the offset), so
        # only an enclosing list item's content column, the `>`, and its
        # optional following space count. A tab after
        # `>` counts one column and stays in the content, exactly as
        # `strip_blockquote_markers` leaves it — unless that one column
        # reaches a tab stop, in which case Markd consumed the whole tab and
        # the flag tells `leading_columns` to skip it.
        private def blockquote_prefix_column(line : String, depth : Int32) : {Int32, Bool}
          slice = line.to_slice
          pos = 0
          column = 0
          depth.times do |level|
            spaces = 0
            while pos < slice.size && slice[pos] === ' ' && spaces < 3
              pos += 1
              spaces += 1
            end
            break unless pos < slice.size && slice[pos] === '>'
            # A list item holding this quote was consumed first, by columns.
            column += list_content_column(level, spaces)
            pos += 1
            column += 1
            if pos < slice.size && slice[pos] === ' '
              pos += 1
              column += 1
            elsif pos < slice.size && slice[pos] === '\t'
              # One column of the tab is the optional space; when that is
              # the whole tab (it ends on a tab stop), Markd consumes it.
              return {column + 1, true} if column % 4 == 3
              column += 1
            end
          end
          {column, false}
        end

        # Whether this line continues a generic HTML block opened earlier
        # (updating the block's state), so it cannot be indented code.
        private def inside_html_block?(content : String, depth : Int32, blank : Bool) : Bool
          return false if @html_block.zero?
          # Leaving the block's quote ends it (HTML has no lazy
          # continuation); a deeper `>` is just more HTML.
          if depth < @html_block_bq_depth || (blank && @html_block == 1)
            @html_block = 0
            return false
          end
          @html_block = 0 if @html_block == 2 && content.includes?("-->")
          true
        end

        private def open_html_block(content : String, depth : Int32) : Nil
          return unless content.includes?('<')
          stripped = content.lstrip
          if stripped.starts_with?("<!--")
            @html_block = 2 unless stripped.index("-->", 4)
          elsif HTML_BLOCK_TAG_RE.matches?(stripped) || HTML_BLOCK_LONE_TAG_RE.matches?(stripped)
            @html_block = 1
          else
            return
          end
          @html_block_bq_depth = depth
        end

        # A `>` marker left of an open item's content column cannot sit
        # inside that item: the item closes (a blockquote start is never a
        # lazy continuation), and with it every item of the quotes nested in
        # it. Marker `level` is measured from the content of quote depth
        # `level`, where that depth's items keep their columns.
        private def close_items_left_of_quote_markers(line : String, depth : Int32) : Nil
          return if @list_items.empty?

          slice = line.to_slice
          pos = 0
          depth.times do |level|
            spaces = 0
            while pos < slice.size && slice[pos] === ' ' && spaces < 3
              pos += 1
              spaces += 1
            end
            break unless pos < slice.size && slice[pos] === '>'
            if @list_items.any? { |item| item[0] == level && item[1] > spaces }
              @list_items.reject! { |item| item[0] > level || (item[0] == level && item[1] > spaces) }
            end
            pos += 1
            pos += 1 if pos < slice.size && slice[pos] === ' '
          end
        end

        # Column of the first non-whitespace character, measured from the
        # end of the stripped blockquote prefix (`prefix` columns wide) but
        # with tabs advancing to the next absolute multiple of 4, as Markd
        # expands them; plus that character's byte offset.
        private def leading_columns(content : String, prefix : Int32, tab_consumed : Bool = false) : {Int32, Int32}
          column = prefix
          offset = tab_consumed && content.starts_with?('\t') ? 1 : 0
          content.to_slice[offset..].each do |byte|
            if byte === ' '
              column += 1
            elsif byte === '\t'
              column += 4 - column % 4
            else
              break
            end
            offset += 1
          end
          {column - prefix, offset}
        end

        # The content column of the innermost open item (at this blockquote
        # depth) that a line starting at `column` sits inside; 0 outside any.
        private def list_content_column(depth : Int32, column : Int32) : Int32
          @list_items.reverse_each do |item|
            return item[1] if item[0] == depth && item[1] <= column
          end
          0
        end

        # A list marker less than 4 columns right of its container's content
        # opens an item (4+ is paragraph continuation or code, never a
        # marker): items whose content starts right of the marker cannot
        # contain it and close. The new item's content column follows
        # Markd's `parse_list_marker` — the text after 1-4 columns of
        # whitespace, or one column past the marker for an empty item or one
        # whose text is itself indented code (5+ columns). Markd measures
        # tabs after the marker from the container's content column plus the
        # marker width (it never advances its column to the marker), so the
        # same virtual column is used here. Text that is itself a marker
        # (`- - b`, `* * *`) opens a nested item at that content column.
        private def track_list_item(content : String, depth : Int32, column : Int32, text_start : Int32, prefix : Int32) : Nil
          # Byte probe first: this runs on every non-blank line.
          first_byte = content.byte_at?(text_start)
          return unless first_byte
          return unless first_byte === '-' || first_byte === '*' || first_byte === '+' || first_byte.unsafe_chr.ascii_number?

          base = list_content_column(depth, column)
          return if column - base >= 4

          virtual_column = prefix + base
          offset = text_start
          first = true
          loop do
            rest = content.byte_slice(offset, content.bytesize - offset)
            marker = LIST_MARKER_RE.match(rest)
            break unless marker

            marker_size = marker[0].bytesize
            virtual_column += marker_size
            width = 0
            spaces = 0
            rest.to_slice[marker_size..].each do |byte|
              if byte === ' '
                width += 1
              elsif byte === '\t'
                width += 4 - (virtual_column + width) % 4
              else
                break
              end
              spaces += 1
            end
            simple = 1 <= width <= 4 && !rest.byte_slice(marker_size).blank?
            content_column = column + marker_size + (simple ? width : 1)

            @list_items.reject! { |item| item[0] == depth && item[1] > column } if first
            @list_items << {depth, content_column}
            @empty_item_open = rest.byte_slice(marker_size).blank?
            break unless simple

            first = false
            column = content_column
            virtual_column += width
            offset += marker_size + spaces
          end
        end

        private def run_length(text : String, char : Char) : Int32
          count = 0
          text.each_char do |c|
            break unless c == char
            count += 1
          end
          count
        end
      end
    end
  end
end
