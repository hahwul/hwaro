require "../../../../spec_helper"

describe Hwaro::Content::Processors::MarkdownExtensions do
  describe ".preprocess_definition_lists" do
    it "leaves lines inside raw <script>/<pre>/<style> blocks verbatim" do
      content = "<script>\nvar x = cond\n  ? \"a\"\n  : \"b\";\n</script>\n\n" \
                "<pre>\nkey\n: value\n</pre>\n\n<style>\na\n: b\n</style>\n\nTerm\n: def"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain("  ? \"a\"\n  : \"b\";")
      result.should contain("key\n: value")
      result.should contain("a\n: b")
      result.scan("<dl>").size.should eq(1)
      result.should contain("<dt>Term</dt>\n<dd>def</dd>")
    end

    it "renders the line right after a definition list as Markdown" do
      # `<dl>` opens a raw HTML block that runs to the next blank line, so a
      # paragraph, list or fence directly after the list shipped unparsed.
      config = Hwaro::Models::MarkdownConfig.new
      html, _ = Hwaro::Processor::Markdown.render("Term\n: Definition\nNext **bold** line\n\nTerm 2\n: Def 2\n- item\n\nT3\n: D3\n```\ncode\n```\n", markdown_config: config)
      html.should contain("<p>Next <strong>bold</strong> line</p>")
      html.should contain("<li>item</li>")
      html.should contain("<pre><code>code\n</code></pre>")
      html.should_not contain("**bold**")
    end
  end
end
