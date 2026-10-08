require "../../../../spec_helper"
require "../../../../support/build_helper"

# A `<!-- more -->` summary is rendered from the text BEFORE the marker, in
# isolation. Definitions that normally sit at the end of a post (link
# references, footnotes) are after the marker, so they used to be lost: the
# summary showed literal `[^1]` and `[text][ref]` in every listing and feed.
private def summary_of(body : String, config : String = BASIC_CONFIG) : String
  summary = ""
  build_site(
    config,
    content_files: {"post.md" => "+++\ntitle = \"P\"\n+++\n#{body}"},
    template_files: {"page.html" => "SUM=[{{ page.summary }}]END{{ content }}", "section.html" => "{{ content }}"},
  ) do |dir|
    html = File.read(File.join(dir, "public", "post", "index.html"))
    summary = html[/SUM=\[(.*?)\]END/m, 1]
  end
  summary
end

describe "marker summary context" do
  it "resolves reference-style links defined after the marker" do
    summary = summary_of("See [the docs][d] here.\n\n<!-- more -->\n\nRest.\n\n[d]: https://example.com/docs \"Docs\"\n")
    summary.should contain(%(<a href="https://example.com/docs" title="Docs">the docs</a>))
    summary.should_not contain("[the docs][d]")
    summary.should_not contain("Rest")
  end

  it "does not pick definitions out of a fenced block after the marker" do
    summary = summary_of("See [the docs][d] here.\n\n<!-- more -->\n\n```\n[d]: https://evil.example\n```\n")
    summary.should_not contain("evil.example")
  end

  it "drops a footnote reference whose definition is after the marker" do
    summary = summary_of("Intro with footnote[^1] and `[^2]` code.\n\n<!-- more -->\n\nRest\n\n[^1]: Note text\n")
    summary.should_not contain("[^1]")
    summary.should_not contain("Note text")
    summary.should contain("Intro with footnote and")
    summary.should contain("<code>[^2]</code>")
  end

  it "keeps a footnote whose definition is inside the summary" do
    summary = summary_of("Intro[^1].\n\n[^1]: Inline note\n\n<!-- more -->\n\nRest")
    summary.should contain("footnote-ref")
  end
end
