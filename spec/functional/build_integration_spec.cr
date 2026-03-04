require "./support/build_helper"

# ---------------------------------------------------------------------------
# 1. Basic page URL generation
# ---------------------------------------------------------------------------
describe "Build Integration: URL generation" do
  it "generates correct URL for a root-level page" do
    build_site(
      BASIC_CONFIG,
      content_files: {"about.md" => "---\ntitle: About\n---\nAbout content"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/about/index.html").should be_true
      html = File.read("public/about/index.html")
      html.should contain("About content")
    end
  end

  it "generates correct URL for a nested section page" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md"     => "---\ntitle: Blog\n---\nBlog index",
        "blog/first-post.md" => "---\ntitle: First Post\n---\nPost body",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "<h1>{{ section.title }}</h1>{{ section_list }}{{ content }}",
      },
    ) do
      File.exists?("public/blog/index.html").should be_true
      File.exists?("public/blog/first-post/index.html").should be_true

      post_html = File.read("public/blog/first-post/index.html")
      post_html.should contain("Post body")
    end
  end

  it "respects slug front-matter for URL" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md"  => "---\ntitle: Blog\n---\n",
        "blog/my-post.md" => "---\ntitle: My Post\nslug: custom-slug\n---\nCustom slug body",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ content }}",
      },
    ) do
      File.exists?("public/blog/custom-slug/index.html").should be_true
      File.exists?("public/blog/my-post/index.html").should be_false
    end
  end

  it "respects custom path front-matter for URL" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "old-post.md" => "---\ntitle: Old Post\npath: /archive/2024/old-post/\n---\nBody",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/archive/2024/old-post/index.html").should be_true
    end
  end

  it "applies permalink remapping from config" do
    config = <<-TOML
    title = "Test"
    base_url = "http://localhost"

    [permalinks]
    "old/posts" = "posts"
    TOML

    build_site(
      config,
      content_files: {
        "old/posts/_index.md" => "---\ntitle: Old Posts\n---\n",
        "old/posts/a.md"      => "---\ntitle: Post A\n---\nBody A",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ content }}",
      },
    ) do
      File.exists?("public/posts/a/index.html").should be_true
      body = File.read("public/posts/a/index.html")
      body.should contain("Body A")
    end
  end
end

