require "../support/build_helper"

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

# Regression: `image = "cover.png"` beside a bundle's index.md is published at
# the page's URL, but og:image / twitter:image / JSON-LD / seo.og_image
# resolved it against the site root (`/cover.png`, a 404).
describe "SEO: bundle-relative page image" do
  it "points og:image and JSON-LD at the bundle asset" do
    build_site(
      SEO_BASIC_CONFIG,
      content_files: {
        "posts/trip/index.md"  => "+++\ntitle = \"Trip\"\nimage = \"cover.png\"\n+++\nbody",
        "posts/trip/cover.png" => "png",
      },
      template_files: {"page.html" => "{{ og_all_tags | safe }}|{{ jsonld | safe }}|{{ seo.og_image }}"},
    ) do
      html = File.read("public/posts/trip/index.html")
      html.should contain(%(og:image" content="http://localhost/posts/trip/cover.png"))
      html.should contain(%(twitter:image" content="http://localhost/posts/trip/cover.png"))
      html.should contain(%("image":"http://localhost/posts/trip/cover.png"))
      html.should contain("|http://localhost/posts/trip/cover.png")
      html.should_not contain("http://localhost/cover.png")
      File.exists?("public/posts/trip/cover.png").should be_true
    end
  end
end

# og:url is percent-encoded; og:image / twitter:image / JSON-LD image emitted
# the raw path, so `my photo.png` or a Unicode filename produced an invalid
# URL that scrapers reject.
describe "SEO: social image URLs are percent-encoded" do
  it "encodes spaces and non-ASCII in og:image and JSON-LD image" do
    build_site(
      SEO_BASIC_CONFIG,
      content_files: {
        "posts/trip/index.md"     => "+++\ntitle = \"Trip\"\nimage = \"my photo.png\"\n+++\nbody",
        "posts/trip/my photo.png" => "png",
        "about.md"                => "+++\ntitle = \"About\"\nimage = \"/img/사진.png\"\n+++\nbody",
      },
      template_files: {"page.html" => "{{ og_all_tags | safe }}|{{ jsonld | safe }}"},
    ) do
      trip = File.read("public/posts/trip/index.html")
      trip.should contain(%(og:image" content="http://localhost/posts/trip/my%20photo.png"))
      trip.should contain(%(twitter:image" content="http://localhost/posts/trip/my%20photo.png"))
      trip.should contain(%("image":"http://localhost/posts/trip/my%20photo.png"))
      about = File.read("public/about/index.html")
      about.should contain(%(og:image" content="http://localhost/img/%EC%82%AC%EC%A7%84.png"))
    end
  end
end

# Regression: the social-image encoder escaped the whole value once it held a
# space or non-ASCII byte, so a cache-busting query (`사진.png?v=2`) became
# `…png%3Fv%3D2` (a 404), and JSON-LD also encoded external URLs that og:image
# leaves as written — the three surfaces disagreed.
describe "SEO: social image query strings and external URLs" do
  it "encodes only the path and leaves external image URLs as written" do
    build_site(
      SEO_BASIC_CONFIG,
      content_files: {
        "about.md" => "+++\ntitle = \"About\"\nimage = \"/img/사진.png?v=2&s=1#top\"\n+++\nbody",
        "cdn.md"   => "+++\ntitle = \"Cdn\"\nimage = \"https://cdn.example.com/사진 1.png?w=1\"\n+++\nbody",
      },
      template_files: {"page.html" => "{{ og_all_tags | safe }}|{{ jsonld | safe }}|{{ seo.og_image }}"},
    ) do
      about = File.read("public/about/index.html")
      encoded = "http://localhost/img/%EC%82%AC%EC%A7%84.png?v=2&amp;s=1#top"
      about.should contain(%(og:image" content="#{encoded}"))
      about.should contain(%(twitter:image" content="#{encoded}"))
      # JSON-LD escapes `&` as `&`; seo.og_image is the raw URL.
      about.should contain(%("image":"http://localhost/img/%EC%82%AC%EC%A7%84.png?v=2\\u0026s=1#top"))
      about.should contain("|http://localhost/img/%EC%82%AC%EC%A7%84.png?v=2&s=1#top")

      cdn = File.read("public/cdn/index.html")
      raw = "https://cdn.example.com/사진 1.png?w=1"
      cdn.should contain(%(og:image" content="#{raw}"))
      cdn.should contain(%(twitter:image" content="#{raw}"))
      cdn.should contain(%("image":"#{raw}"))
    end
  end
end
