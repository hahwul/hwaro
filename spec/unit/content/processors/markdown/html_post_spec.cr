require "../../../../spec_helper"

describe Hwaro::Content::Processors::Markdown do
  describe "heading passes" do
    it "leave headings inside script/style/textarea text alone" do
      content = "## Real\n\n<script>\nel.innerHTML = \"<h2>Injected</h2>\";\n</script>\n\n<textarea><h3>Typed</h3></textarea>\n"
      html, toc = Hwaro::Content::Processors::Markdown.new.render_with_anchors(content, anchor_style: "after")
      html.should contain(%("<h2>Injected</h2>"))
      html.should contain("<textarea><h3>Typed</h3></textarea>")
      html.should contain(%(<h2 id="real">Real <a class="anchor"))
      toc.map(&.id).should eq(["real"])
    end
  end

  describe "lazy loading and external links" do
    it "leave <img>/<a> strings inside a script alone" do
      md_config = Hwaro::Models::MarkdownConfig.new
      md_config.external_links_target_blank = true
      script = %(<script>\nel.innerHTML = "<img src='/b.png'>" + "<a href='http://e.com'>x</a>";\n</script>)
      content = "![real](a.png) [ext](http://ext.com)\n\n#{script}\n"
      html, _ = Hwaro::Processor::Markdown.render(content, lazy_loading: true, markdown_config: md_config)
      html.should contain(script)
      html.should contain(%(<img loading="lazy" src="a.png"))
      html.should contain(%(<a href="http://ext.com" target="_blank" rel="noopener">))
    end
  end

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

    it "shows the converted emoji in TOC titles, keeping the source-derived id" do
      html, toc = Hwaro::Processor::Markdown.render("## Hot :fire: `:x:` take", emoji: true)
      html.should contain(%(<h2 id="hot-fire-x-take">Hot 🔥 <code>:x:</code> take</h2>))
      toc.first.title.should eq("Hot 🔥 :x: take")
      toc.first.id.should eq("hot-fire-x-take")
    end
  end
end
