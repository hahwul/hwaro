# Command suggester utility
#
# Suggests the closest match from a list of candidates for a mistyped
# command. Uses Levenshtein distance with a small threshold, and falls
# back to a shared-prefix heuristic so very short inputs still get useful
# hints (e.g. "bld" -> "build").
#
# Keep the implementation tiny — the candidate list is always small
# (a few dozen entries at most).

module Hwaro
  module Utils
    module CommandSuggester
      extend self

      # Return the closest candidate to `input`, or nil when no candidate
      # is close enough to confidently suggest.
      def suggest(input : String, candidates : Enumerable(String)) : String?
        return if input.empty?

        best : String? = nil
        best_distance = Int32::MAX

        candidates.each do |candidate|
          distance = levenshtein(input, candidate)
          if distance < best_distance
            best_distance = distance
            best = candidate
          end
        end

        return if best.nil?

        # Accept the match if it is close by edit distance, or if the
        # input and candidate share a meaningful (>= 3 char) prefix.
        if best_distance <= 2
          best
        elsif shared_prefix_length(input, best) >= 3 &&
              best_distance <= (input.size // 2 + 1)
          best
        end
      end

      # Simple iterative Levenshtein distance over UTF-8 chars.
      def levenshtein(a : String, b : String) : Int32
        return b.size if a.empty?
        return a.size if b.empty?

        a_chars = a.chars
        b_chars = b.chars
        m = a_chars.size
        n = b_chars.size

        prev = Array(Int32).new(n + 1) { |j| j }
        curr = Array(Int32).new(n + 1, 0)

        m.times do |i|
          curr[0] = i + 1
          n.times do |j|
            cost = a_chars[i] == b_chars[j] ? 0 : 1
            curr[j + 1] = Math.min(
              Math.min(curr[j] + 1, prev[j + 1] + 1),
              prev[j] + cost
            )
          end
          prev, curr = curr, prev
        end

        prev[n]
      end

      private def shared_prefix_length(a : String, b : String) : Int32
        count = 0
        a.each_char_with_index do |ch, i|
          break if i >= b.size
          break if ch != b[i]
          count += 1
        end
        count
      end
    end
  end
end
