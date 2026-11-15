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
    [templates]
    autoescape = #{on}
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

# Every construct whose result depends on the escaping rules, for a text
# render. `t` is whatever title the including context has.
private TEXT_KIT = <<-JINJA.gsub('\n', "")
  {% set t = page.title if page is defined else (p.title if p is defined else item.name) %}
  {% set x %}A&B {{ t }}{% endset %}{{ x }}|{{ x | e }}|{{ ["A&B", t] | join(", ") }}|{{ ["A&B"] | join | e }}|
  {% macro m(v) %}<{{ v }}>{% endmacro %}{{ m(t) }}|{{ m("A&B") | e }}|
  {% for n in [{"t": "a&b", "c": [{"t": "c'd", "c": []}]}] recursive %}[{{ n.t }}{{ loop(n.c) }}]{% endfor %}|
  {{ t | replace("N", "<N>") }}|{{ t | replace("N", "<N>", 1) }}|{{ t | truncate(5, true, "<…>", 0) }}|
  {{ "%s<%d>" | format(t, 3) }}|{{ "see http://x.test/?a=1&b=<2>" | urlize }}|{{ {"x y": "v&w", "k": t} | xmlattr }}|
  {{ "/x?a=1&amp;b=2" | safe | relative_url }}|{{ t ~ "<s>" }}|{{ t ~ ("<s>" | safe) }}|{{ [t, "x&y"] | string }}|{{ [t, "x&y"] }}|
  {{ (content | e) if content is defined else "" }}
  JINJA

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
  it "renders author text as 0.x did with autoescape = false" do
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

  # Review round 2 regressions, end to end.

  it "r2#1 escapes a shortcode body= named argument, keeps a block body safe" do
    build_site(
      <<-TOML,
        title = "x"
        base_url = "https://e.example.com"
        [templates]
        autoescape = true
        TOML
      content_files: {"p.md" => "+++\ntitle = \"p\"\n+++\n{% echo() %}\n<b data-block>\n{% end %}\n\n{{ echo(body=\"<b data-named>\") }}\n"},
      template_files: {"page.html" => "{{ content }}", "shortcodes/echo.html" => %(<div>{{ body }}</div>)},
    ) do
      html = File.read("public/p/index.html")
      html.should contain("<b data-block>")       # block body is safe markup (markdown.safe = false)
      html.should contain("&lt;b data-named&gt;") # named body= argument is plain text
      html.should_not contain("<b data-named>")
    end
  end

  it "r2#8 URL filters on a pre-escaped hook destination escape exactly once" do
    build_site(
      <<-TOML,
        title = "x"
        base_url = "https://example.test"
        [templates]
        autoescape = true
        TOML
      content_files: {"p.md" => "+++\ntitle = \"p\"\n+++\n[x](/p?a=1&b=2)\n"},
      template_files: {"page.html"              => "{{ content }}",
                       "hooks/render-link.html" => %(<a href="{{ destination | absolute_url }}" data-r="{{ destination | relative_url }}" data-u="{{ get_url(path=destination) }}">{{ text }}</a>)},
    ) do
      html = File.read("public/p/index.html")
      html.should contain(%(href="https://example.test/p?a=1&amp;b=2"))
      html.should contain(%(data-r="/p?a=1&amp;b=2"))
      html.should contain(%(data-u="https://example.test/p?a=1&amp;b=2"))
      html.should_not contain("&amp;amp;")
    end
  end

  it "r2#9 xmlattr does not validate keys with the switch off" do
    build_site(
      <<-TOML,
        title = "x"
        base_url = "https://e.example.com"
        [templates]
        autoescape = false
        TOML
      content_files: {"p.md" => "+++\ntitle = \"p\"\n[extra.a]\n\"x y\" = \"v\"\n+++\nb\n"},
      template_files: {"page.html" => %(<div{{ page.extra.a | xmlattr }}></div>)},
    ) do
      File.read("public/p/index.html").should eq(%(<div x y="v"></div>))
    end
  end

  it "r2#10 a block override and super() in an escaping template are escaped (no fail-open)" do
    build_site(
      <<-TOML,
        title = "x"
        base_url = "https://e.example.com"
        [templates]
        autoescape = true
        TOML
      content_files: {"p.md" => "+++\ntitle = \"<x&>\"\n+++\nb\n"},
      template_files: {
        "base.html" => "B[{% block b %}base={{ page.title }}{% endblock %}]",
        "page.html" => "{% extends \"base.html\" %}{% block b %}child={{ page.title }}|{{ super() }}{% endblock %}",
      },
    ) do
      File.read("public/p/index.html").should eq("B[child=&lt;x&amp;&gt;|base=&lt;x&amp;&gt;]")
    end
  end

  it "r2#10 the entry template decides escaping for the whole extends chain" do
    # An HTML entry extending a text-output parent escapes (entry decides,
    # Jinja's one-eval-context-per-render); a text entry does not.
    build_site(
      <<-TOML,
        title = "x"
        base_url = "https://e.example.com"
        [templates]
        autoescape = true
        [outputs]
        page = ["txt"]
        TOML
      content_files: {"p.md" => "+++\ntitle = \"<x>\"\n+++\nb\n"},
      template_files: {
        "base.txt.jinja" => "{{ page.title }}",
        "page.html"      => "{% extends \"base.txt.jinja\" %}",
        "page.txt.jinja" => "{% extends \"base.txt.jinja\" %}",
      },
    ) do
      File.read("public/p/index.html").should eq("&lt;x&gt;") # HTML entry → escaped
      File.read("public/p/index.txt").should eq("<x>")        # txt entry → raw
    end
  end

  # Review round 3 regressions, end to end.

  it "r3#2 a hook destination keeps a semicolonless &name query parameter" do
    build_site(
      <<-TOML,
        title = "x"
        base_url = "https://example.test"
        [templates]
        autoescape = true
        TOML
      content_files: {"p.md" => "+++\ntitle = \"p\"\n+++\n[a](/p?a=1&b=2) [b](/p?a=1&copy=2) [c](/p?a=1&amp;copy;)\n"},
      template_files: {"page.html"              => "{{ content }}",
                       "hooks/render-link.html" => %(<a href="{{ destination | relative_url }}">{{ text }}</a>)},
    ) do
      html = File.read("public/p/index.html")
      html.should contain(%(href="/p?a=1&amp;b=2"))
      html.should contain(%(href="/p?a=1&amp;copy=2"))
      html.should contain(%(href="/p?a=1&amp;copy;"))
      html.should_not contain("©")
    end
  end

  it "r3#3 TOC fields and an image hook's alt are fully escaped text, not raw HTML" do
    build_site(
      <<-TOML,
        title = "x"
        base_url = "https://example.test"
        [templates]
        autoescape = true
        TOML
      content_files: {"p.md" => "+++\ntitle = \"p\"\ntoc = true\n+++\n<h2>\" onmouseover=\"alert(1)</h2>\n\n## Plain &amp; it's\n\n<h2 id=\"<em>owned</em>\">Q</h2>\n\n![<span title=\" onerror=alert(1) x=\">](/missing.png)\n"},
      template_files: {"page.html"               => %({% for h in toc_obj.headers %}<a title="{{ h.title }}" href="{{ h.permalink }}" data-id="{{ h.id }}">x</a>{% endfor %}{{ content }}),
                       "hooks/render-image.html" => %(<img src="{{ destination }}" alt="{{ alt }}">)},
    ) do
      html = File.read("public/p/index.html")
      html.should contain(%(<a title="&quot; onmouseover=&quot;alert(1)"))
      html.should contain(%(<a title="Plain &amp; it&#39;s"))
      html.should_not contain(%(data-id="<em))
      html.should contain(%(alt="&lt;span title=&quot; onerror=alert(1) x=&quot;&gt;"))
      html.should_not contain(%(title="" onmouseover))
      html.should_not contain(%(alt="<span))
    end
  end

  it "never escapes inside a text output, includes and body_template included" do
    q = CANARY.gsub('"', "\\\"")
    build_site(
      <<-TOML,
        title = "x"
        base_url = "https://e.example.com"
        [templates]
        autoescape = true
        [feeds]
        enabled = true
        type = "json"
        [outputs]
        page = ["json", "txt"]
        [[content.generate]]
        source = "items"
        section = "items"
        slug = "id"
        title = '{% include "partials/name.html" %}'
        body_template = "gen.j2"
        TOML
      content_files: {"p.md" => "+++\ntitle = \"T #{q}\"\n+++\nb\n"},
      template_files: {
        "page.html"          => "<h1>{{ page.title }}</h1>{{ content }}",
        "partials/name.html" => "{{ item.name }}",
        "partials/t.html"    => "{{ page.title }}",
        "gen.j2"             => "Body {% include \"partials/name.html\" %} {{ item.name }}",
        "page.json.jinja"    => %({"t": "{% include "partials/t.html" %}"}),
        "page.txt.jinja"     => %({% include "partials/t.html" %}),
        "feed.json.jinja"    => %({"items": [{% for p in pages %}"{% include "partials/f.html" %}"{% endfor %}]}),
        "partials/f.html"    => "{{ p.title }}",
      },
      data_files: {"items.json" => %([{"id": "i1", "name": "N #{q}"}])},
    ) do
      File.read("public/p/index.json").should eq(%({"t": "T #{CANARY}"}))
      File.read("public/p/index.txt").should eq("T #{CANARY}")
      File.read("public/feed.json").should contain(%("T #{CANARY}"))
      # the generated title and body are text: the page template escapes the
      # title once, and the Markdown body carries the record's raw text
      item = File.read("public/items/i1/index.html")
      item.should contain("<h1>N #{ESCAPED}</h1>")
      item.should contain(%(Body N <b a="x">))
      item.should_not contain("Body N &lt;")
      # an HTML page's include still escapes
      File.read("public/p/index.html").should contain("<h1>T #{ESCAPED}</h1>")
    end
  end

  # Every output that is not HTML/XML comes out byte-identical under the
  # default (escaping on) and `autoescape = false`. Text a template renders
  # (output formats, the JSON feed, content.generate) never escapes, and the
  # surfaces hwaro writes itself (search index, robots, llms.txt, manifest,
  # OG images) do not go through template escaping at all.
  it "writes every non-HTML output byte-identical under the default and autoescape = false" do
    q = CANARY.gsub('"', "\\\"")
    base = <<-TOML
      title = "S #{q}"
      description = "D #{q}"
      base_url = "https://e.example.com"
      [feeds]
      enabled = true
      type = "json"
      [search]
      enabled = true
      [robots]
      enabled = true
      [llms]
      enabled = true
      full_enabled = true
      instructions = "I #{q}"
      [pwa]
      enabled = true
      name = "P #{q}"
      [og.auto_image]
      enabled = true
      [outputs]
      page = ["json", "txt", "csv"]
      [[taxonomies]]
      name = "tags"
      [[content.generate]]
      source = "items"
      section = "items"
      slug = "id"
      title = "{{ item.name }} {% include 'partials/n.html' %}"
      description = "{% include 'partials/kit.html' %}"
      body_template = "gen.html"
      TOML
    outputs = [base, base + "\n[templates]\nautoescape = false\n"].map do |toml|
      build_site(
        toml,
        content_files: {"posts/p.md" => "+++\ntitle = \"T #{q}\"\ndescription = \"D #{q}\"\ntags = [\"t #{q}\"]\naliases = [\"/old/\"]\n[extra]\nnote = \"N #{q}\"\n+++\nBody #{CANARY}\n"},
        template_files: {
          "page.html"         => "<h1>{{ page.title }}</h1>{{ content }}",
          "section.html"      => "{{ content }}",
          "partials/n.html"   => "{{ item.name }}",
          "gen.html"          => "Gen {{ item.name }} {% include 'partials/n.html' %} {% include 'partials/kit.html' %}",
          "partials/kit.html" => TEXT_KIT,
          "page.json.jinja"   => %({"t": "{{ page.title }}", "n": "{{ page.extra.note }}", "d": "{{ page.description }}", "k": "{% include 'partials/kit.html' %}"}),
          "page.txt.jinja"    => "{{ page.title }}|{{ page.extra.note }}|{% for t in page.tags %}{{ t }}{% endfor %}|" + TEXT_KIT + "|{{ content }}",
          "page.csv.jinja"    => "{{ page.title }},{{ page.extra.note }},{% include 'partials/kit.html' %}",
          "feed.json.jinja"   => %({"items": [{% for p in pages %}"{{ p.title }} {{ p.description }} {% include 'partials/kit.html' %}"{% endfor %}]}),
        },
        data_files: {"items.json" => %([{"id": "i1", "name": "N #{q}"}])},
      ) do |dir|
        public = File.join(dir, "public")
        files = Dir.glob(File.join(public, "**", "*")).reject { |f| File.directory?(f) || f.ends_with?(".html") || f.ends_with?(".xml") }
        files.to_h { |f| {f.sub(public, ""), File.read(f)} }
      end
    end
    default, off = outputs
    default.keys.sort!.should eq(off.keys.sort!)
    %w[/posts/p/index.json /posts/p/index.txt /posts/p/index.csv /feed.json /search.json /llms.txt /llms-full.txt /robots.txt /manifest.json].each do |path|
      default.has_key?(path).should be_true, "#{path} was not written"
    end
    default["/posts/p/index.txt"].should start_with("T #{CANARY}|N #{CANARY}|")
    default.each { |path, bytes| bytes.should eq(off[path]), path }
  end

  # Review round 4, end to end.

  it "r4#1 a text include without context does not turn escaping off for the page or later pages" do
    q = CANARY.gsub('"', "\\\"")
    build_site(
      %(title = "x"\nbase_url = "https://e.example.com"\n),
      content_files: {"a.md" => "+++\ntitle = \"T #{q}\"\n+++\nb\n", "b.md" => "+++\ntitle = \"T #{q}\"\n+++\nb\n"},
      template_files: {"page.html"       => %({% include "empty.txt.jinja" without context %}{% include "title.html" %}|{{ page.title }}),
                       "empty.txt.jinja" => "",
                       "title.html"      => "{{ page.title }}"},
    ) do
      File.read("public/a/index.html").should eq("T #{ESCAPED}|T #{ESCAPED}")
      File.read("public/b/index.html").should eq("T #{ESCAPED}|T #{ESCAPED}")
    end
  end

  it "r4#2 escapes an HTML page whose front matter picks a text-named template" do
    q = CANARY.gsub('"', "\\\"")
    build_site(
      %(title = "x"\nbase_url = "https://e.example.com"\n[outputs]\npage = ["txt"]\n),
      content_files: {"a.md" => "+++\ntitle = \"T #{q}\"\ntemplate = \"plain.txt\"\n+++\nb\n",
                      "b.md" => "+++\ntitle = \"T #{q}\"\ntemplate = \"page.txt\"\n+++\nb\n"},
      template_files: {"page.html"       => "<h1>{{ page.title }}</h1>",
                       "plain.txt.jinja" => "<h1>{{ page.title }}</h1>",
                       "page.txt.jinja"  => "<h1>{{ page.title }}</h1>"},
    ) do
      File.read("public/a/index.html").should eq("<h1>T #{ESCAPED}</h1>")
      File.read("public/b/index.html").should eq("<h1>T #{ESCAPED}</h1>")
      # the [outputs] text file rendered from the same template stays text
      File.read("public/b/index.txt").should eq("<h1>T #{CANARY}</h1>")
    end
  end

  it "r4#3 expands a shortcode in a text output under the text policy" do
    build_site(
      %(title = "x"\nbase_url = "https://e.example.com"\n[outputs]\npage = ["txt"]\n),
      content_files: {"p.md" => "+++\ntitle = \"p\"\n+++\nb\n"},
      template_files: {"page.html"            => %(<p>{{ echo(label="A&B") }}</p>),
                       "page.txt.jinja"       => %({{ echo(label="A&B") }}),
                       "shortcodes/echo.html" => "{{ label }}"},
    ) do
      File.read("public/p/index.txt").should eq("A&B")
      File.read("public/p/index.html").should eq("<p>A&amp;B</p>")
    end
  end

  it "r4#5 | e on content and summaries escapes the HTML as before 1.0, in HTML and text outputs" do
    tpl = "{{ content | e }}|{{ page.summary | escape | xml_escape }}|{% set c %}<i>{% endset %}{{ c | e }}|{{ \"<b>\" | safe | e }}"
    outputs = ["", "[templates]\nautoescape = false\n"].map do |extra|
      build_site(
        %(title = "x"\nbase_url = "https://e.example.com"\n[outputs]\npage = ["txt"]\n#{extra}),
        content_files: {"p.md" => "+++\ntitle = \"p\"\n+++\nLead & <b>bold</b>\n\n<!-- more -->\n\nRest\n"},
        template_files: {"page.html" => tpl, "page.txt.jinja" => tpl},
      ) { {File.read("public/p/index.html"), File.read("public/p/index.txt")} }
    end
    outputs[0].should eq(outputs[1])
    outputs[0][0].should start_with("&lt;p&gt;Lead &amp;amp; &lt;b&gt;bold&lt;/b&gt;&lt;/p&gt;")
    outputs[0][0].should end_with("|<i>|<b>")
  end
end
