require "../spec_helper"
require "../../src/content/processors/render_hooks"
require "../../src/content/processors/heading_ids"
require "../../src/content/processors/syntax_highlighter"
require "../../src/content/processors/markdown"

private alias RenderHooks = Hwaro::Content::Processors::RenderHooks
private alias SyntaxHighlighter = Hwaro::Content::Processors::SyntaxHighlighter

# Default-equivalent hook templates (also documented in
# docs/content/templates/render-hooks.md) — used by the byte-parity test
# below. `is present` (not a bare `{% if title %}`) matters: Crinja's
# value truthiness only treats `false`/`0`/nil as falsy, NOT an empty
# string, so a bare `{% if title %}` would always render the attribute.
LINK_TPL      = %(<a href="{{ destination }}"{% if title is present %} title="{{ title }}"{% endif %}>{{ text }}</a>)
IMAGE_TPL     = %(<img src="{{ destination }}" alt="{{ alt }}"{% if title is present %} title="{{ title }}"{% endif %} />)
HEADING_TPL   = %(<h{{ level }} id="{{ id }}">{{ text }}</h{{ level }}>)
CODEBLOCK_TPL = %(<pre><code{% if lang is present %} class="language-{{ lang }}"{% endif %}>{% if highlighted is present %}{{ highlighted }}{% else %}{{ code }}{% endif %}</code></pre>)

private def make_registry(
  link : String? = nil,
  image : String? = nil,
  heading : String? = nil,
  codeblock : String? = nil,
  fingerprint : String = "test",
) : RenderHooks::Registry
  RenderHooks::Registry.new(
    link ? {source: link, disk_path: nil} : nil,
    image ? {source: image, disk_path: nil} : nil,
    heading ? {source: heading, disk_path: nil} : nil,
    codeblock ? {source: codeblock, disk_path: nil} : nil,
    fingerprint,
  )
end

# In-memory HookRenderContext — bypasses RenderHooks.configure/registry so
# these tests never touch (or need to reset) the module's global state.
private def make_hooks(
  link : String? = nil,
  image : String? = nil,
  heading : String? = nil,
  codeblock : String? = nil,
  mermaid_bypass : Bool = false,
) : RenderHooks::HookRenderContext
  registry = make_registry(link: link, image: image, heading: heading, codeblock: codeblock)
  env = Hwaro::Content::Processors::TemplateEngine.new.env
  cache = {} of UInt64 => Crinja::Template
  RenderHooks::HookRenderContext.new(registry, env, cache, nil, {} of String => Crinja::Value, mermaid_bypass)
end

describe RenderHooks do
  after_each do
    # Every `.configure` test below mutates the module-wide @@registry —
    # reset it so later specs (including other files in the same process)
    # never see a leftover hook configuration.
    RenderHooks.configure({} of String => String, {} of String => String)
  end

  describe ".configure" do
    it "builds a registry entry per recognized hook and leaves the rest nil" do
      RenderHooks.configure(
        {"hooks/render-link" => "<a>{{ text }}</a>", "page" => "irrelevant"},
        {} of String => String,
      )
      reg = RenderHooks.registry.not_nil!
      reg.link.should_not be_nil
      reg.link.not_nil![:source].should eq("<a>{{ text }}</a>")
      reg.image.should be_nil
      reg.heading.should be_nil
      reg.codeblock.should be_nil
    end

    it "records the on-disk path for a hook template" do
      RenderHooks.configure(
        {"hooks/render-link" => "x"},
        {"hooks/render-link" => "templates/hooks/render-link.html"},
      )
      RenderHooks.registry.not_nil!.link.not_nil![:disk_path].should eq("templates/hooks/render-link.html")
    end

    it "sets the registry to nil when no hook templates are configured" do
      RenderHooks.configure({"page" => "x", "shortcodes/badge" => "y"}, {} of String => String)
      RenderHooks.registry.should be_nil
    end

    it "changes the fingerprint when a hook template's source changes" do
      RenderHooks.configure({"hooks/render-link" => "A"}, {} of String => String)
      fp1 = RenderHooks.registry.not_nil!.fingerprint

      RenderHooks.configure({"hooks/render-link" => "B"}, {} of String => String)
      fp2 = RenderHooks.registry.not_nil!.fingerprint

      fp1.should_not eq(fp2)
    end

    it "warns once about an unrecognized hook name but stays silent about planned ones" do
      log = with_captured_log do
        RenderHooks.configure(
          {"hooks/render-foo" => "x", "hooks/render-blockquote" => "y"},
          {} of String => String,
        )
      end
      log.should contain("unknown render hook 'render-foo'")
      log.should contain("supported: link, image, heading, codeblock")
      log.should_not contain("render-blockquote")
      # Neither "foo" nor "blockquote" is a real hook, so no registry at all.
      RenderHooks.registry.should be_nil
    end

    it "ignores hooks/* keys that aren't render-* hook names" do
      RenderHooks.configure({"hooks/partial" => "x"}, {} of String => String)
      RenderHooks.registry.should be_nil
    end
  end