# ---------------------------------------------------------------------------
# 2. Template variable rendering
# ---------------------------------------------------------------------------
describe "Build Integration: Template variables" do
  it "exposes page_title, page_url, page_section, site_title, base_url" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md"  => "---\ntitle: Blog\n---\n",
        "blog/my-post.md" => "---\ntitle: My Post\n---\nContent here",
      },
      template_files: {
        "page.html"    => "TITLE={{ page_title }}|URL={{ page_url }}|SECTION={{ page_section }}|SITE={{ site_title }}|BASE={{ base_url }}",
        "section.html" => "SEC={{ section.title }}",
      },
    ) do
      html = File.read("public/blog/my-post/index.html")
      html.should contain("TITLE=My Post")
      html.should contain("URL=/blog/my-post/")
      html.should contain("SECTION=blog")
      html.should contain("SITE=Test Site")
      html.should contain("BASE=http://localhost")
    end
  end

  it "renders {{ content }} correctly" do
    build_site(
      BASIC_CONFIG,
      content_files: {"hello.md" => "---\ntitle: Hello\n---\n# Heading\n\nParagraph text"},
      template_files: {"page.html" => "<main>{{ content }}</main>"},
    ) do
      html = File.read("public/hello/index.html")
      html.should contain("<main>")
      html.should contain("<h1")
      html.should contain("Heading")
      html.should contain("<p>Paragraph text</p>")
      html.should contain("</main>")
    end
  end

  it "exposes page.description and page.image" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "post.md" => "---\ntitle: Post\ndescription: My description\nimage: /img/cover.png\n---\nBody",
      },
      template_files: {
        "page.html" => "DESC={{ page_description }}|IMG={{ page_image }}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("DESC=My description")
      html.should contain("IMG=/img/cover.png")
    end
  end

  it "exposes page.word_count and page.reading_time" do
    # 200 words => ~1 min reading time
    words = (1..200).map { |i| "word#{i}" }.join(" ")
    build_site(
      BASIC_CONFIG,
      content_files: {"article.md" => "---\ntitle: Article\n---\n#{words}"},
      template_files: {"page.html" => "WC={{ page_word_count }}|RT={{ page_reading_time }}"},
    ) do
      html = File.read("public/article/index.html")
      html.should contain("WC=200")
      html.should contain("RT=1")
    end
  end

  it "exposes page.extra custom fields from front matter" do
    # Extra fields are top-level front-matter keys that are NOT in the
    # known-keys list.  They are stored in page.extra as flat key-value pairs.
    build_site(
      BASIC_CONFIG,
      content_files: {
        "post.md" => "+++\ntitle = \"Post\"\ncustom_field = \"hello\"\n+++\nBody",
      },
      template_files: {"page.html" => "EXTRA={{ page.extra.custom_field }}"},
    ) do
      html = File.read("public/post/index.html")
      html.should contain("EXTRA=hello")
    end
  end

  it "exposes current_year variable" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "YEAR={{ current_year }}"},
    ) do
      html = File.read("public/index.html")
      html.should contain("YEAR=#{Time.local.year}")
    end
  end

  it "exposes page.permalink (absolute URL)" do
    build_site(
      BASIC_CONFIG,
      content_files: {"about.md" => "---\ntitle: About\n---\nAbout"},
      template_files: {"page.html" => "LINK={{ page_permalink }}"},
    ) do
      html = File.read("public/about/index.html")
      html.should contain("LINK=http://localhost/about/")
    end
  end
end

# ---------------------------------------------------------------------------
# 3. Section list rendering
# ---------------------------------------------------------------------------
describe "Build Integration: Section list" do
  it "renders section_list with links to child pages" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "wiki/_index.md" => "---\ntitle: Wiki\n---\nWiki index",
        "wiki/alpha.md"  => "---\ntitle: Alpha\n---\nAlpha body",
        "wiki/beta.md"   => "---\ntitle: Beta\n---\nBeta body",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "<ul>{{ section_list }}</ul>",
      },
    ) do
      html = File.read("public/wiki/index.html")
      html.should contain("<a href=\"http://localhost/wiki/alpha/\">Alpha</a>")
      html.should contain("<a href=\"http://localhost/wiki/beta/\">Beta</a>")
    end
  end

  it "renders section.pages with correct count" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "docs/_index.md" => "---\ntitle: Docs\n---\n",
        "docs/a.md"      => "---\ntitle: A\n---\nA",
        "docs/b.md"      => "---\ntitle: B\n---\nB",
        "docs/c.md"      => "---\ntitle: C\n---\nC",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "COUNT={{ section.pages_count }}",
      },
    ) do
      html = File.read("public/docs/index.html")
      html.should contain("COUNT=3")
    end
  end
end

# ---------------------------------------------------------------------------
# 4. Prev/Next navigation (lower/higher)
# ---------------------------------------------------------------------------
describe "Build Integration: Prev/Next navigation" do
  it "links lower and higher pages within a section" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\nsort_by: title\n---\n",
        "blog/a.md"      => "---\ntitle: AAA\ndate: 2024-01-01\n---\nA",
        "blog/b.md"      => "---\ntitle: BBB\ndate: 2024-01-02\n---\nB",
        "blog/c.md"      => "---\ntitle: CCC\ndate: 2024-01-03\n---\nC",
      },
      template_files: {
        "section.html" => "{{ content }}",
        "page.html"    => "LOWER={% if page.lower %}{{ page.lower.title }}{% else %}NONE{% endif %}|HIGHER={% if page.higher %}{{ page.higher.title }}{% else %}NONE{% endif %}",
      },
    ) do
      # With sort_by=title order: AAA, BBB, CCC
      a_html = File.read("public/blog/a/index.html")
      a_html.should contain("LOWER=NONE")
      a_html.should contain("HIGHER=BBB")

      b_html = File.read("public/blog/b/index.html")
      b_html.should contain("LOWER=AAA")
      b_html.should contain("HIGHER=CCC")

      c_html = File.read("public/blog/c/index.html")
      c_html.should contain("LOWER=BBB")
      c_html.should contain("HIGHER=NONE")
    end
  end
