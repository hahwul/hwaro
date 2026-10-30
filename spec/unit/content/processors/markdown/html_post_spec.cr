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

    # Regression: a `<script` inside a comment opened a raw-text span that ran
    # to the next real `</script>`, hiding every heading and image between.
    it "ignore a raw-text opener inside an HTML comment" do
      content = "<!-- <script src=\"old.js\"> -->\n\n## Visible\n\n![pic](a.png)\n\n<script>\nx();\n</script>\n"
      html, toc = Hwaro::Processor::Markdown.render(content, lazy_loading: true)
      toc.map(&.id).should eq(["visible"])
      html.should contain(%(<h2 id="visible">))
      html.should contain(%(<img loading="lazy" src="a.png"))
    end

    it "find raw-text elements in time linear in their count" do
      t = Time.instant
      spans = Hwaro::Content::Processors::MarkdownExtensions.raw_text_spans("<!-- c --><script>x</script>" * 40_000)
      spans.size.should eq(40_000)
      (Time.instant - t).should be < 5.seconds # a UTF-8 check per element took 10s+; slack for a loaded suite
    end
  end

  describe "raw-text element scans" do
    it "stay linear in the number of script elements" do
      # Each `<script>` matched let PCRE2 re-validate the whole page's UTF-8.
      md_config = Hwaro::Models::MarkdownConfig.new
      md_config.external_links_target_blank = true
      content = "## H\n\n<script>x</script>\n\nCafé ![i](/i.png) [e](https://e.com)\n\n" * 20_000
      t = Time.instant
      html, toc = Hwaro::Processor::Markdown.render(content, lazy_loading: true, markdown_config: md_config)
      (Time.instant - t).should be < 10.seconds
      toc.size.should eq(20_000)
      html.scan(%(<img loading="lazy")).size.should eq(20_000)
      html.scan(%(target="_blank")).size.should eq(20_000)
    end
  end

  describe "comment spans" do
    it "are looked up in log time per heading" do
      # Every heading scanned every comment/raw-text span: quadratic.
      content = "## H\n\n<!-- c -->\n\n" * 30_000
      t = Time.instant
      html, toc = Hwaro::Content::Processors::Markdown.new.render_with_anchors(content, anchor_style: "after")
      (Time.instant - t).should be < 5.seconds
      toc.size.should eq(30_000)
      html.scan(%(<a class="anchor")).size.should eq(30_000)
    end

    it "still skip headings in overlapping comment and script spans" do
      content = "<!-- a -->\n\n## A\n\n<script>\n// <!-- x -->\n\"<h2>B</h2>\"\n</script>\n\n<!--\n<h2>C</h2>\n-->\n\n## D\n"
      html, toc = Hwaro::Content::Processors::Markdown.new.render_with_anchors(content, anchor_style: "after")
      toc.map(&.id).should eq(["a", "d"])
      html.should contain(%("<h2>B</h2>"))
      html.should contain("<h2>C</h2>")
    end
  end

  describe "long unquoted attribute values" do
    it "insert an anchor into a heading whose attributes hold a 100k-character value" do
      content = %(<h2 data-x=#{"A" * 100_000} id="long">Long</h2>\n\n<h2 id="next" title="a>b">Next</h2>\n)
      html, toc = Hwaro::Content::Processors::Markdown.new.render_with_anchors(content, safe: false, anchor_style: "after")
      toc.map(&.id).should eq(["long", "next"])
      html.should contain(%(<a class="anchor" href="#long"))
      html.should contain(%(<a class="anchor" href="#next"))
    end

    it "id a heading whose attributes hold a 100k-character value" do
      content = %(<h2 data-x=#{"A" * 100_000}>Long</h2>\n\n## Next\n)
      html, toc = Hwaro::Processor::Markdown.render(content, safe: false)
      toc.map(&.id).should eq(["long", "next"])
      html.should contain(%( id="long">Long</h2>))
    end
  end

  describe "lazy loading and external links" do
    it "lazy-load an <img> with a 100k-character unquoted src" do
      content = "<img src=data:image/gif;base64,#{"A" * 100_000}>\n\n<img loading=eager src=b.png>\n\n<img data-loading=x src=c.png />\n"
      html, _ = Hwaro::Processor::Markdown.render(content, lazy_loading: true, safe: false)
      html.should contain(%(<img loading="lazy" src=data:image/gif;base64,AAAA))
      html.should contain(%(<img loading=eager src=b.png>))
      html.should contain(%(<img loading="lazy" data-loading=x src=c.png />))
    end

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

    it "stays linear on many unclosed code and raw-text openers" do
      t = Time.instant
      html, _ = Hwaro::Processor::Markdown.render(":smile: " + "<textarea> x " * 20_000, emoji: true)
      html.should start_with("<p>😄 <textarea>")
      (Time.instant - t).should be < 10.seconds # quadratic took 35s; slack for a loaded suite
    end

    it "stays linear in the number of tags" do
      t = Time.instant
      html, _ = Hwaro::Processor::Markdown.render(":smile: " + "<b>x</b> " * 80_000, emoji: true)
      html.should start_with("<p>😄 <b>x</b>")
      (Time.instant - t).should be < 5.seconds # a UTF-8 check per tag took 10s+; slack for a loaded suite
    end

    it "stays linear on a long page with many tags" do
      # PCRE2 re-validated the whole page's UTF-8 at every `<`: a 1 MB page
      # took over 30 seconds.
      content = "Café :smile: **bold** `code` [l](/x)\n\n" * 20_000
      t = Time.instant
      html, _ = Hwaro::Processor::Markdown.render(content, emoji: true)
      (Time.instant - t).should be < 10.seconds
      html.scan("\u{1F604}").size.should eq(20_000)
    end

    it "shows the converted emoji in TOC titles, keeping the source-derived id" do
      html, toc = Hwaro::Processor::Markdown.render("## Hot :fire: `:x:` take", emoji: true)
      html.should contain(%(<h2 id="hot-fire-x-take">Hot 🔥 <code>:x:</code> take</h2>))
      toc.first.title.should eq("Hot 🔥 :x: take")
      toc.first.id.should eq("hot-fire-x-take")
    end
  end
end
