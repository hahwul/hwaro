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

    it "strips surrounding whitespace" do
      html = "  \n  <p>Hello</p>  \n  "
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should eq("<p>Hello</p>")
    end

    it "handles empty string" do
      Hwaro::Utils::HtmlMinifier.minify("").should eq("")
    end

    it "handles whitespace-only content" do
      Hwaro::Utils::HtmlMinifier.minify("   \n\n\n   ").should eq("")
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

    it "handles nested comments edge case" do
      html = "<p>A</p><!-- outer <!-- inner --> --><p>B</p>"
      result = Hwaro::Utils::HtmlMinifier.minify(html)
      result.should contain("<p>A</p>")
      result.should contain("<p>B</p>")
    end

    describe "block-level whitespace collapse" do
      it "strips whitespace between two block-level tags" do
        html = "<div>\n  <p>indented</p>\n</div>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<div><p>indented</p></div>")
      end

      it "strips whitespace between adjacent block-level siblings" do
        html = "<p>A</p>\n<p>B</p>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<p>A</p><p>B</p>")
      end

      it "collapses deeply indented block markup" do
        html = "<html>\n  <head>\n    <title>T</title>\n  </head>\n  <body>\n    <p>Hi</p>\n  </body>\n</html>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<html><head><title>T</title></head><body><p>Hi</p></body></html>")
      end

      it "strips whitespace between adjacent <meta> tags in <head>" do
        html = "<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"x\">\n</head>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<head><meta charset=\"utf-8\"><meta name=\"x\"></head>")
      end
    end

    describe "inline whitespace preservation" do
      it "preserves a single space between adjacent inline siblings" do
        html = "<span>x</span> <span>y</span>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<span>x</span> <span>y</span>")
      end

      it "collapses whitespace runs between inline siblings to a single space" do
        html = "<a>x</a>     <a>y</a>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<a>x</a> <a>y</a>")
      end

      it "collapses newlines between inline siblings to a single space" do
        html = "<a>x</a>\n  <a>y</a>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<a>x</a> <a>y</a>")
      end

      it "strips whitespace when an inline neighbor sits at a block boundary" do
        # Browsers collapse leading/trailing whitespace inside a block
        # parent, so `<p>\n  <span>only</span>\n</p>` and
        # `<p><span>only</span></p>` render identically.
        html = "<p>\n  <span>only</span>\n</p>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<p><span>only</span></p>")
      end

      it "strips whitespace when an inline closer butts against a block closer" do
        html = "<div>text<a>x</a>\n</div>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<div>text<a>x</a></div>")
      end

      it "strips whitespace when a block opener is followed by an inline child" do
        html = "<li>\n  <a href=\"x\">link</a>\n</li>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<li><a href=\"x\">link</a></li>")
      end

      it "does not collapse whitespace runs in body text" do
        html = "<p>two  spaces</p>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("two  spaces")
      end

      it "does not introduce whitespace where there was none" do
        html = "<a>x</a><b>y</b>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<a>x</a><b>y</b>")
      end
    end

    describe "protected blocks (whitespace-sensitive elements)" do
      it "preserves content inside <pre><code> unchanged" do
        html = "<pre><code>  line1\n    line2\n  line3</code></pre>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("  line1\n    line2\n  line3")
      end

      it "preserves inline <code> whitespace exactly" do
        html = "<p>Use <code>two   spaces</code> here</p>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("<code>two   spaces</code>")
      end

      it "preserves <textarea> content as-is" do
        html = "<form>\n  <textarea>line 1\n  line 2\nline 3</textarea>\n</form>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("<textarea>line 1\n  line 2\nline 3</textarea>")
      end

      it "preserves <script> body unchanged" do
        html = "<head>\n  <script>\n    if (a < b) {\n      foo();\n    }\n  </script>\n</head>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("if (a < b) {\n      foo();\n    }")
      end

      it "preserves <style> body unchanged" do
        html = "<head><style>\n  .x {\n    color: red;\n  }\n</style></head>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain(".x {\n    color: red;\n  }")
      end

      it "preserves <svg> subtree unchanged" do
        html = "<div>\n  <svg width=\"10\">\n    <text x=\"0\" y=\"0\">hi</text>\n  </svg>\n</div>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("<svg width=\"10\">\n    <text x=\"0\" y=\"0\">hi</text>\n  </svg>")
      end

      it "does not pair an opening <pre> with a different protected closer" do
        # Regression: prior alternation-based regex could match
        # `<pre>...</script>` across a mix of protected tags. With per-tag
        # passes each tag's content is captured independently.
        html = "<pre>first</pre>\n<script>second</script>\n<pre>third</pre>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("<pre>first</pre>")
        result.should contain("<script>second</script>")
        result.should contain("<pre>third</pre>")
      end

      it "does not let a literal <script> string inside <style> derail extraction" do
        # `<style>` is extracted before `<script>` precisely so the
        # script pass cannot mis-pair a real `</script>` elsewhere
        # with a `<script>` text fragment that lived inside CSS.
        html = "<style>p::before { content: \"<script>\" }</style>\n<p>hi</p>\n<script>real()</script>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("<style>p::before { content: \"<script>\" }</style>")
        result.should contain("<script>real()</script>")
        result.should contain("<p>hi</p>")
      end

      it "preserves XML comments inside <svg>" do
        html = "<div>\n  <svg><!-- generator note --><circle/></svg>\n</div>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("<!-- generator note -->")
      end

      it "cleans template-induced whitespace inside pre/code" do
        # The protection covers <pre> first, so its content is opaque
        # afterward. Whitespace inside the <code> alone (without a
        # surrounding <pre>) is preserved verbatim too.
        html = "<pre><code>x\n  y</code></pre>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("x\n  y")
      end

      it "strips whitespace between a block tag and a protected-block sibling" do
        # <pre> is whitespace-sensitive (protected) AND a block element.
        # Indentation between an outer block and a <pre> placeholder
        # should be removed since <pre>'s body is opaque and both
        # neighbours are block.
        html = "<div>\n  <pre>x</pre>\n</div>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<div><pre>x</pre></div>")
      end

      it "keeps one space between two inline protected siblings" do
        # <code> placeholders are inline. Two inline neighbours keep a
        # single space.
        html = "<p><code>a</code>   <code>b</code></p>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<p><code>a</code> <code>b</code></p>")
      end

      it "strips whitespace between an inline tag and an inline protected sibling at a block boundary" do
        # `<button>` (inline) wraps an `<svg>` (inline, protected). The
        # surrounding `<div>` is block, so whitespace between `<div>`
        # and `<button>` collapses; whitespace inside `<button>`
        # around the `<svg>` stays one space (inline neighbours).
        html = "<div>\n  <button>\n    <svg><path/></svg>\n    label\n  </button>\n</div>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should contain("<div><button>")
        result.should contain("<svg><path/></svg>")
        result.should_not contain("\n  <button")
      end
    end

    describe "edge cases" do
      it "treats uppercase tag names the same as lowercase" do
        html = "<DIV>\n  <P>hi</P>\n</DIV>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<DIV><P>hi</P></DIV>")
      end

      it "collapses whitespace around self-closing void elements between blocks" do
        html = "<head>\n  <meta charset=\"utf-8\"/>\n  <link rel=\"icon\" href=\"x\"/>\n</head>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<head><meta charset=\"utf-8\"/><link rel=\"icon\" href=\"x\"/></head>")
      end

      it "preserves DOCTYPE and collapses whitespace before <html>" do
        html = "<!doctype html>\n<html>\n  <head></head>\n</html>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should start_with("<!doctype html>")
        result.should contain("<html><head></head></html>")
      end
    end

    describe "intra-tag whitespace collapse" do
      it "collapses runs of whitespace between attributes to a single space" do
        html = "<a   href=\"/x\"   class=\"y\">link</a>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<a href=\"/x\" class=\"y\">link</a>")
      end

      it "strips trailing whitespace before the closing >" do
        html = "<a href=\"/x\"   >link</a>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<a href=\"/x\">link</a>")
      end

      it "collapses newlines between attributes spanning multiple lines" do
        html = "<svg\n  width=\"10\"\n  height=\"10\"\n  viewBox=\"0 0 10 10\">x</svg>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        # <svg> is protected — its body is opaque — but the *opening*
        # tag is part of the protected match too, so it survives
        # untouched. The collapse below confirms a non-protected
        # multi-line tag gets squashed.
        result.should contain("<svg")
      end

      it "collapses multi-line attribute lists on a normal tag" do
        html = "<a\n  href=\"/x\"\n  class=\"y\"\n  data-x=\"1\"\n>link</a>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<a href=\"/x\" class=\"y\" data-x=\"1\">link</a>")
      end

      it "preserves whitespace inside quoted attribute values" do
        html = "<a title=\"two  spaces\"   class=\"y\">link</a>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<a title=\"two  spaces\" class=\"y\">link</a>")
      end

      it "preserves single-quoted attribute values verbatim" do
        html = "<a data-x='hello  world'   data-y='1'>x</a>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<a data-x='hello  world' data-y='1'>x</a>")
      end

      it "handles tags with no attributes unchanged" do
        html = "<div><p>x</p></div>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<div><p>x</p></div>")
      end

      it "does not touch text content between tags" do
        html = "<p>two  spaces  and  more</p>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<p>two  spaces  and  more</p>")
      end

      it "leaves DOCTYPE unchanged" do
        html = "<!DOCTYPE html><html><head></head></html>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should start_with("<!DOCTYPE html>")
      end

      it "handles tags containing > inside a quoted attribute value" do
        html = "<a title=\"x > y\"   class=\"z\">link</a>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<a title=\"x > y\" class=\"z\">link</a>")
      end

      it "collapses whitespace before /> on void elements" do
        html = "<meta charset=\"utf-8\"   />"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<meta charset=\"utf-8\"/>")
      end
    end

    describe "trailing and blank-line whitespace" do
      it "strips trailing spaces from each line" do
        html = "<div>A</div>   \n<div>B</div>\t\t\n<div>C</div>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<div>A</div><div>B</div><div>C</div>")
      end

      it "collapses runs of blank lines" do
        html = "<p>A</p>\n\n\n\n<p>B</p>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<p>A</p><p>B</p>")
      end
    end
  end
end
