require "./support/build_helper"

# =============================================================================
# Output formats functional tests (see `[outputs]`, docs/content/features/
# output-formats.md)
#
# Verifies: section-format generation (page 1 of pagination only), per-page
# format generation, front matter overrides (including explicit suppression
# and the missing-template hard error), alternate_output_tags under a subpath
# base_url, and cache staleness (deleted format file + template-only edits).
# =============================================================================

SECTION_OUTPUTS_CONFIG = <<-TOML
  title = "Test"
  base_url = "http://localhost"

  [pagination]
  enabled = true
  per_page = 1

  [outputs]
  section = ["json"]
  TOML

PAGE_OUTPUTS_CONFIG = <<-TOML
  title = "Test"
  base_url = "http://localhost"

  [outputs]
  page = ["json"]
  TOML

SUBPATH_OUTPUTS_CONFIG = <<-TOML
  title = "Test"
  base_url = "http://localhost/blog"

  [outputs]
  page = ["json"]
  TOML

describe "Output formats: [outputs].section" do
  it "renders a sibling index.json for the section, page 1 only" do
    build_site(
      SECTION_OUTPUTS_CONFIG,
      content_files: {
        "posts/_index.md" => "---\ntitle: Posts\n---\n",
        "posts/a.md"      => "---\ntitle: A\ndate: 2024-01-01\n---\nA",
        "posts/b.md"      => "---\ntitle: B\ndate: 2024-01-02\n---\nB",
      },
      template_files: {
        "page.html"          => "{{ content }}",
        "section.html"       => "{{ section.title }}",
        "section.json.jinja" => %({"title": "{{ section.title }}", "pages": [{% for p in section.pages %}"{{ p.url }}"{% if not loop.last %},{% endif %}{% endfor %}]}),
      },
    ) do
      File.exists?("public/posts/index.json").should be_true
      json = File.read("public/posts/index.json")
      json.should contain(%("title": "Posts"))
      json.should contain("/posts/a/")
      json.should contain("/posts/b/")

      # Pagination produces a second HTML page but formats apply once, to
      # page 1 only — no index.json under page/2/.
      File.exists?("public/posts/page/2/index.html").should be_true
      File.exists?("public/posts/page/2/index.json").should be_false
    end
  end
end

describe "Output formats: [outputs].page" do
  it "renders a sibling index.json per page" do
    build_site(
      PAGE_OUTPUTS_CONFIG,
      content_files: {"about.md" => "---\ntitle: About\n---\nAbout body"},
      template_files: {
        "page.html"       => "{{ content }}",
        "page.json.jinja" => %({"title": "{{ page.title }}", "url": "{{ page.url }}"}),
      },
    ) do
      File.exists?("public/about/index.json").should be_true
      File.read("public/about/index.json").should eq(%({"title": "About", "url": "/about/"}))
    end
  end

  it "suppresses the format when front matter sets an explicit empty outputs list" do
    build_site(
      PAGE_OUTPUTS_CONFIG,
      content_files: {"about.md" => "---\ntitle: About\noutputs: []\n---\nAbout body"},
      template_files: {
        "page.html"       => "{{ content }}",
        "page.json.jinja" => %({"title": "{{ page.title }}"}),
      },
    ) do
      File.exists?("public/about/index.html").should be_true
      File.exists?("public/about/index.json").should be_false
    end
  end

  it "overrides the config default with a front matter format list" do
    build_site(
      PAGE_OUTPUTS_CONFIG,
      content_files: {"about.md" => "---\ntitle: About\noutputs: [xml]\n---\nAbout body"},
      template_files: {
        "page.html"      => "{{ content }}",
        "page.xml.jinja" => %(<page><title>{{ page.title }}</title></page>),
      },
    ) do
      File.exists?("public/about/index.json").should be_false
      File.exists?("public/about/index.xml").should be_true
      File.read("public/about/index.xml").should eq("<page><title>About</title></page>")
    end
  end

  it "fails the build with the tried-template-names error when no matching format template exists" do
    expect_raises(Hwaro::HwaroError, /No template found for output format 'txt'/) do
      build_site(
        BASIC_CONFIG,
        content_files: {"about.md" => "---\ntitle: About\noutputs: [txt]\n---\nAbout body"},
        template_files: {"page.html" => "{{ content }}"},
      ) { }
    end
  end
end

describe "Output formats: alternate_output_tags" do
  it "resolves the sibling format href under a subpath base_url" do
    build_site(
      SUBPATH_OUTPUTS_CONFIG,
      content_files: {"about.md" => "---\ntitle: About\n---\nAbout body"},
      template_files: {
        "page.html"       => "<head>{{ alternate_output_tags }}</head><body>{{ content }}</body>",
        "page.json.jinja" => %({"title": "{{ page.title }}"}),
      },
    ) do
      html = File.read("public/about/index.html")
      html.should contain(%(rel="alternate"))
      html.should contain(%(type="application/json"))
      html.should contain(%(href="http://localhost/blog/about/index.json"))
    end
  end
end

describe "Output formats: cache staleness (--cache)" do
  it "regenerates a manually deleted format file on a warm rebuild" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", PAGE_OUTPUTS_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/about.md", "---\ntitle: About\n---\nAbout body")
        File.write("templates/page.html", "{{ content }}")
        File.write("templates/page.json.jinja", %({"title": "{{ page.title }}"}))

        builder1 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder1.register(h) }
        builder1.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.exists?("public/about/index.json").should be_true
        File.delete("public/about/index.json")

        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.exists?("public/about/index.json").should be_true
      end
    end
  end

  it "re-renders affected pages when only the format template is edited" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", PAGE_OUTPUTS_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/about.md", "---\ntitle: About\n---\nAbout body")
        File.write("templates/page.html", "{{ content }}")
        File.write("templates/page.json.jinja", %({"title": "{{ page.title }}"}))

        builder1 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder1.register(h) }
        builder1.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.read("public/about/index.json").should eq(%({"title": "About"}))

        sleep 10.milliseconds
        File.write("templates/page.json.jinja", %({"title": "{{ page.title }}", "extra": true}))

        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.read("public/about/index.json").should eq(%({"title": "About", "extra": true}))
      end
    end
  end
end
