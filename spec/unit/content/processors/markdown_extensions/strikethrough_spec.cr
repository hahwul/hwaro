require "../../../../spec_helper"

# The lazy `~~`, `==`, `++` (and, in table cells, footnotes and definition
# lists, `**`/`*`/`_`) patterns rescanned to the end of the line for every
# opener that never closes.
describe "inline delimiters that never close" do
  # 40k unclosed openers on one line took ~20 s each (a scan to the end of
  # the line per opener; ~10 s in a spec build); linear, they take ~30 ms.
  it "is linear in the number of openers that never close" do
    config = Hwaro::Models::MarkdownConfig.new
    config.ins = true
    config.mark = true
    {"~~a ", "==a ", "++a "}.each do |unit|
      elapsed = Time.measure { Hwaro::Content::Processors::MarkdownExtensions.preprocess(unit * 40_000 + "\n", config) }
      elapsed.should be < 500.milliseconds
    end
    elapsed = Time.measure { Hwaro::Content::Processors::InlineMarkdown.render("**a " * 40_000) }
    elapsed.should be < 500.milliseconds
  end
end

describe "strikethrough next to an HTML tag holding link syntax" do
  # The tag was stashed after its `](b)` link destination, so restoring the
  # destination first left the destination's placeholder in the output.
  it "keeps the tag's attribute intact" do
    html, _ = Hwaro::Processor::Markdown.render(%(<span title="see [a](b)">~~old~~ new</span>\n), markdown_config: Hwaro::Models::MarkdownConfig.new)
    html.should eq %(<p><span title="see [a](b)"><del>old</del> new</span></p>\n)
  end
end
