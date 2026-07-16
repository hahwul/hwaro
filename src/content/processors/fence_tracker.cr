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
      #   non-blank line after a blank line opens a run — unless a list is
      #   open, where the same indent is item continuation, not code — and
      #   the run survives blanks until the first non-blank line back under
      #   4 columns. The list heuristic is deliberately sticky (a marker
      #   opens it; only a blank followed by a flush-left non-marker line
      #   closes it): staying "in list" too long merely keeps today's
      #   under-protective behavior, while leaving it too early would newly
      #   skip transforms on real list content. Known limits: code indented
      #   6+ columns inside list items is not recognized (unchanged), and
      #   a fence closer followed directly by indented code opens no run.
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
        # A bullet or ordered-list marker at up to 3 spaces indent. The
        # trailing space/tab is required — CommonMark's empty-item form
        # (a bare "-") is intentionally not matched; a missed marker only
        # keeps the list heuristic closed in a case too rare to matter.
        LIST_MARKER_RE = /\A {0,3}(?:[-*+]|\d{1,9}[.)])[ \t]/

        @in_fence = false
        @fence_char = '`'
        @fence_len = 0
        @fence_bq_depth = 0
        @in_indented_code = false
        @in_list = false
        @prev_blank = true

        # True while inside an open fence: after the opener line was fed,
        # until (and excluding) the line after the closer. Lets callers
        # that need to route in-fence lines differently branch before
        # feeding the line.
        def in_fence? : Bool
          @in_fence
        end

        # Feed the next line (with or without its trailing newline).
        # Returns true when the line must pass through verbatim: a fence
        # delimiter or any line inside an open fence.
        def fence_line?(line : String) : Bool
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

          if @in_indented_code
            if blank
              @prev_blank = true
              return true
            elsif indented?(content)
              @prev_blank = false
              return true
            end
            # First non-blank line back under 4 columns ends the run and
            # is evaluated normally below.
            @in_indented_code = false
          end

          if !blank && indented?(content) && @prev_blank && !@in_list
            @in_indented_code = true
            @prev_blank = false
            return true
          end

          if LIST_MARKER_RE.matches?(content)
            @in_list = true
          elsif @in_list && @prev_blank && !blank && !content.starts_with?(' ') && !content.starts_with?('\t')
            # A flush-left non-marker block after a blank line ends the
            # list context; indented lines and lazy continuations keep it.
            @in_list = false
          end

          stripped = content.lstrip
          if !indented?(content) && (run = opener_run(stripped))
            @in_fence = true
            @fence_char = stripped[0]
            @fence_len = run
            @fence_bq_depth = depth
            @prev_blank = false
            true
          else
            @prev_blank = blank
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
