require "../../../../spec_helper"

# A long unquoted attribute value (an inline `src=data:…` in raw HTML) used to
# fail the whole page render with "Regex match error: JIT stack limit
# reached" in every quote-aware tag scan that was not possessive.
private LONG = "A" * 100_000

private def render_with(content : String, &)
  md_config = Hwaro::Models::MarkdownConfig.new
  yield md_config
  html, _ = Hwaro::Processor::Markdown.render(content, safe: false, markdown_config: md_config)
  html
end

describe Hwaro::Content::Processors::MarkdownExtensions do
  it "applies the external-link policy past an <a> with a 100k-character value" do
    html = render_with(%(<a href="https://e.com" data-x=#{LONG}>long</a>\n\n[ext](https://ext.com)\n)) do |c|
      c.external_links_target_blank = true
    end
    html.should contain(%(<a href="https://e.com" data-x=AAAA))
    html.should contain(%(<a href="https://ext.com" target="_blank" rel="noopener">))
  end

  it "sets a {#id} next to a heading whose attributes hold a 100k-character value" do
    html = render_with(%(<h2 data-x=#{LONG}>Raw</h2>\n\n## Title {#custom}\n), &.heading_ids = true)
    html.should contain(%(<h2 id="custom">Title</h2>))
  end

  it "keeps math out of a <code> span whose attributes hold a 100k-character value" do
    html = render_with(%(<code data-x=#{LONG}>$a$</code> and $b$\n), &.math = true)
    html.should contain(%(>$a$</code>))
    html.should_not contain(%(>$a$</code> and $b$))
  end

  it "binds an image attribute block past an <img> with a 100k-character value" do
    html = render_with(%(<img src=data:image/gif;base64,#{LONG}>\n\n![alt](a.png){.wide}\n), &.attributes = true)
    html.should contain(%(<img src="a.png" alt="alt" class="wide"))
  end
end
