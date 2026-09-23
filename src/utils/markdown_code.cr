# Markdown source regions that render as literal text, not markup.
#
# Content tools scan Markdown for links and raw HTML with regexes. Anything
# inside a code block, an inline code span or an HTML comment is shown (or
# hidden) verbatim by the build, never rendered as a link or an image, so the
# scanners blank those regions out first. `tool check-links` and
# `tool validate` share this one stripper so they agree on what counts.
module Hwaro
  module Utils
    module MarkdownCode
      extend self

      # Markdown links inside fenced code blocks or inline code spans are
      # documentation examples (e.g. a `![Diagram](/images/diagram.png)`
      # snippet demonstrating image syntax), not real links. Strip them
      # before scanning so `check-links` doesn't report false-positive dead
      # links — mirrors the code-stripping the scaffold link-integrity spec
      # already performs.
      #
      # Fences are tracked line-by-line, CommonMark-style: a fence opens
      # with 3+ backticks/tildes (up to 3 spaces of indent) and only
      # closes on a fence of the same character at least as long. The old
      # non-greedy /```[\s\S]*?```/ mispaired nested fences — a 4-backtick
      # example wrapping a 3-backtick fence desynchronized every fence
      # after it, resurrecting example links as false positives.
      # Also stripped: HTML comments and indented (4-space/tab) code
      # blocks. Both hold example markup that is not a link — a
      # `<!-- <img src="/old.png"> -->` note and an indented
      # `<a href="/example/">` demo were each reported dead.
      #
      # Indented code is recognized conservatively, per CommonMark: a run
      # only counts as code when it follows a blank line AND no list item
      # is open. Without the list guard a 4-space list-item continuation
      # would be swallowed, which is exactly the failure that made the
      # sibling validator give up on indented blocks entirely.
      def strip(content : String) : String
        result = String::Builder.new
        fence_char : Char? = nil
        fence_len = 0
        in_comment = false
        in_indented_code = false
        in_list = false
        prev_blank = true

        content.each_line(chomp: false) do |line|
          blank = line.strip.empty?

          # HTML comments span lines and can open/close mid-line.
          if in_comment
            if idx = line.index("-->")
              in_comment = false
              result << line[(idx + 3)..].gsub(/`[^`\n]*`/, "")
            else
              result << '\n'
            end
            prev_blank = blank
            next
          end

          if m = line.match(/\A {0,3}(`{3,}|~{3,})/)
            marker = m[1]
            if fence_char.nil?
              fence_char = marker[0]
              fence_len = marker.size
              in_indented_code = false
              result << '\n'
              prev_blank = false
              next
            elsif marker[0] == fence_char && marker.size >= fence_len
              fence_char = nil
              fence_len = 0
              result << '\n'
              prev_blank = false
              next
            end
          end

          if fence_char
            result << '\n'
            prev_blank = blank
            next
          end

          # Track list context so a 4-space continuation line is treated as
          # prose, not code.
          if line.matches?(/\A {0,3}(?:[-*+]|\d+[.)])\s/)
            in_list = true
          elsif blank
            # A blank line alone does not close a list; a subsequent
            # unindented non-list line does.
          elsif !line.starts_with?(" ") && !line.starts_with?("\t")
            in_list = false
          end

          indented = line.starts_with?("    ") || line.starts_with?("\t")
          if in_indented_code
            if blank || indented
              result << '\n'
              prev_blank = blank
              next
            end
            in_indented_code = false
          elsif indented && prev_blank && !in_list && !blank
            in_indented_code = true
            result << '\n'
            prev_blank = false
            next
          end

          stripped = line.gsub(/`[^`\n]*`/, "")
          # A comment opened on this line: keep the text before it.
          if idx = stripped.index("<!--")
            if close = stripped.index("-->", idx)
              stripped = stripped[0...idx] + stripped[(close + 3)..]
            else
              in_comment = true
              stripped = stripped[0...idx] + "\n"
            end
          end
          result << stripped
          prev_blank = blank
        end

        result.to_s
      end
    end
  end
end
