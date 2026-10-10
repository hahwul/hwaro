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

describe "marker summary inside a raw HTML block" do
  it "closes the elements the marker leaves open" do
    summary = summary_of("<details>\n<summary>Click</summary>\n\n<div class=\"x\">\n\nHidden <span>a<br>b.\n\n<!-- more -->\n\nMore.</span>\n\n</div>\n</details>\n")
    summary.should contain("Hidden")
    summary.should end_with("b.</p>\n</div>\n</details>\n")
  end

  it "leaves a balanced summary untouched" do
    summary_of("<details>\n<summary>S</summary>\n\nIn.\n\n</details>\n\n<!-- x <div> -->\n\nText.\n\n<!-- more -->\n\nRest.\n")
      .should end_with("<p>Text.</p>\n")
  end
end

private def summary_png(w : Int32, h : Int32) : String
  Dir.mktmpdir do |dir|
    path = File.join(dir, "x.png")
    px = Bytes.new(w * h * 3, 90_u8)
    LibStb.stbi_write_png(path, w, h, 3, px.to_unsafe.as(Void*), w * 3)
    File.read(path)
  end
end

# Summaries render in ParseContent, before the BeforeRender `image:resize`
# hook fills the resize map: `resize_image()` in a summary shortcode returned
# the original URL and summary `<img>` never got the body's srcset.
describe "marker summary and image processing" do
  it "uses the resized variants the body gets, in listings and author lists" do
    config = BASIC_CONFIG + "\n[image_processing]\nenabled = true\nwidths = [100]\n"
    body = "+++\ntitle = \"P\"\nauthors = [\"ann\"]\n+++\nIntro {{ rz() }} [x](@/missing.md)\n\n![logo](/logo.png)\n\n<!-- more -->\n\nRest.\n"
    log = with_captured_log do
      build_site(
        config,
        content_files: {"blog/_index.md" => "+++\ntitle = \"B\"\n+++\n", "blog/post.md" => body},
        template_files: {"page.html"          => "{{ content }}",
                         "section.html"       => "{% for p in section.pages %}L[{{ p.summary }}]{% endfor %}A[{{ site.authors.ann.pages[0].summary }}]",
                         "shortcodes/rz.html" => %(<img src="{{ resize_image(path='/logo.png', width=100).url }}" alt="rz">)},
        static_files: {"logo.png" => summary_png(400, 200)},
      ) do |dir|
        html = File.read(File.join(dir, "public", "blog", "index.html"))
        listing = html[/L\[(.*?)\]A\[/m, 1]
        authors = html[/A\[(.*)\]/m, 1]
        {listing, authors}.each do |summary|
          summary.should contain(%(/logo_100w.png" alt="rz"))
          summary.should contain(%(srcset="/logo_100w.png 100w"))
        end
      end
    end
    log.scan("could not be resolved").size.should eq(1)
  end
end