end

# ---------------------------------------------------------------------------
# 5. Pagination
# ---------------------------------------------------------------------------
describe "Build Integration: Pagination" do
  it "produces paginated output directories" do
    config = <<-TOML
    title = "Test"
    base_url = "http://localhost"

    [pagination]
    enabled = true
    per_page = 2
    TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/p1.md"     => "---\ntitle: P1\n---\nP1",
        "blog/p2.md"     => "---\ntitle: P2\n---\nP2",
        "blog/p3.md"     => "---\ntitle: P3\n---\nP3",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "PAGE={{ paginator.current_index }}|{{ section_list }}{{ pagination }}",
      },
    ) do
      # First page at /blog/index.html
      File.exists?("public/blog/index.html").should be_true
      # Second page at /blog/page/2/index.html
      File.exists?("public/blog/page/2/index.html").should be_true

      page1 = File.read("public/blog/index.html")
      page1.should contain("PAGE=1")

      page2 = File.read("public/blog/page/2/index.html")
      page2.should contain("PAGE=2")
    end
  end
end

# ---------------------------------------------------------------------------
# 6. Redirect pages (redirect_to and aliases)
# ---------------------------------------------------------------------------
describe "Build Integration: Redirects" do
  it "generates a redirect page for redirect_to on a section" do
    # NOTE: Currently redirect_to is only assigned for Section pages
    # (pages backed by _index.md), not regular pages.
    build_site(
      BASIC_CONFIG,
      content_files: {
        "old-section/_index.md" => "---\ntitle: Old Section\nredirect_to: /new-section/\n---\nOld content",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ content }}",
      },
    ) do
      File.exists?("public/old-section/index.html").should be_true
      html = File.read("public/old-section/index.html")
      html.should contain("url=/new-section/")
      html.should contain("Redirecting")
      # Should NOT contain the markdown-rendered content
      html.should_not contain("<p>Old content</p>")
    end
  end

  it "generates a redirect page for redirect_to on a regular page" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "old-page.md" => "---\ntitle: Old Page\nredirect_to: /new-page/\n---\nOld content",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/old-page/index.html").should be_true
      html = File.read("public/old-page/index.html")
      html.should contain("url=/new-page/")
      html.should contain("Redirecting")
      # Should NOT contain the markdown-rendered content
      html.should_not contain("<p>Old content</p>")
    end
  end

  it "generates alias redirect pages" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "new-page.md" => "---\ntitle: New Page\naliases:\n  - /legacy/\n  - /old-url/\n---\nNew content",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      # Main page
      File.exists?("public/new-page/index.html").should be_true
      main = File.read("public/new-page/index.html")
      main.should contain("New content")

      # Alias redirects
      File.exists?("public/legacy/index.html").should be_true
      alias1 = File.read("public/legacy/index.html")
      alias1.should contain("url=/new-page/")

      File.exists?("public/old-url/index.html").should be_true
      alias2 = File.read("public/old-url/index.html")
      alias2.should contain("url=/new-page/")
    end
  end
end

