require "../../../../spec_helper"

private def render_md(content : String, attributes : Bool = false) : String
  md_config = Hwaro::Models::MarkdownConfig.new
  md_config.attributes = attributes
  html, _ = Hwaro::Processor::Markdown.render(content, safe: false, markdown_config: md_config)
  html
end

describe Hwaro::Content::Processors::MarkdownExtensions do
  describe "custom heading ids" do
    it "keeps an escaped {#id} as literal heading text" do
      html = render_md("## Escaped \\{#esc}\n")
      html.should contain("Escaped {#esc}</h2>")
      html.should_not contain(%(id="esc"))
      html.should_not contain("\\")
    end

    it "still applies the id after an escaped backslash" do
      html = render_md("## Path \\\\{#p}\n")
      html.should contain(%(id="p"))
      html.should contain("Path \\</h2>")
    end

    it "keeps an escaped attribute block literal" do
      html = render_md("## Escaped \\{#esc .c}\n", attributes: true)
      html.should contain("Escaped {#esc .c}</h2>")
      html.should_not contain(%(class="c"))
    end

    it "handles a long heading full of escapes without exhausting the regex stack" do
      html = render_md("## #{"a\\b" * 100_000} {#long}\n", attributes: true)
      html.should contain(%(id="long"))
    end

    it "applies an id after other escapes in the heading text" do
      render_md("## A \\* b {#ab}\n").should contain(%(<h2 id="ab">A * b</h2>))
    end
  end
end
