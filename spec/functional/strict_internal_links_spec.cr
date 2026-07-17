require "./support/build_helper"

# =============================================================================
# Strict broken internal links functional tests
#
# `[links] broken_internal = "error"` must fail the build with ONE
# aggregated classified error listing every unresolved @/ link, while the
# default "warn" mode keeps today's log-and-continue behavior.
# =============================================================================

private STRICT_LINKS_CONFIG = <<-TOML
  title = "Test Site"
  base_url = "http://localhost"

  [links]
  broken_internal = "error"
  TOML

describe "Strict internal links: error mode" do
  it "fails the build with one aggregated error listing every offender" do
    ex = expect_raises(Hwaro::HwaroError) do
      build_site(
        STRICT_LINKS_CONFIG,
        content_files: {
          "page.md"  => "---\ntitle: Page\n---\nSee [missing](@/nonexistent.md)",
          "other.md" => "---\ntitle: Other\n---\nAn [empty](@/) link",
        },
        template_files: {"page.html" => "{{ content }}"},
        parallel: true,
      ) { }
    end

    ex.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
    message = ex.message.not_nil!
    message.should contain("2 broken internal links")
    message.should contain("page.md → @/nonexistent.md (page not found)")
    message.should contain("other.md → @/ (empty link)")
    ex.hint.not_nil!.should contain(%([links] broken_internal = "warn"))
  end

  it "does not flag resolvable links" do
    build_site(
      STRICT_LINKS_CONFIG,
      content_files: {
        "about.md" => "---\ntitle: About\n---\nAbout page",
        "page.md"  => "---\ntitle: Page\n---\nSee [About](@/about.md)",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/page/index.html")
      html.should contain("href=\"/about/\"")
    end
  end
end

describe "Strict internal links: warn mode (default)" do
  it "builds successfully and leaves the unresolved markup unchanged" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "page.md" => "---\ntitle: Page\n---\nSee [missing](@/nonexistent.md)",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/page/index.html")
      html.should contain("@/nonexistent.md")
    end
  end
end
