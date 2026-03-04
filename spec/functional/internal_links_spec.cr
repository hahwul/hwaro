require "./support/build_helper"

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
        "blog/_index.md"  => "---\ntitle: Blog\n---\n",
        "blog/post.md"    => "---\ntitle: Post\n---\nPost content",
        "docs/_index.md"  => "---\ntitle: Docs\n---\n",
        "docs/guide.md"   => "---\ntitle: Guide\n---\nCheck the [blog post](@/blog/post.md)",
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
