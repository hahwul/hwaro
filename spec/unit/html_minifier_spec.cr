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

    it "preserves content inside pre/code blocks unchanged" do
      html = "<pre><code>  line1\n  line2\n  line3</code></pre>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should contain("line1")
      result.should contain("line2")
    end

    it "handles nested comments edge case" do
      html = "<p>A</p><!-- outer <!-- inner --> --><p>B</p>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should contain("<p>A</p>")
      result.should contain("<p>B</p>")
    end

    it "collapses exactly 3 blank lines to 2" do
      html = "<p>A</p>\n\n\n<p>B</p>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should eq("<p>A</p>\n\n<p>B</p>")
    end

    it "preserves 2 blank lines unchanged" do
      html = "<p>A</p>\n\n<p>B</p>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should eq("<p>A</p>\n\n<p>B</p>")
    end

    it "handles multiple pre blocks" do
      html = "<pre>\n  <code>first</code>\n</pre>\n<p>gap</p>\n<pre>\n  <code>second</code>\n</pre>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should contain("<pre><code")
      result.should contain("first")
      result.should contain("second")
    end

    it "handles comments adjacent to preserved more marker" do
      html = "<!-- remove this --><!-- more -->"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should_not contain("remove this")
      result.should contain("<!-- more -->")
    end

    it "handles whitespace-only content" do
      Hwaro::Utils::HtmlMinifier.minify("   \n\n\n   ").should eq("")
    end

    describe "trailing whitespace" do
      it "strips trailing spaces from each line" do
        html = "<p>A</p>   \n<p>B</p>\t\t\n<p>C</p>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<p>A</p>\n<p>B</p>\n<p>C</p>")
      end

      it "strips trailing whitespace even inside pre blocks (no visual effect)" do
        html = "<pre><code>line1   \nline2\t</code></pre>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("line1\nline2")
        result.should_not match(/line1 +\n/)
      end
    end

    describe "conservative guarantees (things it must NOT do)" do
      # Prior attempts to strip these broke content rendering. The flag
      # is contractually conservative — these assertions pin that down.

      it "does not collapse whitespace between tags" do
        html = "<span>x</span> <span>y</span>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<span>x</span> <span>y</span>")
      end

      it "does not strip leading whitespace from lines (preserves indentation)" do
        html = "<div>\n  <p>indented</p>\n</div>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<div>\n  <p>indented</p>\n</div>")
      end

      it "does not collapse whitespace runs in body text" do
        html = "<p>two  spaces</p>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("two  spaces")
      end

      it "preserves inline whitespace inside pre/code blocks" do
        html = "<pre><code>  leading\n    indented\n  outdented</code></pre>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("  leading\n    indented\n  outdented")
      end

      it "preserves single newline between block elements" do
        html = "<p>A</p>\n<p>B</p>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<p>A</p>\n<p>B</p>")
      end
    end
  end
end
