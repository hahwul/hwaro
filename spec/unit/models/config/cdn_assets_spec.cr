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

# The one place URL and hash are pinned together. Bumping a version means
# recomputing its hash from the CDN bytes, then editing the tag AND this row:
#   curl -fsSL <url> | openssl dgst -sha384 -binary | openssl base64 -A
private def cdn_hashes : Hash(String, String)
  {
    "https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/katex.min.css"               => "sha384-zh0CIslj+VczCZtlzBcjt5ppRcsAmDnRem7ESsYwWwg3m/OaJ2l4x7YBZl9Kxxib",
    "https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/katex.min.js"                => "sha384-Rma6DA2IPUwhNxmrB/7S3Tno0YY7sFu9WSYMCuulLhIqYSGZ2gKCJWIqhBWqMQfh",
    "https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/contrib/auto-render.min.js"  => "sha384-hCXGrW6PitJEwbkoStFjeJxv+fSOOQKOPbJxSfM6G5sWZjAyWhXiTIIAmQqnlLlh",
    "https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-chtml.js"                 => "sha384-AHAnt9ZhGeHIrydA1Kp1L7FN+2UosbF7RQg6C+9Is/a7kDpQ1684C2iH2VWil6r4",
    "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js" => "sha384-F/bZzf7p3Joyp5psL90p/p89AZJsndkSoGwRpXcZhleCWhd8SnRuoYo4d0yirjJp",
  }
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

  it "pairs every emitted CDN URL with the hash pinned in cdn_hashes" do
    math = Hwaro::Models::MarkdownConfig.new
    math.math = true
    mathjax = Hwaro::Models::MarkdownConfig.new
    mathjax.math = true
    mathjax.math_engine = "mathjax"
    highlight = Hwaro::Models::HighlightConfig.new
    highlight.mode = "client"
    tags = [math.math_tags, math.math_tags(csp: true), mathjax.math_tags, highlight.js_tag].flat_map { |html| cdn_tags(html) }
    seen = Set(String).new
    tags.each do |tag|
      url = tag.match!(/(?:src|href)="([^"]+)"/)[1]
      expected = cdn_hashes[url]?
      fail "#{url} is not in cdn_hashes; add it with: curl -fsSL #{url} | openssl dgst -sha384 -binary | openssl base64 -A" unless expected
      tag.should contain(%(integrity="#{expected}")), "hash for #{url} changed or the URL was bumped without recomputing it: curl -fsSL #{url} | openssl dgst -sha384 -binary | openssl base64 -A"
      seen << url
    end
    (cdn_hashes.keys.to_set - seen).should be_empty
  end
end