# ---------------------------------------------------------------------------
# 7. 404 page generation
# ---------------------------------------------------------------------------
describe "Build Integration: 404 page" do
  it "generates 404.html when 404 template exists" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {
        "page.html" => "{{ content }}",
        "404.html"  => "<h1>{{ page_title }}</h1><p>Page not found</p>",
      },
    ) do
      File.exists?("public/404.html").should be_true
      html = File.read("public/404.html")
      html.should contain("404 Not Found")
      html.should contain("Page not found")
    end
  end

  it "does NOT generate 404.html when 404 template is missing" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/404.html").should be_false
    end
  end
end

# ---------------------------------------------------------------------------
# 8. Draft handling
# ---------------------------------------------------------------------------
describe "Build Integration: Drafts" do
  it "excludes draft pages by default" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "published.md" => "---\ntitle: Published\ndraft: false\n---\nPublished",
        "wip.md"       => "---\ntitle: WIP\ndraft: true\n---\nWIP",
      },
      template_files: {"page.html" => "{{ content }}"},
      drafts: false,
    ) do
      File.exists?("public/published/index.html").should be_true
      File.exists?("public/wip/index.html").should be_false
    end
  end

  it "includes draft pages when drafts=true" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "wip.md" => "---\ntitle: WIP\ndraft: true\n---\nWIP body",
      },
      template_files: {"page.html" => "{{ content }}"},
      drafts: true,
    ) do
      File.exists?("public/wip/index.html").should be_true
    end
  end
end

# ---------------------------------------------------------------------------
# 9. render: false
# ---------------------------------------------------------------------------
describe "Build Integration: render=false" do
  it "does not write output for pages with render: false" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "visible.md" => "---\ntitle: Visible\n---\nVisible",
        "hidden.md"  => "---\ntitle: Hidden\nrender: false\n---\nHidden",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/visible/index.html").should be_true
      File.exists?("public/hidden/index.html").should be_false
    end
  end
end

# ---------------------------------------------------------------------------
# 10. Minification
# ---------------------------------------------------------------------------
describe "Build Integration: Minification" do
  it "collapses excessive blank lines in output" do
    build_site(
      BASIC_CONFIG,
      content_files: {"test.md" => "---\ntitle: Test\n---\nSome content"},
      template_files: {"page.html" => "<main>\n\n\n\n\n{{ content }}\n\n\n\n\n</main>"},
      minify: true,
    ) do
      html = File.read("public/test/index.html")
      # Should not contain 3+ consecutive newlines after minification
      html.should_not contain("\n\n\n")
    end
  end
end

# ---------------------------------------------------------------------------
# 11. Static file copying
# ---------------------------------------------------------------------------
describe "Build Integration: Static files" do
  it "copies static files to output" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
      static_files: {
        "css/style.css" => "body { color: red; }",
        "js/app.js"     => "console.log('hello');",
      },
    ) do
      File.exists?("public/css/style.css").should be_true
      File.read("public/css/style.css").should eq("body { color: red; }")
      File.exists?("public/js/app.js").should be_true
    end
  end
end

# ---------------------------------------------------------------------------
# 12. Shortcode rendering
# ---------------------------------------------------------------------------
describe "Build Integration: Shortcodes" do
  it "renders shortcodes in content" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "test.md" => "---\ntitle: Test\n---\n{{ alert(type=\"warning\", message=\"Be careful!\") }}",
      },
      template_files: {
        "page.html"             => "<div>{{ content }}</div>",
        "shortcodes/alert.html" => "<div class=\"alert alert-{{ type }}\">{{ message }}</div>",
      },
    ) do
      File.exists?("public/test/index.html").should be_true
      html = File.read("public/test/index.html")
      html.should contain("alert-warning")
      html.should contain("Be careful!")
    end
  end
end

