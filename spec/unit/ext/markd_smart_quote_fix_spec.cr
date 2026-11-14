require "../../spec_helper"

# The oracle: Markd 0.5.0's own `process_emphasis`, verbatim, selectable per
# render. `previous_def` is src/ext/markd_smart_quote_fix.cr.
module Markd::Parser
  class Inline
    class_property? __upstream = false

    private def process_emphasis(delimiter : Delimiter?)
      return __upstream_process_emphasis(delimiter) if Inline.__upstream?
      previous_def
    end

    private def __upstream_process_emphasis(delimiter : Delimiter?)
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
          when '"'
            closer.node.text = "\u{201D}"
            if opener
              opener.node.text = "\u{201C}"
            end
            closer = closer.next?
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

private def smart_html(text : String, upstream : Bool) : String
  Markd::Parser::Inline.__upstream = upstream
  Markd.to_html(text, Markd::Options.new(smart: true))
ensure
  Markd::Parser::Inline.__upstream = false
end

describe "Markd smart quotes (src/ext/markd_smart_quote_fix.cr)" do
  it "renders random text exactly as upstream does" do
    alphabet = ["\"", "\"", "'", "'", "*", "_", "[", "]", "(", ")", "!", "`", "\\", "<", ">",
                "-", ".", " ", " ", "\n", "a", "b", "é"]
    rng = Random.new(1114)
    20_000.times do
      text = String.build { |io| rng.rand(1..60).times { io << alphabet.sample(rng) } }
      expected = smart_html(text, upstream: true)
      actual = smart_html(text, upstream: false)
      fail "#{text.inspect}: #{actual.inspect} != #{expected.inspect}" unless actual == expected
    end
  end

  # A matched quote closer stayed on the delimiter stack, so each later
  # closer walked back over all of them: 40k took ~3 s (80k: 13 s).
  it "is linear in the number of quotes" do
    text = "\"'" * 40_000
    Time.measure { smart_html(text, upstream: false) }.should be < 500.milliseconds
  end
end
