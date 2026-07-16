require "../spec_helper"
require "../../src/content/processors/markdown_extensions"

private def make_config(**opts) : Hwaro::Models::MarkdownConfig
  config = Hwaro::Models::MarkdownConfig.new
  config.task_lists = opts[:task_lists]? || false
  config.footnotes = opts[:footnotes]? || false
  config.definition_lists = opts[:definition_lists]? || false
  config.mermaid = opts[:mermaid]? || false
  config.math = opts[:math]? || false
  config.admonitions = opts[:admonitions]? || false
  config.heading_ids = opts[:heading_ids]? || false
  config.ins = opts[:ins]? || false
  config.mark = opts[:mark]? || false
  config.sub = opts[:sub]? || false
  config.sup = opts[:sup]? || false
  config.attributes = opts[:attributes]? || false
  config
end

describe Hwaro::Content::Processors::MarkdownExtensions do
  describe "task lists" do
    it "converts unchecked task items" do
      content = "- [ ] Todo item"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_task_lists(content)
      result.should contain("<input type=\"checkbox\" disabled>")
      result.should_not contain("checked")
    end

    it "converts checked task items" do
      content = "- [x] Done item"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_task_lists(content)
      result.should contain("<input type=\"checkbox\" checked disabled>")
    end

    it "handles uppercase X" do
      content = "- [X] Done"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_task_lists(content)
      result.should contain("checked")
    end

    it "preserves non-task list items" do
      content = "- Normal item"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_task_lists(content)
      result.should eq("- Normal item")
    end

    it "handles mixed list items" do
      content = "- [x] Done\n- [ ] Todo\n- Normal"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_task_lists(content)
      result.should contain("checked disabled")
      result.should contain("checkbox\" disabled")
      result.should contain("- Normal")
    end
  end

  describe "definition lists" do
    it "converts term and definition" do
      content = "Term\n: Definition text"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain("<dl>")
      result.should contain("<dt>Term</dt>")
      result.should contain("<dd>Definition text</dd>")
      result.should contain("</dl>")
    end

    it "handles multiple definitions for one term" do
      content = "Term\n: First definition\n: Second definition"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain("<dt>Term</dt>")
      result.should contain("<dd>First definition</dd>")
      result.should contain("<dd>Second definition</dd>")
    end

    it "preserves non-definition content" do
      content = "Normal paragraph\n\nAnother one"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should_not contain("<dl>")
      result.should contain("Normal paragraph")
    end

    it "does not emit an empty <dl> when a blank line precedes a ': ' line" do
      # An orphan definition (blank term line) must pass through unchanged
      # rather than producing a stray empty <dl></dl>.
      content = "\n: orphan def\n\nReal paragraph"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should_not contain("<dl>")
      result.should contain(": orphan def")
      result.should contain("Real paragraph")
    end
  end

  describe "footnotes" do
    it "replaces footnote references with superscript links" do
      content = "Text with a footnote[^1].\n\n[^1]: This is the footnote."
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_footnotes(content)
      result.should contain("fnref-1")
      result.should contain("fn-1")
      result.should contain("[1]")
      result.should_not contain("[^1]: This is the footnote.")
    end

    it "handles multiple footnotes" do
      content = "First[^a] and second[^b].\n\n[^a]: Note A\n[^b]: Note B"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_footnotes(content)
      result.should contain("fnref-a")
      result.should contain("fnref-b")
      result.should contain("[1]")
      result.should contain("[2]")
    end

    it "postprocess generates footnotes section" do
      html = "<p>Text<sup class=\"footnote-ref\"><a href=\"#fn-1\" id=\"fnref-1\">[1]</a></sup></p>\n<!--HWARO-FOOTNOTES-START-->\n<!--HWARO-FN:1:1:Footnote text-->\n<!--HWARO-FOOTNOTES-END-->\n"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_footnotes(html)
      result.should contain("<section class=\"footnotes\">")
      result.should contain("Footnote text")
      result.should contain("fn-1")
      result.should contain("footnote-backref")
    end

    it "does not promote author-typed HWARO markers into a footnotes section (injection)" do
      # A page literally containing the engine's internal comment markers must
      # NOT be turned into a fabricated footnotes section.
      content = "Text.\n\n<!--HWARO-FOOTNOTES-START-->\n<!--HWARO-FN:x:1:injected-->\n<!--HWARO-FOOTNOTES-END-->\n\nBye."
      pre = Hwaro::Content::Processors::MarkdownExtensions.preprocess_footnotes(content)
      post = Hwaro::Content::Processors::MarkdownExtensions.postprocess_footnotes(pre)
      post.should_not contain("class=\"footnotes\"")
      post.should_not contain("injected </a>") # not rendered as a real footnote
    end

    it "leaves footnote def/ref syntax inside a fenced code block verbatim" do
      content = "```\n[^1]: documentation example def\n```\n\nReal ref[^1].\n\n[^1]: actual def"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_footnotes(content)
      # The def line inside the fence must NOT be eaten...
      result.should contain("documentation example def")
      # ...but the real def outside the fence IS extracted and its ref linked.
      result.should contain("fnref-1")
      result.should_not contain("[^1]: actual def")
    end

    it "does not drop footnotes after a >=4-space-indented ``` (indented code, not a fence)" do
      # A line indented >=4 spaces beginning with ``` is INDENTED code per
      # CommonMark, not a fence opener; mis-reading it stuck the fence state open
      # and dropped every footnote after it.
      content = "Intro.\n\n    ```\n\nReal ref[^1].\n\n[^1]: the real def"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_footnotes(content)
      result.should contain("fnref-1")
      result.should_not contain("[^1]: the real def")
    end

    it "returns unchanged html if no footnotes" do
      html = "<p>No footnotes here</p>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_footnotes(html)
      result.should eq(html)
    end
  end

  describe "math" do
    it "wraps display math in div" do
      content = "$$E = mc^2$$"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should contain("math-display")
      result.should contain("\\[E = mc^2\\]")
    end

    it "wraps inline math in span" do
      content = "The formula $x^2$ is simple."
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should contain("math-inline")
      # Doubled backslashes so Markd's inline parser yields `\(...\)` after rendering;
      # see "math (extended) keeps KaTeX delimiters" below.
      result.should contain("\\\\(x^2\\\\)")
    end

    it "does not match dollar signs with spaces" do
      content = "Price is $ 5 or $ 10"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should_not contain("math-inline")
    end

    it "escapes HTML in math" do
      content = "$$a < b > c$$"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should contain("&lt;")
      result.should contain("&gt;")
    end
  end

  describe "mermaid" do
    it "converts mermaid code blocks to div" do
      html = "<pre><code class=\"language-mermaid hljs\">graph LR\n  A --&gt; B</code></pre>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_mermaid(html)
      result.should contain("<div class=\"mermaid\">")
      # Browser decodes &gt; to > when Mermaid.js reads textContent
      result.should contain("A --&gt; B")
      result.should_not contain("<pre>")
    end

    it "does not modify non-mermaid code blocks" do
      html = "<pre><code class=\"language-javascript hljs\">const x = 1;</code></pre>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_mermaid(html)
      result.should contain("<pre>")
      result.should_not contain("mermaid")
    end
  end

  describe "task lists (extended)" do
    it "handles * marker" do
      content = "* [x] Done with star"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_task_lists(content)
      result.should contain("checked disabled")
    end

    it "handles + marker" do
      content = "+ [ ] Todo with plus"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_task_lists(content)
      result.should contain("<input type=\"checkbox\" disabled>")
    end

    it "handles indented task items" do
      content = "  - [x] Indented done\n    - [ ] Deeper indent"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_task_lists(content)
      result.should contain("checked disabled")
      result.should contain("checkbox\" disabled>")
    end

    it "does not match inside paragraphs (no list marker)" do
      content = "This is [x] not a task"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_task_lists(content)
      result.should eq(content)
    end

    it "handles empty content" do
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_task_lists("")
      result.should eq("")
    end
  end

  describe "definition lists (extended)" do
    it "escapes HTML in terms" do
      content = "<script>alert(1)</script>\n: Safe definition"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain("&lt;script&gt;")
      result.should_not contain("<script>alert")
    end

    it "escapes HTML in definitions" do
      content = "Term\n: <b>bold</b> text"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain("&lt;b&gt;")
    end

    it "does not create dl when definition is on first line only" do
      content = ": orphan definition"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      # No term before the definition, so it should not be parsed as dl
      result.should_not contain("<dl>")
    end

    it "handles definition with leading whitespace" do
      content = "Term\n  : Indented definition"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain("<dd>Indented definition</dd>")
    end

    it "handles multiple terms with blank line between groups" do
      content = "Term1\n: Def1\n\nTerm2\n: Def2"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain("<dt>Term1</dt>")
      result.should contain("<dd>Def1</dd>")
    end

    it "handles content before and after definition list" do
      content = "Intro paragraph\n\nTerm\n: Definition\n\nOutro paragraph"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain("Intro paragraph")
      result.should contain("<dl>")
      result.should contain("Outro paragraph")
    end

    it "does not infinite loop when empty line precedes orphan definition" do
      content = "\n: orphan definition"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should_not contain("<dt></dt>")
    end
  end

  describe "footnotes (extended)" do
    it "handles footnote keys with special characters (dashes)" do
      content = "Text[^my--note].\n\n[^my--note]: Note with dashes"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_footnotes(content)
      result.should contain("fnref-")
      result.should contain("[1]")
    end

    it "handles footnote keys with colons" do
      content = "Text[^key:val].\n\n[^key:val]: Note with colon"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_footnotes(content)
      result.should contain("[1]")
    end

    it "produces whitespace-free, matching anchors for keys with spaces" do
      # `[^my note]` must not emit `id="fn-my note"` (invalid id/fragment).
      # Forward (fnref/fn) and backward (backref) anchors must still match.
      content = "Text[^my note].\n\n[^my note]: Note with a space"
      pre = Hwaro::Content::Processors::MarkdownExtensions.preprocess_footnotes(content)
      pre.should_not contain("fn-my note")
      pre.should_not contain("fnref-my note")
      pre.should contain("id=\"fnref-my-note\"")
      pre.should contain("href=\"#fn-my-note\"")

      html = "<p>#{pre}</p>"
      post = Hwaro::Content::Processors::MarkdownExtensions.postprocess_footnotes(html)
      post.should contain("id=\"fn-my-note\"")
      post.should contain("href=\"#fnref-my-note\"")
      post.should_not contain("my note\"")
    end

    it "ignores undefined footnote references" do
      content = "Text[^undefined] here."
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_footnotes(content)
      result.should contain("[^undefined]")
    end

    it "handles duplicate references to same footnote" do
      content = "First[^1] and second[^1].\n\n[^1]: Shared note"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_footnotes(content)
      # Both should get the same number
      matches = result.scan(/\[1\]/)
      matches.size.should eq(2)
    end

    it "handles footnote content with HTML" do
      content = "Text[^1].\n\n[^1]: Note with <em>emphasis</em>"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_footnotes(content)
      result.should contain("HWARO-FN")
    end

    it "postprocess handles footnotes with special chars roundtrip" do
      # Simulate the preprocess -> postprocess cycle
      content = "Text[^a--b].\n\n[^a--b]: Note with -- dashes"
      preprocessed = Hwaro::Content::Processors::MarkdownExtensions.preprocess_footnotes(content)
      # Wrap in paragraph tags like Markd would
      html = "<p>#{preprocessed}</p>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_footnotes(html)
      result.should contain("<section class=\"footnotes\">")
      result.should contain("Note with -- dashes")
    end

    it "postprocess skips invalid footnote numbers" do
      html = "<p>Text</p>\n<!--HWARO-FOOTNOTES-START-->\n<!--HWARO-FN:key:0:text-->\n<!--HWARO-FOOTNOTES-END-->\n"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_footnotes(html)
      # num <= 0 should be skipped, resulting in no footnotes section
      result.should_not contain("<section class=\"footnotes\">")
    end
  end

  describe "math (extended)" do
    it "handles multiline display math" do
      content = "$$\na + b\n= c\n$$"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should contain("math-display")
      result.should contain("a + b")
    end

    it "does not match escaped dollar signs" do
      content = "Price is \\$5 each"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should_not contain("math-inline")
    end

    it "does not match dollar amount like $100" do
      content = "It costs $100 to buy"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      # $100 ends with digit, should not match due to (?!\d) lookahead
      result.should_not contain("math-inline")
    end

    it "handles math with ampersand" do
      content = "$$a & b$$"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should contain("&amp;")
    end

    it "handles multiple inline math expressions" do
      content = "Both $x$ and $y$ are variables."
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      matches = result.scan(/math-inline/)
      matches.size.should eq(2)
    end

    it "handles empty display math" do
      content = "$$$$"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should contain("math-display")
    end

    # Regression for https://github.com/hahwul/hwaro/issues/484
    # Markd's inline parser interprets `\(` as a backslash-escape of `(`, so the
    # backslash needs to survive into the rendered HTML for KaTeX auto-render to
    # match the expression.
    it "keeps KaTeX delimiters in the rendered HTML for inline math" do
      cfg = make_config(math: true)
      html, _ = Hwaro::Processor::Markdown.render(
        "Inline $x^2 + y^2$ here.",
        markdown_config: cfg,
      )
      html.should contain(%(<span class="math math-inline">\\(x^2 + y^2\\)</span>))
      html.should_not contain(">(x^2 + y^2)<")
    end

    it "keeps KaTeX delimiters in the rendered HTML for display math" do
      cfg = make_config(math: true)
      html, _ = Hwaro::Processor::Markdown.render(
        "$$\nE = mc^2\n$$",
        markdown_config: cfg,
      )
      html.should contain(%(<div class="math math-display">\\[))
      html.should contain(%(\\]</div>))
    end

    it "keeps an escaped dollar inside inline math" do
      content = "The price $x = \\$5$ is fixed."
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.scan("math-inline").size.should eq(1)
      # The whole formula (including the escaped dollar) lands in the span;
      # nothing dangles after it.
      result.should contain("$5")
      result.should_not contain("5$")
    end

    it "leaves a body ending in a lone backslash unmatched" do
      content = "literal $a\\$ text"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should_not contain("math-inline")
    end

    it "does not pair display math across a blank line" do
      content = "before $$ stray\n\nprose here\n\n$$x$$"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should contain("$$ stray")
      result.should contain("prose here")
      result.scan("math-display").size.should eq(1)
    end

    it "does not pair display math across a whitespace-only line" do
      content = "$$ stray\n \t\nprose"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should_not contain("math-display")
    end

    it "renders mid-paragraph display math as an inline-safe span" do
      cfg = make_config(math: true)
      html, _ = Hwaro::Processor::Markdown.render(
        "Euler: $$e_a * e_b$$ inline.",
        markdown_config: cfg,
      )
      # Doubled delimiters and escaped `*`/`_` collapse back through Markd's
      # inline parser — no emphasis, no dropped brackets, wrapper stays a
      # span inside the paragraph.
      html.should contain(%(<span class="math math-display">\\[e_a * e_b\\]</span>))
      html.should_not contain("<em>")
      html.should_not contain("<div class=\"math math-display\">")
    end

    it "keeps standalone display math as a div HTML block" do
      cfg = make_config(math: true)
      html, _ = Hwaro::Processor::Markdown.render(
        "before\n\n$$\nx * y\n$$\n\nafter",
        markdown_config: cfg,
      )
      html.should contain(%(<div class="math math-display">\\[))
      html.should_not contain("math-display\">\\\\[")
    end

    it "keeps display math in a table cell as a div (raw HTML context)" do
      cfg = make_config(math: true)
      html, _ = Hwaro::Processor::Markdown.render(
        "| f |\n|---|\n| $$x$$ |",
        markdown_config: cfg,
      )
      html.should contain(%(<div class="math math-display">\\[x\\]</div>))
    end

    it "keeps a <code> span with a quoted '>' attribute opaque to math" do
      content = %(<code data-x="a>b">$x$</code> and $y$)
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should contain("$x$")
      result.scan("math-inline").size.should eq(1)
    end
  end

  describe "mermaid (extended)" do
    it "decodes &amp; in mermaid content" do
      html = "<pre><code class=\"language-mermaid\">A --&amp;gt;|label&amp;| B</code></pre>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_mermaid(html)
      result.should contain("<div class=\"mermaid\">")
      result.should contain("A --&gt;|label&| B")
    end

    it "handles mermaid block with multiple lines" do
      html = "<pre><code class=\"language-mermaid\">graph TD\n  A --> B\n  B --> C</code></pre>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_mermaid(html)
      result.should contain("<div class=\"mermaid\">")
      result.should contain("A --> B")
      result.should contain("B --> C")
      result.should_not contain("<pre>")
    end

    it "preserves multiple mermaid blocks" do
      html = "<pre><code class=\"language-mermaid\">graph LR\nA-->B</code></pre><p>text</p><pre><code class=\"language-mermaid\">pie\n\"A\": 50</code></pre>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_mermaid(html)
      matches = result.scan(/class="mermaid"/)
      matches.size.should eq(2)
    end
  end

  describe "preprocess integration" do
    it "applies all enabled extensions" do
      config = make_config(task_lists: true, footnotes: true, definition_lists: true, math: true)
      content = "- [x] Done\n\nTerm\n: Def\n\nNote[^1].\n\n[^1]: Footnote\n\n$x^2$"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess(content, config)
      result.should contain("checkbox")
      result.should contain("<dl>")
      result.should contain("fnref-1")
      result.should contain("math-inline")
    end

    it "skips disabled extensions" do
      config = make_config
      content = "- [ ] Todo\n\nTerm\n: Def"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess(content, config)
      result.should eq(content)
    end
  end

  describe "definition list with multiple blank lines" do
    it "keeps single dl across double blank lines between term groups" do
      content = "Term1\n: Def1\n\n\nTerm2\n: Def2"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.scan(/<dl>/).size.should eq(1)
      result.should contain("<dt>Term1</dt>")
      result.should contain("<dt>Term2</dt>")
    end

    it "keeps single dl across triple blank lines" do
      content = "Term1\n: Def1\n\n\n\nTerm2\n: Def2"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.scan(/<dl>/).size.should eq(1)
    end
  end

  describe "definition list inline markdown" do
    it "renders bold markdown inside terms" do
      content = "**Bold term**\n: Plain definition"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain("<dt><strong>Bold term</strong></dt>")
    end

    it "renders links inside definitions" do
      content = "Term\n: See [docs](https://example.com)"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain(%(<a href="https://example.com">docs</a>))
    end

    it "renders italic and code spans inside definitions" do
      content = "Term\n: *emphasis* and `inline code`"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain("<em>emphasis</em>")
      result.should contain("<code>inline code</code>")
    end

    it "renders strikethrough inside definitions" do
      content = "Term\n: ~~deprecated~~ feature"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain("<del>deprecated</del>")
    end

    it "still escapes raw HTML alongside inline markdown" do
      content = "Term\n: <b>raw</b> and **md bold**"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain("&lt;b&gt;raw&lt;/b&gt;")
      result.should contain("<strong>md bold</strong>")
    end

    it "rejects unsafe link schemes" do
      content = "Term\n: [click](javascript:alert(1))"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should_not contain("<a href")
      result.should contain("[click]")
    end
  end

  describe "admonitions" do
    it "rewrites a single-line GitHub-style note" do
      html = "<blockquote>\n<p>[!NOTE]\nUseful info here</p>\n</blockquote>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_admonitions(html)
      result.should contain(%(<div class="admonition admonition-note">))
      result.should contain(%(<p class="admonition-title">Note</p>))
      result.should contain("<p>Useful info here</p>")
      result.should_not contain("<blockquote>")
    end

    it "handles separate-paragraph body for warning" do
      html = "<blockquote>\n<p>[!WARNING]</p>\n<p>Body paragraph</p>\n</blockquote>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_admonitions(html)
      result.should contain(%(admonition-warning))
      result.should contain(%(<p class="admonition-title">Warning</p>))
      result.should contain("<p>Body paragraph</p>")
    end

    it "supports title-only admonition with no body" do
      html = "<blockquote>\n<p>[!TIP]</p>\n</blockquote>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_admonitions(html)
      result.should contain(%(admonition-tip))
      result.should contain(%(<p class="admonition-title">Tip</p>))
      result.should_not contain("<blockquote>")
    end

    it "recognises all five GitHub admonition types" do
      %w[NOTE TIP IMPORTANT WARNING CAUTION].each do |type|
        html = "<blockquote>\n<p>[!#{type}]\nbody</p>\n</blockquote>"
        result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_admonitions(html)
        result.should contain("admonition-#{type.downcase}")
      end
    end

    it "leaves regular blockquotes untouched" do
      html = "<blockquote>\n<p>Just a quote</p>\n</blockquote>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_admonitions(html)
      result.should eq(html)
    end

    it "ignores unknown admonition types" do
      html = "<blockquote>\n<p>[!UNKNOWN]\nbody</p>\n</blockquote>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_admonitions(html)
      result.should eq(html)
    end

    it "is case-sensitive on the type token" do
      html = "<blockquote>\n<p>[!note]\nbody</p>\n</blockquote>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_admonitions(html)
      result.should eq(html)
    end
  end

  describe "heading ids" do
    it "extracts id from `## Heading {#custom-id}`" do
      content = "## My Heading {#custom-id}"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_heading_ids(content)
      result.should eq("## My Heading <!--HID:custom-id-->")
    end

    it "preserves headings without an id marker" do
      content = "## Plain heading"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_heading_ids(content)
      result.should eq(content)
    end

    it "applies the marker to a rendered heading tag" do
      html = "<h2>My Heading <!--HID:custom-->\n</h2>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_heading_ids(html)
      result.should contain(%(<h2 id="custom">))
      result.should_not contain("HID:")
    end

    it "replaces an existing id attribute" do
      html = %(<h3 class="foo" id="auto-slug">Heading <!--HID:wanted--></h3>)
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_heading_ids(html)
      result.should contain(%(id="wanted"))
      result.should_not contain("auto-slug")
      result.should contain(%(class="foo"))
    end

    it "does not mistake data-id for an existing id attribute" do
      html = %(<h3 data-id="tracker">Heading <!--HID:wanted--></h3>)
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_heading_ids(html)
      result.should contain(%(data-id="tracker"))
      result.should contain(%(id="wanted"))
    end

    it "neutralizes an author-typed HID marker in prose" do
      cfg = make_config(heading_ids: true)
      html, _ = Hwaro::Processor::Markdown.render(
        "## Heading <!--HID:evil--> {#real}\n\ntext",
        markdown_config: cfg,
      )
      html.should contain(%(id="real"))
      html.should_not contain(%(id="evil"))
    end

    it "keeps author-typed markers verbatim in code spans and fences" do
      cfg = make_config(heading_ids: true, attributes: true)
      content = "Use `<!--HID:x-->` inline.\n\n```\n<!--HATTR:41-->\n```"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess(content, cfg)
      result.should contain("`<!--HID:x-->`")
      result.should contain("\n<!--HATTR:41-->\n")
    end

    it "resolves the marker on a heading with a quoted '>' attribute" do
      html = %(<h2 title="a > b">Heading <!--HID:wanted--></h2>)
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_heading_ids(html)
      result.should contain(%(id="wanted"))
      result.should contain(%(title="a > b"))
      result.should_not contain("HID:")
    end

    it "handles each heading level h1-h6" do
      (1..6).each do |level|
        content = "#{"#" * level} Heading {#h#{level}}"
        result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_heading_ids(content)
        result.should contain("<!--HID:h#{level}-->")
      end
    end

    it "renders end-to-end through Markdown.render" do
      cfg = make_config(heading_ids: true)
      html, _ = Hwaro::Processor::Markdown.render(
        "## Section {#intro}\n\nBody text.",
        markdown_config: cfg,
      )
      html.should contain(%(<h2 id="intro">))
      html.should_not contain("HID:")
    end

    it "leaves heading-id syntax inside fenced code blocks alone" do
      content = "```markdown\n## Example {#example}\n```\n\n## Real heading {#real}"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_heading_ids(content)
      # Inside the code fence: untouched
      result.should contain("## Example {#example}")
      # Outside the code fence: marker injected
      result.should contain("## Real heading <!--HID:real-->")
    end

    it "supports tilde-fenced code blocks" do
      content = "~~~\n## Example {#x}\n~~~"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_heading_ids(content)
      result.should contain("## Example {#x}")
      result.should_not contain("HID:")
    end

    it "matches headings indented up to 3 spaces (CommonMark)" do
      content = "   ## Indented heading {#deep}"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_heading_ids(content)
      result.should eq("   ## Indented heading <!--HID:deep-->")
    end

    it "does not match a heading-like line indented 4+ spaces (code block)" do
      content = "    ## Looks like heading {#nope}"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_heading_ids(content)
      result.should eq(content)
    end

    it "strips {#id} syntax under safe mode and skips marker injection" do
      content = "## Foo {#bar}"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_heading_ids(content, safe: true)
      result.should eq("## Foo")
      result.should_not contain("HID:")
      result.should_not contain("{#")
    end

    it "leaves a clean heading end-to-end under safe mode" do
      cfg = make_config(heading_ids: true)
      cfg.safe = true
      html, _ = Hwaro::Processor::Markdown.render(
        "## Foo {#bar}\n",
        safe: cfg.safe,
        markdown_config: cfg,
      )
      html.should contain("Foo")
      html.should_not contain("{#")
      html.should_not contain("raw HTML omitted")
    end
  end

  describe "heading ids (TOC dedup)" do
    it "de-duplicates identical custom IDs across both HTML and TOC" do
      cfg = make_config(heading_ids: true)
      content = "## A {#x}\n\nbody\n\n## B {#x}\n\nbody2\n"
      html, toc = Hwaro::Content::Processors::Markdown.new.render_with_anchors(
        content, markdown_config: cfg)
      html.scan(/<h2 id="x">/).size.should eq(1)
      html.scan(/<h2 id="x-1">/).size.should eq(1)
      toc.size.should eq(2)
      toc[0].id.should eq("x")
      toc[1].id.should eq("x-1")
    end

    it "de-duplicates raw HTML headings that share an existing id" do
      content = %(<h2 id="dup">First</h2>\n\n<h2 id="dup">Second</h2>\n)
      html, toc = Hwaro::Content::Processors::Markdown.new.render_with_anchors(content)
      html.scan(/id="dup"/).size.should eq(1)
      html.should contain(%(id="dup-1"))
      toc.size.should eq(2)
      toc[0].id.should eq("dup")
      toc[1].id.should eq("dup-1")
    end
  end

  describe "admonitions (limitations)" do
    it "closes early on a nested blockquote (documented v1 limitation)" do
      # Inner </blockquote> ends the lazy match, so the outer admonition body
      # is truncated before the second </blockquote>. This locks the current
      # behaviour; lifting the restriction would mean a nest-aware matcher.
      html = "<blockquote>\n<p>[!NOTE]\nouter</p>\n<blockquote>\n<p>inner</p>\n</blockquote>\n</blockquote>"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_admonitions(html)
      result.should contain("admonition-note")
      # Trailing outer </blockquote> is left behind in the output.
      result.scan(/<\/blockquote>/).size.should eq(1)
    end
  end

  describe "admonitions end-to-end" do
    it "renders `> [!NOTE]` blockquotes via Markdown.render" do
      cfg = make_config(admonitions: true)
      html, _ = Hwaro::Processor::Markdown.render(
        "> [!NOTE]\n> Pay attention.",
        markdown_config: cfg,
      )
      html.should contain(%(class="admonition admonition-note"))
      html.should contain("Pay attention.")
      html.should_not contain("<blockquote>")
    end

    it "leaves admonitions disabled when config flag is off" do
      cfg = make_config
      html, _ = Hwaro::Processor::Markdown.render(
        "> [!NOTE]\n> body",
        markdown_config: cfg,
      )
      html.should contain("<blockquote>")
      html.should contain("[!NOTE]")
    end
  end

  describe "strikethrough" do
    it "converts ~~text~~ to <del> in body text" do
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_strikethrough("Some ~~deleted~~ thing.")
      result.should contain("<del>deleted</del>")
    end

    it "leaves ~~ inside fenced code blocks alone" do
      content = "```\n~~not strike~~\n```\n\n~~yes strike~~"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_strikethrough(content)
      result.should contain("~~not strike~~")
      result.should contain("<del>yes strike</del>")
    end

    it "leaves ~~ inside inline code spans alone" do
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_strikethrough("inline `~~code~~` here, ~~real~~ there")
      result.should contain("`~~code~~`")
      result.should contain("<del>real</del>")
    end

    it "renders body strikethrough through the full pipeline" do
      cfg = make_config
      html, _ = Hwaro::Processor::Markdown.render("~~bye~~", markdown_config: cfg)
      html.should contain("<del>bye</del>")
    end
  end

  describe "footnote inline markdown" do
    it "renders inline markdown inside footnote bodies" do
      html = "<p>Text<sup class=\"footnote-ref\"><a href=\"#fn-1\" id=\"fnref-1\">[1]</a></sup></p>\n" \
             "<!--HWARO-FOOTNOTES-START-->\n" \
             "<!--HWARO-FN:1:1:Has `code` and *emphasis* and ~~strike~~-->\n" \
             "<!--HWARO-FOOTNOTES-END-->\n"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_footnotes(html)
      result.should contain("<code>code</code>")
      result.should contain("<em>emphasis</em>")
      result.should contain("<del>strike</del>")
    end

    it "blocks javascript: links inside footnote bodies" do
      html = "<p>x<sup class=\"footnote-ref\"><a href=\"#fn-1\" id=\"fnref-1\">[1]</a></sup></p>\n" \
             "<!--HWARO-FOOTNOTES-START-->\n" \
             "<!--HWARO-FN:1:1:bad [click](javascript:alert(1)) link-->\n" \
             "<!--HWARO-FOOTNOTES-END-->\n"
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_footnotes(html)
      result.should_not contain("href=\"javascript:")
    end
  end

  describe "nested fences (CommonMark closing-fence rules)" do
    it "leaves ``` examples nested inside ```` fences verbatim" do
      config = make_config(heading_ids: true)
      content = "````markdown\n```\n~~not strike~~\n```\n## Heading {#nope}\n````\n\n~~real~~"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess(content, config)
      result.should contain("~~not strike~~")
      result.should_not contain("HID:nope")
      result.should contain("<del>real</del>")
    end

    it "does not treat a ```lang line as closing an open fence" do
      content = "```text\n```ruby\n~~code~~\n```\n\n~~real~~"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess(content, make_config)
      result.should contain("~~code~~")
      result.should contain("<del>real</del>")
    end
  end

  describe "blockquoted fences" do
    it "leaves transforms alone inside a > ``` fence" do
      config = make_config(heading_ids: true, task_lists: true)
      content = "> ```\n> ~~x~~\n> - [ ] task\n> ## H {#nope}\n> ```\n\n~~real~~"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess(content, config)
      result.should contain("~~x~~")
      result.should contain("- [ ] task")
      result.should_not contain("HID:nope")
      result.should contain("<del>real</del>")
    end

    it "leaves $ and $$ alone inside a > ``` fence" do
      content = "> ```make\n> echo $$PATH $HOME\n> ```"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should eq(content)
    end

    it "still transforms blockquote text outside the quoted fence" do
      content = "> ~~quoted~~\n> ```\n> ~~code~~\n> ```\n> ~~after~~"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess(content, make_config)
      result.should contain("<del>quoted</del>")
      result.should contain("~~code~~")
      result.should contain("<del>after</del>")
    end

    it "resumes transforms when an unclosed quoted fence ends with its blockquote" do
      content = "> ```\n> ~~code~~\n\n~~real~~"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess(content, make_config)
      result.should contain("~~code~~")
      result.should contain("<del>real</del>")
    end
  end

  describe "indented code blocks" do
    it "leaves transforms alone inside an indented code run" do
      config = make_config(math: true)
      content = "Build:\n\n\techo ${A}/${B}\n\t~~x~~\n\n~~real~~ and $y$"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess(content, config)
      result.should contain("${A}/${B}")
      result.should contain("~~x~~")
      result.should contain("<del>real</del>")
      result.should contain("math-inline")
    end

    it "still transforms 4-space list continuations" do
      content = "- item\n\n    ~~strike~~ continues"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess(content, make_config)
      result.should contain("<del>strike</del>")
    end

    it "still converts nested task lists at 4-space indent" do
      config = make_config(task_lists: true)
      content = "- [ ] outer\n    - [ ] nested"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess(content, config)
      result.scan("checkbox").size.should eq 2
    end
  end

  describe "math fence and code-span awareness" do
    it "leaves $$ inside fenced code blocks verbatim" do
      content = "```make\nall:\n\techo $$PATH\n\techo $$HOME\n```"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should eq(content)
    end

    it "leaves $...$ inside inline code spans verbatim" do
      content = "Use `$HOME` and `$PATH` to read env vars."
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should eq(content)
    end

    it "still renders math on a line that also has inline code" do
      content = "The value `x` equals $y+1$ here."
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should contain("math-inline")
      result.should contain("`x`")
      result.should_not contain("$y+1$")
    end

    it "uses single-backslash delimiters inside raw HTML blocks" do
      content = "<td>$x+y$</td>"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_math(content)
      result.should contain("\\(x+y\\)")
      result.should_not contain("\\\\(")
    end
  end

  describe "footnote refs in inline code" do
    it "leaves a literal `[^1]` code span verbatim" do
      config = make_config(footnotes: true)
      content = "Real ref[^1] and literal `[^1]` in code.\n\n[^1]: note"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess(content, config)
      result.should contain("`[^1]`")
      result.should contain("fnref-1")
    end
  end

  describe "CRLF line endings" do
    it "extracts heading ids from CRLF content" do
      config = make_config(heading_ids: true)
      content = "## Title {#custom}\r\n\r\nbody\r\n"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess(content, config)
      result.should contain("<!--HID:custom-->")
    end
  end

  describe "definition lists inside fences" do
    it "leaves Term/: def syntax inside a fenced example verbatim" do
      content = "```\nTerm\n: Definition\n```"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should eq(content)
    end
  end

  describe "extensions inside table cells and definitions (end-to-end)" do
    it "renders strikethrough inside a table cell" do
      html, _ = Hwaro::Processor::Markdown.render("| col |\n|-----|\n| ~~del me~~ |", markdown_config: make_config)
      html.should contain("<td><del>del me</del></td>")
      html.should_not contain("&lt;del&gt;")
    end

    it "renders inline math inside a table cell with single-backslash delimiters" do
      html, _ = Hwaro::Processor::Markdown.render("| col |\n|-----|\n| $x+y$ |", markdown_config: make_config(math: true))
      html.should contain("<td><span class=\"math math-inline\">\\(x+y\\)</span></td>")
    end

    it "renders footnote refs inside a table cell" do
      html, _ = Hwaro::Processor::Markdown.render("| col |\n|-----|\n| see[^1] |\n\n[^1]: note", markdown_config: make_config(footnotes: true))
      html.should contain("<td>see<sup class=\"footnote-ref\">")
      html.should contain("class=\"footnotes\"")
    end

    it "renders strikethrough inside a definition body" do
      html, _ = Hwaro::Processor::Markdown.render("Term\n: has ~~del~~ text", markdown_config: make_config(definition_lists: true))
      html.should contain("<dd>has <del>del</del> text</dd>")
    end

    it "renders strikethrough inside an extracted footnote body" do
      html, _ = Hwaro::Processor::Markdown.render("Note[^1].\n\n[^1]: has ~~del~~ text", markdown_config: make_config(footnotes: true))
      html.should contain("has <del>del</del> text")
      html.should_not contain("&lt;del&gt;")
    end
  end

  describe "strikethrough inside math" do
    it "keeps ~~ verbatim inside inline math" do
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess("$~~x~~$", make_config(math: true))
      result.should contain("math-inline")
      result.should contain("~~x~~")
      result.should_not contain("<del>")
    end

    it "still strikes outside math on the same line" do
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess("~~a~~ and $~~b~~$", make_config(math: true))
      result.should contain("<del>a</del>")
      result.should contain("~~b~~")
    end

    it "keeps ~~ verbatim inside multi-line display math" do
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess("$$\na ~~b~~ c\n$$", make_config(math: true))
      result.should contain("math-display")
      result.should contain("~~b~~")
      result.should_not contain("<del>")
    end

    it "applies strikethrough to $-delimited text when math is disabled" do
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess("$~~x~~$", make_config)
      result.should contain("$<del>x</del>$")
    end

    it "keeps ~~ verbatim inside math in a table cell (end-to-end)" do
      html, _ = Hwaro::Processor::Markdown.render("| col |\n|-----|\n| $~~x~~$ |", markdown_config: make_config(math: true))
      html.should contain("\\(~~x~~\\)")
      html.should_not contain("<del>")
    end

    it "still strikes non-math cell text when math is enabled" do
      html, _ = Hwaro::Processor::Markdown.render("| col |\n|-----|\n| ~~strike~~ and $x$ |", markdown_config: make_config(math: true))
      html.should contain("<del>strike</del>")
      html.should contain("\\(x\\)")
    end

    it "keeps ~~ verbatim inside math in a definition body" do
      html, _ = Hwaro::Processor::Markdown.render("Term\n: value $~~x~~$ here", markdown_config: make_config(math: true, definition_lists: true))
      html.should contain("~~x~~")
      html.should_not contain("<del>")
    end

    it "keeps math spans untouched in footnote bodies while striking the rest" do
      html, _ = Hwaro::Processor::Markdown.render("Note[^1].\n\n[^1]: formula $~~x~~$ and ~~real~~", markdown_config: make_config(math: true, footnotes: true))
      html.should contain("$~~x~~$")
      html.should contain("<del>real</del>")
    end

    it "leaves links inside math untouched in table cells" do
      html, _ = Hwaro::Processor::Markdown.render("| col |\n|-----|\n| $f([x])(y)$ |", markdown_config: make_config(math: true))
      html.should contain("\\(f([x])(y)\\)")
      html.should_not contain("<a href")
    end
  end

  describe "emphasis chars inside inline math" do
    it "keeps * inside inline math literal (no emphasis pairing across spans)" do
      html, _ = Hwaro::Processor::Markdown.render("Two products: $a*b$ and $c*d$.", markdown_config: make_config(math: true))
      html.should contain("\\(a*b\\)")
      html.should contain("\\(c*d\\)")
      html.should_not contain("<em>")
    end

    it "keeps _ inside inline math literal" do
      html, _ = Hwaro::Processor::Markdown.render("Indices $a_i$ and $b_j$.", markdown_config: make_config(math: true))
      html.should contain("\\(a_i\\)")
      html.should contain("\\(b_j\\)")
      html.should_not contain("<em>")
    end
  end

  describe "code spans already rendered to <code> HTML (cells, definitions)" do
    it "keeps `$x$` in a table cell as literal code, not math" do
      html, _ = Hwaro::Processor::Markdown.render("| col |\n|-----|\n| `$x$` |", markdown_config: make_config(math: true))
      html.should contain("<code>$x$</code>")
      html.should_not contain("math-inline")
    end

    it "keeps `~~x~~` in a table cell as literal code" do
      html, _ = Hwaro::Processor::Markdown.render("| col |\n|-----|\n| `~~x~~` |", markdown_config: make_config)
      html.should contain("<code>~~x~~</code>")
      html.should_not contain("<del>")
    end

    it "keeps `[^1]` in a table cell literal while the real ref still links" do
      html, _ = Hwaro::Processor::Markdown.render("| col |\n|-----|\n| `[^1]` and real[^1] |\n\n[^1]: note", markdown_config: make_config(footnotes: true))
      html.should contain("<code>[^1]</code>")
      html.should contain("real<sup class=\"footnote-ref\">")
    end

    it "keeps `~~x~~` in a definition literal while striking outside it" do
      html, _ = Hwaro::Processor::Markdown.render("Term\n: has `~~x~~` and ~~real~~", markdown_config: make_config(definition_lists: true))
      html.should contain("<code>~~x~~</code>")
      html.should contain("<del>real</del>")
    end

    it "does not mathify author-written inline <code> content" do
      html, _ = Hwaro::Processor::Markdown.render("Author <code>$x$</code> in paragraph.", markdown_config: make_config(math: true))
      html.should contain("<code>$x$</code>")
      html.should_not contain("math-inline")
    end
  end

  describe "F10 inline markup — ins" do
    it "converts ++text++ to <ins>" do
      html, _ = Hwaro::Processor::Markdown.render("++inserted++ text", markdown_config: make_config(ins: true))
      html.should contain("<ins>inserted</ins>")
    end

    it "leaves ++text++ literal when the flag is off" do
      html, _ = Hwaro::Processor::Markdown.render("++inserted++ text", markdown_config: make_config)
      html.should contain("++inserted++")
      html.should_not contain("<ins>")
    end

    it "leaves ++text++ untouched inside a backtick code span" do
      html, _ = Hwaro::Processor::Markdown.render("`++inserted++`", markdown_config: make_config(ins: true))
      html.should contain("<code>++inserted++</code>")
      html.should_not contain("<ins>")
    end

    it "leaves ++text++ untouched inside a fenced code block" do
      content = "```\n++inserted++\n```"
      html, _ = Hwaro::Processor::Markdown.render(content, markdown_config: make_config(ins: true))
      html.should contain("++inserted++")
      html.should_not contain("<ins>")
    end

    it "leaves ++text++ untouched inside an author-written <code> HTML span" do
      html, _ = Hwaro::Processor::Markdown.render("Author <code>++x++</code> text.", markdown_config: make_config(ins: true))
      html.should contain("<code>++x++</code>")
      html.should_not contain("<ins>")
    end

    it "does not touch a lone C++ (no closing delimiter)" do
      html, _ = Hwaro::Processor::Markdown.render("C++ is nice", markdown_config: make_config(ins: true))
      html.should contain("C++ is nice")
      html.should_not contain("<ins>")
    end
  end

  describe "F10 inline markup — mark" do
    it "converts ==text== to <mark>" do
      html, _ = Hwaro::Processor::Markdown.render("==highlighted== text", markdown_config: make_config(mark: true))
      html.should contain("<mark>highlighted</mark>")
    end

    it "leaves ==text== literal when the flag is off" do
      html, _ = Hwaro::Processor::Markdown.render("==highlighted==", markdown_config: make_config)
      html.should contain("==highlighted==")
      html.should_not contain("<mark>")
    end

    it "leaves ==text== untouched inside a backtick code span" do
      html, _ = Hwaro::Processor::Markdown.render("`==x==`", markdown_config: make_config(mark: true))
      html.should contain("<code>==x==</code>")
      html.should_not contain("<mark>")
    end

    it "leaves ==text== untouched inside a fenced code block" do
      content = "```\n==x==\n```"
      html, _ = Hwaro::Processor::Markdown.render(content, markdown_config: make_config(mark: true))
      html.should contain("==x==")
      html.should_not contain("<mark>")
    end

    it "leaves ==text== untouched inside an author-written <code> HTML span" do
      html, _ = Hwaro::Processor::Markdown.render("Author <code>==x==</code> text.", markdown_config: make_config(mark: true))
      html.should contain("<code>==x==</code>")
      html.should_not contain("<mark>")
    end

    it "does not touch a setext heading underline (Title\\n=====)" do
      html, _ = Hwaro::Processor::Markdown.render("Title\n=====", markdown_config: make_config(mark: true))
      html.should contain(">Title</h1>")
      html.should_not contain("<mark>")
    end

    it "does not touch spaced == (a == b)" do
      html, _ = Hwaro::Processor::Markdown.render("a == b", markdown_config: make_config(mark: true))
      html.should contain("a == b")
      html.should_not contain("<mark>")
    end

    it "keeps == verbatim inside math even when mark is enabled" do
      html, _ = Hwaro::Processor::Markdown.render("$a == b$", markdown_config: make_config(math: true, mark: true))
      html.should contain("a == b")
      html.should_not contain("<mark>")
    end
  end

  describe "F10 inline markup — sub" do
    it "converts ~text~ to <sub>" do
      html, _ = Hwaro::Processor::Markdown.render("H~2~O", markdown_config: make_config(sub: true))
      html.should contain("H<sub>2</sub>O")
    end

    it "leaves ~text~ literal when the flag is off" do
      html, _ = Hwaro::Processor::Markdown.render("H~2~O", markdown_config: make_config)
      html.should contain("H~2~O")
      html.should_not contain("<sub>")
    end

    it "leaves ~text~ untouched inside a backtick code span" do
      html, _ = Hwaro::Processor::Markdown.render("`~x~`", markdown_config: make_config(sub: true))
      html.should contain("<code>~x~</code>")
      html.should_not contain("<sub>")
    end

    it "leaves ~text~ untouched inside a fenced code block" do
      content = "```\n~x~\n```"
      html, _ = Hwaro::Processor::Markdown.render(content, markdown_config: make_config(sub: true))
      html.should contain("~x~")
      html.should_not contain("<sub>")
    end

    it "leaves ~text~ untouched inside an author-written <code> HTML span" do
      html, _ = Hwaro::Processor::Markdown.render("Author <code>~x~</code> text.", markdown_config: make_config(sub: true))
      html.should contain("<code>~x~</code>")
      html.should_not contain("<sub>")
    end

    it "converts strikethrough and sub together on the same line (~~x~~ and ~y~)" do
      html, _ = Hwaro::Processor::Markdown.render("~~x~~ and ~y~", markdown_config: make_config(sub: true))
      html.should contain("<del>x</del>")
      html.should contain("<sub>y</sub>")
    end
  end

  describe "F10 inline markup — sup" do
    it "converts ^text^ to <sup>" do
      html, _ = Hwaro::Processor::Markdown.render("x^2^ formula", markdown_config: make_config(sup: true))
      html.should contain("x<sup>2</sup> formula")
    end

    it "leaves ^text^ literal when the flag is off" do
      html, _ = Hwaro::Processor::Markdown.render("x^2^", markdown_config: make_config)
      html.should contain("x^2^")
      html.should_not contain("<sup>")
    end

    it "leaves ^text^ untouched inside a backtick code span" do
      html, _ = Hwaro::Processor::Markdown.render("`x^2^`", markdown_config: make_config(sup: true))
      html.should contain("<code>x^2^</code>")
      html.should_not contain("<sup>")
    end

    it "leaves ^text^ untouched inside a fenced code block" do
      content = "```\nx^2^\n```"
      html, _ = Hwaro::Processor::Markdown.render(content, markdown_config: make_config(sup: true))
      html.should contain("x^2^")
      html.should_not contain("<sup>")
    end

    it "leaves ^text^ untouched inside an author-written <code> HTML span" do
      html, _ = Hwaro::Processor::Markdown.render("Author <code>x^2^</code> text.", markdown_config: make_config(sup: true))
      html.should contain("<code>x^2^</code>")
      html.should_not contain("<sup>")
    end

    it "does not mangle a footnote reference marker ([^1]) when sup is also enabled" do
      html, _ = Hwaro::Processor::Markdown.render("Note[^1].\n\n[^1]: text", markdown_config: make_config(footnotes: true, sup: true))
      html.should contain(%(<sup class="footnote-ref">))
      html.should_not contain(%(<sup>1]</sup>))
    end
  end

  describe "F10 inline markup inside table cells, definitions, and footnotes" do
    it "renders mark inside a table cell" do
      html, _ = Hwaro::Processor::Markdown.render("| col |\n|-----|\n| ==x== |", markdown_config: make_config(mark: true))
      html.should contain("<td><mark>x</mark></td>")
    end

    it "renders sub inside a definition body" do
      html, _ = Hwaro::Processor::Markdown.render("Term\n: H~2~O", markdown_config: make_config(definition_lists: true, sub: true))
      html.should contain("<dd>H<sub>2</sub>O</dd>")
    end

    it "renders sup inside a footnote body" do
      html, _ = Hwaro::Processor::Markdown.render("Note[^1].\n\n[^1]: x^2^ formula", markdown_config: make_config(footnotes: true, sup: true))
      html.should contain("x<sup>2</sup> formula")
    end
  end

  describe "F9 markdown attributes — headings and images" do
    it "renders id/class/other attrs end-to-end on a heading" do
      cfg = make_config(attributes: true, heading_ids: true)
      html, _ = Hwaro::Processor::Markdown.render("## H {#i .c k=v}", markdown_config: cfg)
      html.should contain(%(<h2 id="i" class="c" k="v">H</h2>))
    end

    it "renders a pure {#id} block byte-equal to attributes-off, when heading_ids is also on" do
      cfg_on = make_config(attributes: true, heading_ids: true)
      cfg_off = make_config(heading_ids: true)
      content = "## H {#id}\n\nBody.\n"
      html_on, _ = Hwaro::Processor::Markdown.render(content, markdown_config: cfg_on)
      html_off, _ = Hwaro::Processor::Markdown.render(content, markdown_config: cfg_off)
      html_on.should eq(html_off)
    end

    it "leaves {#id .class key=val} literal when the attributes flag is off" do
      cfg = make_config(heading_ids: true)
      html, _ = Hwaro::Processor::Markdown.render("## H {#i .c k=v}", markdown_config: cfg)
      html.should contain("H {#i .c k=v}")
      html.should_not contain(%(class="c"))
    end

    it "strips the attribute block under safe mode instead of leaking a marker" do
      cfg = make_config(attributes: true)
      cfg.safe = true
      html, _ = Hwaro::Processor::Markdown.render("## H {#i .c}\n", safe: true, markdown_config: cfg)
      html.should contain("H")
      html.should_not contain("{#")
      html.should_not contain("HATTR")
    end

    it "leaves an attribute-block-like line verbatim inside a fenced code block" do
      cfg = make_config(attributes: true)
      content = "```\n## H {#i .c}\n```\n"
      html, _ = Hwaro::Processor::Markdown.render(content, markdown_config: cfg)
      html.should contain("## H {#i .c}")
      html.should_not contain(%(class="c"))
    end

    it "handles a CRLF-terminated heading attribute line" do
      cfg = make_config(attributes: true)
      html, _ = Hwaro::Processor::Markdown.render("## H {#id}\r\n\r\nBody\r\n", markdown_config: cfg)
      html.should contain(%(<h2 id="id">H</h2>))
    end

    it "merges an inline image's attribute block onto the generated <img> tag" do
      cfg = make_config(attributes: true)
      html, _ = Hwaro::Processor::Markdown.render("![a](b){.r width=300}", markdown_config: cfg)
      html.should contain(%(<img src="b" alt="a" class="r" width="300" />))
    end

    it "leaves an invalid attribute block literal" do
      cfg = make_config(attributes: true, heading_ids: true)
      html, _ = Hwaro::Processor::Markdown.render("## H {#bad k=<}", markdown_config: cfg)
      html.should contain("H {#bad k=&lt;}")
    end

    it "keeps working alongside lazy_loading's own <img> attribute injection" do
      cfg = make_config(attributes: true)
      html, _ = Hwaro::Processor::Markdown.render("![a](b.png){.r width=300}", lazy_loading: true, markdown_config: cfg)
      html.should contain(%(<img loading="lazy" src="b.png" alt="a" class="r" width="300" />))
    end

    it "cleans up a stray/malformed HATTR marker rather than leaking it" do
      result = Hwaro::Content::Processors::MarkdownExtensions.postprocess_attributes("<p>x</p><!--HATTR:00-->")
      result.should_not contain("HATTR")
    end

    it "respects and dedupes an attribute id in the TOC, with anchors pointing at it" do
      cfg = make_config(attributes: true)
      content = "## A {#x}\n\nbody\n\n## B {#x}\n\nbody2\n"
      html, toc = Hwaro::Content::Processors::Markdown.new.render_with_anchors(content, markdown_config: cfg)
      html.scan(/<h2 id="x">/).size.should eq(1)
      html.scan(/<h2 id="x-1">/).size.should eq(1)
      toc.size.should eq(2)
      toc[0].id.should eq("x")
      toc[1].id.should eq("x-1")
    end
  end
end
