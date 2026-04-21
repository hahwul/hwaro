require "../spec_helper"

describe "Site Variables Integration" do
  it "exposes site.pages, site.sections, and site.taxonomies" do
    Dir.mktmpdir do |tmp_dir|
      # Setup structure
      FileUtils.mkdir_p(File.join(tmp_dir, "content/blog"))
      FileUtils.mkdir_p(File.join(tmp_dir, "templates"))

      # Config — Models::Config.load now raises HwaroError(HWARO_E_CONFIG)
      # when config.toml is missing, so provide a minimal one.
      File.write(File.join(tmp_dir, "config.toml"), %(title = "Test Site"\nbase_url = "http://example.com"))

      # Content
      File.write(File.join(tmp_dir, "content/index.md"), "---\ntitle: Home\n---\nHello")
      File.write(File.join(tmp_dir, "content/blog/_index.md"), "---\ntitle: Blog\n---\nBlog Index")
      File.write(File.join(tmp_dir, "content/blog/post1.md"), "---\ntitle: Post 1\ntags: [news]\n---\nPost 1 Content")

      # Template
      # We check lengths. We assume filters 'length' works (it's standard Jinja).
      template = <<-HTML
        Pages: {{ site.pages | length }}
        Sections: {{ site.sections | length }}
        Taxonomies: {{ site.taxonomies | length }}
        Tags: {{ site.taxonomies.tags.items | length }}
        HTML
      File.write(File.join(tmp_dir, "templates/page.html"), template)

      # Run Build
      Dir.cd(tmp_dir) do
        builder = Hwaro::Core::Build::Builder.new
        builder.run(output_dir: "public")
      end

      # Assert
      output = File.read(File.join(tmp_dir, "public/index.html"))

      # Pages: index.md, blog/post1.md -> 2
      # Sections: blog/_index.md -> 1
      # Taxonomies: tags -> 1
      # Tags items: news -> 1

      # Currently, this is expected to fail or return 0 if variables are missing
      output.should contain("Pages: 2")
      output.should contain("Sections: 1")
      output.should contain("Tags: 1")
    end
  end

  it "exposes site.title and site.base_url" do
    Dir.mktmpdir do |tmp_dir|
      FileUtils.mkdir_p(File.join(tmp_dir, "content"))
      FileUtils.mkdir_p(File.join(tmp_dir, "templates"))

      File.write(File.join(tmp_dir, "config.toml"), "title = \"My Awesome Site\"\nbase_url = \"https://example.com\"")
      File.write(File.join(tmp_dir, "content/index.md"), "---\ntitle: Home\n---\nHello")

      template = <<-HTML
        SITE_TITLE={{ site_title }}
        BASE_URL={{ base_url }}
        HTML
      File.write(File.join(tmp_dir, "templates/page.html"), template)

      Dir.cd(tmp_dir) do
        builder = Hwaro::Core::Build::Builder.new
        builder.run(output_dir: "public")
      end

      output = File.read(File.join(tmp_dir, "public/index.html"))
      output.should contain("SITE_TITLE=My Awesome Site")
      output.should contain("BASE_URL=https://example.com")
    end
  end

  it "exposes site.pages with page attributes" do
    Dir.mktmpdir do |tmp_dir|
      FileUtils.mkdir_p(File.join(tmp_dir, "content"))
      FileUtils.mkdir_p(File.join(tmp_dir, "templates"))

      File.write(File.join(tmp_dir, "config.toml"), "title = \"Test\"\nbase_url = \"http://localhost\"")
      File.write(File.join(tmp_dir, "content/index.md"), "---\ntitle: Home\n---\nHello")
      File.write(File.join(tmp_dir, "content/about.md"), "---\ntitle: About\n---\nAbout")

      template = "{% for p in site.pages %}{{ p.title }},{% endfor %}"
      File.write(File.join(tmp_dir, "templates/page.html"), template)

      Dir.cd(tmp_dir) do
        builder = Hwaro::Core::Build::Builder.new
        builder.run(output_dir: "public")
      end

      output = File.read(File.join(tmp_dir, "public/index.html"))
      output.should contain("Home,")
      output.should contain("About,")
    end
  end
end
