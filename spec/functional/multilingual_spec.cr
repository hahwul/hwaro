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
        "blog/_index.md"     => "---\ntitle: Blog\n---\n",
        "blog/_index.ko.md"  => "---\ntitle: 블로그\n---\n",
        "blog/post.md"       => "---\ntitle: Post\n---\nEnglish post",
        "blog/post.ko.md"    => "---\ntitle: 포스트\n---\n한국어 포스트",
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
