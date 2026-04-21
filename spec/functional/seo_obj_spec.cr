require "./support/build_helper"

# =============================================================================
# SEO object functional tests
#
# Verifies the seo structured object exposes individual SEO field values
# for custom meta tag markup in templates.
# =============================================================================

SEO_CONFIG = <<-TOML
  title = "Test"
  base_url = "http://localhost"

  [og]
  type = "website"
  twitter_card = "summary"
  twitter_site = "@testsite"
  twitter_creator = "@testauthor"
  fb_app_id = "123456"
  default_image = "/img/default.png"
  TOML

SEO_BASIC_CONFIG = <<-TOML
  title = "Test"
  base_url = "http://localhost"
  TOML

describe "SEO: seo object exposes structured SEO data" do
  it "exposes canonical_url with base_url" do
    build_site(
      SEO_BASIC_CONFIG,
      content_files: {
        "about.md" => "+++\ntitle = \"About\"\n+++\nAbout page",
      },
      template_files: {
        "page.html" => "CANONICAL={{ seo.canonical_url }}",
      },
    ) do
      html = File.read("public/about/index.html")
      html.should contain("CANONICAL=http://localhost/about/")
    end
  end

  it "exposes og_type from config" do
    build_site(
      SEO_CONFIG,
      content_files: {
        "post.md" => "+++\ntitle = \"Post\"\n+++\nContent",
      },
      template_files: {
        "page.html" => "TYPE={{ seo.og_type }}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("TYPE=website")
    end
  end

  it "exposes twitter config values" do
    build_site(
      SEO_CONFIG,
      content_files: {
        "post.md" => "+++\ntitle = \"Post\"\n+++\nContent",
      },
      template_files: {
        "page.html" => "CARD={{ seo.twitter_card }}|SITE={{ seo.twitter_site }}|CREATOR={{ seo.twitter_creator }}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("CARD=summary")
      html.should contain("SITE=@testsite")
      html.should contain("CREATOR=@testauthor")
    end
  end

  it "exposes fb_app_id" do
    build_site(
      SEO_CONFIG,
      content_files: {
        "post.md" => "+++\ntitle = \"Post\"\n+++\nContent",
      },
      template_files: {
        "page.html" => "FB={{ seo.fb_app_id }}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("FB=123456")
    end
  end

  it "exposes resolved og_image URL" do
    build_site(
      SEO_CONFIG,
      content_files: {
        "post.md" => "+++\ntitle = \"Post\"\n+++\nContent",
      },
      template_files: {
        "page.html" => "IMG={{ seo.og_image }}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("IMG=http://localhost/img/default.png")
    end
  end

  it "uses page image over default_image" do
    build_site(
      SEO_CONFIG,
      content_files: {
        "post.md" => "+++\ntitle = \"Post\"\nimage = \"/img/custom.jpg\"\n+++\nContent",
      },
      template_files: {
        "page.html" => "IMG={{ seo.og_image }}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("IMG=http://localhost/img/custom.jpg")
    end
  end

  it "defaults og_type to article when not configured" do
    build_site(
      SEO_BASIC_CONFIG,
      content_files: {
        "post.md" => "+++\ntitle = \"Post\"\n+++\nContent",
      },
      template_files: {
        "page.html" => "TYPE={{ seo.og_type }}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("TYPE=article")
    end
  end
end