end

describe Hwaro::Content::Processors::HeadingIds do
  describe ".assign" do
    it "slugifies unescaped title text" do
      used = Set(String).new
      counters = Hash(String, Int32).new(0)
      Hwaro::Content::Processors::HeadingIds.assign("Tom &amp; Jerry", nil, used, counters).should eq("tom-jerry")
    end

    it "respects an existing id without slugifying the title" do
      used = Set(String).new
      counters = Hash(String, Int32).new(0)
      Hwaro::Content::Processors::HeadingIds.assign("Ignored Title", "custom-id", used, counters).should eq("custom-id")
    end

    it "dedups repeated ids with -1, -2 suffixes" do
      used = Set(String).new
      counters = Hash(String, Int32).new(0)
      Hwaro::Content::Processors::HeadingIds.assign("Foo", nil, used, counters).should eq("foo")
      Hwaro::Content::Processors::HeadingIds.assign("Foo", nil, used, counters).should eq("foo-1")
      Hwaro::Content::Processors::HeadingIds.assign("Foo", nil, used, counters).should eq("foo-2")
    end

    it %(falls back to "heading" when the slug is empty) do
      used = Set(String).new
      counters = Hash(String, Int32).new(0)
      Hwaro::Content::Processors::HeadingIds.assign("!!!", nil, used, counters).should eq("heading")
    end
  end
end

