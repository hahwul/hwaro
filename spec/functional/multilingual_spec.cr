require "./support/build_helper"

# =============================================================================
# Multilingual build functional tests
#
# Verifies language-specific URL generation, translation links between pages,
# and section list isolation per language.
# =============================================================================

MULTILINGUAL_CONFIG = <<-TOML
  title = "Test Site"
  base_url = "http://localhost"
  default_language = "en"

  [languages.ko]
  language_name = "한국어"
  weight = 1
  TOML

describe "Multilingual: URL generation" do
  it "generates language-prefixed URLs for non-default language" do
    build_site(
      MULTILINGUAL_CONFIG,
      content_files: {
        "about.md"    => "---\ntitle: About\n---\nAbout in English",
        "about.ko.md" => "---\ntitle: 소개\n---\n한국어 소개",
      },
      template_files: {
        "page.html" => "TITLE={{ page_title }}|URL={{ page_url }}|{{ content }}",
      },
    ) do
      # Default language (en) — no prefix
      File.exists?("public/about/index.html").should be_true
      en_html = File.read("public/about/index.html")
      en_html.should contain("TITLE=About")
      en_html.should contain("URL=/about/")

      # Non-default language (ko) — prefixed with /ko/
      File.exists?("public/ko/about/index.html").should be_true
      ko_html = File.read("public/ko/about/index.html")
      ko_html.should contain("TITLE=소개")
      ko_html.should contain("URL=/ko/about/")
    end
  end

  it "generates language-prefixed URLs for section pages" do
    build_site(
      MULTILINGUAL_CONFIG,
      content_files: {
        "blog/_index.md"    => "---\ntitle: Blog\n---\n",
        "blog/_index.ko.md" => "---\ntitle: 블로그\n---\n",
        "blog/post.md"      => "---\ntitle: Post\n---\nEnglish post",
        "blog/post.ko.md"   => "---\ntitle: 포스트\n---\n한국어 포스트",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "TITLE={{ section.title }}|{{ section_list }}",
      },
    ) do
      File.exists?("public/blog/index.html").should be_true
      File.exists?("public/ko/blog/index.html").should be_true
      File.exists?("public/blog/post/index.html").should be_true
      File.exists?("public/ko/blog/post/index.html").should be_true
    end
  end
end

describe "Multilingual: Translation links" do
  it "exposes page.translations for translated pages" do
    build_site(
      MULTILINGUAL_CONFIG,
      content_files: {
        "about.md"    => "---\ntitle: About\n---\nEnglish",
        "about.ko.md" => "---\ntitle: 소개\n---\n한국어",
      },
      template_files: {
        "page.html" => "TRANSLATIONS={% for t in page.translations %}{{ t.code }}:{{ t.url }},{% endfor %}",
      },
    ) do
      en_html = File.read("public/about/index.html")
      en_html.should contain("en:/about/")
      en_html.should contain("ko:/ko/about/")

      ko_html = File.read("public/ko/about/index.html")
      ko_html.should contain("en:/about/")
      ko_html.should contain("ko:/ko/about/")
    end
  end
end

describe "Multilingual: Section list isolation" do
  it "section_list only shows pages of the same language" do
    build_site(
      MULTILINGUAL_CONFIG,
      content_files: {
        "blog/_index.md"    => "---\ntitle: Blog\n---\n",
        "blog/_index.ko.md" => "---\ntitle: 블로그\n---\n",
        "blog/a.md"         => "---\ntitle: English Post\n---\nEN",
        "blog/a.ko.md"      => "---\ntitle: 한국어 포스트\n---\nKO",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "LIST={{ section_list }}",
      },
    ) do
      en_blog = File.read("public/blog/index.html")
      en_blog.should contain("English Post")
      en_blog.should_not contain("한국어 포스트")

      ko_blog = File.read("public/ko/blog/index.html")
      ko_blog.should contain("한국어 포스트")
      ko_blog.should_not contain("English Post")
    end
  end
end

describe "Multilingual: Three or more languages" do
  it "supports more than two languages" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"
      default_language = "en"

      [languages.ko]
      language_name = "한국어"
      weight = 1

      [languages.ja]
      language_name = "日本語"
      weight = 2
      TOML

    build_site(
      config,
      content_files: {
        "about.md"    => "---\ntitle: About\n---\nEnglish",
        "about.ko.md" => "---\ntitle: 소개\n---\n한국어",
        "about.ja.md" => "---\ntitle: 紹介\n---\n日本語",
      },
      template_files: {
        "page.html" => "TITLE={{ page_title }}|URL={{ page_url }}|{{ content }}",
      },
    ) do
      # English (default) - no prefix
      File.exists?("public/about/index.html").should be_true
      en_html = File.read("public/about/index.html")
      en_html.should contain("TITLE=About")

      # Korean - /ko/ prefix
      File.exists?("public/ko/about/index.html").should be_true
      ko_html = File.read("public/ko/about/index.html")
      ko_html.should contain("TITLE=소개")
      ko_html.should contain("URL=/ko/about/")

      # Japanese - /ja/ prefix
      File.exists?("public/ja/about/index.html").should be_true
      ja_html = File.read("public/ja/about/index.html")
      ja_html.should contain("TITLE=紹介")
      ja_html.should contain("URL=/ja/about/")
    end
  end
end

describe "Multilingual: Translation links for three languages" do
  it "lists all translations including all languages" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"
      default_language = "en"

      [languages.ko]
      language_name = "한국어"
      weight = 1

      [languages.ja]
      language_name = "日本語"
      weight = 2
      TOML

    build_site(
      config,
      content_files: {
        "about.md"    => "---\ntitle: About\n---\nEnglish",
        "about.ko.md" => "---\ntitle: 소개\n---\n한국어",
        "about.ja.md" => "---\ntitle: 紹介\n---\n日本語",
      },
      template_files: {
        "page.html" => "TRANSLATIONS={% for t in page.translations %}{{ t.code }}:{{ t.url }},{% endfor %}",
      },
    ) do
      en_html = File.read("public/about/index.html")
      en_html.should contain("en:")
      en_html.should contain("ko:")
      en_html.should contain("ja:")
    end
  end
end

describe "Multilingual: Page without translation" do
  it "generates page only for languages with content" do
    build_site(
      MULTILINGUAL_CONFIG,
      content_files: {
        "about.md" => "---\ntitle: About\n---\nOnly in English",
        # No about.ko.md - Korean version doesn't exist
      },
      template_files: {
        "page.html" => "TITLE={{ page_title }}|{{ content }}",
      },
    ) do
      File.exists?("public/about/index.html").should be_true
      # Korean version should not exist since there's no content for it
      File.exists?("public/ko/about/index.html").should be_false
    end
  end
end

describe "Multilingual: Homepage per language" do
  it "generates language-specific homepages" do
    build_site(
      MULTILINGUAL_CONFIG,
      content_files: {
        "index.md"    => "---\ntitle: Home\n---\nWelcome",
        "index.ko.md" => "---\ntitle: 홈\n---\n환영합니다",
      },
      template_files: {
        "page.html" => "TITLE={{ page_title }}|{{ content }}",
      },
    ) do
      File.exists?("public/index.html").should be_true
      en_html = File.read("public/index.html")
      en_html.should contain("TITLE=Home")
      en_html.should contain("Welcome")

      File.exists?("public/ko/index.html").should be_true
      ko_html = File.read("public/ko/index.html")
      ko_html.should contain("TITLE=홈")
      ko_html.should contain("환영합니다")
    end
  end
end
