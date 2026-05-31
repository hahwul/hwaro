require "./support/build_helper"

# =============================================================================
# Related-posts rendering functional test.
#
# Verifies the scaffold's guarded related block — {% if page.related_posts %}
# … {% for r in page.related_posts %} … — renders when [related] is enabled
# (self-excluded, limit-respected) and renders nothing when it is disabled.
# =============================================================================

RELATED_POST_TEMPLATE = <<-HTML
  <article>
  {{ content }}
  {% if page.related_posts %}
  <aside class="related-posts">
    {% for r in page.related_posts %}
    <a href="{{ r.url }}">{{ r.title }}</a>
    {% endfor %}
  </aside>
  {% endif %}
  </article>
  HTML

RELATED_CONTENT = {
  "posts/_index.md" => "+++\ntitle = \"Posts\"\npage_template = \"post\"\n+++\n",
  "posts/a.md"      => "+++\ntitle = \"AAA\"\ndate = \"2026-01-01\"\ntags = [\"crystal\"]\n+++\nA",
  "posts/b.md"      => "+++\ntitle = \"BBB\"\ndate = \"2026-01-02\"\ntags = [\"crystal\"]\n+++\nB",
  "posts/c.md"      => "+++\ntitle = \"CCC\"\ndate = \"2026-01-03\"\ntags = [\"crystal\"]\n+++\nC",
}

RELATED_TEMPLATES = {
  "page.html"    => "{{ content }}",
  "section.html" => "{{ content }}",
  "post.html"    => RELATED_POST_TEMPLATE,
}

describe "Related posts rendering" do
  it "renders related posts (self-excluded) when [related] is enabled" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [[taxonomies]]
      name = "tags"

      [related]
      enabled = true
      limit = 5
      taxonomies = ["tags"]
      TOML

    build_site(config, content_files: RELATED_CONTENT, template_files: RELATED_TEMPLATES) do
      a = File.read("public/posts/a/index.html")
      a.should contain(%(class="related-posts"))
      # The other two crystal-tagged posts are related…
      a.should contain(">BBB<")
      a.should contain(">CCC<")
      # …but the post never lists itself.
      a.should_not contain(">AAA<")
    end
  end

  it "renders no related block when [related] is disabled" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [[taxonomies]]
      name = "tags"
      TOML

    build_site(config, content_files: RELATED_CONTENT, template_files: RELATED_TEMPLATES) do
      File.read("public/posts/a/index.html").should_not contain("related-posts")
    end
  end
end
