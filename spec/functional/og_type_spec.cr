require "./support/build_helper"

# =============================================================================
# og:type per-page-kind functional tests (gh#601)
#
# `og_type_for` must emit og:type="website" only for landing-style pages
# (homepage, `_index.md` section landings, taxonomy listings, 404) and fall
# back to the configured `[og].type` for ordinary article content.
#
# Regression for gh#601: page-bundle leaves (`some/post/index.md`) carry
# `is_index = true` just like section landings, so keying the override off
# `is_index` rendered og:type="website" for *every* page-bundle post. The
# sentinel `[og].type` below ("ZZARTICLE") makes the misclassification
# unambiguous — a page-bundle post wrongly tagged "website" would never show
# the sentinel.
# =============================================================================

OG_TYPE_CONFIG = <<-TOML
  title = "Test"
  base_url = "http://localhost"

  [og]
  type = "ZZARTICLE"
  TOML

# Every template kind echoes og_all_tags so the assertions stay agnostic to
# which template the renderer picks for a given page kind.
OG_TYPE_TEMPLATES = {
  "index.html"   => "{{ og_all_tags }}",
  "page.html"    => "{{ og_all_tags }}",
  "section.html" => "{{ og_all_tags }}",
}

private def og_type_of(path : String) : String?
  html = File.read(path)
  if m = html.match(/<meta property="og:type" content="([^"]*)">/)
    m[1]
  end
end

describe "og:type per page kind (gh#601)" do
  it "uses the configured [og].type for page-bundle leaves, website for landings" do
    build_site(
      OG_TYPE_CONFIG,
      content_files: {
        # homepage (root index.md)
        "index.md" => "+++\ntitle = \"Home\"\n+++\nHome",
        # flat leaf post
        "posts/flat.md" => "+++\ntitle = \"Flat\"\ndate = 2026-01-01\n+++\nFlat body",
        # page-bundle leaf post (the gh#601 case): index.md inside a dir
        "posts/bundle/index.md" => "+++\ntitle = \"Bundle\"\ndate = 2026-01-01\n+++\nBundle body",
        # deeply nested page-bundle leaf post
        "archive/sec/web-security/websocket/index.md" => "+++\ntitle = \"WS\"\ndate = 2026-01-01\n+++\nWS body",
        # section landing (_index.md -> Models::Section)
        "blog/_index.md" => "+++\ntitle = \"Blog\"\n+++\nBlog landing",
        "blog/post.md"   => "+++\ntitle = \"Blog Post\"\ndate = 2026-01-01\n+++\nBlog body",
      },
      template_files: OG_TYPE_TEMPLATES,
    ) do
      # Landing-style pages -> website
      og_type_of("public/index.html").should eq("website")
      og_type_of("public/blog/index.html").should eq("website")

      # Article content -> configured [og].type, regardless of bundle layout
      og_type_of("public/posts/flat/index.html").should eq("ZZARTICLE")
      og_type_of("public/posts/bundle/index.html").should eq("ZZARTICLE")
      og_type_of("public/archive/sec/web-security/websocket/index.html").should eq("ZZARTICLE")
      og_type_of("public/blog/post/index.html").should eq("ZZARTICLE")
    end
  end

  it "classifies multilingual page-bundle leaves and homepages correctly" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"
      default_language = "en"

      [og]
      type = "ZZARTICLE"

      [languages.en]
      language_name = "English"
      weight = 1

      [languages.ko]
      language_name = "한국어"
      weight = 2
      TOML

    build_site(
      config,
      content_files: {
        "index.md"               => "+++\ntitle = \"Home\"\n+++\nHome",
        "index.ko.md"            => "+++\ntitle = \"홈\"\n+++\n홈",
        "archive/ws/index.md"    => "+++\ntitle = \"WS\"\ndate = 2026-01-01\n+++\nWS",
        "archive/ws/index.ko.md" => "+++\ntitle = \"웹소켓\"\ndate = 2026-01-01\n+++\n웹소켓",
      },
      template_files: OG_TYPE_TEMPLATES,
    ) do
      # Homepages (default + per-language) -> website
      og_type_of("public/index.html").should eq("website")
      og_type_of("public/ko/index.html").should eq("website")

      # Page-bundle leaves in both languages -> configured type
      og_type_of("public/archive/ws/index.html").should eq("ZZARTICLE")
      og_type_of("public/ko/archive/ws/index.html").should eq("ZZARTICLE")
    end
  end
end
