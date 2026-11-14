require "../../../../spec_helper"
require "../../../../support/build_helper"

# A `redirect_to` stub page is a meta-refresh bounce, not content: like the
# sitemap, feeds and search index already did, every listing and every
# reading-order relation leaves it out. A section with `redirect_to` (the
# index that bounces to its own first page) stays listed.
private REDIRECT_CONFIG = <<-TOML
  title = "T"
  base_url = "http://localhost"

  [content]
  backlinks = true

  [series]
  enabled = true

  [related]
  enabled = true
  taxonomies = ["tags"]

  [[taxonomies]]
  name = "tags"
  TOML

private REDIRECT_TEMPLATES = {
  "page.html" => <<-HTML,
    <h1>{{ page.title }}</h1>
    PREV={% if page.lower %}{{ page.lower.title }}{% endif %} NEXT={% if page.higher %}{{ page.higher.title }}{% endif %}
    SERIES={% for p in page.series_pages %}{{ p.title }};{% endfor %} IDX={{ page.series_index }}
    RELATED={% for p in page.related_posts %}{{ p.title }};{% endfor %}
    BACKLINKS={% for p in page.backlinks %}{{ p.title }};{% endfor %}
    TAX={% for t in get_taxonomy(kind="tags").items %}{{ t.name }}:{{ t.count }};{% endfor %}
    AUTHOR={{ "ghost" in site.authors }}
    GETPAGE={{ get_page(path="blog/stub.md").title }}
    GETSEC={% for p in get_section(path="blog/_index.md").pages %}{{ p.title }};{% endfor %}
    HTML
  "section.html" => <<-HTML,
    <h1>{{ section.title }}</h1>
    LIST={% for p in section.pages %}{{ p.title }};{% endfor %} COUNT={{ section.pages_count }}
    PAGERS={% if paginator %}{{ paginator.number_pagers }}{% endif %}
    HTML
  "taxonomy.html"      => "{{ content }}",
  "taxonomy_term.html" => "{{ content }}",
}

private def redirect_content : Hash(String, String)
  {
    "blog/_index.md"  => "+++\ntitle = \"Blog\"\nsort_by = \"date\"\npaginate = 2\n+++\n",
    "blog/a.md"       => "+++\ntitle = \"A\"\ndate = 2024-01-01\ntags = [\"t\"]\nseries = \"s\"\nseries_weight = 1\n+++\nA",
    "blog/stub.md"    => "+++\ntitle = \"Stub\"\ndate = 2024-01-02\ntags = [\"t\"]\nauthors = [\"ghost\"]\nseries = \"s\"\nseries_weight = 2\nredirect_to = \"https://elsewhere.example/\"\n+++\n[a](@/blog/a.md)",
    "blog/b.md"       => "+++\ntitle = \"B\"\ndate = 2024-01-03\ntags = [\"t\"]\nseries = \"s\"\nseries_weight = 3\n+++\nB",
    "moved/_index.md" => "+++\ntitle = \"Moved\"\nredirect_to = \"@/moved/child.md\"\n+++\n",
    "moved/child.md"  => "+++\ntitle = \"Child\"\ndate = 2024-02-01\n+++\nC",
  }
end

describe "redirect_to stub pages in listings" do
  it "leaves the stub out of section.pages, pages_count and pagination" do
    build_site(REDIRECT_CONFIG, content_files: redirect_content, template_files: REDIRECT_TEMPLATES) do
      blog = File.read("public/blog/index.html")
      blog.should contain("LIST=B;A; COUNT=2")
      blog.should contain("PAGERS=1")
      File.exists?("public/blog/page/2/index.html").should be_false
      File.read("public/blog/a/index.html").should contain("GETSEC=B;A;")
    end
  end

  it "links previous/next past the stub" do
    build_site(REDIRECT_CONFIG, content_files: redirect_content, template_files: REDIRECT_TEMPLATES) do
      File.read("public/blog/a/index.html").should contain("PREV=B NEXT=")
      File.read("public/blog/b/index.html").should contain("NEXT=A\n")
    end
  end

  it "leaves the stub out of series, related posts, backlinks, taxonomies and authors" do
    build_site(REDIRECT_CONFIG, content_files: redirect_content, template_files: REDIRECT_TEMPLATES) do
      a = File.read("public/blog/a/index.html")
      a.should contain("SERIES=A;B; IDX=1")
      a.should contain("RELATED=B;\n")
      a.should contain("BACKLINKS=\n")
      a.should contain("TAX=t:2;")
      a.should contain("AUTHOR=false")
      File.read("public/blog/b/index.html").should contain("IDX=2")
      File.read("public/tags/t/index.html").should_not contain("Stub")
    end
  end

  it "keeps the stub reachable by explicit lookup and still writes it" do
    build_site(REDIRECT_CONFIG, content_files: redirect_content, template_files: REDIRECT_TEMPLATES) do
      File.read("public/blog/a/index.html").should contain("GETPAGE=Stub")
      File.read("public/blog/stub/index.html").should contain("https://elsewhere.example/")
    end
  end

  it "keeps a redirecting section and its pages listed" do
    build_site(REDIRECT_CONFIG, content_files: redirect_content, template_files: REDIRECT_TEMPLATES) do
      File.read("public/moved/child/index.html").should contain("PREV=Moved ")
    end
  end
end

describe "Page#excluded_from_listings? with redirect_to" do
  it "excludes a stub page but not a redirecting section" do
    page = Hwaro::Models::Page.new("blog/stub.md")
    page.excluded_from_listings?.should be_false
    page.redirect_to = "https://elsewhere.example/"
    page.excluded_from_listings?.should be_true

    section = Hwaro::Models::Section.new("moved/_index.md")
    section.redirect_to = "@/moved/child.md"
    section.excluded_from_listings?.should be_false
  end
end
