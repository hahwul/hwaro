require "../spec_helper"
require "../../src/content/processors/markdown_extensions"

private def make_config(**opts) : Hwaro::Models::MarkdownConfig
  config = Hwaro::Models::MarkdownConfig.new
  config.task_lists = opts[:task_lists]? || false
  config.footnotes = opts[:footnotes]? || false
  config.definition_lists = opts[:definition_lists]? || false
  config.mermaid = opts[:mermaid]? || false
  config.math = opts[:math]? || false
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
end
