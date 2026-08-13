# Monkey-patch for Markd's ordered-list marker scanner — kept here so we
# don't fork the vendored library, mirroring ext/markd_entity_fix.cr and
# ext/crinja_resolve_fix.cr.
#
# Upstream `Markd::Rule::List#parse_list_marker` (markd 0.5.0,
# src/markd/rules/list.cr:93) converts the leading digit run to an Int32
# BEFORE it checks whether that run could be a list marker at all:
#
#   number = pos >= 1 ? line[0..pos - 1].to_i : -1
#   if pos >= 1 && pos <= 9 && ORDERED_LIST_MARKERS.includes?(line[pos]?) &&
#      (!container.type.paragraph? || number == 1)
#
# `String#to_i` is the raising form, so a digit run whose VALUE exceeds
# Int32::MAX aborts the render with `ArgumentError: Invalid Int32:
# "12345678901"`. The block parser offers every line of every document to
# this rule, so it does not take a list to trigger — ordinary prose whose
# first token is a large number followed by `.` or `)` is enough:
#
#   12345678901.50 USD in revenue this year.
#   3000000000. first record
#   > 9999999999 requests/sec
#
# Each of those killed the whole build (HWARO_E_TEMPLATE, exit 4) with the
# offending page unwritten and the pages rendered before it already
# published — a half-published site from one sentence of prose.
#
# The fix is to run the shape check first. CommonMark 0.31.2 ("List items")
# caps an ordered-list marker at 9 digits, which upstream already encodes as
# `pos <= 9`; a longer run is not a marker at all and must simply fall
# through to `empty_data` ("this line does not start a list item"), which is
# what leaves the line as the paragraph text it is. Nine digits can never
# exceed Int32::MAX, so the conversion below cannot fail today — it stays in
# the `to_i?` form anyway so that any future change to the digit cap
# degrades into "not a list" instead of aborting a build.
#
# Nothing else in the method changes: the marker set, the paragraph
# condition (`start` must be 1 to interrupt a paragraph), the data hash and
# every early return are copied verbatim from upstream, so documents that
# already rendered are unaffected — `1. x` is still an ordered list and
# `999999999. x` still starts at 999999999.
#
# Remove when: upstream bounds the digit run before converting it, or
# converts with `to_i?`.

require "markd"

# This patch REPLACES the upstream method wholesale (no `previous_def`), so a
# shard bump that changes `parse_list_marker` would be silently reverted by the
# copy below — no compile error, no failing spec, and every upstream fix in
# that method quietly undone. Fail the build loudly instead; re-verify the copy
# against the new source, then bump the pin here.
{% if Markd::VERSION != "0.5.0" %}
  {% raise "src/ext/markd_list_fix.cr replaces Markd::Rule::List#parse_list_marker verbatim from markd 0.5.0, but markd #{Markd::VERSION} is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

module Markd::Rule
  struct List
    private def parse_list_marker(parser : Parser, container : Node) : Node::DataType
      empty_data = {} of String => Node::DataValue
      if parser.indent >= 4
        return empty_data
      end

      data = {
        "delimiter"     => 0,
        "marker_offset" => parser.indent,
        "bullet_char"   => "",
        "tight"         => true, # lists are tight by default
        "start"         => 1,
      } of String => Node::DataValue

      line = parser.line[parser.next_nonspace..-1]

      if BULLET_LIST_MARKERS.includes?(line[0])
        data["type"] = "bullet"
        data["bullet_char"] = line[0].to_s
        first_match_size = 1
      else
        pos = 0
        while line[pos]?.try &.ascii_number?
          pos += 1
        end

        # Shape first, conversion second (see the header): a run of more than
        # 9 digits is not an ordered-list marker per CommonMark, so it must
        # never reach the Int32 conversion below.
        unless pos >= 1 && pos <= 9 && ORDERED_LIST_MARKERS.includes?(line[pos]?)
          return empty_data
        end

        # `to_i?`, not `to_i`: at most 9 digits always fits in Int32, so this
        # cannot fail — but a marker we cannot turn into a number is simply
        # not a list, never a crash.
        number = line[0, pos].to_i? || return empty_data
        return empty_data if container.type.paragraph? && number != 1

        data["type"] = "ordered"
        data["start"] = number
        data["delimiter"] = line[pos].to_s
        first_match_size = pos + 1
      end

      next_char = parser.line[parser.next_nonspace + first_match_size]?
      unless next_char.nil? || space_or_tab?(next_char)
        return empty_data
      end

      if container.type.paragraph? &&
         parser.line[(parser.next_nonspace + first_match_size)..-1].each_char.all? &.ascii_whitespace?
        return empty_data
      end

      parser.advance_next_nonspace
      parser.advance_offset(first_match_size, true)
      spaces_start_column = parser.column
      spaces_start_offset = parser.offset

      loop do
        parser.advance_offset(1, true)
        next_char = parser.line[parser.offset]?

        break unless parser.column - spaces_start_column < 5 && space_or_tab?(next_char)
      end

      blank_item = parser.line[parser.offset]?.nil?
      spaces_after_marker = parser.column - spaces_start_column
      if spaces_after_marker >= 5 || spaces_after_marker < 1 || blank_item
        data["padding"] = first_match_size + 1
        parser.column = spaces_start_column
        parser.offset = spaces_start_offset

        parser.advance_offset(1, true) if space_or_tab?(parser.line[parser.offset]?)
      else
        data["padding"] = first_match_size + spaces_after_marker
      end

      data
    end
  end
end
