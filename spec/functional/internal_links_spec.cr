require "../support/build_helper"

# =============================================================================
# Internal link resolution functional tests
#
# Verifies @/path.md link format resolves to correct URLs,
# anchor handling, and behavior for non-existent paths.
# =============================================================================

describe "Internal Links: Basic resolution" do
  it "resolves @/path.md links to correct URLs" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "about.md"   => "---\ntitle: About\n---\nAbout page",
        "contact.md" => "---\ntitle: Contact\n---\nSee [About](@/about.md) for more info",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/contact/index.html")
      html.should contain("href=\"/about/\"")
      html.should_not contain("@/about.md")
    end
  end

  it "resolves @/path.md links in nested sections" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/post.md"   => "---\ntitle: Post\n---\nPost content",
        "docs/_index.md" => "---\ntitle: Docs\n---\n",
        "docs/guide.md"  => "---\ntitle: Guide\n---\nCheck the [blog post](@/blog/post.md)",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ content }}",
      },
    ) do
      html = File.read("public/docs/guide/index.html")
      html.should contain("href=\"/blog/post/\"")
      html.should_not contain("@/blog/post.md")
    end
  end
end

describe "Internal Links: Anchor handling" do
  it "preserves anchors in @/path.md#section links" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "about.md"   => "---\ntitle: About\n---\n## Team\n\nOur team",
        "contact.md" => "---\ntitle: Contact\n---\nSee [our team](@/about.md#team)",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/contact/index.html")
      html.should contain("href=\"/about/#team\"")
      html.should_not contain("@/about.md")
    end
  end
end

describe "Internal Links: Non-existent paths" do
  it "leaves unresolved internal links unchanged" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "page.md" => "---\ntitle: Page\n---\nSee [missing](@/nonexistent.md)",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/page/index.html")
      # Unresolved link stays as @/nonexistent.md
      html.should contain("@/nonexistent.md")
    end
  end
end

describe "Internal Links: Multiple links in one page" do
  it "resolves multiple @/ links in a single page" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "about.md"   => "---\ntitle: About\n---\nAbout page",
        "contact.md" => "---\ntitle: Contact\n---\nContact page",
        "index.md"   => "---\ntitle: Home\n---\nSee [About](@/about.md) and [Contact](@/contact.md) for more.",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/index.html")
      html.should contain("href=\"/about/\"")
      html.should contain("href=\"/contact/\"")
      html.should_not contain("@/about.md")
      html.should_not contain("@/contact.md")
    end
  end
end

describe "Internal Links: Link to section _index" do
  it "resolves @/ link pointing to a section index" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\nBlog index",
        "index.md"       => "---\ntitle: Home\n---\nVisit the [Blog](@/blog/_index.md)",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ content }}",
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("href=\"/blog/\"")
      html.should_not contain("@/blog/_index.md")
    end
  end
end

describe "Internal Links: Mixed internal and external links" do
  it "resolves internal links without affecting external ones" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "about.md" => "---\ntitle: About\n---\nAbout page",
        "page.md"  => "---\ntitle: Page\n---\nSee [About](@/about.md) and [Google](https://google.com)",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/page/index.html")
      html.should contain("href=\"/about/\"")
      html.should contain("href=\"https://google.com\"")
      html.should_not contain("@/about.md")
    end
  end
end

describe "Internal Links: Link with custom slug target" do
  it "resolves @/ link to page with custom slug" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "my-page.md" => "---\ntitle: My Page\nslug: custom-url\n---\nCustom slug page",
        "other.md"   => "---\ntitle: Other\n---\nLink to [My Page](@/my-page.md)",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/other/index.html")
      html.should contain("href=\"/custom-url/\"")
      html.should_not contain("@/my-page.md")
    end
  end
end
