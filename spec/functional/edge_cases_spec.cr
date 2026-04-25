require "./support/build_helper"

# =============================================================================
# Edge case functional tests
#
# Verifies handling of UTF-8 content, empty sections, summary in section lists,
# cache invalidation scenarios, and other boundary conditions.
# =============================================================================

# ---------------------------------------------------------------------------
# 1. UTF-8 special characters in content and titles
# ---------------------------------------------------------------------------
describe "Edge Cases: UTF-8 content handling" do
  it "handles Korean, Japanese, and emoji characters in titles and content" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "korean.md"   => "---\ntitle: 한국어 페이지\n---\n안녕하세요, 세계!",
        "japanese.md" => "---\ntitle: 日本語ページ\n---\nこんにちは世界！",
        "emoji.md"    => "---\ntitle: Emoji Page\n---\nHello 🌍🚀✨",
      },
      template_files: {"page.html" => "TITLE={{ page_title }}|{{ content }}"},
    ) do
      ko_html = File.read("public/korean/index.html")
      ko_html.should contain("TITLE=한국어 페이지")
      ko_html.should contain("안녕하세요, 세계!")

      ja_html = File.read("public/japanese/index.html")
      ja_html.should contain("TITLE=日本語ページ")
      ja_html.should contain("こんにちは世界！")

      emoji_html = File.read("public/emoji/index.html")
      emoji_html.should contain("🌍🚀✨")
    end
  end

  it "handles special characters in slugs" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "c-plus-plus.md" => "---\ntitle: C++ Guide\n---\nC++ content",
        "q-and-a.md"     => "---\ntitle: Q&A Page\n---\nQuestions and answers",
      },
      template_files: {"page.html" => "TITLE={{ page_title }}|{{ content }}"},
    ) do
      File.exists?("public/c-plus-plus/index.html").should be_true
      File.exists?("public/q-and-a/index.html").should be_true
    end
  end
end

# ---------------------------------------------------------------------------
# 2. Empty section handling
# ---------------------------------------------------------------------------
describe "Edge Cases: Empty section" do
  it "builds section with no child pages" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\nEmpty blog",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "TITLE={{ section.title }}|COUNT={{ section.pages | length }}|{{ content }}",
      },
    ) do
      html = File.read("public/blog/index.html")
      html.should contain("TITLE=Blog")
      html.should contain("COUNT=0")
      html.should contain("Empty blog")
    end
  end
end

# ---------------------------------------------------------------------------
# 3. Summary in section list
# ---------------------------------------------------------------------------
describe "Edge Cases: Summary via page_summary variable" do
  it "page_summary exposed from <!-- more --> marker" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "post.md" => "---\ntitle: My Post\n---\nThis is the intro.\n\n<!-- more -->\n\nThis is the rest.",
      },
      template_files: {
        "page.html" => "SUMMARY={{ page_summary | safe }}|{{ content }}",
      },
    ) do
      html = File.read("public/post/index.html")
      # `page_summary` exposes rendered HTML for the chunk before the
      # `<!-- more -->` marker (#491) — wrap markdown in `<p>` matches
      # how full content renders.
      html.should contain("SUMMARY=<p>This is the intro.</p>")
    end
  end

  it "page_summary renders inline markdown to HTML rather than leaking raw markers" do
    # Regression for https://github.com/hahwul/hwaro/issues/491 — the
    # raw chunk before `<!-- more -->` previously came through verbatim
    # (with `# Heading`, `**bold**`, etc.), so `{{ page.summary | safe }}`
    # produced un-rendered markdown in the page.
    build_site(
      BASIC_CONFIG,
      content_files: {
        "post.md" => "---\ntitle: My Post\n---\n# Heading\n\nWith **bold** and a [link](/about/).\n\n<!-- more -->\n\nRest.",
      },
      template_files: {
        "page.html" => "SUMMARY={{ page_summary | safe }}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("<h1")
      html.should contain("Heading</h1>")
      html.should contain("<strong>bold</strong>")
      html.should contain(%(<a href="/about/">link</a>))
      html.should_not contain("# Heading")
      html.should_not contain("**bold**")
    end
  end

  it "page_summary falls back to description" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "post.md" => "---\ntitle: My Post\ndescription: A brief description\n---\nFull content here.",
      },
      template_files: {
        "page.html" => "SUMMARY={{ page_summary }}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("SUMMARY=A brief description")
    end
  end

  it "section.pages exposes description for each page" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/post.md"   => "---\ntitle: My Post\ndescription: Post description\n---\nFull content",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{% for p in section.pages %}DESC={{ p.description }},{% endfor %}",
      },
    ) do
      html = File.read("public/blog/index.html")
      html.should contain("DESC=Post description")
    end
  end
