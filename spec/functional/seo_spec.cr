require "./support/build_helper"

# =============================================================================
# SEO feature integration tests
#
# Verifies llms.txt / llms-full.txt generation, Atom feed generation,
# and multiple SEO features working together.
# =============================================================================

describe "SEO: llms.txt generation" do
  it "generates llms.txt with instructions" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [llms]
      enabled = true
      instructions = "This is a test site about Crystal programming."
      TOML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/llms.txt").should be_true
      txt = File.read("public/llms.txt")
      txt.should contain("This is a test site about Crystal programming.")
    end
  end

  it "generates llms-full.txt with page content" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [llms]
      enabled = true
      instructions = "Test instructions"
      full_enabled = true
      TOML

    build_site(
      config,
      content_files: {
        "about.md" => "---\ntitle: About\n---\nAbout this site",
        "post.md"  => "---\ntitle: Post\n---\nPost body here",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/llms-full.txt").should be_true
      full = File.read("public/llms-full.txt")
      full.should contain("Test")
      full.should contain("About this site")
      full.should contain("Post body here")
      full.should contain("Test instructions")
    end
  end

  it "does not generate llms.txt when disabled" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [llms]
      enabled = false
      TOML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/llms.txt").should be_false
    end
  end
end

describe "SEO: Atom feed generation" do
  it "generates Atom feed" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"
      description = "A test site"

      [feeds]
      enabled = true
      type = "atom"
      filename = "atom.xml"
      TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/post.md"   => "---\ntitle: My Atom Post\ndate: 2024-06-15\n---\nAtom body",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ content }}",
      },
    ) do
      File.exists?("public/atom.xml").should be_true
      atom = File.read("public/atom.xml")
      atom.should contain("<feed")
      atom.should contain("My Atom Post")
    end
  end
end

describe "SEO: Multiple features simultaneously" do
  it "generates sitemap, robots, feed, and llms.txt together" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"
      description = "Multi-SEO test"

      [sitemap]
      enabled = true

      [robots]
      enabled = true

      [feeds]
      enabled = true
      type = "rss"
      filename = "rss.xml"

      [llms]
      enabled = true
      instructions = "Multi SEO"
      full_enabled = true
      TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/post.md"   => "---\ntitle: Post\ndate: 2024-01-01\n---\nContent",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ content }}",
      },
    ) do
      File.exists?("public/sitemap.xml").should be_true
      File.exists?("public/robots.txt").should be_true
      File.exists?("public/rss.xml").should be_true
      File.exists?("public/llms.txt").should be_true
      File.exists?("public/llms-full.txt").should be_true

      # Verify content correctness
      sitemap = File.read("public/sitemap.xml")
      sitemap.should contain("<urlset")

      robots = File.read("public/robots.txt")
      robots.should contain("User-agent")

      rss = File.read("public/rss.xml")
      rss.should contain("<rss")
      rss.should contain("Post")

      llms = File.read("public/llms.txt")
      llms.should contain("Multi SEO")
    end
  end
end

describe "SEO: Sitemap with custom configuration" do
  it "generates sitemap with configured changefreq and priority" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [sitemap]
      enabled = true
      changefreq = "daily"
      priority = 0.8
      TOML

    build_site(
      config,
      content_files: {
        "about.md"       => "---\ntitle: About\n---\nAbout",
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/post.md"   => "---\ntitle: Post\n---\nPost",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ content }}",
      },
    ) do
      File.exists?("public/sitemap.xml").should be_true
      sitemap = File.read("public/sitemap.xml")
      sitemap.should contain("<urlset")
      sitemap.should contain("http://localhost/about/")
      sitemap.should contain("http://localhost/blog/post/")
    end
  end

  it "excludes configured paths from sitemap" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [sitemap]
      enabled = true
      exclude = ["/secret/"]
      TOML

    build_site(
      config,
      content_files: {
        "about.md"  => "---\ntitle: About\n---\nAbout",
        "secret.md" => "---\ntitle: Secret\n---\nSecret",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      sitemap = File.read("public/sitemap.xml")
      sitemap.should contain("/about/")
      sitemap.should_not contain("/secret/")
    end
  end
end

describe "SEO: Robots.txt with custom rules" do
  it "generates robots.txt with multiple user-agent rules" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [robots]
      enabled = true

      [[robots.rules]]
      user_agent = "*"
      allow = ["/"]
      disallow = ["/private/", "/admin/"]

      [[robots.rules]]
      user_agent = "Googlebot"
      allow = ["/"]
      TOML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/robots.txt").should be_true
      robots = File.read("public/robots.txt")
      robots.should contain("User-agent")
    end
  end
end

describe "SEO: Search index with different formats" do
  it "generates search index with content field" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [search]
      enabled = true
      fields = ["title", "url", "content"]
      TOML

    build_site(
      config,
      content_files: {
        "page1.md" => "---\ntitle: Page One\n---\nSearchable content here",
        "page2.md" => "---\ntitle: Page Two\n---\nAnother searchable page",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/search.json").should be_true
      json = File.read("public/search.json")
      json.should contain("Page One")
      json.should contain("Page Two")
      json.should contain("Searchable content here")
    end
  end

  it "excludes pages with in_search_index: false" do
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
        "visible.md" => "---\ntitle: Visible Page\n---\nV",
        "hidden.md"  => "---\ntitle: Hidden Page\nin_search_index: false\n---\nH",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      json = File.read("public/search.json")
      json.should contain("Visible Page")
      json.should_not contain("Hidden Page")
    end
  end
end

describe "SEO: Atom feed with multiple posts" do
  it "generates Atom feed with correct entry structure" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"
      description = "A test site"

      [feeds]
      enabled = true
      type = "atom"
      filename = "atom.xml"
      TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/post1.md"  => "---\ntitle: First Post\ndate: 2024-06-15\n---\nFirst body",
        "blog/post2.md"  => "---\ntitle: Second Post\ndate: 2024-07-20\n---\nSecond body",
        "blog/post3.md"  => "---\ntitle: Third Post\ndate: 2024-08-25\n---\nThird body",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ content }}",
      },
    ) do
      atom = File.read("public/atom.xml")
      atom.should contain("<feed")
      atom.should contain("First Post")
      atom.should contain("Second Post")
      atom.should contain("Third Post")
      atom.should contain("<entry>")
    end
  end
end

describe "SEO: RSS feed content verification" do
  it "generates RSS with proper channel and item structure" do
    config = <<-TOML
      title = "My Site"
      base_url = "http://localhost"
      description = "Site description"

      [feeds]
      enabled = true
      type = "rss"
      filename = "feed.xml"
      TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/post.md"   => "---\ntitle: RSS Post\ndate: 2024-06-15\ndescription: Post summary\n---\nFull content here",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ content }}",
      },
    ) do
      rss = File.read("public/feed.xml")
      rss.should contain("<rss")
      rss.should contain("<channel>")
      rss.should contain("<item>")
      rss.should contain("RSS Post")
      rss.should contain("My Site")
    end
  end
end

describe "SEO: llms.txt content structure" do
  it "includes page titles and URLs in llms.txt" do
    config = <<-TOML
      title = "My Site"
      base_url = "http://localhost"

      [llms]
      enabled = true
      instructions = "This is My Site."
      TOML

    build_site(
      config,
      content_files: {
        "about.md"       => "---\ntitle: About Us\n---\nAbout content",
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/post.md"   => "---\ntitle: Hello World\n---\nPost content",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ content }}",
      },
    ) do
      llms = File.read("public/llms.txt")
      llms.should contain("My Site")
      llms.should contain("This is My Site.")
    end
  end
end
