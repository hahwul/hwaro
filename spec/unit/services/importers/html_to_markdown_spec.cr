require "../../../spec_helper"

describe Hwaro::Services::Importers::HtmlToMarkdown do
  describe ".convert" do
    it "converts headings" do
      Hwaro::Services::Importers::HtmlToMarkdown.convert("<h1>Title</h1>").should eq("# Title")
      Hwaro::Services::Importers::HtmlToMarkdown.convert("<h2>Sub</h2>").should eq("## Sub")
      Hwaro::Services::Importers::HtmlToMarkdown.convert("<h3>Sub3</h3>").should eq("### Sub3")
    end

    it "converts paragraphs" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert("<p>Hello world</p>")
      result.should eq("Hello world")
    end

    it "converts bold text" do
      Hwaro::Services::Importers::HtmlToMarkdown.convert("<strong>bold</strong>").should eq("**bold**")
      Hwaro::Services::Importers::HtmlToMarkdown.convert("<b>bold</b>").should eq("**bold**")
    end

    it "converts italic text" do
      Hwaro::Services::Importers::HtmlToMarkdown.convert("<em>italic</em>").should eq("*italic*")
      Hwaro::Services::Importers::HtmlToMarkdown.convert("<i>italic</i>").should eq("*italic*")
    end

    it "converts links" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(%(<a href="https://example.com">Link</a>))
      result.should eq("[Link](https://example.com)")
    end

    it "converts images" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(%(<img src="/img.png" alt="Alt text" />))
      result.should eq("![Alt text](/img.png)")
    end

    it "converts an uppercase closing anchor tag" do
      # The anchor pass is skipped for documents with no closing tag at all,
      # and that probe has to be case-insensitive like the conversion itself.
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(%(<A HREF="https://example.com">Link</A>))
      result.should eq("[Link](https://example.com)")
    end

    # Deterministic half of the quadratic-anchor regression: the anchor body is
    # BOUNDED, so a `<a href=…>` that never closes costs a fixed scan instead of
    # a scan to end-of-document. Asserted on behaviour, not on a clock.
    it "bounds the anchor body instead of scanning to end of document" do
      max = Hwaro::Services::Importers::HtmlToMarkdown::MAX_INLINE_BODY_CHARS

      # Just inside the bound: still converted.
      inside = "y" * (max - 1)
      Hwaro::Services::Importers::HtmlToMarkdown
        .convert(%(<a href="/x">#{inside}</a>))
        .should eq("[#{inside}](/x)")

      # Past it: the regex gives up rather than rescanning, and the text
      # survives via the tag-stripping pass. This is what makes an unclosed
      # anchor O(1) instead of O(remaining document).
      outside = "y" * (max + 1)
      Hwaro::Services::Importers::HtmlToMarkdown
        .convert(%(<a href="/x">#{outside}</a>))
        .should eq(outside)
    end

    it "skips the anchor pass for a document with no closing anchor tag" do
      # Cheap short-circuit, assertable without timing it.
      Hwaro::Services::Importers::HtmlToMarkdown
        .anchor_pass_applicable?(%(<a href="x">) * 100).should be_false
      Hwaro::Services::Importers::HtmlToMarkdown
        .anchor_pass_applicable?(%(<a href="x">t</A>)).should be_true
    end

    it "converts a document full of unclosed anchors without quadratic blowup" do
      # Smoke half of the same regression, kept IN ADDITION to the deterministic
      # examples above (a timing assertion alone is a function of machine load).
      # Measured pre-fix: 1.4 s for 20k unclosed anchors, 6.0 s for 40k, while
      # the same count of CLOSED anchors — a 1.4x larger document — took 0.07 s.
      # MAX_REGEX_HTML_BYTES (4 MB) still admits ~175k of them, so it never
      # bounded this. Untrusted WXR exports reach here.
      #
      # The budget is deliberately loose — the fixed path finishes in
      # milliseconds — so it only trips on the seconds-scale blowup it guards
      # and not on a slow CI machine.
      html = %(<a href="x">) * 40_000

      started = Time.instant
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      elapsed = Time.instant - started

      # Output is unchanged: with no `</a>` there was never a link to convert,
      # so the tags fall through to the tag-stripping pass exactly as before.
      result.should be_empty
      elapsed.should be < 3.seconds
    end

    it "drops a javascript: link href but keeps the text (no live XSS in imported content)" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(%(<a href="javascript:alert(document.cookie)">Click</a>))
      result.should eq("Click")
      result.should_not contain("javascript:")
    end

    it "drops a javascript: image src but keeps the alt text" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(%(<img src="javascript:alert(1)" alt="x" />))
      result.should_not contain("javascript:")
    end

    it "drops a non-image data: link" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(%(<a href="data:text/html,<script>alert(1)</script>">x</a>))
      result.should_not contain("data:text/html")
    end

    it "converts unordered lists" do
      html = "<ul><li>One</li><li>Two</li></ul>"
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      result.should contain("- One")
      result.should contain("- Two")
    end

    it "converts ordered lists" do
      html = "<ol><li>First</li><li>Second</li></ol>"
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      result.should contain("1. First")
      result.should contain("2. Second")
    end

    it "converts code blocks" do
      html = "<pre><code>puts 1</code></pre>"
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      result.should contain("```")
      result.should contain("puts 1")
    end

    it "converts inline code" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert("<code>foo</code>")
      result.should eq("`foo`")
    end

    it "converts blockquotes" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert("<blockquote>Quote here</blockquote>")
      result.should contain("> Quote here")
    end

    it "converts strikethrough" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert("<del>removed</del>")
      result.should eq("~~removed~~")
    end

    it "decodes HTML entities" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert("&amp; &lt; &gt; &quot;")
      result.should eq("& < > \"")
    end

    it "decodes an in-range numeric entity to its codepoint" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert("a &#128512; b")
      result.should eq("a 😀 b")
    end

    it "drops a numeric entity that overflows Int32 instead of crashing" do
      # &#99999999999999999999; would raise ArgumentError on to_i; it must be
      # dropped (out of Unicode range) while the surrounding text survives.
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert("<p>x &#99999999999999999999; y</p>")
      result.should contain("x")
      result.should contain("y")
      result.should_not contain("9999")
    end

    it "strips unknown tags" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert("<div><span>text</span></div>")
      result.should eq("text")
    end

    it "returns empty string for empty input" do
      Hwaro::Services::Importers::HtmlToMarkdown.convert("").should eq("")
    end

    it "handles complex nested HTML" do
      html = "<p>Hello <strong>bold <em>and italic</em></strong> world</p>"
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      result.should contain("**bold *and italic***")
    end

    it "converts a table with <thead> and <tbody> into a Markdown pipe-table" do
      html = <<-HTML
        <table>
          <thead><tr><th>A</th><th>B</th></tr></thead>
          <tbody>
            <tr><td>1</td><td>2</td></tr>
            <tr><td>3</td><td>4</td></tr>
          </tbody>
        </table>
        HTML
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      result.should contain("| A | B |")
      result.should contain("| --- | --- |")
      result.should contain("| 1 | 2 |")
      result.should contain("| 3 | 4 |")
    end

    it "promotes the first row to a header when no <th> is present" do
      html = "<table><tr><td>x</td><td>y</td></tr><tr><td>1</td><td>2</td></tr></table>"
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      result.should contain("| x | y |")
      result.should contain("| --- | --- |")
      result.should contain("| 1 | 2 |")
    end

    it "escapes pipe characters inside table cells" do
      html = "<table><tr><th>k</th><th>v</th></tr><tr><td>a</td><td>x | y</td></tr></table>"
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      result.should contain(%q(| a | x \| y |))
    end

    it "keeps entity-encoded markup in prose as text, not live HTML" do
      # The author wrote `&lt;script&gt;` to SHOW the tag. Decoding it to a
      # bare `<script>` made the Markdown renderer emit a live, unclosed
      # script element that swallowed the rest of the page.
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert("<p>Use the &lt;script&gt; tag &amp; the &lt;!-- comment --&gt;.</p>")
      result.should eq("Use the &lt;script> tag & the &lt;!-- comment -->.")
      html = Hwaro::Content::Processors::Markdown.new.render(result)[0]
      html.should_not contain("<script>")
      html.should contain("&lt;script&gt;")
    end

    it "keeps a literal entity name in prose literal" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert("<p>Write &amp;copy; for ©, or &mdash;</p>")
      result.should eq("Write &amp;copy; for ©, or &mdash;")
    end

    it "decodes inline code exactly once and leaves it unescaped" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert("<p>Wrap it in <code>&lt;div&gt;</code> &amp; done</p>")
      result.should eq("Wrap it in `<div>` & done")
    end

    it "keeps links, emphasis and code inside list items" do
      html = %(<ul><li><a href="https://crystal-lang.org">Crystal</a> is <strong>fast</strong></li><li>Read <code>docs</code> and <em>enjoy</em></li></ul>)
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      result.should eq("- [Crystal](https://crystal-lang.org) is **fast**\n- Read `docs` and *enjoy*")
    end

    it "keeps links and code inside table cells" do
      html = %(<table><tr><th>Name</th><th>Link</th></tr><tr><td><code>a|b</code></td><td><a href="https://hwaro.dev">site</a></td></tr></table>)
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      result.should contain(%q(| `a\|b` | [site](https://hwaro.dev) |))
    end

    it "keeps the paragraphs of a blockquote apart" do
      html = %(<blockquote class="wp-block-quote"><p>First.</p><p>Second.</p><cite>Someone</cite></blockquote>)
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      result.should eq("> First.\n>\n> Second.\n>\n> Someone")
    end

    it "unwraps a [caption] shortcode into the image and its caption" do
      html = %([caption id="attachment_12" align="aligncenter" width="300"]<img src="https://example.com/cat.jpg" alt="A cat" width="300" /> My lovely cat[/caption])
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      result.should eq("![A cat](https://example.com/cat.jpg)\n\nMy lovely cat")
    end

    it "reads a pre-3.4 [caption] whose text is an attribute" do
      html = %([caption id="a" caption="Old caption"]<a href="https://example.com/big.jpg"><img src="https://example.com/cat.jpg" alt="" /></a>[/caption])
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      result.should eq("[![](https://example.com/cat.jpg)](https://example.com/big.jpg)\n\nOld caption")
    end

    it "keeps WordPress's <!--more--> tag as hwaro's excerpt marker" do
      html = "<!-- wp:paragraph -->\n<p>Teaser.</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:more -->\n<!--more Keep reading-->\n<!-- /wp:more -->\n\n<p>Rest.</p>"
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      result.should eq("Teaser.\n\n<!-- more -->\n\nRest.")
    end

    it "moves edge whitespace outside emphasis delimiters" do
      result = Hwaro::Services::Importers::HtmlToMarkdown.convert("<p>This is <strong>bold </strong>text and <em> spaced</em>.</p>")
      result.should eq("This is **bold** text and  *spaced*.")
    end
  end
end
