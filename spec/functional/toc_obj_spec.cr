require "./support/build_helper"

# =============================================================================
# TOC object functional tests
#
# Verifies toc_obj exposes structured header data alongside pre-rendered HTML.
# =============================================================================

TOC_CONFIG = <<-TOML
  title = "Test"
  base_url = "http://localhost"
  TOML

describe "TOC: toc_obj.headers exposes structured header data" do
  it "exposes title, level, and id for each header" do
    build_site(
      TOC_CONFIG,
      content_files: {
        "post.md" => "+++\ntitle = \"Post\"\ntoc = true\ninsert_anchor_links = true\n+++\n## First\n## Second\n",
      },
      template_files: {
        "page.html" => "{% for h in toc_obj.headers %}[T={{ h.title }}|L={{ h.level }}|ID={{ h.id }}]{% endfor %}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("[T=First|L=2|ID=first]")
      html.should contain("[T=Second|L=2|ID=second]")
    end
  end

  it "exposes nested children" do
    build_site(
      TOC_CONFIG,
      content_files: {
        "post.md" => "+++\ntitle = \"Post\"\ntoc = true\ninsert_anchor_links = true\n+++\n## Parent\n### Child\n## Another\n",
      },
      template_files: {
        "page.html" => "{% for h in toc_obj.headers %}[{{ h.title }}{% for c in h.children %}({{ c.title }}){% endfor %}]{% endfor %}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("[Parent(Child)]")
      html.should contain("[Another]")
    end
  end

  it "returns empty headers when toc is disabled" do
    build_site(
      TOC_CONFIG,
      content_files: {
        "post.md" => "+++\ntitle = \"Post\"\ntoc = false\n+++\n## Heading\n",
      },
      template_files: {
        "page.html" => "HEADERS={% for h in toc_obj.headers %}X{% endfor %}END",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("HEADERS=END")
    end
  end

  it "preserves toc_obj.html backward compatibility" do
    build_site(
      TOC_CONFIG,
      content_files: {
        "post.md" => "+++\ntitle = \"Post\"\ntoc = true\ninsert_anchor_links = true\n+++\n## Hello\n",
      },
      template_files: {
        "page.html" => "HTML={{ toc_obj.html }}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("<ul>")
      html.should contain("Hello")
    end
  end

  it "exposes permalink for each header" do
    build_site(
      TOC_CONFIG,
      content_files: {
        "post.md" => "+++\ntitle = \"Post\"\ntoc = true\ninsert_anchor_links = true\n+++\n## My Section\n",
      },
      template_files: {
        "page.html" => "{% for h in toc_obj.headers %}LINK={{ h.permalink }}{% endfor %}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("LINK=")
      html.should contain("my-section")
    end
  end

  # The scaffolds (docs/book) render the TOC with the guarded wrapper
  # `{% if toc %}<nav class="...-toc">{{ toc }}</nav>{% endif %}`. Verify the
  # wrapper appears with a header link when toc is on, and is omitted when off.
  it "renders the guarded toc wrapper only when toc is enabled" do
    build_site(
      TOC_CONFIG,
      content_files: {
        "on.md"  => "+++\ntitle = \"On\"\ntoc = true\ninsert_anchor_links = true\n+++\n## Alpha\n## Beta\n",
        "off.md" => "+++\ntitle = \"Off\"\ntoc = false\n+++\n## Alpha\n",
      },
      template_files: {
        "page.html" => %({% if toc %}<nav class="docs-toc">{{ toc }}</nav>{% endif %}OUT={{ content }}),
      },
    ) do
      on = File.read("public/on/index.html")
      on.should contain(%(<nav class="docs-toc">))
      on.should contain("<ul>")
      on.should contain("#alpha")

      off = File.read("public/off/index.html")
      off.should_not contain("docs-toc")
    end
  end
end
