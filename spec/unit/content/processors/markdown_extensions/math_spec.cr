require "../../../../spec_helper"

private def math_config : Hwaro::Models::MarkdownConfig
  config = Hwaro::Models::MarkdownConfig.new
  config.math = true
  config
end

describe Hwaro::Content::Processors::MarkdownExtensions do
  describe "display math blocks" do
    it "renders the line right after a display math block as Markdown" do
      # The math <div> opens a raw HTML block that runs to the next blank
      # line, so a paragraph or list directly after `$$` shipped unparsed
      # (its code span's `<b>` even became a live tag).
      html, _ = Hwaro::Processor::Markdown.render("$$\nx^2\n$$\nNext **bold** `<b>`\n\n$$x$$\n- item\n", markdown_config: math_config)
      html.should eq(<<-HTML)
        <div class="math math-display">\\[
        x^2
        \\]</div>
        <p>Next <strong>bold</strong> <code>&lt;b&gt;</code></p>
        <div class="math math-display">\\[x\\]</div>
        <ul>
        <li>item</li>
        </ul>

        HTML
    end

    it "does the same inside a blockquote" do
      html, _ = Hwaro::Processor::Markdown.render("> $$\n> y\n> $$\n> quoted **after**\n", markdown_config: math_config)
      html.should eq("<blockquote>\n<div class=\"math math-display\">\\[\ny\n\\]</div>\n<p>quoted <strong>after</strong></p>\n</blockquote>\n")
    end

    it "leaves a block followed by a blank line or the end of the page as before" do
      html, _ = Hwaro::Processor::Markdown.render("$$x$$\n\nafter\n", markdown_config: math_config)
      html.should eq("<div class=\"math math-display\">\\[x\\]</div>\n<p>after</p>\n")
      html, _ = Hwaro::Processor::Markdown.render("$$x$$", markdown_config: math_config)
      html.should eq("<div class=\"math math-display\">\\[x\\]</div>\n")
    end
  end
end
