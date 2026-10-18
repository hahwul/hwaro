require "../../../../spec_helper"

describe Hwaro::Content::Processors::Markdown do
  describe "emoji conversion" do
    it "leaves raw-text elements, math and mermaid untouched" do
      md_config = Hwaro::Models::MarkdownConfig.new
      md_config.math = true
      md_config.mermaid = true
      content = "<style>\na:link:hover { color: red }\n</style>\n\n" \
                "<script>\nvar t = {a:x:1};\n</script>\n\n" \
                "Inline $a:x:b$ and :smile: text.\n\n" \
                "```mermaid\nA:x:B\n```\n"
      html, _ = Hwaro::Processor::Markdown.render(content, emoji: true, markdown_config: md_config)
      html.should contain("a:link:hover")
      html.should contain("{a:x:1}")
      html.should contain("\\(a:x:b\\)")
      html.should contain("A:x:B")
      html.should contain("😄 text")
    end
  end
end
