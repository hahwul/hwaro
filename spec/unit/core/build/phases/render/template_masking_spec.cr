require "../../../../../support/build_helper"

describe "Render template masking" do
  # Regression: the shortcode pass over the raw template read the recursive
  # loop's `{{ loop(item.children) }}` as a shortcode call, so every nested
  # level became `<!-- hwaro: missing shortcode 'loop' -->`.
  it "keeps a recursive for loop's loop() call" do
    template = <<-HTML
      {% set tree = [{"n": "a", "c": [{"n": "b", "c": []}]}] %}
      <ul>{% for i in tree recursive %}<li>{{ i.n }}{% if i.c %}<ul>{{ loop(i.c) }}</ul>{% endif %}</li>{% endfor %}</ul>
      HTML

    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nBody"},
      template_files: {"page.html" => template},
    ) do
      html = File.read("public/index.html")
      html.should contain("<ul><li>a<ul><li>b</li></ul></li></ul>")
      html.should_not contain("missing shortcode")
    end
  end
end
