require "../../../../spec_helper"

describe Hwaro::Content::Processors::MarkdownExtensions do
  describe ".preprocess_footnotes" do
    it "stays linear in the footnote count on a long page" do
      # Each note's marker comment was appended with `result +=`, recopying
      # the whole page per note.
      content = String.build do |io|
        40_000.times { |i| io << "Paragraph #{i} with some filler text to make the page long[^n#{i}].\n\n[^n#{i}]: Note #{i}\n\n" }
      end
      t = Time.instant
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_footnotes(content)
      (Time.instant - t).should be < 5.seconds # quadratic took 15s+
      result.should contain("<!--HWARO-FN:n0:1.1:Note 0-->\n<!--HWARO-FN:n1:2.1:Note 1-->\n")
      result.should end_with("<!--HWARO-FN:n39999:40000.1:Note 39999-->\n<!--HWARO-FOOTNOTES-END-->\n")
    end
  end
end
