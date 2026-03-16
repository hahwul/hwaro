require "../spec_helper"
require "../../src/utils/html_minifier"

describe Hwaro::Utils::HtmlMinifier do
  describe ".minify" do
    it "removes HTML comments" do
      html = "<p>Hello</p><!-- this is a comment --><p>World</p>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should_not contain("<!-- this is a comment -->")
      result.should contain("<p>Hello</p>")
      result.should contain("<p>World</p>")
    end

    it "preserves conditional comments" do
      html = "<p>Hello</p><!--[if IE]><p>IE only</p><![endif]--><p>World</p>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should contain("<!--[if IE]>")
    end

    it "preserves <!-- more --> markers" do
      html = "<p>Intro</p><!-- more --><p>Rest</p>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should contain("<!-- more -->")
    end

    it "collapses excessive blank lines" do
      html = "<p>Hello</p>\n\n\n\n\n<p>World</p>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should_not contain("\n\n\n")
      result.should contain("<p>Hello</p>")
      result.should contain("<p>World</p>")
    end

    it "cleans whitespace inside pre/code blocks" do
      html = "<pre>\n  <code>content</code>\n</pre>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should contain("<pre><code")
      result.should contain("</code></pre>")
    end

    it "cleans pre blocks with attributes" do
      html = "<pre class=\"highlight\">\n  <code>content</code>\n</pre>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should contain("<pre class=\"highlight\"><code")
      result.should contain("</code></pre>")
    end

    it "strips surrounding whitespace" do
      html = "  \n  <p>Hello</p>  \n  "
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should eq("<p>Hello</p>")
    end

    it "handles empty string" do
      Hwaro::Utils::HtmlMinifier.minify("").should eq("")
    end

    it "handles html with no minifiable content" do
      html = "<p>Hello World</p>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should eq("<p>Hello World</p>")
    end

    it "removes multiple comments" do
      html = "<!-- a --><p>Hello</p><!-- b --><p>World</p><!-- c -->"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should_not contain("<!-- a -->")
      result.should_not contain("<!-- b -->")
      result.should_not contain("<!-- c -->")
      result.should contain("<p>Hello</p>")
    end

    it "removes multi-line comments" do
      html = "<p>Hello</p>\n<!--\n  multi\n  line\n  comment\n-->\n<p>World</p>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should_not contain("multi")
      result.should_not contain("line")
      result.should_not contain("comment")
    end
  end
end