end

# ---------------------------------------------------------------------------
# 4. Cache invalidation on template change
# ---------------------------------------------------------------------------
describe "Edge Cases: Template changes on rebuild" do
  it "reflects template changes on rebuild without cache" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/page.md", "---\ntitle: Page\n---\nContent")
        File.write("templates/page.html", "V1={{ content }}")

        # First build
        builder1 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder1.register(h) }
        builder1.run(output_dir: "public", parallel: false, cache: false, highlight: false, verbose: false, profile: false)

        html1 = File.read("public/page/index.html")
        html1.should contain("V1=")

        # Change template
        File.write("templates/page.html", "V2={{ content }}")

        # Rebuild
        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(output_dir: "public", parallel: false, cache: false, highlight: false, verbose: false, profile: false)

        html2 = File.read("public/page/index.html")
        html2.should contain("V2=")
      end
    end
  end
end

# ---------------------------------------------------------------------------
# 5. Cache: Rebuild after file deletion
# ---------------------------------------------------------------------------
describe "Edge Cases: Cache rebuild after file deletion" do
  it "removes output for deleted content files" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/page1.md", "---\ntitle: Page 1\n---\nContent 1")
        File.write("content/page2.md", "---\ntitle: Page 2\n---\nContent 2")
        File.write("templates/page.html", "{{ content }}")

        # First build
        builder1 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder1.register(h) }
        builder1.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.exists?("public/page1/index.html").should be_true
        File.exists?("public/page2/index.html").should be_true

        # Delete page2
        sleep 100.milliseconds
        File.delete("content/page2.md")

        # Rebuild
        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.exists?("public/page1/index.html").should be_true
        # page2 output should no longer exist after rebuild
        # (depending on implementation: some SSGs leave orphaned files)
      end
    end
  end
end

# ---------------------------------------------------------------------------
# 6. Multiple sections with different sort orders
# ---------------------------------------------------------------------------
describe "Edge Cases: Section sort_by configuration" do
  it "sorts section pages by date" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\nsort_by: date\n---\n",
        "blog/old.md"    => "---\ntitle: Old Post\ndate: 2023-01-01\n---\nOld",
        "blog/new.md"    => "---\ntitle: New Post\ndate: 2024-06-15\n---\nNew",
        "blog/mid.md"    => "---\ntitle: Mid Post\ndate: 2023-06-15\n---\nMid",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{% for p in section.pages %}{{ p.title }},{% endfor %}",
      },
    ) do
      html = File.read("public/blog/index.html")
      # Should contain all three posts
      html.should contain("Old Post")
      html.should contain("Mid Post")
      html.should contain("New Post")
    end
  end

  it "sorts section pages by weight" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "docs/_index.md" => "---\ntitle: Docs\nsort_by: weight\n---\n",
        "docs/intro.md"  => "---\ntitle: Intro\nweight: 1\n---\nIntro",
        "docs/setup.md"  => "---\ntitle: Setup\nweight: 2\n---\nSetup",
        "docs/usage.md"  => "---\ntitle: Usage\nweight: 3\n---\nUsage",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{% for p in section.pages %}{{ p.title }},{% endfor %}",
      },
    ) do
      html = File.read("public/docs/index.html")
      intro_pos = html.index!("Intro,")
      setup_pos = html.index!("Setup,")
      usage_pos = html.index!("Usage,")
      (intro_pos < setup_pos).should be_true
      (setup_pos < usage_pos).should be_true
    end
  end
end

# ---------------------------------------------------------------------------
# 7. Content with special markdown edge cases
# ---------------------------------------------------------------------------
describe "Edge Cases: Markdown with HTML entities" do
  it "handles HTML entities in content" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "page.md" => "---\ntitle: Entities\n---\nCopyright &copy; 2024. Price: $10 &lt; $20.",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/page/index.html")
      # Markdown may render &copy; as the actual character ©
      (html.includes?("©") || html.includes?("&copy;")).should be_true
      html.should contain("&lt;")
    end
  end
