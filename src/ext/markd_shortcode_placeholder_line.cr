# Shortcode placeholders at the start of a line — hwaro's side of Markd's
# HTML-block rule, kept here so we don't fork the vendored library.
#
# The shortcode pass leaves `<!--HWARO-SHORTCODE-PLACEHOLDER-N-->` in the
# Markdown for each rendered call. On a line of its own that comment must be
# an HTML block (type 2), so block-level shortcode output is not wrapped in a
# `<p>`. But CommonMark starts the block for ANY line opening with `<!--`: a
# call used inline at the start of a line (`{{ badge() }} new *feature*`)
# interrupted the paragraph and kept the rest of the line as raw text. When
# text (not raw HTML) follows the placeholders, refuse the block start; the
# line is then paragraph text and the comment inline HTML, as with the call
# mid-line.
# Author-typed placeholders never reach Markd (the shortcode pass strips
# them), so only hwaro's own lines are affected.

require "markd"

module Markd::Rule
  struct HTMLBlock
    def match(parser : Parser, container : Node) : MatchValue
      # The `<` probe first, as Markd's own rule does: `match` runs once per
      # open container on a line, so a whole-line scan here is quadratic on
      # deeply nested lines (`1. 1. 1. …`).
      if !parser.indented && parser.line[parser.next_nonspace]? == '<'
        rest = parser.line[parser.next_nonspace..]
        if rest.starts_with?("<!--HWARO-SHORTCODE-PLACEHOLDER-") &&
           Hwaro::Content::Processors::InlineMarkdown::SHORTCODE_PLACEHOLDER_LEADS_TEXT_RE.matches?(rest)
          return MatchValue::None
        end
      end
      previous_def
    end
  end
end
