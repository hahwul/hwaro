# Monkey-patch for Markd's inline/HTML-block regexes — kept here so we don't
# fork the vendored library, mirroring ext/markd_thematic_break_fix.cr.
#
# Several markd 0.5.0 regexes repeat a GROUP over input of unbounded length:
#
#   Rule::HTML_TAG         `(?:\s+NAME(?:\s*=\s*VALUE)?)*`  (attributes) and the
#                          comment body `(?:-?[^-])*`
#   Rule::HTML_BLOCK_OPEN  the same attribute loop (type-7 HTML blocks)
#   Rule::LINK_DESTINATION_BRACES  `(?:[^<>\t\n\\\x00]|ESC)*`
#   Rule::LINK_TITLE       `"(ESC|[^"\x00])*"`, `'…'`, `\((ESC|[^)\x00])*\)`
#   Rule::LINK_LABEL       `\[(?:[^\\\[\]]|ESC|\\){0,}\]`
#
# PCRE2's JIT keeps one backtracking frame per repetition, so a long enough
# line (an HTML tag with ~50k attributes, a 100k-character comment, a
# `[a](b (` run with no closing paren) raises `Regex::Error: JIT stack limit
# reached` out of `String#match`. Nothing in the render path expects that, so
# the page fails to render and the build exits 4.
#
# Two kinds of fix, each chosen so ordinary input matches exactly as before:
#
# * Possessive quantifiers where backtracking can never change the outcome:
#   every iteration of the attribute loop, the comment body and the braced
#   destination is forced by the characters it sees (an attribute starts with
#   whitespace + a name character, which the tag's tail `\s*/?>` cannot use;
#   the comment body steps over `-x` pairs; a lone `\` cannot be consumed in a
#   braced destination at all), so giving iterations back only ever lands on a
#   position where the rest of the pattern fails.
#
# * A linear scanner for the title and label, where backtracking DOES matter:
#   `(ESC|[^)])*\)` lets the regex split an escaped `\)` back into `\` + `)`,
#   so `(a\)` is a title, and splitting a `\\` pair shifts which later
#   bracket counts as escaped. `MarkdRegexStackFix.bracketed_length` computes
#   the regex's exact result, backtracking included, in one backward pass.
#
# `[a](` x 16_000 on one line took over 100 seconds: every failed inline link
# entity-decoded and URI-normalized the whole rest of the line as its
# destination before noticing there was no `)`, and `Inline#match` copied the
# rest of the paragraph (`byte_slice`) on every call. A doomed destination is
# no longer decoded, and matching happens in place at `@pos` with anchored
# copies of the `^`-rules.
#
# Remove when: upstream markd stops repeating groups over unbounded input.

require "markd"