# ---------------------------------------------------------------------------
# 13. TOC generation
# ---------------------------------------------------------------------------
describe "Build Integration: Table of Contents" do
  it "generates TOC HTML when toc: true" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "doc.md" => "---\ntitle: Doc\ntoc: true\n---\n## Section One\n\nContent\n\n## Section Two\n\nMore content",
      },
      template_files: {"page.html" => "<nav>{{ toc }}</nav><main>{{ content }}</main>"},
    ) do
      html = File.read("public/doc/index.html")
      html.should contain("<nav>")
      html.should contain("Section One")
      html.should contain("Section Two")
      html.should contain("<ul")
    end
  end

  it "does NOT generate TOC when toc: false" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "doc.md" => "---\ntitle: Doc\ntoc: false\n---\n## Section One\n\nContent",
      },
      template_files: {"page.html" => "<nav>{{ toc }}</nav><main>{{ content }}</main>"},
    ) do
      html = File.read("public/doc/index.html")
      html.should contain("<nav></nav>")
    end
  end
end

# ---------------------------------------------------------------------------
# 14. Taxonomy pages
# ---------------------------------------------------------------------------
describe "Build Integration: Taxonomy pages" do
  it "generates taxonomy index and term pages" do
    config = <<-TOML
    title = "Test"
    base_url = "http://localhost"

    [[taxonomies]]
    name = "tags"
    TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/post1.md"  => "---\ntitle: Post 1\ntags:\n  - crystal\n  - web\n---\nPost 1",
        "blog/post2.md"  => "---\ntitle: Post 2\ntags:\n  - crystal\n---\nPost 2",
      },
      template_files: {
        "page.html"          => "{{ content }}",
        "section.html"       => "{{ content }}",
        "taxonomy.html"      => "<h1>{{ taxonomy_name }}</h1>{{ content }}",
        "taxonomy_term.html" => "<h1>{{ taxonomy_term }}</h1>{{ content }}",
      },
    ) do
      # Taxonomy index page
      File.exists?("public/tags/index.html").should be_true
      idx = File.read("public/tags/index.html")
      idx.should contain("tags")

      # Term pages
      File.exists?("public/tags/crystal/index.html").should be_true
      crystal_html = File.read("public/tags/crystal/index.html")
      crystal_html.should contain("crystal")

      File.exists?("public/tags/web/index.html").should be_true
    end
  end
end

# ---------------------------------------------------------------------------
# 15. SEO file generation (sitemap, robots, feeds)
# ---------------------------------------------------------------------------
describe "Build Integration: SEO files" do
  it "generates sitemap.xml" do
    config = <<-TOML
    title = "Test"
    base_url = "http://localhost"

    [sitemap]
    enabled = true
    TOML

    build_site(
      config,
      content_files: {"about.md" => "---\ntitle: About\n---\nAbout"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/sitemap.xml").should be_true
      xml = File.read("public/sitemap.xml")
      xml.should contain("<urlset")
      xml.should contain("http://localhost/about/")
    end
  end

  it "generates robots.txt" do
    config = <<-TOML
    title = "Test"
    base_url = "http://localhost"

    [robots]
    enabled = true
    TOML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/robots.txt").should be_true
      txt = File.read("public/robots.txt")
      txt.should contain("User-agent")
    end
  end

  it "generates RSS feed" do
    config = <<-TOML
    title = "Test"
    base_url = "http://localhost"
    description = "A test site"

    [feeds]
    enabled = true
    type = "rss"
    filename = "rss.xml"
    TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/post.md"   => "---\ntitle: My Post\ndate: 2024-06-15\n---\nPost body",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ content }}",
      },
    ) do
      File.exists?("public/rss.xml").should be_true
      rss = File.read("public/rss.xml")
      rss.should contain("<rss")
      rss.should contain("My Post")
    end
  end
end

