require "../../../spec_helper"

private def reads?(*sources : String) : Bool
  templates = {} of String => String
  sources.each_with_index { |src, i| templates["t#{i}.html"] = src }
  Hwaro::Core::Build::SummaryReaders.read?(templates)
end

describe Hwaro::Core::Build::SummaryReaders do
  it "sees templates that name the summary" do
    reads?("{{ page.summary }}").should be_true
    reads?("{% for p in section.pages %}{{ p.summary_truncated }}{% endfor %}").should be_true
    reads?("{{ page_summary }}").should be_true
  end

  it "sees whole page objects printed, serialized or iterated" do
    {
      "{{ page }}",
      "{{ section }}",
      "{{ site }}",
      "{{ section.pages }}",
      "{{ page.lower }}",
      "{{ pages | first }}",
      "{{ page | tojson }}",
      "{{ p | inspect }}",
      "{{ page | list }}",
      "{{ \"x\" ~ page }}",
      "{{ get_page(path=\"a.md\") }}",
      "{% for k, v in page %}{{ v }}{% endfor %}",
      "{% for f in site.data.fields %}{{ page[f] }}{% endfor %}",
      "{{ page | attr(name) }}",
      "{{ section.pages | map(attribute=field) | join }}",
      "{% for p in section.pages %}{{ p }}{% endfor %}",
      "{% for p in pages | sort(attribute=\"date\") %}{{ p | join }}{% endfor %}",
      "{% for p in section.pages[:3] %}{{ p }}{% endfor %}",
      "{% set s = get_section(path=\"posts\") %}{% for p in s.pages %}{{ p }}{% endfor %}",
      "{% for t in get_taxonomy(kind=\"tags\").items %}{% for p in t.pages %}{{ p }}{% endfor %}{% endfor %}",
      "{% for p in section.pages %}{{ card(p) }}{% endfor %}",
      "{% for p in section.pages %}{% set html = card(post=p) %}{% endfor %}",
    }.each do |source|
      reads?(source).should be_true, source
    end
  end

  it "follows a loop variable into a template it includes" do
    reads?(%({% for p in section.pages %}{% include "card.html" %}{% endfor %}), "<li>{{ p }}</li>").should be_true
  end

  it "ignores templates that only read named fields" do
    {
      "{{ content }}",
      "{{ page.title }} {{ page.date }} {{ page.lower.url }} {{ page.permalink }}",
      "{% for tag in page.tags %}<span>{{ tag }}</span>{% endfor %}",
      "{% for p in section.pages %}<a href=\"{{ p.url }}\">{{ p.title }}</a>{% endfor %}",
      "{{ section.pages | length }} {% if page and page.title %}{{ page.title }}{% endif %}",
      "{{ \"a\" if page.higher else \"b\" }} {{ page.tags | join(\", \") }}",
      "{% set posts = get_section(path=\"posts\") %}{% for post in posts.pages %}{{ post.title }}{% endfor %}",
      "{% for term in get_taxonomy(kind=\"tags\").items %}{{ term.name }} ({{ term.count }}){% endfor %}",
      "{% for p in pages | slice(end=10) %}{{ p.title }}{% endfor %}",
      "{{ get_url(path=page.path) }} {{ site.title | upper }}",
      "<h1>{{ taxonomy_name }}: {{ taxonomy_term }}</h1> {{ pagination }} {{ section_list }}",
    }.each do |source|
      reads?(source).should be_false, source
    end
  end

  it "keeps the ssg-benchmark heavy sidebar gated" do
    reads?(<<-JINJA).should be_false
      {% set posts_section = get_section(path="posts") %}
      {% for post in posts_section.pages %}{% if loop.index <= 10 %}
      <li><a href="{{ post.url }}">{{ post.title }}</a></li>
      {% endif %}{% endfor %}
      {% set tags_taxonomy = get_taxonomy(kind="tags") %}
      {% for term in tags_taxonomy.items %}<a href="/tags/{{ term.slug }}/">{{ term.name }} ({{ term.count }})</a>{% endfor %}
      JINJA
  end
end
