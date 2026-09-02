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

# ---------------------------------------------------------------------------
# 13. Duplicate output path / alias collision detection
# ---------------------------------------------------------------------------
describe "Edge Cases: Duplicate output path detection" do
  it "warns when two pages resolve to the same URL (slug collision)" do
    # Both pages live in the same directory and share slug 'dup', so both
    # resolve to /posts/dup/ — one silently overwrites the other in render
    # order. The render phase detects this and warns so users see the data loss.
    log = with_captured_log do
      build_site(
        BASIC_CONFIG,
        content_files: {
          "posts/a.md" => "---\ntitle: A\nslug: dup\n---\nA",
          "posts/b.md" => "---\ntitle: B\nslug: dup\n---\nB",
        },
        template_files: {"page.html" => "{{ content }}"},
      ) { }
    end

    log.should contain("Duplicate output path")
  end

  it "warns when an alias collides with an already-seen alias" do
    # Two pages declare the same alias. The first page registers /shared/ as an
    # alias; the second page's identical alias then collides with the
    # already-seen alias path and is reported as 'Duplicate alias output path'.
    log = with_captured_log do
      build_site(
        BASIC_CONFIG,
        content_files: {
          "one.md" => "---\ntitle: One\naliases:\n  - /shared/\n---\nOne",
          "two.md" => "---\ntitle: Two\naliases:\n  - /shared/\n---\nTwo",
        },
        template_files: {"page.html" => "{{ content }}"},
      ) { }
    end

    log.should contain("Duplicate alias output path")
  end

  it "writes the first page in source-path order on a slug collision (deterministic winner)" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "posts/a.md" => "---\ntitle: A\nslug: dup\n---\nAAA-WINNER",
        "posts/b.md" => "---\ntitle: B\nslug: dup\n---\nBBB-LOSER",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/posts/dup/index.html")
      html.should contain("AAA-WINNER")
      html.should_not contain("BBB-LOSER")
    end
  end

  it "keeps the deterministic winner under parallel render too" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "posts/a.md" => "---\ntitle: A\nslug: dup\n---\nAAA-WINNER",
        "posts/b.md" => "---\ntitle: B\nslug: dup\n---\nBBB-LOSER",
      },
      template_files: {"page.html" => "{{ content }}"},
      parallel: true,
    ) do
      html = File.read("public/posts/dup/index.html")
      html.should contain("AAA-WINNER")
      html.should_not contain("BBB-LOSER")
    end
  end

  it "keeps the real page when a later page's alias collides with its URL" do
    # zzz.md's alias points at /about/, which about.md already owns. The
    # alias redirect must not stomp the real page's index.html.
    build_site(
      BASIC_CONFIG,
      content_files: {
        "about.md" => "---\ntitle: About\n---\nREAL-PAGE-BODY",
        "zzz.md"   => "---\ntitle: Z\naliases:\n  - /about/\n---\nZ",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/about/index.html")
      html.should contain("REAL-PAGE-BODY")
    end
  end

  it "writes the alias redirect of the first claimant on alias collisions" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "one.md" => "---\ntitle: One\naliases:\n  - /shared/\n---\nOne",
        "two.md" => "---\ntitle: Two\naliases:\n  - /shared/\n---\nTwo",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/shared/index.html")
      html.should contain("/one/")
      html.should_not contain("/two/")
    end
  end

  it "lets the real page beat an earlier page's alias for the same URL" do
    # a-legacy.md sorts before guide.md, but a page's own content always
    # outranks a redirect stub — real URLs claim before aliases.
    build_site(
      BASIC_CONFIG,
      content_files: {
        "a-legacy.md" => "---\ntitle: Legacy\naliases:\n  - /guide/\n---\nLEGACY",
        "guide.md"    => "---\ntitle: Guide\n---\nREAL-GUIDE-BODY",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/guide/index.html")
      html.should contain("REAL-GUIDE-BODY")
    end
  end

  it "does not let a render:false page claim a URL from a real page" do
    # A headless page never writes output, so it must not suppress the
    # real page that shares its URL.
    build_site(
      BASIC_CONFIG,
      content_files: {
        "a-headless.md" => "---\ntitle: Headless\nrender: false\nslug: about\n---\nHIDDEN",
        "z-about.md"    => "---\ntitle: About\nslug: about\n---\nREAL-ABOUT-BODY",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/about/index.html")
      html.should contain("REAL-ABOUT-BODY")
    end
  end

  it "ignores an alias that duplicates the page's own URL" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "about.md" => "---\ntitle: About\naliases:\n  - /about/\n---\nOWN-BODY",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/about/index.html")
      html.should contain("OWN-BODY")
    end
  end

  # `posts/a%2fb.md` claims the URL `/posts/a%2fb/`, but the output path was
  # computed by decoding the WHOLE URL first, which turned `%2f` into a real
  # directory level: the page landed on `posts/a/b/index.html` and destroyed
  # the rendered output of the file that owns it. The build exited 0 and
  # reported "render: 2 pages" with one file on disk.
  it "refuses a page whose URL hides a separator instead of overwriting another page" do
    log = with_captured_log do
      build_site(
        BASIC_CONFIG,
        content_files: {
          "posts/a/b.md"   => "---\ntitle: Real\n---\nREAL-PAGE-BODY",
          "posts/a%2fb.md" => "---\ntitle: Injected\n---\nINJECTED-BODY",
        },
        template_files: {"page.html" => "{{ content }}"},
      ) do
        html = File.read("public/posts/a/b/index.html")
        html.should contain("REAL-PAGE-BODY")
        html.should_not contain("INJECTED-BODY")
      end
    end

    log.should contain("Not publishing posts/a%2fb.md")
  end

  # A literal backslash is a legal POSIX filename character but a separator on
  # Windows, and browsers rewrite it to `/` inside a URL path — so it too used
  # to split into directories and clobber the real page.
  it "refuses a page whose URL contains a backslash" do
    log = with_captured_log do
      build_site(
        BASIC_CONFIG,
        content_files: {
          "posts/a/b.md"  => "---\ntitle: Real\n---\nREAL-PAGE-BODY",
          "posts/a\\b.md" => "---\ntitle: Backslash\n---\nBACKSLASH-BODY",
        },
        template_files: {"page.html" => "{{ content }}"},
      ) do
        html = File.read("public/posts/a/b/index.html")
        html.should contain("REAL-PAGE-BODY")
        html.should_not contain("BACKSLASH-BODY")
      end
    end

    log.should contain("Not publishing")
  end

  # `/Foo/` and `/foo/` are two files on ext4 and ONE file on APFS/NTFS, so
  # the exact-string collision map never saw the conflict and the second page
  # silently overwrote the first on the project's primary dev platform. The
  # warning is unconditional so a case-sensitive CI still reports it; only the
  # skip is gated on what the filesystem actually does.
  it "warns when two pages differ only by letter case in their URL" do
    log = with_captured_log do
      build_site(
        BASIC_CONFIG,
        content_files: {
          "a.md" => "---\ntitle: Upper\nslug: Foo\n---\nUPPER-BODY",
          "b.md" => "---\ntitle: Lower\nslug: foo\n---\nLOWER-BODY",
        },
        template_files: {"page.html" => "{{ content }}"},
      ) { }
    end

    log.should contain("Duplicate output path")
    log.should contain("a.md")
    log.should contain("b.md")
  end

  # Two URL strings, one file: the exact-string map treated them as separate
  # claims, so both pages wrote to `public/dup/index.html` in render order.
  it "detects a collision between two URL spellings of one output file" do
    log = with_captured_log do
      build_site(
        BASIC_CONFIG,
        content_files: {
          "a.md" => "---\ntitle: A\npath: /dup/\n---\nAAA-WINNER",
          "b.md" => "---\ntitle: B\npath: //dup//\n---\nBBB-LOSER",
        },
        template_files: {"page.html" => "{{ content }}"},
      ) do
        html = File.read("public/dup/index.html")
        html.should contain("AAA-WINNER")
        html.should_not contain("BBB-LOSER")
      end
    end

    log.should contain("Duplicate output path")
  end

  # Detecting the collision and declining to write the loser is only half a
  # fix: the build then advertised the URL it had just refused to write in
  # sitemap.xml, llms.txt, the feeds and the search index — trading a silent
  # overwrite for a dead link the site's own sitemap points at.
  it "does not advertise the URL of a page whose write was suppressed" do
    with_captured_log do
      build_site(
        <<-TOML,
          title = "Test Site"
          base_url = "http://localhost"
          [sitemap]
          enabled = true
          TOML
        content_files: {
          "a.md" => "---\ntitle: A\npath: /dup/\n---\nAAA-WINNER",
          "b.md" => "---\ntitle: B\npath: //dup//\n---\nBBB-LOSER",
        },
        template_files: {"page.html" => "{{ content }}"},
      ) do
        sitemap = File.read("public/sitemap.xml")
        sitemap.scan(/<loc>[^<]*dup[^<]*<\/loc>/).size.should eq(1)

        llms = File.read("public/llms.txt")
        llms.scan(/\/dup\//).size.should eq(1)
        llms.should contain("[A]")
        llms.should_not contain("[B]")
      end
    end
  end

  # Same hole for the OTHER kind of unwritten page: a URL that traverses out
  # of the output directory is refused at write time ("Not publishing"), but
  # it was never marked suppressed, so sitemap.xml, search.json and llms.txt
  # still advertised `/posts/../../escape/` — a guaranteed 404.
  it "does not advertise the URL of a page it refuses to publish" do
    log = with_captured_log do
      build_site(
        <<-TOML,
          title = "Test Site"
          base_url = "http://localhost"
          [sitemap]
          enabled = true
          [search]
          enabled = true
          TOML
        content_files: {
          "posts/ok.md"        => "---\ntitle: Ok\n---\nOK-BODY",
          "posts/traversal.md" => "---\ntitle: Traversal\nslug: ../../escape\n---\nESCAPE-BODY",
        },
        template_files: {"page.html" => "{{ content }}"},
      ) do
        File.read("public/sitemap.xml").should_not contain("escape")
        File.read("public/search.json").should_not contain("escape")

        llms = File.read("public/llms.txt")
        llms.should contain("[Ok]")
        llms.should_not contain("[Traversal]")
      end
    end

    log.should contain("Not publishing posts/traversal.md")
  end

  # A Markdown link destination cannot hold a raw space, so a page whose slug
  # has one rendered as `- [T](http://localhost/posts/custom slug/)` — not a
  # link at all. The sitemap already percent-encoded; llms.txt and the alias
  # redirect stub must agree with it.
  it "percent-encodes page URLs with spaces in llms.txt and alias redirects" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "posts/spaced.md" => "---\ntitle: Spaced\nslug: custom slug\naliases:\n  - /old-url/\n---\nSPACED-BODY",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.read("public/llms.txt").should contain("[Spaced](http://localhost/posts/custom%20slug/)")
      File.read("public/old-url/index.html").should contain("url=/posts/custom%20slug/")
    end
  end
end

# ---------------------------------------------------------------------------
# 14. Sequential render failure aggregation
# ---------------------------------------------------------------------------
describe "Edge Cases: sequential render failure aggregation" do
  it "renders past a failing page and reports every failure once (no first-error abort)" do
    # build_helper runs with parallel: false, so this exercises
    # process_files_sequential. Two pages share a broken template; the loop
    # must attempt both (grouped "Render failed for 2 pages" summary) instead
    # of aborting on the first, and still fail loud with the classified error.
    err = nil
    log = with_captured_log do
      err = expect_raises(Hwaro::HwaroError) do
        build_site(
          BASIC_CONFIG,
          content_files: {
            "bad1.md" => "---\ntitle: B1\ntemplate: broken\n---\nx",
            "bad2.md" => "---\ntitle: B2\ntemplate: broken\n---\nx",
            "good.md" => "---\ntitle: Good\n---\nok",
          },
          template_files: {
            "page.html"   => "{{ content }}",
            "broken.html" => "{{ page.title.nonexistent_attr }}",
          },
        ) { }
      end
    end

    err.not_nil!.code.should eq(Hwaro::Errors::HWARO_E_TEMPLATE)
    log.should contain("Render failed for 2 pages")
  end
end

# ---------------------------------------------------------------------------
# 15. Symlinks and non-regular files in the source tree
#
# One unreadable entry must cost exactly that entry — never the whole build.
# These cases used to abort Initialize with a raw `File::Error` (mapped to
# HWARO_E_INTERNAL, leaving public/ EMPTY), hang the copy forever, or publish
# a file from outside the project.
# ---------------------------------------------------------------------------
private def run_symlink_build(output_dir : String = "public")
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: output_dir, parallel: false, highlight: false, verbose: false))
end

# Minimal project written directly (not via build_site) because the symlinks
# and sockets below have to exist BEFORE the build runs.
private def symlink_project
  File.write("config.toml", BASIC_CONFIG)
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates")
  FileUtils.mkdir_p("static")
  File.write("content/index.md", "---\ntitle: Home\n---\nHOME-BODY")
  File.write("templates/index.html", "{{ content }}")
  File.write("templates/page.html", "{{ content }}")
  File.write("templates/section.html", "{{ content }}")
  File.write("static/keep.txt", "KEEP")
end

describe "Edge Cases: symlinks and non-regular files" do
  it "skips a symlink cycle under static/ and still publishes the site" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        symlink_project
        # Self-referential link: stat fails with ELOOP, which `File.info?`
        # raises instead of reporting as a missing target.
        File.symlink("loop", "static/loop")

        built = false
        log = with_captured_log { built = run_symlink_build }

        built.should be_true
        File.read("public/index.html").should contain("HOME-BODY")
        File.read("public/keep.txt").should eq("KEEP")
        File.exists?("public/loop").should be_false
        log.should contain("Skipping unresolvable static symlink")
      end
    end
  end

  it "skips a non-regular file under static/ and still publishes the site" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        symlink_project
        # A unix socket stands in for the `mkfifo static/pipe` of the original
        # report: both are non-regular files that the copy must never open.
        # The FIFO itself cannot be used in a spec — without the guard,
        # `open(2)` on it blocks forever, which would HANG this suite rather
        # than fail it. The socket exercises the identical `type.file?` guard
        # and fails fast if it ever regresses.
        server = UNIXServer.new("static/s.sock")
        begin
          log = with_captured_log { run_symlink_build }

          File.read("public/index.html").should contain("HOME-BODY")
          File.read("public/keep.txt").should eq("KEEP")
          File.exists?("public/s.sock").should be_false
          log.should contain("Skipping non-regular static file")
        ensure
          server.close
        end
      end
    end
  end

  it "skips a content symlink whose target lives outside the project" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "outside.md"), "---\ntitle: Leak\n---\nSECRET-BODY")
      project = File.join(dir, "site")
      FileUtils.mkdir_p(project)
      Dir.cd(project) do
        symlink_project
        File.symlink(File.join("..", "..", "outside.md"), "content/leak.md")

        log = with_captured_log { run_symlink_build }

        File.read("public/index.html").should contain("HOME-BODY")
        File.exists?("public/leak/index.html").should be_false
        log.should contain("Skipping content symlink that does not resolve inside the project")
      end
    end
  end

  it "skips a symlink cycle under content/ and still publishes the site" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        symlink_project
        File.symlink("loop.md", "content/loop.md")

        built = false
        log = with_captured_log { built = run_symlink_build }

        built.should be_true
        File.read("public/index.html").should contain("HOME-BODY")
        log.should contain("Skipping content symlink that does not resolve inside the project")
      end
    end
  end
end

# ---------------------------------------------------------------------------
# 16. Invalid UTF-8 in a template
#
# `File.read` does not validate UTF-8, so a single stray byte travelled into
# the templates hash and the first PCRE2 pass over it (the TemplateDeps
# reference scan) aborted the Initialize phase with "Regex match error: UTF-8
# error: illegal byte" — reported as HWARO_E_INTERNAL / exit 70, and naming
# no file, so on a site with dozens of templates the offender was unfindable.
# Content and data files already degrade per-file; templates must too.
# ---------------------------------------------------------------------------
describe "Edge Cases: invalid UTF-8 in a template" do
  it "scrubs the bad bytes, names the template, and still builds" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        symlink_project
        # 0xff is illegal in UTF-8 anywhere (a latin-1 paste, a truncated
        # multi-byte sequence). Written as raw bytes because the invalid
        # sequence cannot survive a Crystal string literal.
        File.open("templates/page.html", "wb") do |io|
          io.write("<p>".to_slice)
          io.write(Bytes[0xff])
          io.write("{{ content }}</p>".to_slice)
        end
        File.write("content/about.md", "---\ntitle: About\n---\nABOUT-BODY")

        built = false
        log = with_captured_log { built = run_symlink_build }

        built.should be_true
        log.should contain("templates/page.html")
        log.should contain("invalid UTF-8")
        # The template still renders — only the offending byte was replaced.
        html = File.read("public/about/index.html")
        html.should contain("ABOUT-BODY")
      end
    end
  end
end
