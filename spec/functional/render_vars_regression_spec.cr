require "./support/build_helper"

# =============================================================================
# Regressions in per-page template variables (render phase).
#
# These cover cross-page cache-sharing bugs in build_template_variables:
# values that are correct in isolation but wrong when the Crinja value
# caches are shared between a section-index page and its member pages.
# =============================================================================

describe "Render vars: page.ancestors cache" do
  # Regression: @ancestors_crinja_cache was keyed {section, language}, a key
  # SHARED by the section-index page (whose ancestors exclude itself) and its
  # member pages (whose ancestors include the section). First writer won, so
  # either the section listed itself in its own breadcrumb or member pages
  # lost their parent section — nondeterministically across --cache builds.
  it "keeps section-index and member-page ancestors distinct" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "posts/_index.md" => "---\ntitle: Posts\n---\n",
        "posts/a.md"      => "---\ntitle: A\n---\nBody",
      },
      template_files: {
        "page.html"    => "ANC:[{% for a in page.ancestors %}{{ a.url }};{% endfor %}]",
        "section.html" => "ANC:[{% for a in page.ancestors %}{{ a.url }};{% endfor %}]",
      },
    ) do
      # The top-level section has no ancestors — in particular NOT itself.
      section_html = File.read("public/posts/index.html")
      section_html.should contain("ANC:[]")

      # A member page's ancestors still include its parent section.
      page_html = File.read("public/posts/a/index.html")
      page_html.should contain("ANC:[/posts/;]")
    end
  end

  it "keeps nested section ancestors distinct from member pages too" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "docs/_index.md"       => "---\ntitle: Docs\n---\n",
        "docs/guide/_index.md" => "---\ntitle: Guide\n---\n",
        "docs/guide/a.md"      => "---\ntitle: A\n---\nBody",
      },
      template_files: {
        "page.html"    => "ANC:[{% for a in page.ancestors %}{{ a.url }};{% endfor %}]",
        "section.html" => "ANC:[{% for a in page.ancestors %}{{ a.url }};{% endfor %}]",
      },
    ) do
      # The nested section's ancestors stop at its parent (no self).
      guide_html = File.read("public/docs/guide/index.html")
      guide_html.should contain("ANC:[/docs/;]")

      # The member page keeps the full chain including its own section.
      page_html = File.read("public/docs/guide/a/index.html")
      page_html.should contain("ANC:[/docs/;/docs/guide/;]")
    end
  end
end

describe "Render vars: section.subsections pages_count" do
  # Regression: subsection entries in the per-page `section` object read
  # `sub.pages.size` — but `Models::Section#pages` is never populated by the
  # build (the live list is site.pages_for_section), so pages_count was
  # always 0 while the get_section() global-vars path reported the truth.
  it "reports the real page count for each subsection" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "s/_index.md"     => "---\ntitle: S\n---\n",
        "s/sub/_index.md" => "---\ntitle: Sub\n---\n",
        "s/sub/a.md"      => "---\ntitle: A\n---\nBody",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "SUBC:[{% for sub in section.subsections %}{{ sub.title }}={{ sub.pages_count }};{% endfor %}]",
      },
    ) do
      html = File.read("public/s/index.html")
      html.should contain("SUBC:[Sub=1;]")
    end
  end
end

describe "Render vars: get_taxonomy_url language slugs" do
  # get_taxonomy_url on a non-default-language page must emit exactly the
  # term-page URL the taxonomy generator wrote for that language — including
  # when distinct terms collide on the same base slug ("C#"/"C++" → "c") and
  # disambiguation assigns "-N" suffixes.
  it "links to the term page the generator actually wrote for the page's language" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"
      default_language = "en"

      [[taxonomies]]
      name = "tags"

      [languages.en]
      language_name = "English"
      weight = 1
      taxonomies = ["tags"]

      [languages.ko]
      language_name = "한국어"
      weight = 2
      taxonomies = ["tags"]
      TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md"     => "---\ntitle: Blog\n---\n",
        "blog/_index.ko.md"  => "---\ntitle: 블로그\n---\n",
        "blog/en-post.md"    => "---\ntitle: En Post\ntags:\n  - \"C#\"\n---\nEnglish post",
        "blog/ko-post.ko.md" => "---\ntitle: Ko Post\ntags:\n  - \"C++\"\n---\n한국어 포스트",
      },
      template_files: {
        "page.html"          => %(TAXURL:[{{ get_taxonomy_url(kind="tags", term="C++") }}]{{ content }}),
        "section.html"       => "{{ content }}",
        "taxonomy.html"      => "<h1>{{ taxonomy_name }}</h1>",
        "taxonomy_term.html" => "<h1>{{ taxonomy_term }}</h1>",
      },
    ) do
      html = File.read("public/ko/blog/ko-post/index.html")
      match = /TAXURL:\[http:\/\/localhost(\/[^\]]*)\]/.match(html)
      match.should_not be_nil
      url = match.not_nil![1]
      url.should start_with("/ko/tags/")
      # The emitted link must resolve to a file the generator wrote.
      File.exists?(File.join("public", url, "index.html")).should be_true

      # And it must be THE ko term page (only C++ has Korean pages), so the
      # link and the written path agree on the disambiguated slug.
      written = Dir.children("public/ko/tags").select do |d|
        File.directory?(File.join("public/ko/tags", d))
      end
      written.size.should eq(1)
      url.should eq("/ko/tags/#{written.first}/")
    end
  end
end
