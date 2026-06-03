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

  [[taxonomies]]
  name = "tags"
  TOML

# Every template kind echoes og_all_tags so the assertions stay agnostic to
# which template the renderer picks for a given page kind.
OG_TYPE_TEMPLATES = {
  "index.html"   => "{{ og_all_tags }}",
  "page.html"    => "{{ og_all_tags }}",
  "section.html" => "{{ og_all_tags }}",
  "404.html"     => "{{ og_all_tags }}",
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
        # flat leaf post (carries a tag so the taxonomy pages get generated)
        "posts/flat.md" => "+++\ntitle = \"Flat\"\ndate = 2026-01-01\ntags = [\"x\"]\n+++\nFlat body",
        # page-bundle leaf post (the gh#601 case): index.md inside a dir
        "posts/bundle/index.md" => "+++\ntitle = \"Bundle\"\ndate = 2026-01-01\n+++\nBundle body",
        # one-level page bundle: section resolves to "" yet it is NOT the
        # homepage — the case a naive `is_index && section.empty?` test breaks
        "guide/index.md" => "+++\ntitle = \"Guide\"\ndate = 2026-01-01\n+++\nGuide body",
        # deeply nested page-bundle leaf post
        "archive/sec/web-security/websocket/index.md" => "+++\ntitle = \"WS\"\ndate = 2026-01-01\n+++\nWS body",
        # section landing (_index.md -> Models::Section)
        "blog/_index.md" => "+++\ntitle = \"Blog\"\n+++\nBlog landing",
        "blog/post.md"   => "+++\ntitle = \"Blog Post\"\ndate = 2026-01-01\n+++\nBlog body",
      },
      template_files: OG_TYPE_TEMPLATES,
    ) do
      # Landing-style pages -> website
      og_type_of("public/index.html").should eq("website")        # homepage
      og_type_of("public/blog/index.html").should eq("website")   # section landing
      og_type_of("public/tags/index.html").should eq("website")   # taxonomy index
      og_type_of("public/tags/x/index.html").should eq("website") # taxonomy term
      og_type_of("public/404.html").should eq("website")          # synthetic 404

      # Article content -> configured [og].type, regardless of bundle layout
      og_type_of("public/posts/flat/index.html").should eq("ZZARTICLE")
      og_type_of("public/posts/bundle/index.html").should eq("ZZARTICLE")
      og_type_of("public/guide/index.html").should eq("ZZARTICLE")
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

  # The homepage discriminator (`home?`) is shared with JSON-LD schema
  # selection, which had the same `is_index && section.empty?` flaw: a
  # one-level page bundle (`content/guide/index.md`) resolves to an empty
  # section and was wrongly served the WebSite schema instead of an Article.
  it "emits Article (not WebSite) JSON-LD for a one-level page bundle" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"
      description = "A site about things"
      TOML

    build_site(
      config,
      content_files: {
        "index.md"       => "+++\ntitle = \"\"\n+++\nHome",
        "guide/index.md" => "+++\ntitle = \"Guide\"\ndate = 2026-01-01\n+++\nGuide body",
      },
      template_files: {
        "index.html" => "{{ jsonld }}",
        "page.html"  => "{{ jsonld }}",
      },
    ) do
      # The real homepage stays a WebSite.
      home = File.read("public/index.html")
      home.should contain(%("@type":"WebSite"))

      # The one-level bundle is article content: Article with a real headline,
      # never the WebSite schema.
      guide = File.read("public/guide/index.html")
      guide.should contain(%("@type":"Article"))
      guide.should contain(%("headline":"Guide"))
      guide.should_not contain(%("@type":"WebSite"))
    end
  end
end
