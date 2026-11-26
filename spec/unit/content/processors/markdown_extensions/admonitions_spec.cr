require "../../../../spec_helper"

describe Hwaro::Content::Processors::MarkdownExtensions do
  describe ".postprocess_admonitions" do
    it "keeps a nested blockquote inside the admonition" do
      # The body ended at the FIRST `</blockquote>` — the nested quote's —
      # so `</div>` was emitted inside it, the rest of the admonition fell
      # out of it, and a stray `</blockquote>` was left behind.
      config = Hwaro::Models::MarkdownConfig.new
      html, _ = Hwaro::Processor::Markdown.render("> [!NOTE]\n> outer\n>\n> > quoted\n>\n> tail\n\nafter\n", markdown_config: config)
      html.should eq(<<-HTML)
        <div class="admonition admonition-note">
        <p class="admonition-title">Note</p>
        <p>outer</p>
        <blockquote>
        <p>quoted</p>
        </blockquote>
        <p>tail</p>
        </div>
        <p>after</p>

        HTML
    end

    it "rewrites an admonition nested in another, foldable ones included" do
      config = Hwaro::Models::MarkdownConfig.new
      config.wikilinks = true
      html, _ = Hwaro::Processor::Markdown.render("> [!TIP]- Outer\n> > [!WARNING] Inner\n> > inner body\n>\n> tail\n", markdown_config: config)
      html.should eq(<<-HTML)
        <details class="admonition admonition-tip">
        <summary class="admonition-title">Outer</summary>
        <div class="admonition admonition-warning">
        <p class="admonition-title">Inner</p>
        <p>inner body</p>
        </div>
        <p>tail</p>
        </details>

        HTML
    end

    it "stays linear in the admonition count and nesting depth" do
      # Every match revalidated the page's UTF-8, and every nesting level
      # rescanned and copied its body.
      many = "<blockquote>\n<p>[!NOTE]\nx é</p>\n</blockquote>\n" * 40_000
      deep = (1..2000).join { "<blockquote>\n<p>[!NOTE]</p>\n" } + "x" + "</blockquote>\n" * 2000
      t = Time.instant
      Hwaro::Content::Processors::MarkdownExtensions.postprocess_admonitions(many).scan("admonition-note").size.should eq(40_000)
      out = Hwaro::Content::Processors::MarkdownExtensions.postprocess_admonitions(deep)
      (Time.instant - t).should be < 5.seconds # quadratic took 30s+
      out.scan("admonition-note").size.should eq(Hwaro::Content::Processors::MarkdownExtensions::MAX_ADMONITION_NESTING)
    end

    it "falls back to the first closer when raw HTML leaves the quote unbalanced" do
      html = "<blockquote>\n<p>[!NOTE]</p>\n<blockquote>\n<p>x</p>\n</blockquote>\nrest"
      Hwaro::Content::Processors::MarkdownExtensions.postprocess_admonitions(html).should eq(
        "<div class=\"admonition admonition-note\">\n<p class=\"admonition-title\">Note</p>\n<blockquote>\n<p>x</p>\n</div>\nrest")
    end
  end
end
