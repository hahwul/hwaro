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

    it "renders the footnotes of a page that ends inside an unclosed fence" do
      # CommonMark runs an unclosed fence to the end of the page, so the
      # appended marker block became code text: the engine comments showed
      # on the page and the footnotes section was never built.
      config = Hwaro::Models::MarkdownConfig.new
      %w[``` ~~~~].each do |fence|
        html, _ = Hwaro::Processor::Markdown.render("Text[^1]\n\n[^1]: the note\n\n#{fence}\ncode\n", markdown_config: config)
        html.should_not contain("HWARO-")
        html.should contain(%(<pre><code>code\n</code></pre>))
        html.should contain(%(<li id="fn-1">\n<p>the note))
      end
    end

    it "keeps the footnotes in safe mode when the page ends with raw HTML and no newline" do
      # The marker block joined the raw HTML block on the last line, which
      # safe mode omits whole, so the section silently disappeared.
      config = Hwaro::Models::MarkdownConfig.new
      config.safe = true
      html, _ = Hwaro::Processor::Markdown.render("Text[^1]\n\n[^1]: the note\n\n<div>raw</div>", safe: true, markdown_config: config)
      html.should contain(%(<li id="fn-1">\n<p>the note))
      with_newline, _ = Hwaro::Processor::Markdown.render("Text[^1]\n\n[^1]: the note\n\n<div>raw</div>\n", safe: true, markdown_config: config)
      html.should eq(with_newline)
    end
  end
end
