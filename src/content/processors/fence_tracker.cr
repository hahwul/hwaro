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
      #   context where ```/~~~ is literal text, never a delimiter.
      class FenceTracker
        @in_fence = false
        @fence_char = '`'
        @fence_len = 0

        # True while inside an open fence: after the opener line was fed,
        # until (and excluding) the line after the closer. Lets callers that
        # need to route in-fence lines differently (e.g. the shortcode
        # processor's chunk buffering) branch before feeding the line.
        def in_fence? : Bool
          @in_fence
        end

        # Feed the next line (with or without its trailing newline).
        # Returns true when the line must pass through verbatim: a fence
        # delimiter or any line inside an open fence.
        def fence_line?(line : String) : Bool
          eligible = !(line.starts_with?("    ") || line.starts_with?('\t'))
          stripped = line.lstrip

          if @in_fence
            @in_fence = false if eligible && closes_fence?(stripped)
            true
          elsif eligible && (run = opener_run(stripped))
            @in_fence = true
            @fence_char = stripped[0]
            @fence_len = run
            true
          else
            false
          end
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