# These patches REPLACE upstream methods wholesale (no `previous_def`), so a
# shard bump that changes them would be silently reverted. Fail the build
# loudly instead; re-verify against the new source, then bump the pin.
{% if Markd::VERSION != "0.5.0" %}
  {% raise "src/ext/markd_regex_stack_fix.cr replaces Markd::Parser::Inline#match/#html_tag/#link_title/#link_label/#link_destination and Markd::Rule::HTMLBlock#match verbatim from markd 0.5.0, but markd #{Markd::VERSION} is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

module Hwaro
  module MarkdRegexStackFix
    # Rule::ATTRIBUTE repeated possessively (see the file comment).
    OPEN_TAG_STRING = "<#{Markd::Rule::TAG_NAME_STRING}#{Markd::Rule::ATTRIBUTE}*+\\s*/?>"
    OPEN_TAG        = OPEN_TAG_STRING
    COMMENT_STRING  = "<!---->|<!--(?:-?[^>-])(?:-?[^-])*+-->"

    HTML_TAG_STRING = "(?:#{OPEN_TAG_STRING}|#{Markd::Rule::CLOSE_TAG_STRING}|#{COMMENT_STRING}|" \
                      "#{Markd::Rule::PROCESSING_INSTRUCTION_STRING}|#{Markd::Rule::DECLARATION_STRING}|" \
                      "#{Markd::Rule::CDATA_STRING})"
    # Compile-time ANCHORED: matches only at the start offset handed to
    # `match_at_byte_index`, so the parser never has to copy the rest of the
    # paragraph to anchor a `^` pattern.
    HTML_TAG = Regex.new(HTML_TAG_STRING, Regex::Options::IGNORE_CASE | Regex::Options::ANCHORED)

    LINK_DESTINATION_BRACES = Regex.new(
      "(?:[<](?:[^<>\\t\\n\\\\\\x00]|" + Markd::Rule::ESCAPED_CHAR_STRING + ")*+[>])",
      Regex::Options::ANCHORED)

    HTML_BLOCK_OPEN = Markd::Rule::HTML_BLOCK_OPEN[0...-1] + [
      Regex.new("^(?:" + OPEN_TAG + "|" + Markd::Rule::CLOSE_TAG + ")\\s*$", Regex::Options::IGNORE_CASE),
    ]

    # Anchored copies of the other `^`-rules `Inline#match` is called with.
    ANCHORED = {
      Markd::Rule::ESCAPABLE           => anchored(Markd::Rule::ESCAPABLE),
      Markd::Rule::EMAIL_AUTO_LINK     => anchored(Markd::Rule::EMAIL_AUTO_LINK),
      Markd::Rule::AUTO_LINK           => anchored(Markd::Rule::AUTO_LINK),
      Markd::Rule::NUMERIC_HTML_ENTITY => anchored(Markd::Rule::NUMERIC_HTML_ENTITY),
    }

    def self.anchored(regex : Regex) : Regex
      raise ArgumentError.new("expected a ^-anchored rule: #{regex.source}") unless regex.source.starts_with?('^')
      Regex.new(regex.source.lchop('^'), regex.options | Regex::Options::ANCHORED)
    end

    # CommonMark's escapable ASCII punctuation (Rule::ESCAPABLE_STRING).
    ESCAPABLE_BYTES = Set(UInt8).new(%q(!"#$%&'()*+,./:;<=>?@[\]^_`{|}~-).bytes)

    # Byte length of the bracketed construct starting at `pos` — exactly the
    # match the upstream `open (ESC | body)* close` regex produces, including
    # its backtracking — or nil when there is none. `stops` are the bytes the
    # body cannot contain besides `close` (NUL for titles, `[` for labels).
    #
    # The regex's search order at each position `p` between iterations is:
    # a `\X` escape pair (X escapable), then a single body byte (a `\` is
    # always one), and only when no further iteration succeeds, the closer.
    # So its result from `p` depends only on its results from `p + 1` and
    # `p + 2`, and one backward pass computes it with no recursion and no
    # stack. The pass only needs to reach the first `close`/`stops` byte that
    # is NOT preceded by `\`: no parse can step past that byte, so nothing
    # beyond it can affect the match. That bounds the work by the length of
    # the text the regex itself had to walk.
    def self.bracketed_length(text : String, pos : Int32, close : UInt8, stops : Tuple) : Int32?
      bytes = text.to_slice
      size = bytes.size
      limit = pos + 1
      while limit < size
        byte = bytes[limit]
        break if (byte == close || stops.includes?(byte)) &&
                 (limit == pos + 1 || bytes[limit - 1] != '\\'.ord || byte == 0_u8)
        limit += 1
      end
      # The regex's result from `limit`: the closer ends it; a stop byte or the
      # end of the text fails it.
      at_next = limit < size && bytes[limit] == close ? limit + 1 : nil
      at_after = nil.as(Int32?)
      p = limit - 1
      while p > pos
        byte = bytes[p]
        result = nil.as(Int32?)
        if byte == '\\'.ord
          if p + 1 < size && ESCAPABLE_BYTES.includes?(bytes[p + 1])
            # `at_after` is the result from `p + 2`, just past the pair.
            result = at_after
          end
          result ||= at_next
        elsif byte != close && !stops.includes?(byte)
          result = at_next
        end
        result ||= p + 1 if byte == close
        at_after = at_next
        at_next = result
        p -= 1
      end
      at_next.try { |end_index| end_index - pos }
    end
  end
end

module Markd::Parser
  class Inline
    # Upstream: `text = @text.byte_slice(@pos)` then `text.match(regex)` — an
    # O(rest-of-paragraph) copy per call. Matches in place instead; a `^`-rule
    # goes through its anchored copy (PCRE2's `^` means start of SUBJECT, not
    # start offset), the unanchored `TICKS` searches forward exactly as it
    # did in the copied remainder.
    private def match(regex : Regex) : String?
      regex = Hwaro::MarkdRegexStackFix::ANCHORED.fetch(regex, regex)
      if regex.source.starts_with?('^')
        # A `^`-rule without an anchored copy: keep upstream's semantics.
        text = @text.byte_slice(@pos)
        if match = text.match(regex)
          @pos += match.byte_end(0)
          return match[0]
        end
        return
      end
      if match = regex.match_at_byte_index(@text, @pos)
        @pos = match.byte_end(0)
        match[0]
      end
    end

    private def html_tag(node : Node)
      if text = match(Hwaro::MarkdRegexStackFix::HTML_TAG)
        child = Node.new(Node::Type::HTMLInline)
        child.text = text
        node.append_child(child)
        true
      else
        false
      end
    end

    private def link_label
      text = bracketed(']', {'['.ord.to_u8}) if char_at?(@pos) == '['
      if text && text.size <= 1001 && (!text.ends_with?("\\]") || text[-3]? == '\\')
        text.bytesize - 1
      else
        0
      end
    end

    private def link_title
      title = case char_at?(@pos)
              when '"'  then bracketed('"', {0_u8})
              when '\'' then bracketed('\'', {0_u8})
              when '('  then bracketed(')', {0_u8})
              end
      return unless title

      Utils.decode_entities_string(title[1..-2])
    end

    # Consume the bracketed construct at `@pos` (see
    # `MarkdRegexStackFix.bracketed_length`), returning its text.
    private def bracketed(close : Char, stops : Tuple) : String?
      length = Hwaro::MarkdRegexStackFix.bracketed_length(@text, @pos, close.ord.to_u8, stops)
      return unless length
      text = @text.byte_slice(@pos, length)
      @pos += length
      text
    end

    private def link_destination
      dest = if text = match(Hwaro::MarkdRegexStackFix::LINK_DESTINATION_BRACES)
               text[1..-2]
             elsif char_at?(@pos) != '<'
               save_pos = @pos
               open_parens = 0
               while char = char_at?(@pos)
                 case char
                 when '\\'
                   @pos += 1
                   match(Rule::ESCAPABLE)
                 when '('
                   @pos += 1
                   open_parens += 1
                 when ')'
                   break if open_parens < 1

                   @pos += 1
                   open_parens -= 1
                 when .ascii_whitespace?
                   break
                 else
                   @pos += 1
                 end
               end

               # A scan that ran to the END of the text cannot be followed by
               # the `)` an inline link needs, so `close_bracket` is about to
               # discard this destination (a failed inline link never reads
               # it). Decoding it anyway made `[a](` x 16_000 quadratic in the
               # entity decoder. A reference definition CAN end at the end of
               # the text, so it still gets the real value.
               return "" if char_at?(@pos).nil? && !@hwaro_in_reference

               @text.byte_slice(save_pos, @pos - save_pos)
             end

      normalize_uri(Utils.decode_entities_string(dest)) if dest
    end

    # True while `reference` parses a link reference definition (see
    # `link_destination`).
    @hwaro_in_reference = false

    def reference(text : String, refmap)
      @hwaro_in_reference = true
      previous_def
    ensure
      @hwaro_in_reference = false
    end
  end
end

module Markd::Rule
  struct HTMLBlock
    def match(parser : Parser, container : Node) : MatchValue
      if !parser.indented && parser.line[parser.next_nonspace]? == '<'
        text = parser.line[parser.next_nonspace..-1]
        block_type_size = Hwaro::MarkdRegexStackFix::HTML_BLOCK_OPEN.size - 1

        Hwaro::MarkdRegexStackFix::HTML_BLOCK_OPEN.each_with_index do |regex, index|
          if text.match(regex) &&
             (index < block_type_size || !container.type.paragraph?)
            parser.close_unmatched_blocks
            # We don't adjust parser.offset;
            # spaces are part of the HTML block:
            node = parser.add_child(Node::Type::HTMLBlock, parser.offset)
            node.data["html_block_type"] = index

            return MatchValue::Leaf
          end
        end
      end

      MatchValue::None
    end
  end
end
