require "./support/build_helper"

# ---------------------------------------------------------------------------
# Templates are Jinja2 (Crinja): macro definitions, macro invocations,
# `{% call %}` bodies and `{% raw %}` blocks must all survive the shortcode
# pass that `apply_template` runs over the RAW template source before Crinja
# parses it. That pass reads every `{{ name(...) }}` as a direct shortcode
# call and has no notion of Jinja block structure, so each of these used to be
# rewritten away (a macro call became
# `<!-- hwaro: missing shortcode 'name' -->`, a raw block's example expanded).
# ---------------------------------------------------------------------------
describe "Build Integration: template macros" do
  it "renders a macro defined and called in the same template" do
    template = <<-HTML
      {% macro nav_item(href, label) %}<a href="{{ href }}">{{ label }}</a>{% endmacro %}
      <nav>{{ nav_item("/", "Home") }}</nav>
      HTML

    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nBody"},
      template_files: {"page.html" => template},
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<a href="/">Home</a>))
      html.should_not contain("missing shortcode")
    end
  end

  it "preserves a {% call %} block body through caller()" do
    template = <<-HTML
      {% macro box() %}<div class="box">{{ caller() }}</div>{% endmacro %}
      {% call box() %}INNER{% endcall %}
      HTML

    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nBody"},
      template_files: {"page.html" => template},
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<div class="box">INNER</div>))
      html.should_not contain("missing shortcode")
    end
  end

  it "renders a macro imported from another template under its alias" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nBody"},
      template_files: {
        "macros.html" => %({% macro btn(label) %}<button>{{ label }}</button>{% endmacro %}),
        "page.html"   => %({% from "macros.html" import btn as button %}<p>{{ button("Go") }}</p>),
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("<button>Go</button>")
      html.should_not contain("missing shortcode")
    end
  end

  # The likeliest real-world shape of the same bug, and the one the original
  # fix missed: shared macros declared in a base layout and called from the
  # template that `{% extends %}` it. The child's own source has no
  # `{% macro %}`, so a single-template scan saw an ordinary shortcode call and
  # replaced it with `<!-- hwaro: missing shortcode 'shared' -->` plus a bogus
  # "Shortcode template 'shortcodes/shared' not found." warning.
  it "renders a macro inherited through {% extends %}" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nBody"},
      template_files: {
        "base.html" => %({% macro shared(x) %}<i>{{ x }}</i>{% endmacro %}<html>{% block main %}{% endblock %}</html>),
        "page.html" => %({% extends "base.html" %}{% block main %}<p>{{ shared("inherited") }}</p>{% endblock %}),
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("<i>inherited</i>")
      html.should_not contain("missing shortcode")
    end
  end

  # Two levels up, so the union really is transitive and not just one hop.
  it "renders a macro inherited through a chain of {% extends %}" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nBody"},
      template_files: {
        "root.html"   => %({% macro deep(x) %}<b>{{ x }}</b>{% endmacro %}<html>{% block main %}{% endblock %}</html>),
        "middle.html" => %({% extends "root.html" %}),
        "page.html"   => %({% extends "middle.html" %}{% block main %}<p>{{ deep("two-levels") }}</p>{% endblock %}),
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("<b>two-levels</b>")
      html.should_not contain("missing shortcode")
    end
  end

  it "keeps shortcode-shaped syntax inside {% raw %} literal" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nBody"},
      template_files: {
        "page.html" => %(<p>Example: {% raw %}{{ youtube("dQw4w9WgXcQ") }}{% endraw %}</p>),
      },
    ) do
      html = File.read("public/index.html")
      html.should contain(%({{ youtube("dQw4w9WgXcQ") }}))
      html.should_not contain("<iframe")
    end
  end

  it "still drops (and comments) a genuinely missing shortcode call" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nBody"},
      template_files: {"page.html" => %(<p>{{ no_such_thing("x") }}</p>)},
    ) do
      html = File.read("public/index.html")
      html.should contain("missing shortcode 'no_such_thing'")
    end
  end
end
