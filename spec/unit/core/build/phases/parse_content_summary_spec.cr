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

describe "marker summary and render hooks" do
  it "renders links through the body's render-link hook" do
    build_site(
      BASIC_CONFIG,
      content_files: {"post.md" => "+++\ntitle = \"P\"\n+++\nSee [x](https://example.com).\n\n<!-- more -->\n\nRest.\n"},
      template_files: {"page.html" => "SUM=[{{ page.summary }}]END", "section.html" => "{{ content }}",
                       "hooks/render-link.html" => %(<a class="hooked" href="{{ destination }}">{{ text }}</a>)},
    ) do |dir|
      summary = File.read(File.join(dir, "public", "post", "index.html"))[/SUM=\[(.*?)\]END/m, 1]
      summary.should contain(%(<a class="hooked" href="https://example.com">x</a>))
    end
  end
end

describe "marker summary inside a block shortcode" do
  it "closes the block where the summary ends" do
    summary = ""
    log = with_captured_log do
      build_site(
        BASIC_CONFIG,
        content_files: {"post.md" => "+++\ntitle = \"P\"\n+++\nIntro.\n\n{% note() %}\nInside.\n\n{% note() %}\nDeep.\n{% end %}\n\n<!-- more -->\n\nStill inside.\n{% end %}\n\nAfter.\n"},
        template_files: {"page.html" => "SUM=[{{ page.summary }}]END", "section.html" => "{{ content }}",
                         "shortcodes/note.html" => "<div class=\"note\">{{ body | markdownify }}</div>"},
      ) do |dir|
        summary = File.read(File.join(dir, "public", "post", "index.html"))[/SUM=\[(.*?)\]END/m, 1]
      end
    end
    summary.should contain(%(<div class="note"><p>Inside.</p>))
    summary.should contain(%(<div class="note"><p>Deep.</p>))
    summary.should_not contain("{%")
    summary.should_not contain("Still inside")
    log.should_not contain("never closed")
  end

  it "leaves an opener the body never closes literal, as the body does" do
    summary = summary_of("{% note() %}\nInside.\n\n<!-- more -->\n\nRest.\n")
    summary.should contain("{% note() %}")
  end
end

# The summary passes render the page's Markdown before the body render does;
# each diagnostic used to print once per pass.
describe "summary pass diagnostics" do
  it "prints each of a page's warnings once" do
    body = "See [a](@/missing.md).\n\n## A {#dup}\n\n## B {#dup}\n\n{{ bad() }}\n\n<!-- more -->\n\nRest.\n"
    {body, body.sub("<!-- more -->", "")}.each do |text|
      log = with_captured_log do
        build_site(
          BASIC_CONFIG,
          content_files: {"post.md" => "+++\ntitle = \"P\"\n+++\n#{text}"},
          template_files: {"page.html" => "{{ page.summary }}{{ content }}", "section.html" => "{{ content }}",
                           "shortcodes/bad.html" => "{% if x %}oops"},
        ) { }
      end
      log.scan("could not be resolved").size.should eq(1)
      log.scan("Duplicate explicit heading id").size.should eq(1)
      log.scan("Template error in shortcode").size.should eq(1)
    end
  end
end
