require "../spec_helper"

# Open the class to expose private method for testing
class Hwaro::Content::Processors::Html
  def test_minify_html(html : String) : String
    minify_html(html)
  end
end

describe Hwaro::Content::Processors::Html do
  describe "minify_html" do
    it "removes trailing whitespace on lines" do
      html = "Line 1   \nLine 2\t\t\nLine 3"
      processor = Hwaro::Content::Processors::Html.new
      result = processor.test_minify_html(html)
      result.should eq("Line 1\nLine 2\nLine 3")
    end

    it "collapses excessive blank lines" do
      html = "Line 1\n\n\n\nLine 2"
      processor = Hwaro::Content::Processors::Html.new
      result = processor.test_minify_html(html)
      result.should eq("Line 1\n\nLine 2")
    end

    it "removes standard HTML comments" do
      html = "Line 1\n<!-- This is a comment -->\nLine 2"
      processor = Hwaro::Content::Processors::Html.new
      result = processor.test_minify_html(html)
      result.should eq("Line 1\n\nLine 2")
    end

    it "preserves conditional comments" do
      html = "<!--[if IE]>Conditional<![endif]-->"
      processor = Hwaro::Content::Processors::Html.new
      result = processor.test_minify_html(html)
      result.should eq(html)
    end

    it "preserves 'more' markers" do
      html = "Line 1\n<!-- more -->\nLine 2"
      processor = Hwaro::Content::Processors::Html.new
      result = processor.test_minify_html(html)
      result.should eq("Line 1\n<!-- more -->\nLine 2")
    end

    it "preserves 'more' markers with whitespace" do
      html = "Line 1\n<!--  more  -->\nLine 2"
      processor = Hwaro::Content::Processors::Html.new
      result = processor.test_minify_html(html)
      result.should eq("Line 1\n<!--  more  -->\nLine 2")
    end

    it "cleans up pre/code blocks" do
      html = "<pre>\n  <code>code</code>\n</pre>"
      processor = Hwaro::Content::Processors::Html.new
      result = processor.test_minify_html(html)
      result.should eq("<pre><code>code</code></pre>")
    end

    it "preserves pre attributes" do
      html = "<pre class=\"language-ruby\">\n  <code>code</code>\n</pre>"
      processor = Hwaro::Content::Processors::Html.new
      result = processor.test_minify_html(html)
      result.should eq("<pre class=\"language-ruby\"><code>code</code></pre>")
    end

    it "strips leading/trailing whitespace of the string" do
      html = "   \nContent\n   "
      processor = Hwaro::Content::Processors::Html.new
      result = processor.test_minify_html(html)
      result.should eq("Content")
    end

    it "preserves meaningful structure and indentation" do
      html = <<-HTML
      <div>
        <p>Paragraph</p>
      </div>
      HTML
      processor = Hwaro::Content::Processors::Html.new
      result = processor.test_minify_html(html)
      result.should eq("<div>\n  <p>Paragraph</p>\n</div>")
    end
  end
end
