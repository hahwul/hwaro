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