# ---------------------------------------------------------------------------
# 16. Search index generation
# ---------------------------------------------------------------------------
describe "Build Integration: Search index" do
  it "generates search.json" do
    config = <<-TOML
    title = "Test"
    base_url = "http://localhost"

    [search]
    enabled = true
    fields = ["title", "url"]
    TOML

    build_site(
      config,
      content_files: {
        "page1.md" => "---\ntitle: Page One\n---\nContent 1",
        "page2.md" => "---\ntitle: Page Two\n---\nContent 2",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/search.json").should be_true
      json = File.read("public/search.json")
      json.should contain("Page One")
      json.should contain("Page Two")
    end
  end
end

# ---------------------------------------------------------------------------
# 17. OpenGraph / Twitter Card tags
# ---------------------------------------------------------------------------
describe "Build Integration: OG tags" do
  it "renders og_tags and twitter_tags in template" do
    config = <<-TOML
    title = "Test"
    base_url = "http://localhost"

    [og]
    default_image = "/img/default.png"
    twitter_card = "summary_large_image"
    twitter_site = "@testsite"
    TOML

    build_site(
      config,
      content_files: {
        "post.md" => "---\ntitle: My Post\ndescription: Post desc\n---\nBody",
      },
      template_files: {
        "page.html" => "<head>{{ og_all_tags }}</head><body>{{ content }}</body>",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("og:title")
      html.should contain("My Post")
      html.should contain("twitter:card")
      html.should contain("@testsite")
    end
  end
end

# ---------------------------------------------------------------------------
# 18. Template inheritance (extends / blocks)
# ---------------------------------------------------------------------------
describe "Build Integration: Template inheritance" do
  it "supports extends and block" do
    build_site(
      BASIC_CONFIG,
      content_files: {"hello.md" => "---\ntitle: Hello\n---\nHello World"},
      template_files: {
        "base.html" => "<!DOCTYPE html><html><head><title>{% block title %}Default{% endblock %}</title></head><body>{% block body %}{% endblock %}</body></html>",
        "page.html" => "{% extends \"base.html\" %}{% block title %}{{ page_title }}{% endblock %}{% block body %}<main>{{ content }}</main>{% endblock %}",
      },
    ) do
      html = File.read("public/hello/index.html")
      html.should contain("<!DOCTYPE html>")
      html.should contain("<title>Hello</title>")
      html.should contain("<main>")
      html.should contain("Hello World")
    end
  end
end

# ---------------------------------------------------------------------------
# 19. Subsections
# ---------------------------------------------------------------------------
describe "Build Integration: Subsections" do
  it "builds subsection hierarchy accessible via section.subsections" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "docs/_index.md"        => "---\ntitle: Docs\n---\n",
        "docs/guide/_index.md"  => "---\ntitle: Guide\n---\n",
        "docs/guide/basics.md"  => "---\ntitle: Basics\n---\nBasics content",
        "docs/api/_index.md"    => "---\ntitle: API Reference\n---\n",
        "docs/api/endpoints.md" => "---\ntitle: Endpoints\n---\nEndpoints content",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "SUBS={% for sub in section.subsections %}{{ sub.title }},{% endfor %}|{{ content }}",
      },
    ) do
      html = File.read("public/docs/index.html")
      html.should contain("Guide")
      html.should contain("API Reference")
    end
  end
end

# ---------------------------------------------------------------------------
# 20. Ancestors (breadcrumbs)
# ---------------------------------------------------------------------------
describe "Build Integration: Ancestors" do
  it "provides ancestors chain for nested pages" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "docs/_index.md"       => "---\ntitle: Docs\n---\n",
        "docs/guide/_index.md" => "---\ntitle: Guide\n---\n",
        "docs/guide/intro.md"  => "---\ntitle: Intro\n---\nIntro content",
      },
      template_files: {
        "page.html"    => "ANCESTORS={% for a in page.ancestors %}{{ a.title }}/{% endfor %}|{{ content }}",
        "section.html" => "{{ content }}",
      },
    ) do
      html = File.read("public/docs/guide/intro/index.html")
      html.should contain("Docs/")
      html.should contain("Guide/")
    end
  end
end

