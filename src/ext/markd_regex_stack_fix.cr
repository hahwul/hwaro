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
#   Rule::EMAIL_AUTO_LINK  the domain-label loop `(?:\.LABEL)*`
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
#   braced destination at all; an email domain label starts with `.`), so
#   giving iterations back only ever lands on a position where the rest of the
#   pattern fails. The one exception is Unicode whitespace: Crystal compiles
#   regexes with PCRE2 UCP, so markd's `\s` also matches U+00A0, U+3000, … —
#   which an unquoted attribute value may contain, and upstream backtracks a
#   value to end before one. So when the possessive tag regex fails on text
#   holding such a character, upstream's own regex decides
#   (`MarkdRegexStackFix.html_tag_length`, `.html_block_open?`).
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
      Markd::Rule::EMAIL_AUTO_LINK     => EMAIL_AUTO_LINK,
      Markd::Rule::AUTO_LINK           => anchored(Markd::Rule::AUTO_LINK),
      Markd::Rule::NUMERIC_HTML_ENTITY => anchored(Markd::Rule::NUMERIC_HTML_ENTITY),
    }

    def self.anchored(regex : Regex) : Regex
      raise ArgumentError.new("expected a ^-anchored rule: #{regex.source}") unless regex.source.starts_with?('^')
      Regex.new(regex.source.lchop('^'), regex.options | Regex::Options::ANCHORED)
    end

    # Rule::EMAIL_AUTO_LINK with its domain-label loop possessive: every
    # iteration starts with `.`, and giving one back (or shortening its label)
    # leaves a `.` or an alphanumeric where the closing `>` must be, so
    # backtracking can never produce a match.
    EMAIL_AUTO_LINK = Regex.new(
      "<([a-zA-Z0-9.!#$%&'*+\\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?" \
      "(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*+)>",
      Regex::Options::ANCHORED)

    # Upstream's own tag regexes, for the fallback below.
    UPSTREAM_HTML_TAG = anchored(Markd::Rule::HTML_TAG)

    # A whitespace character outside ASCII. Crystal compiles regexes with
    # PCRE2 UCP, so markd's `\s` also matches U+00A0, U+3000, U+2000–U+200A,
    # U+202F, U+205F, U+1680, U+0085, U+2028 and U+2029 — and an unquoted
    # attribute value may contain those characters too.
    NON_ASCII_SPACE = /(?=[^\x00-\x7F])\s/

    def self.non_ascii_space?(text : String) : Bool
      NON_ASCII_SPACE.matches?(text)
    end

    # Match `regex` at byte `pos` of `text` without copying it. PCRE2 checks
    # the WHOLE subject for valid UTF-8 on every call unless told not to, so
    # matching in place once per bracket was still quadratic on a long line;
    # `valid` (the caller checked `text.valid_encoding?` once) lets it skip
    # that check. Invalid text keeps the check, and PCRE2's own error for it.
    def self.match_at(regex : Regex, text : String, pos : Int32, valid : Bool) : Regex::MatchData?
      options = valid ? Regex::MatchOptions::NO_UTF_CHECK : Regex::MatchOptions::None
      regex.match_at_byte_index(text, pos, options)
    end

    # Byte length of the HTML tag at `pos`, exactly as Rule::HTML_TAG reads it.
    #
    # The possessive fast path takes the greedy path upstream tries first, so
    # when it matches, upstream matches the same text. It can only miss a tag
    # upstream finds by backtracking an unquoted value to end before a
    # NON-ASCII `\s` character (the only whitespace a value can contain), so
    # just then upstream's regex decides. `ucp` is whether the text contains
    # such a character (callers cache it per paragraph). A fallback that still
    # exhausts the JIT stack reads as "no tag", where upstream crashed.
    def self.html_tag_length(text : String, pos : Int32, ucp : Bool = non_ascii_space?(text),
                             valid : Bool = text.valid_encoding?) : Int32?
      if m = match_at(HTML_TAG, text, pos, valid)
        return m.byte_end(0) - pos
      end
      return unless ucp
      begin
        match_at(UPSTREAM_HTML_TAG, text, pos, valid).try { |upstream| upstream.byte_end(0) - pos }
      rescue Regex::Error
        nil
      end
    end

    # Whether `line` opens a type-7 HTML block, exactly as the last
    # Rule::HTML_BLOCK_OPEN pattern decides (same fast path and fallback).
    def self.html_block_open?(line : String) : Bool
      return true if line.matches?(HTML_BLOCK_OPEN.last)
      return false unless non_ascii_space?(line)
      begin
        line.matches?(Markd::Rule::HTML_BLOCK_OPEN.last)
      rescue Regex::Error
        false
      end
    end

    # CommonMark's escapable ASCII punctuation (Rule::ESCAPABLE_STRING).
    ESCAPABLE_BYTES = Set(UInt8).new(%q(!"#$%&'()*+,./:;<=>?@[\]^_`{|}~-).bytes)

    # Byte length of the bracketed construct starting at `pos` — exactly the
    # match the upstream `open (ESC | body)* close` regex produces, including
    # its backtracking — or nil when there is none. `stops` are the bytes the
    # body cannot contain besides `close` (NUL for titles, `[` for labels).
    def self.bracketed_length(text : String, pos : Int32, close : UInt8, stops : Tuple) : Int32?
      bracketed_length(bracketed_table(text, close, stops), pos)
    end

    def self.bracketed_length(table : Array(Int32), pos : Int32) : Int32?
      finish = table[pos + 1]? || -1
      finish < 0 ? nil : finish - pos
    end

    # For every position `p`, where the regex's body loop, entered at `p`,
    # finally matches the closer (the index just past it), or -1 for no match.
    # The result for a bracket opening at `pos` is `table[pos + 1]`, and it
    # does not depend on `pos` itself — so one table answers every attempt in
    # a paragraph, and a line of thousands of unclosed titles costs one pass
    # instead of one pass per title.
    #
    # The regex's search order at each position is: a `\X` escape pair (X
    # escapable), then a single body byte (a `\` is always one), and only
    # when no further iteration succeeds, the closer. So the result at `p`
    # depends only on the results at `p + 1` and `p + 2`, and one backward
    # pass computes all of them with no recursion and no stack. A `close` or
    # `stops` byte NOT preceded by `\` is where every parse stops: the loop
    # cannot step over it, so the result there is the closer or nothing.
    def self.bracketed_table(text : String, close : UInt8, stops : Tuple) : Array(Int32)
      bytes = text.to_slice
      size = bytes.size
      table = Array(Int32).new(size + 1, -1)
      p = size - 1
      while p >= 0
        byte = bytes[p]
        special = byte == close || stops.includes?(byte)
        if special && (p == 0 || bytes[p - 1] != '\\'.ord || byte == 0_u8)
          table[p] = byte == close ? p + 1 : -1
        else
          result = -1
          if byte == '\\'.ord
            result = table[p + 2] if p + 1 < size && ESCAPABLE_BYTES.includes?(bytes[p + 1])
            result = table[p + 1] if result < 0
          elsif !special
            result = table[p + 1]
          end
          result = p + 1 if result < 0 && byte == close
          table[p] = result
        end
        p -= 1
      end
      table
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
      if match = Hwaro::MarkdRegexStackFix.match_at(regex, @text, @pos, false)
        @pos = match.byte_end(0)
        match[0]
      end
    end

    private def html_tag(node : Node)
      memo = hwaro_memo
      length = Hwaro::MarkdRegexStackFix.html_tag_length(@text, @pos, memo.ucp, false)
      text = length.try { |len| @text.byte_slice(@pos, len) }
      @pos += length if length
      if text
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

    # Per-paragraph facts the patched methods reuse across attempts, rebuilt
    # whenever the parser moves to a new `@text`.
    class HwaroMemo
      getter text : String
      getter tables = {} of Char => Array(Int32)
      getter ucp : Bool
      getter valid : Bool
      getter last_dest_stop : Int32

      def initialize(@text : String)
        @valid = @text.valid_encoding?
        @ucp = @valid && Hwaro::MarkdRegexStackFix.non_ascii_space?(@text)
        bytes = @text.to_slice
        stop = bytes.size - 1
        while stop >= 0 && !(bytes[stop].unsafe_chr.ascii_whitespace? || bytes[stop] == ')'.ord)
          stop -= 1
        end
        @last_dest_stop = stop
      end
    end

    @hwaro_memo : HwaroMemo? = nil

    private def hwaro_memo : HwaroMemo
      memo = @hwaro_memo
      return memo if memo && memo.text.same?(@text)
      @hwaro_memo = HwaroMemo.new(@text)
    end

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
          opens = index < block_type_size ? text.matches?(regex) : Hwaro::MarkdRegexStackFix.html_block_open?(text)
          if opens &&
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
