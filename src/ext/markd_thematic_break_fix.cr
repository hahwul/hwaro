# Monkey-patch for Markd's thematic-break matcher — kept here so we don't fork
# the vendored library, mirroring ext/markd_list_fix.cr and
# ext/markd_entity_fix.cr.
#
# Upstream `Markd::Rule::ThematicBreak#match` (markd 0.5.0,
# src/markd/rules/thematic_break.cr:8) tests every line against
#
#   /^(?:(?:\*[ \t]*){3,}|(?:_[ \t]*){3,}|(?:-[ \t]*){3,})[ \t]*$/
#
# Those are nested quantifiers over a group that can match a single character,
# so PCRE2 recurses once per repetition. Past roughly 44_000 marker characters
# on ONE line the JIT runs out of stack and Crystal raises
#
#   Regex::Error: Regex match error: JIT stack limit reached
#
# out of `String#match` — which nothing in the render path expects, so it
# escapes `Markdown.render` and aborts the whole build. The block parser offers
# EVERY line to this rule, so a match is not required to trigger it: a long run
# of `-`, `*` or `_` anywhere in a document does it, and machine-generated
# separators, pasted logs and dumped tables all produce exactly that.
#
# A thematic break has no structure worth a regex: it is a line made only of
# spaces/tabs and at least three of ONE marker character. The scan below says
# that directly, in one linear pass with no backtracking and no allocation, so
# line length stops mattering. CommonMark 0.31.2 ("Thematic breaks") is the
# reference; the caller already passes the line sliced at `next_nonspace` and
# still guards `parser.indented`, so leading-indent handling is unchanged.
#
# Remove when: upstream stops matching this rule with nested quantifiers.

require "markd"

# This patch REPLACES the upstream method wholesale (no `previous_def`), so a
# shard bump that changes `match` would be silently reverted by the copy below.
# Fail the build loudly instead; re-verify the copy against the new source,
# then bump the pin here.
{% if Markd::VERSION != "0.5.0" %}
  {% raise "src/ext/markd_thematic_break_fix.cr replaces Markd::Rule::ThematicBreak#match verbatim from markd 0.5.0, but markd #{Markd::VERSION} is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

module Markd::Rule
  struct ThematicBreak
    # True when `text` is spaces/tabs plus three or more of a single `*`, `_`
    # or `-` — the exact language of the regex it replaces.
    def self.hwaro_thematic_break?(text : String) : Bool
      marker = nil.as(Char?)
      count = 0
      text.each_char do |char|
        case char
        when ' ', '\t'
          next
        when '*', '_', '-'
          return false if marker && marker != char
          marker = char
          count += 1
        else
          return false
        end
      end
      count >= 3
    end

    def match(parser : Parser, container : Node) : MatchValue
      if !parser.indented &&
         ThematicBreak.hwaro_thematic_break?(parser.line[parser.next_nonspace..-1])
        parser.close_unmatched_blocks
        parser.add_child(Node::Type::ThematicBreak, parser.next_nonspace)
        parser.advance_offset(parser.line.size - parser.offset, false)
        MatchValue::Leaf
      else
        MatchValue::None
      end
    end
  end
end
