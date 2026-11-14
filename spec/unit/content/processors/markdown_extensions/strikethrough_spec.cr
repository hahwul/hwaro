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
