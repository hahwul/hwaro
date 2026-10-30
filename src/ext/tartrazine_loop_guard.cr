# Guards against two lexer shapes that never finish, kept here so we don't
# fork the vendored library, like ext/tartrazine_mt_fix.cr. Both turn a
# grammar bug into an exception, which ServerHighlighter's rescue degrades
# to plain output (with a warning for a `[highlight] lexers_dir` grammar).
# A lexer that never hit either case — every bundled one in practice, or
# builds would hang — tokenizes exactly as before.
#
# 1. A rule that matches the empty string (`[a-z]*`) without moving the
#    state stack matches again at the same position forever, queueing an
#    empty token each time (unbounded memory). Zero-width matches are
#    legitimate when they change state (`(?=x)` + `<pop>`), so the guard
#    counts consecutive zero-width matches at one position and gives up
#    past HWARO_MAX_STALLS — far more state changes than any grammar
#    makes at a single byte, and a stack that keeps growing there is the
#    same bug.
# 2. `<usingself>` / `<using lexer="its own name">` on a rule that can
#    match its whole input re-tokenizes the same text one level deeper
#    each time, until the stack overflows and the process dies. Nesting is
#    capped at HWARO_MAX_NESTING per fiber (tokenization can suspend on
#    the template-cache mutex, so a thread-local count could mix fibers).
#
# Remove when: upstream bounds zero-width progress and delegation depth.

require "tartrazine"

class Fiber
  # Lexer delegation depth of the tokenization running on this fiber.
  property hwaro_lexer_depth : Int32 = 0
end

module Tartrazine
  HWARO_MAX_STALLS  = 1_000
  HWARO_MAX_NESTING =    32

  class Tokenizer
    @hwaro_stalls = 0

    # Stock body, plus the zero-width counter (see the file comment).
    def next : Iterator::Stop | Token
      if @dq.size > 0
        return @dq.shift
      end
      if pos == @text.size
        return stop
      end

      matched = false
      while @pos < @text.size
        @lexer.states[@state_stack.last].rules.each do |rule|
          matched, new_pos, new_tokens = rule.match(@text, @pos, self)
          if matched
            if new_pos == @pos
              @hwaro_stalls += 1
              if @hwaro_stalls > HWARO_MAX_STALLS
                raise Exception.new("a rule in state '#{@state_stack.last}' matches the empty string at byte #{@pos} without making progress")
              end
            else
              @hwaro_stalls = 0
            end
            @pos = new_pos
            split_tokens(new_tokens).each { |token| @dq << token }
            break
          end
        end
        if !matched
          @hwaro_stalls = 0
          if @text[@pos] == 10u8
            @dq << {type: "Text", value: "\n"}
            @state_stack = ["root"]
          else
            @dq << {type: "Error", value: String.new(@text[@pos..@pos])}
          end
          @pos += 1
          break
        end
      end
      self.next
    end
  end

  struct Action
    def emit(match : MatchData, tokenizer : Tokenizer, match_group = 0) : Array(Token)
      return previous_def unless @type.using? || @type.usingself? || @type.usingbygroup?

      fiber = Fiber.current
      if fiber.hwaro_lexer_depth >= HWARO_MAX_NESTING
        raise Exception.new("lexer delegation (<using>/<usingself>) nested deeper than #{HWARO_MAX_NESTING} levels")
      end
      fiber.hwaro_lexer_depth += 1
      begin
        previous_def
      ensure
        fiber.hwaro_lexer_depth -= 1
      end
    end
  end
end
