# Monkey-patch for Markd's closing-fence matcher — kept here so we don't fork
# the vendored library, mirroring ext/markd_thematic_break_fix.cr.
#
# Upstream `Markd::Rule::CodeBlock` (markd 0.5.0,
# src/markd/rules/code_block.cr:6) recognises a closing fence with
#
#   /^(?:`{3,}|~{3,})(?= *$)/
#
# which allows only SPACES after the fence run. CommonMark 0.31.2 ("Fenced
# code blocks") lets a closing fence be "followed only by spaces or tabs".
# A closer with a trailing tab (an editor's indent left on the line) did not
# close the block, so the rest of the page rendered as code — while hwaro's
# own `FenceTracker` already treated that line as the closer, so the Markdown
# extensions ran on lines Markd then printed verbatim.
#
# Remove when: upstream accepts tabs after a closing fence.

require "markd"

# This patch REPLACES the upstream method wholesale (no `previous_def`), so a
# shard bump that changes `continue` would be silently reverted by the copy
# below. Fail the build loudly instead; re-verify the copy against the new
# source, then bump the pin here.
{% if Markd::VERSION != "0.5.0" %}
  {% raise "src/ext/markd_closing_fence_fix.cr replaces Markd::Rule::CodeBlock#continue verbatim from markd 0.5.0, but markd #{Markd::VERSION} is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

module Markd::Rule
  struct CodeBlock
    HWARO_CLOSING_CODE_FENCE = /^(?:`{3,}|~{3,})(?=[ \t]*$)/

    # Upstream body; only the closing-fence regex is hwaro's.
    def continue(parser : Parser, container : Node) : ContinueStatus
      line = parser.line
      indent = parser.indent
      if container.fenced?
        # fenced
        match = indent <= 3 &&
                line[parser.next_nonspace]? == container.fence_char[0] &&
                line[parser.next_nonspace..-1].match(HWARO_CLOSING_CODE_FENCE)

        if match && match.as(Regex::MatchData)[0].size >= container.fence_length
          # closing fence - we're at end of line, so we can return
          parser.token(container, parser.current_line)
          return ContinueStatus::Return
        else
          # skip optional spaces of fence offset
          index = container.fence_offset
          while index > 0 && space_or_tab?(parser.line[parser.offset]?)
            parser.advance_offset(1, true)
            index -= 1
          end
        end
      else
        # indented
        if indent >= Rule::CODE_INDENT
          parser.advance_offset(Rule::CODE_INDENT, true)
        elsif parser.blank
          parser.advance_next_nonspace
        else
          return ContinueStatus::Stop
        end
      end

      ContinueStatus::Continue
    end
  end
end
