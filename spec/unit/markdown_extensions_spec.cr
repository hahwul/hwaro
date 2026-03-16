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
      result.should contain("\\(x^2\\)")
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
end
