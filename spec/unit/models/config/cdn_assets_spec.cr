require "../../../spec_helper"

# Third-party assets the build links from a CDN must be pinned to an exact
# version, and carry an SRI hash wherever the browser can check one, so a
# compromised or re-pointed CDN path cannot run its own script on every page.
private def cdn_tags(html : String) : Array(String)
  html.scan(/<(?:script|link)\b[^>]*(?:src|href)="https:\/\/(?:cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com)[^>]*>/).map(&.[0])
end

private def pinned_and_checked(tag : String) : Nil
  tag.should match(/integrity="sha384-[A-Za-z0-9+\/]{64}"/)
  tag.should contain(%(crossorigin="anonymous"))
  tag.should match(/@\d+\.\d+\.\d+\//) if tag.includes?("cdn.jsdelivr.net")
end

describe "CDN assets emitted by the build" do
  it "pins KaTeX and checks every file with SRI" do
    config = Hwaro::Models::MarkdownConfig.new
    config.math = true
    [config.math_tags, config.math_tags(csp: true)].each do |html|
      tags = cdn_tags(html)
      tags.size.should eq 3
      tags.each { |tag| pinned_and_checked(tag) }
    end
  end

  it "pins MathJax and checks it with SRI" do
    config = Hwaro::Models::MarkdownConfig.new
    config.math = true
    config.math_engine = "mathjax"
    tags = cdn_tags(config.math_tags)
    tags.size.should eq 1
    tags.each { |tag| pinned_and_checked(tag) }
  end

  it "pins Mermaid to an exact version" do
    config = Hwaro::Models::MarkdownConfig.new
    config.mermaid = true
    config.mermaid_tags.should match(/mermaid@\d+\.\d+\.\d+\/dist\//)
  end

  it "checks the client-side highlight.js script with SRI" do
    config = Hwaro::Models::HighlightConfig.new
    config.enabled = true
    config.mode = "client"
    config.use_cdn = true
    tags = cdn_tags(config.js_tag)
    tags.size.should eq 1
    tags.each { |tag| pinned_and_checked(tag) }
  end
end