# ---------------------------------------------------------------------------
# 21. Transparent sections
# ---------------------------------------------------------------------------
describe "Build Integration: Transparent sections" do
  it "includes transparent section pages in parent section list" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md"        => "---\ntitle: Blog\n---\n",
        "blog/2024/_index.md"   => "---\ntitle: '2024'\ntransparent: true\n---\n",
        "blog/2024/jan-post.md" => "---\ntitle: January Post\n---\nJan",
        "blog/direct-post.md"   => "---\ntitle: Direct Post\n---\nDirect",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ section_list }}",
      },
    ) do
      blog_html = File.read("public/blog/index.html")
      # Both direct and transparent-section page should appear
      blog_html.should contain("Direct Post")
      blog_html.should contain("January Post")
    end
  end
end

# ---------------------------------------------------------------------------
# 22. GFM Table support
# ---------------------------------------------------------------------------
describe "Build Integration: GFM Tables" do
  it "renders markdown tables to HTML" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "table.md" => "---\ntitle: Table\n---\n| Name | Age |\n|------|-----|\n| Alice | 30 |\n| Bob | 25 |",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/table/index.html")
      html.should contain("<table>")
      html.should contain("<th>Name</th>")
      html.should contain("<td>Alice</td>")
      html.should contain("<td>Bob</td>")
    end
  end
end

# ---------------------------------------------------------------------------
# 23. Data directory
# ---------------------------------------------------------------------------
describe "Build Integration: Data directory" do
  it "loads JSON data files and exposes via site.data" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {
        "page.html" => "{% for item in site.data.menu %}{{ item.name }},{% endfor %}",
      },
      data_files: {
        "menu.json" => "[{\"name\": \"Home\"}, {\"name\": \"About\"}]",
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("Home,")
      html.should contain("About,")
    end
  end
end

# ---------------------------------------------------------------------------
# 24. Auto includes
# ---------------------------------------------------------------------------
describe "Build Integration: Auto includes" do
  it "generates CSS/JS link/script tags for auto_includes" do
    config = <<-TOML
    title = "Test"
    base_url = "http://localhost"

    [auto_includes]
    enabled = true
    dirs = ["assets/css", "assets/js"]
    TOML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "<head>{{ auto_includes_css }}</head><body>{{ content }}{{ auto_includes_js }}</body>"},
      static_files: {
        "assets/css/style.css" => "body{}",
        "assets/js/app.js"     => "console.log('x');",
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("stylesheet")
      html.should contain("assets/css/style.css")
      html.should contain("<script")
      html.should contain("assets/js/app.js")
    end
  end
end

# ---------------------------------------------------------------------------
# 25. Highlight tags
# ---------------------------------------------------------------------------
describe "Build Integration: Highlight tags" do
  it "renders highlight CSS/JS tags when highlight is enabled" do
    config = <<-TOML
    title = "Test"
    base_url = "http://localhost"

    [highlight]
    enabled = true
    theme = "github-dark"
    TOML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ highlight_css }}{{ highlight_js }}{{ content }}"},
    ) do
      html = File.read("public/index.html")
      html.should contain("highlight")
      html.should contain("github-dark")
    end
  end
end

# ---------------------------------------------------------------------------
# 26. Canonical and hreflang tags
# ---------------------------------------------------------------------------
describe "Build Integration: Canonical tag" do
  it "renders canonical_tag in template" do
    build_site(
      BASIC_CONFIG,
      content_files: {"about.md" => "---\ntitle: About\n---\nAbout"},
      template_files: {"page.html" => "{{ canonical_tag }}{{ content }}"},
    ) do
      html = File.read("public/about/index.html")
      html.should contain("rel=\"canonical\"")
      html.should contain("http://localhost/about/")
    end
  end
end

# ---------------------------------------------------------------------------
# 27. Index page (homepage)
# ---------------------------------------------------------------------------
describe "Build Integration: Homepage" do
  it "builds index.md as the root index.html" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nWelcome home!"},
      template_files: {"page.html" => "<body>{{ content }}</body>"},
    ) do
      File.exists?("public/index.html").should be_true
      html = File.read("public/index.html")
      html.should contain("Welcome home!")
    end
  end