describe "HookedRenderer (via SyntaxHighlighter.render with in-memory contexts)" do
  it "renders link destination/title/text, including nested emphasis" do
    hooks = make_hooks(link: "LINK[{{ destination }}|{{ title }}|{{ text }}]")
    html = SyntaxHighlighter.render(%([**bold** link](http://example.com "Title")), hooks: hooks)
    html.should contain(%(LINK[http://example.com|Title|<strong>bold</strong> link]))
  end

  it "omits nothing when title is absent (empty string, not missing)" do
    hooks = make_hooks(link: "LINK[{{ destination }}|{{ title }}|{{ text }}]")
    html = SyntaxHighlighter.render("[plain](http://example.com)", hooks: hooks)
    html.should contain("LINK[http://example.com||plain]")
  end

  it "renders image alt as plain text extracted from nested markup" do
    hooks = make_hooks(image: "IMG[{{ destination }}|{{ alt }}|{{ title }}]")
    html = SyntaxHighlighter.render("![*italic* alt](http://example.com/img.png)", hooks: hooks)
    html.should contain("IMG[http://example.com/img.png|italic alt|]")
  end

  it "captures a link nested inside a heading (capture stack)" do
    hooks = make_hooks(link: "L[{{ text }}]", heading: "H{{ level }}[{{ id }}]:{{ text }}")
    html = SyntaxHighlighter.render("## Has [a link](http://x) inside", hooks: hooks)
    html.should contain("L[a link]")
    html.should match(/H2\[[a-z0-9-]+\]:Has L\[a link\] inside/)
  end

  it "captures an image nested inside a link (capture stack)" do
    hooks = make_hooks(link: "L[{{ text }}]", image: "I[{{ alt }}]")
    html = SyntaxHighlighter.render("[![alt text](http://img.png)](http://link.png)", hooks: hooks)
    html.should contain("L[I[alt text]]")
  end

  it "keeps a link nested in image alt as plain text (stock @disable_tag suppression)" do
    hooks = make_hooks(link: "L[{{ text }}]", image: "I[{{ alt }}]")
    html = SyntaxHighlighter.render("![before [link text](http://x) after](http://img.png)", hooks: hooks)
    html.should contain("I[before link text after]")
    html.should_not contain("L[")
  end

  it "extracts a custom {#id} into the heading hook's id" do
    hooks = make_hooks(heading: "H[{{ id }}]:{{ text }}")
    cfg = Hwaro::Models::MarkdownConfig.new
    html, _ = Hwaro::Content::Processors::Markdown.new.render("## Title {#custom-id}\n\nBody", markdown_config: cfg, hooks: hooks)
    html.should contain("H[custom-id]:Title")
  end

  it "dedups duplicate heading ids as foo, foo-1" do
    hooks = make_hooks(heading: "H[{{ id }}]")
    html = SyntaxHighlighter.render("## Foo\n\nBody\n\n## Foo\n\nBody2", hooks: hooks)
    html.should contain("H[foo]")
    html.should contain("H[foo-1]")
  end

  describe "codeblock" do
    it "splits lang and a {opts} block via FenceOptions" do
      hooks = make_hooks(codeblock: "CB[{{ lang }}|{{ options }}]")
      html = SyntaxHighlighter.render("```python {linenos=true}\ncode\n```", hooks: hooks)
      html.should contain("CB[python|{linenos=true}]")
    end

    it "splits lang and trailing info without a {opts} block" do
      hooks = make_hooks(codeblock: "CB[{{ lang }}|{{ options }}]")
      html = SyntaxHighlighter.render("```python extra\ncode\n```", hooks: hooks)
      html.should contain("CB[python|extra]")
    end

    it "renders an empty-lang fence with empty lang/options" do
      hooks = make_hooks(codeblock: "CB[{{ lang }}|{{ options }}]")
      html = SyntaxHighlighter.render("```\ncode\n```", hooks: hooks)
      html.should contain("CB[|]")
    end

    it "escapes code" do
      hooks = make_hooks(codeblock: "CODE[{{ code }}]")
      html = SyntaxHighlighter.render("```\n<b>&\n```", hooks: hooks)
      html.should contain("CODE[&lt;b&gt;&amp;")
    end

    it "computes a non-empty highlighted body under server mode" do
      previous = SyntaxHighlighter.server_mode?
      SyntaxHighlighter.server_mode = true
      begin
        hooks = make_hooks(codeblock: "H=<<<{{ highlighted }}>>>")
        html = SyntaxHighlighter.render("```python\nprint(1)\n```", highlight: true, hooks: hooks)
        match = html.match(/H=<<<(.*?)>>>/m)
        match.should_not be_nil
        highlighted = match.not_nil![1]
        highlighted.should_not be_empty
        highlighted.should contain("hljs-")
      ensure
        SyntaxHighlighter.server_mode = previous
      end
    end

    it "bypasses the hook for a mermaid fence when mermaid is enabled" do
      hooks = make_hooks(codeblock: "CB[{{ lang }}]", mermaid_bypass: true)
      html = SyntaxHighlighter.render("```mermaid\ngraph TD;\n```", hooks: hooks)
      html.should_not contain("CB[")
      html.should contain(%(class="language-mermaid))
    end

    it "runs the hook for a mermaid fence when mermaid is disabled" do
      hooks = make_hooks(codeblock: "CB[{{ lang }}]", mermaid_bypass: false)
      html = SyntaxHighlighter.render("```mermaid\ngraph TD;\n```", hooks: hooks)
      html.should contain("CB[mermaid]")
    end
  end

  it "empties the destination in safe mode for an unsafe protocol" do
    hooks = make_hooks(link: "D=[{{ destination }}]")
    html = SyntaxHighlighter.render("[text](javascript:alert(1))", safe: true, hooks: hooks)
    html.should contain("D=[]")
  end

  it "warns once and falls back to stock markup when a hook template errors" do
    hooks = make_hooks(link: "{{ text")
    html = ""
    log = with_captured_log do
      html = SyntaxHighlighter.render(%([hello](http://x "T")), hooks: hooks)
    end
    html.should contain(%(<a href="http://x" title="T">hello</a>))
    log.should contain("Template error in render hook 'hooks/render-link'")
  end
end

describe "default-equivalent hook templates" do
  it "produces byte-identical output to the stock renderer on a mixed document" do
    content = [
      "# Heading One",
      "",
      %(Some [link text](http://example.com "Example") and ![alt text](http://example.com/img.png "Img Title") here.),
      "",
      "## Heading Two",
      "",
      "```python",
      %(print("hi")),
      "```",
      "",
      "```",
      "plain fence",
      "```",
    ].join("\n")

    cfg = Hwaro::Models::MarkdownConfig.new
    processor = Hwaro::Content::Processors::Markdown.new

    stock_html, _ = processor.render(content, highlight: false, markdown_config: cfg)

    hooks = make_hooks(link: LINK_TPL, image: IMAGE_TPL, heading: HEADING_TPL, codeblock: CODEBLOCK_TPL)
    hook_html, _ = processor.render(content, highlight: false, markdown_config: cfg, hooks: hooks)

    hook_html.should eq(stock_html)
  end
end

describe "Feeds/Search fallback rendering (RenderHooks.fallback_context)" do
  after_each do
    RenderHooks.configure({} of String => String, {} of String => String)
  end

  it "applies the link hook when Feeds falls back to rendering an empty page.content" do
    RenderHooks.configure(
      {"hooks/render-link" => %(<a class="hook" href="{{ destination }}">{{ text }}</a>)},
      {} of String => String,
    )

    config = Hwaro::Models::Config.new
    config.base_url = "https://example.com"
    config.title = "Test Site"
    config.description = "desc"
    config.feeds.enabled = true
    config.feeds.full_content = true

    page = Hwaro::Models::Page.new("posts/hello.md")
    page.title = "Hello"
    page.url = "/posts/hello/"
    page.draft = false
    page.render = true
    page.is_index = false
    page.raw_content = "[a link](http://example.com)"
    # page.content is left empty — Feeds must hit rendered_body_fallback.

    Dir.mktmpdir do |output_dir|
      Hwaro::Content::Seo::Feeds.generate([page], config, output_dir)
      feed = File.read(File.join(output_dir, "rss.xml"))
      feed.should contain(%(class="hook"))
    end
  end

  it "applies the link hook when Search falls back to rendering an empty page.content" do
    RenderHooks.configure(
      {"hooks/render-link" => "L[{{ text }}]"},
      {} of String => String,
    )

    config = Hwaro::Models::Config.new
    config.search.enabled = true
    config.search.fields = ["title", "content"]

    page = Hwaro::Models::Page.new("posts/hello.md")
    page.title = "Hello"
    page.url = "/posts/hello/"
    page.raw_content = "[a link](http://example.com)"
    # page.content is left empty — Search must hit rendered_body_fallback.

    Dir.mktmpdir do |output_dir|
      Hwaro::Content::Search.generate([page], config, output_dir)
      content = File.read(File.join(output_dir, "search.json"))
      content.should contain("L[a link]")
    end
  end
end
