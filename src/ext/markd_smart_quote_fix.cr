# Smart punctuation: a quote closer that found its opener stays on Markd's
# delimiter stack, so every later closer of the same quote walks back over
# all of them to reach the one opener: a line of N `"'` took O(N²) (40k:
# 3 s, 80k: 13 s). Kept here so we don't fork the vendored library,
# mirroring ext/markd_link_label_fix.cr.
#
# Upstream `Markd::Parser::Inline#process_emphasis` (markd 0.5.0,
# src/markd/parsers/inline.cr:285) ports commonmark.js, which also leaves a
# matched quote closer in place (cmark removes it). It already removes an
# UNmatched quote closer that cannot open; this removes a matched one the
# same way. A quote that can close cannot open (`can_open = left_flanking &&
# !right_flanking`, `can_close = right_flanking`), and only a delimiter that
# can open is ever matched as an opener, so the stack lost nothing any later
# closer could have used: the rendered text is the same, and each closer's
# walk now stops at the nearest live candidate. Everything else is copied
# verbatim from upstream.

require "markd"

{% if Markd::VERSION != "0.5.0" %}
  {% raise "src/ext/markd_smart_quote_fix.cr replaces Markd::Parser::Inline#process_emphasis verbatim from markd 0.5.0, but markd #{Markd::VERSION} is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

module Markd::Parser
  class Inline
    private def process_emphasis(delimiter : Delimiter?)
      # find first closer above stack_bottom:
      closer = @delimiters
      while closer
        previous = closer.previous?
        break if previous == delimiter
        closer = previous
      end

      if closer
        openers_bottom = {
          '_'  => delimiter,
          '*'  => delimiter,
          '\'' => delimiter,
          '"'  => delimiter,
        } of Char => Delimiter?

        # move forward, looking for closers, and handling each
        while closer
          closer_char = closer.char

          unless closer.can_close
            closer = closer.next?
            next
          end

          # found emphasis closer. now look back for first matching opener:
          opener = closer.previous?
          opener_found = false
          while opener && opener != delimiter && opener != openers_bottom[closer_char]
            odd_match = (closer.can_open || opener.can_close) &&
                        closer.orig_delims % 3 != 0 &&
                        (opener.orig_delims + closer.orig_delims) % 3 == 0
            if opener.char == closer.char && opener.can_open && !odd_match
              opener_found = true
              break
            end
            opener = opener.previous?
          end
          opener = nil unless opener_found

          old_closer = closer

          case closer_char
          when '*', '_'
            unless opener # ameba:disable Style/UnlessElse -- verbatim upstream
              closer = closer.next?
            else
              # calculate actual number of delimiters used from closer
              use_delims = (closer.num_delims >= 2 && opener.num_delims >= 2) ? 2 : 1
              opener_inl = opener.node
              closer_inl = closer.node

              # remove used delimiters from stack elts and inlines
              opener.num_delims -= use_delims
              closer.num_delims -= use_delims

              opener_inl.text = opener_inl.text[0..(-use_delims - 1)]
              closer_inl.text = closer_inl.text[0..(-use_delims - 1)]

              # build contents for new emph element
              emph = Node.new((use_delims == 1) ? Node::Type::Emphasis : Node::Type::Strong)

              tmp = opener_inl.next?
              while tmp && tmp != closer_inl
                next_node = tmp.next?
                tmp.unlink
                emph.append_child(tmp)
                tmp = next_node
              end

              opener_inl.insert_after(emph)

              # remove elts between opener and closer in delimiters stack
              remove_delimiter_between(opener, closer)

              # if opener has 0 delims, remove it and the inline
              if opener.num_delims == 0
                opener_inl.unlink
                remove_delimiter(opener)
              end

              if closer.num_delims == 0
                closer_inl.unlink
                tmp_stack = closer.next?
                remove_delimiter(closer)
                closer = tmp_stack
              end
            end
          when '\''
            closer.node.text = "\u{2019}"
            if opener
              opener.node.text = "\u{2018}"
            end
            closer = closer.next?
            # hwaro: a used quote closer never opens; drop it (see above).
            remove_delimiter(old_closer) if opener && !old_closer.can_open
          when '"'
            closer.node.text = "\u{201D}"
            if opener
              opener.node.text = "\u{201C}"
            end
            closer = closer.next?
            # hwaro: as above.
            remove_delimiter(old_closer) if opener && !old_closer.can_open
          else
            nil # ameba:disable Lint/ElseNil -- verbatim upstream
          end

          if !opener && !odd_match
            openers_bottom[closer_char] = old_closer.previous?
            remove_delimiter(old_closer) if !old_closer.can_open
          end
        end
      end

      # remove all delimiters
      while (curr_delimiter = @delimiters) && curr_delimiter != delimiter
        remove_delimiter(curr_delimiter)
      end
    end
  end
end