end

# ---------------------------------------------------------------------------
# 28. TOML front matter
# ---------------------------------------------------------------------------
describe "Build Integration: TOML front matter" do
  it "parses TOML front matter correctly" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "post.md" => "+++\ntitle = \"TOML Post\"\ndraft = false\ntags = [\"crystal\", \"test\"]\n+++\nTOML body",
      },
      template_files: {"page.html" => "TITLE={{ page_title }}|{{ content }}"},
    ) do
      html = File.read("public/post/index.html")
      html.should contain("TITLE=TOML Post")
      html.should contain("TOML body")
    end
  end
end

# ---------------------------------------------------------------------------
# 29. in_sitemap: false
# ---------------------------------------------------------------------------
describe "Build Integration: in_sitemap exclusion" do
  it "excludes pages with in_sitemap: false from sitemap" do
    config = <<-TOML
    title = "Test"
    base_url = "http://localhost"

    [sitemap]
    enabled = true
    TOML

    build_site(
      config,
      content_files: {
        "visible.md" => "---\ntitle: Visible\nin_sitemap: true\n---\nV",
        "hidden.md"  => "---\ntitle: Hidden\nin_sitemap: false\n---\nH",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      sitemap = File.read("public/sitemap.xml")
      sitemap.should contain("/visible/")
      sitemap.should_not contain("/hidden/")
    end
  end
end

# ---------------------------------------------------------------------------
# 30. site.pages and site.sections
# ---------------------------------------------------------------------------
describe "Build Integration: site object" do
  it "exposes site.pages and site.sections with correct counts" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "index.md"       => "---\ntitle: Home\n---\nHome",
        "about.md"       => "---\ntitle: About\n---\nAbout",
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/post1.md"  => "---\ntitle: Post 1\n---\nP1",
        "docs/_index.md" => "---\ntitle: Docs\n---\n",
      },
      template_files: {
        "page.html"    => "PAGES={{ site.pages | length }}|SECTIONS={{ site.sections | length }}",
        "section.html" => "{{ content }}",
      },
    ) do
      html = File.read("public/index.html")
      # Pages: index.md, about.md, blog/post1.md => 3
      html.should contain("PAGES=3")
      # Sections: blog, docs => 2
      html.should contain("SECTIONS=2")
    end
  end
end

# ---------------------------------------------------------------------------
# 31. Multiple sections don't leak pages
# ---------------------------------------------------------------------------
describe "Build Integration: Section isolation" do
  it "section_list only shows pages from the same section" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/post.md"   => "---\ntitle: Blog Post\n---\nBlog",
        "docs/_index.md" => "---\ntitle: Docs\n---\n",
        "docs/guide.md"  => "---\ntitle: Guide\n---\nGuide",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "SECTION={{ section.title }}|LIST={{ section_list }}",
      },
    ) do
      blog_html = File.read("public/blog/index.html")
      blog_html.should contain("Blog Post")
      blog_html.should_not contain("Guide")

      docs_html = File.read("public/docs/index.html")
      docs_html.should contain("Guide")
      docs_html.should_not contain("Blog Post")
    end
  end
end

# ---------------------------------------------------------------------------
# 32. Empty site builds without errors
# ---------------------------------------------------------------------------
describe "Build Integration: Edge cases" do
  it "builds an empty content directory without crashing" do
    build_site(
      BASIC_CONFIG,
      content_files: {} of String => String,
      template_files: {"page.html" => "{{ content }}"},
    ) do
      Dir.exists?("public").should be_true
    end
  end

  it "builds a page without any template without crashing" do
    build_site(
      BASIC_CONFIG,
      content_files: {"test.md" => "---\ntitle: Test\n---\nBody"},
      template_files: {} of String => String,
    ) do
      # Should still create the file (raw content fallback)
      File.exists?("public/test/index.html").should be_true
    end
  end
end