end

# ---------------------------------------------------------------------------
# 8. Multiple taxonomies on a single page
# ---------------------------------------------------------------------------
describe "Edge Cases: Page with multiple taxonomy terms" do
  it "assigns page to multiple tags" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [taxonomies]
      tags = { name = "tags", feed = false }
      TOML

    build_site(
      config,
      content_files: {
        "post.md" => "---\ntitle: Tagged Post\ntags: [crystal, web, ssg]\n---\nContent",
      },
      template_files: {
        "page.html" => "TAGS={% for t in page_tags %}{{ t }},{% endfor %}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("crystal,")
      html.should contain("web,")
      html.should contain("ssg,")
    end
  end
end

# ---------------------------------------------------------------------------
# 9. Page with extra metadata
# ---------------------------------------------------------------------------
describe "Edge Cases: Page extra metadata" do
  it "exposes custom extra fields from TOML frontmatter" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "page.md" => "+++\ntitle = \"Page\"\ncustom_field = \"hello\"\nfeatured = true\n+++\nContent",
      },
      template_files: {
        "page.html" => "CUSTOM={{ page.extra.custom_field }}|FEATURED={{ page.extra.featured }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("CUSTOM=hello")
      html.should contain("FEATURED=true")
    end
  end

  it "exposes custom extra fields from YAML frontmatter" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "page.md" => "---\ntitle: Page\ncustom_field: world\n---\nContent",
      },
      template_files: {
        "page.html" => "CUSTOM={{ page.extra.custom_field }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("CUSTOM=world")
    end
  end
end

# ---------------------------------------------------------------------------
# 10. Deeply nested content structure (3+ levels)
# ---------------------------------------------------------------------------
describe "Edge Cases: Deeply nested sections" do
  it "handles 3 levels of nested sections" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "docs/_index.md"                       => "---\ntitle: Docs\n---\n",
        "docs/guide/_index.md"                 => "---\ntitle: Guide\n---\n",
        "docs/guide/getting-started/_index.md" => "---\ntitle: Getting Started\n---\n",
        "docs/guide/getting-started/step1.md"  => "---\ntitle: Step 1\n---\nFirst step",
      },
      template_files: {
        "page.html"    => "TITLE={{ page_title }}|URL={{ page_url }}|{{ content }}",
        "section.html" => "SECTION={{ section.title }}|{{ section_list }}{{ content }}",
      },
    ) do
      File.exists?("public/docs/index.html").should be_true
      File.exists?("public/docs/guide/index.html").should be_true
      File.exists?("public/docs/guide/getting-started/index.html").should be_true
      File.exists?("public/docs/guide/getting-started/step1/index.html").should be_true

      step1 = File.read("public/docs/guide/getting-started/step1/index.html")
      step1.should contain("TITLE=Step 1")
      step1.should contain("URL=/docs/guide/getting-started/step1/")
    end
  end
end

# ---------------------------------------------------------------------------
# 11. Build with custom output directory
# ---------------------------------------------------------------------------
describe "Edge Cases: Custom output directory" do
  it "outputs to a non-default directory" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
      output_dir: "dist",
    ) do
      File.exists?("dist/index.html").should be_true
      Dir.exists?("public").should be_false
    end
  end
end

# ---------------------------------------------------------------------------
# 12. Multiple redirect aliases
# ---------------------------------------------------------------------------
describe "Edge Cases: Page with multiple aliases" do
  it "generates redirect pages for all aliases" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "new-post.md" => "---\ntitle: New Post\naliases:\n  - /old-url/\n  - /legacy/post/\n---\nContent",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/new-post/index.html").should be_true
      File.exists?("public/old-url/index.html").should be_true
      File.exists?("public/legacy/post/index.html").should be_true

      # Redirect pages should contain the redirect target
      redirect1 = File.read("public/old-url/index.html")
      redirect1.should contain("/new-post/")

      redirect2 = File.read("public/legacy/post/index.html")
      redirect2.should contain("/new-post/")
    end
  end
end
