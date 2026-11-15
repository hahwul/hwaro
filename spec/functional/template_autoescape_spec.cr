require "../support/build_helper"

# `[templates] autoescape`, end to end: author text prints escaped exactly
# once, every value hwaro renders to HTML prints as is, text outputs never
# escape, and toggling the switch rebuilds a `--cache` tree.

private CANARY  = %(<b a="x">&')
private ESCAPED = "&lt;b a=&quot;x&quot;&gt;&amp;&#39;"

private def ae_config(on : Bool) : String
  <<-TOML
    title = "Site #{CANARY.gsub('"', "\\\"")}"
    base_url = "https://ae.example.com"

    [highlight]
    enabled = true

    [feeds]
    enabled = true
    type = "json"

    [outputs]
    page = ["json"]

    [[content.generate]]
    source = "items"
    section = "items"
    slug = "id"
    title = "{{ item.name }}"
    #{on ? "\n[templates]\nautoescape = true\n" : ""}
    TOML
end

private AE_PAGE = <<-MD
  +++
  title = "T #{CANARY.gsub('"', "\\\"")}"
  description = "D #{CANARY.gsub('"', "\\\"")}"
  toc = true
  [extra]
  note = "N #{CANARY.gsub('"', "\\\"")}"
  +++
  Lead **bold**.

  <!-- more -->

  ## Heading one

  [a link](/x/ "tip")

  {% box(arg="A #{CANARY.gsub('"', "\\\"")}") %}
  Body **md**.
  {% end %}
  MD

private AE_TEMPLATES = {
  "page.html" => <<-HTML,
    <title>{{ page.title }}</title>|{{ site.title }}|{{ page.description }}|{{ page.extra.note }}
    OG {{ og_tags }}
    CANON {{ canonical_tag }}
    TOC {{ toc }}{% for h in toc_obj.headers %}[{{ h.title }}]{% endfor %}
    SUM {{ page.summary }}
    JSON <script>var t = {{ page.title | tojson }};</script>
    MAIN {{ content }}
    HTML
  "section.html"           => "{{ content }}",
  "index.html"             => "{{ content }}",
  "shortcodes/box.html"    => %(<div data-arg="{{ arg }}">{{ body | markdownify }}</div>),
  "hooks/render-link.html" => %(<a class="hook" href="{{ destination }}" title="{{ title }}">{{ text }}</a>),
  "page.json.jinja"        => %({"title": "{{ page.title }}"}),
  "feed.json.jinja"        => %({"items": [{% for p in pages %}"{{ p.title }}"{% endfor %}]}),
}

private def ae_build(on : Bool, &)
  build_site(
    ae_config(on),
    content_files: {"posts/p.md" => AE_PAGE},
    template_files: AE_TEMPLATES,
    data_files: {"items.json" => %([{"id": "i1", "name": "Item #{CANARY.gsub('"', "\\\"")}"}])},
  ) do |dir|
    yield dir
  end
end

private def rerun(cache : Bool) : Nil
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: cache,
    highlight: false, verbose: false, profile: false))
end

describe "Template autoescape" do
  it "is off by default and renders author text as before" do
    ae_build(false) do
      html = File.read("public/posts/p/index.html")
      html.should contain("<title>T #{CANARY}</title>")
      html.should contain("|D #{CANARY}|N #{CANARY}")
    end
  end

  it "escapes author text once and prints hwaro-built HTML as is" do
    ae_build(true) do
      html = File.read("public/posts/p/index.html")
      html.should contain("<title>T #{ESCAPED}</title>|Site #{ESCAPED}|D #{ESCAPED}|N #{ESCAPED}")
      html.should_not contain(CANARY)
      html.should contain(%(OG <meta property="og:title" content="T &lt;b))
      html.should_not contain("&amp;amp;")
      html.should contain(%(CANON <link rel="canonical"))
      html.should contain(%(TOC <ul><li><a href="#heading-one">Heading one</a></li></ul>[Heading one]))
      html.should contain("SUM <p>Lead <strong>bold</strong>.</p>")
      html.should contain(%(<h2 id="heading-one">Heading one</h2>))
      # render hook values and a shortcode's body are markup; its arguments text
      html.should contain(%(<a class="hook" href="/x/" title="tip">a link</a>))
      html.should contain(%(<div data-arg="A #{ESCAPED}"><p>Body <strong>md</strong>.</p>))
      # tojson in a <script> stays JSON
      html.should contain(%(var t = "T \\u003cb a=\\"x\\"\\u003e\\u0026\\u0027";))
    end
  end

  it "never escapes a text output (output format, JSON feed, content.generate spec)" do
    ae_build(true) do
      File.read("public/posts/p/index.json").should eq(%({"title": "T #{CANARY}"}))
      File.read("public/feed.json").should contain(%("T #{CANARY}"))
      # the generated title is text: escaped once, by the page template
      File.read("public/items/i1/index.html").should contain("<title>Item #{ESCAPED}</title>")
    end
  end

  it "rebuilds a --cache tree when the switch flips" do
    ae_build(false) do
      rerun(cache: true)
      File.read("public/posts/p/index.html").should contain("<title>T #{CANARY}</title>")
      File.write("config.toml", ae_config(true))
      rerun(cache: true)
      File.read("public/posts/p/index.html").should contain("<title>T #{ESCAPED}</title>")
      File.write("config.toml", ae_config(false))
      rerun(cache: true)
      File.read("public/posts/p/index.html").should contain("<title>T #{CANARY}</title>")
    end
  end

  # Review-round regressions, end to end.

  it "#1 does not let a JSON output template share the HTML template's escaping" do
    # Byte-identical source for the HTML and JSON templates: the compiled-template
    # cache must still give each its own escaping (HTML escaped, JSON raw).
    build_site(
      <<-TOML,
        title = "x"
        base_url = "https://e.example.com"
        [templates]
        autoescape = true
        [outputs]
        page = ["json"]
        TOML
      content_files: {"p.md" => "+++\ntitle = \"<x&>\"\n+++\nb\n"},
      template_files: {"page.html" => "T:{{ page.title }}", "page.json.jinja" => "T:{{ page.title }}"},
    ) do
      File.read("public/p/index.html").should eq("T:&lt;x&amp;&gt;")
      File.read("public/p/index.json").should eq("T:<x&>")
    end
  end

  it "#11 strips a .ecr wrapper before reading the output type" do
    build_site(
      <<-TOML,
        title = "x"
        base_url = "https://e.example.com"
        [templates]
        autoescape = true
        [outputs]
        page = ["json"]
        TOML
      content_files: {"p.md" => "+++\ntitle = \"<x>\"\n+++\nb\n"},
      template_files: {"page.html" => "H", "page.json.ecr" => %({"t":"{{ page.title }}"})},
    ) do
      File.read("public/p/index.json").should eq(%({"t":"<x>"}))
    end
  end

  it "#5 escapes apostrophes in render-hook attribute text so a quote can't break out" do
    build_site(
      <<-TOML,
        title = "x"
        base_url = "https://e.example.com"
        [templates]
        autoescape = true
        TOML
      content_files: {"p.md" => "+++\ntitle = \"p\"\n+++\n![x' onerror='boom](/i)\n"},
      template_files: {"page.html" => "{{ content }}", "hooks/render-image.html" => "<img src=\"{{ destination }}\" alt='{{ alt }}'>"},
    ) do
      html = File.read("public/p/index.html")
      html.should contain("alt='x&#39; onerror=&#39;boom'")
      html.should_not contain("alt='x' onerror='boom'")
    end
  end

  it "#2 keeps a shortcode body safe only when markdown.safe is off" do
    [{false, true}, {true, false}].each do |safe_mode, raw|
      build_site(
        <<-TOML,
          title = "x"
          base_url = "https://e.example.com"
          [templates]
          autoescape = true
          [markdown]
          safe = #{safe_mode}
          TOML


        content_files: {"p.md" => "+++\ntitle = \"p\"\n+++\n{% echo() %}\n<img src=x data-ae>\n{% end %}\n"},
        template_files: {"page.html" => "{{ content }}", "shortcodes/echo.html" => %(<div>{{ body }}</div>)},
      ) do
        html = File.read("public/p/index.html")
        if raw
          html.should contain("<img src=x data-ae>")
        else
          html.should contain("&lt;img src=x data-ae&gt;")
          html.should_not contain("<img src=x data-ae>")
        end
      end
    end
  end
end
