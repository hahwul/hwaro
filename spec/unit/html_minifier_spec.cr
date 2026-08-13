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

    describe "inline replaced elements (A14)" do
      # iframe/video/audio/canvas (and embed/object) default to
      # display:inline — whitespace adjacent to them is a rendered
      # space and must survive minification.
      it "keeps a space between an inline closer and a video element" do
        html = "<a>x</a>\n<video src=\"v.mp4\"></video>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<a>x</a> <video src=\"v.mp4\"></video>")
      end

      it "treats iframe, audio and canvas as inline" do
        Hwaro::Utils::HtmlMinifier.minify("<span>see</span>\n<iframe src=\"x\"></iframe>")
          .should eq("<span>see</span> <iframe src=\"x\"></iframe>")
        Hwaro::Utils::HtmlMinifier.minify("<em>a</em>  <audio controls></audio>")
          .should eq("<em>a</em> <audio controls></audio>")
        Hwaro::Utils::HtmlMinifier.minify("<b>x</b>\n<canvas></canvas>")
          .should eq("<b>x</b> <canvas></canvas>")
      end

      it "treats embed and object as inline" do
        Hwaro::Utils::HtmlMinifier.minify("<em>a</em>\n<embed src=\"x\">")
          .should eq("<em>a</em> <embed src=\"x\">")
        Hwaro::Utils::HtmlMinifier.minify("<em>a</em>\n<object data=\"x\"></object>")
          .should eq("<em>a</em> <object data=\"x\"></object>")
      end

      it "still strips whitespace between a block neighbour and a video element" do
        html = "<div>\n  <video src=\"v.mp4\"></video>\n</div>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<div><video src=\"v.mp4\"></video></div>")
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

      it "scrubs a counterfeit preserve token's NUL delimiters on entry" do
        # This is a NUL-SCRUB assertion, not a guard assertion: minify() strips
        # every NUL before extraction, so the forged sentinel is inert literal
        # text by the time restore runs and neither the to_i? nor the bounds
        # branch is reached. (Asserting otherwise here is what let a mutation
        # delete both guards with the whole file still green — the guards are
        # pinned directly, in ".restore_sensitive_blocks" below.)
        html = "<pre>real</pre><p>\u{0}HW_HTML_PB_999\u{0}</p>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<pre>real</pre><p>HW_HTML_PB_999</p>")
        result.should_not contain("\u{0}")
      end

      it "scrubs the NUL delimiters of an index that would overflow Int32" do
        # Same: what this pins is that minification completes and emits the
        # digits as inert text, with the delimiters gone.
        html = "<pre>real</pre><p>\u{0}HW_HTML_PB_99999999999999999999\u{0}</p>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<pre>real</pre><p>HW_HTML_PB_99999999999999999999</p>")
      end

      it "emits the same bytes with and without minification for a NUL-bearing page" do
        # The scrub used to live only inside minify(), so `hwaro build` wrote
        # the raw NUL while `hwaro build --minify` dropped it — an optional
        # whitespace pass silently changing author-controlled page content.
        # scrub_nul is now applied by the render phase on both paths.
        html = "<p>a\u{0}b</p>"
        Hwaro::Utils::HtmlMinifier.scrub_nul(html).should eq("<p>ab</p>")
        Hwaro::Utils::HtmlMinifier.minify(html).should eq(Hwaro::Utils::HtmlMinifier.scrub_nul(html))
      end
    end

    # Counterfeit-token guards, pinned directly. They are unreachable through
    # `minify` (its NUL scrub defuses any forged sentinel first), so driving
    # them through the public entry point tests nothing — a mutation deleting
    # both `to_i?` and the bounds check kept all 65 examples of this file green.
    describe ".restore_sensitive_blocks" do
      it "leaves an out-of-range token untouched instead of indexing past the array" do
        html = "<p>\u{0}HW_HTML_PB_999\u{0}</p>"
        result = Hwaro::Utils::HtmlMinifier.restore_sensitive_blocks(html, ["<pre>real</pre>"])
        result.should eq(html)
      end

      it "leaves a token whose index overflows Int32 untouched instead of raising" do
        # `$1.to_i` would raise ArgumentError here and abort the page.
        html = "<p>\u{0}HW_HTML_PB_99999999999999999999\u{0}</p>"
        result = Hwaro::Utils::HtmlMinifier.restore_sensitive_blocks(html, ["<pre>real</pre>"])
        result.should eq(html)
      end

      it "restores a real token" do
        # Control: the guards must not break the substitution they wrap.
        result = Hwaro::Utils::HtmlMinifier.restore_sensitive_blocks(
          "<p>\u{0}HW_HTML_PB_0\u{0}</p>", ["<pre>real</pre>"]
        )
        result.should eq("<p><pre>real</pre></p>")
      end

      it "terminates on a self-referential token instead of growing forever" do
        # The pass cap is the second layer behind the NUL scrub: a preserved
        # block that expands to a token pointing back at itself would otherwise
        # add one copy per pass and never reach a fixed point.
        result = Hwaro::Utils::HtmlMinifier.restore_sensitive_blocks(
          "<p>\u{0}HW_HTML_PB_0\u{0}</p>", ["x\u{0}HW_HTML_PB_0\u{0}"]
        )
        result.size.should be < 200
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

      it "preserves UTF-8 in attribute values when stripping space before />" do
        # Regression: a prior implementation used char-indexed
        # `body[0, body.bytesize - 2]` to drop the trailing ` /`,
        # which over-ran the string for multi-byte UTF-8 and left
        # a stray `/` in the output.
        html = "<img alt=\"안녕 세계\"   />"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<img alt=\"안녕 세계\"/>")
      end

      it "preserves UTF-8 in attribute values when collapsing inter-attribute whitespace" do
        html = "<a   title=\"안녕\"   class=\"y\">x</a>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<a title=\"안녕\" class=\"y\">x</a>")
      end
    end

    describe "non-breaking and other Unicode spaces" do
      # `\s` under PCRE2's UCP flag (which Crystal enables) matches U+00A0
      # and friends, so the inter-token pass used to treat rendered `&nbsp;`
      # text as collapsible layout whitespace.
      it "keeps a non-breaking space between inline siblings" do
        html = "<em>a</em>\u{00A0}<em>b</em>"
        Hwaro::Utils::HtmlMinifier.minify(html).should eq(html)
      end

      it "keeps a non-breaking space between block siblings" do
        html = "<p>a</p>\u{00A0}<p>b</p>"
        Hwaro::Utils::HtmlMinifier.minify(html).should eq(html)
      end

      it "keeps an ideographic space between tags" do
        html = "<p>a</p>\u{3000}<p>b</p>"
        Hwaro::Utils::HtmlMinifier.minify(html).should eq(html)
      end

      it "still collapses ASCII whitespace next to a non-breaking space" do
        html = "<p>a</p>\n<p>b</p>"
        Hwaro::Utils::HtmlMinifier.minify(html).should eq("<p>a</p><p>b</p>")
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

    describe "forged protected-block placeholders" do
      # The protected-block sentinels are `\x00`-delimited on the assumption
      # that NUL never reaches the rendered page. It does: a NUL inside a
      # data-file value (data/*.json, data/*.yml) is emitted verbatim by the
      # template, so author-controlled text can forge a real token.
      it "does not expand a forged token into a preserved block" do
        html = "<div>\u0000HW_HTML_PB_0\u0000</div><script>x</script>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        # Previously the forged token was indistinguishable from the sentinel
        # minted for the <script>, so the restore pass injected a second copy
        # of the script into the <div>.
        result.should eq("<div>HW_HTML_PB_0</div><script>x</script>")
      end

      it "terminates when a forged token names the block that contains it" do
        # NOTE: on the unfixed minifier this call never returns — restoring
        # index 0 re-emits the token, so each pass wraps another <script>
        # around it and the fixed-point loop grows the string forever.
        html = "<script>\u0000HW_HTML_PB_0\u0000</script>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<script>HW_HTML_PB_0</script>")
      end

      it "still restores legitimately nested protected blocks" do
        # `style` is extracted before `script`, so the script's preserved body
        # holds a style placeholder that only a second restore pass resolves.
        # The pass cap must stay wide enough for that (depth <= preserves.size).
        html = "<div> <script>var x = \"<style>body{}</style>\";</script> </div>"
        result = Hwaro::Utils::HtmlMinifier.minify(html)
        result.should eq("<div><script>var x = \"<style>body{}</style>\";</script></div>")
      end
    end
  end
end
