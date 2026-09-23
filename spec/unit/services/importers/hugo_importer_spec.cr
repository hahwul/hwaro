require "../../../spec_helper"
require "../../../../src/services/importers/hugo_importer"

private def make_hugo_options(path : String, output_dir : String, drafts : Bool = false) : Hwaro::Config::Options::ImportOptions
  Hwaro::Config::Options::ImportOptions.new(
    source_type: "hugo",
    path: path,
    output_dir: output_dir,
    drafts: drafts,
    verbose: false
  )
end

private def setup_hugo_site(tmpdir : String) : String
  hugo_dir = File.join(tmpdir, "hugo_site")
  FileUtils.mkdir_p(File.join(hugo_dir, "content"))
  hugo_dir
end

private def write_hugo_content(hugo_dir : String, relative_path : String, content : String)
  full_path = File.join(hugo_dir, "content", relative_path)
  FileUtils.mkdir_p(File.dirname(full_path))
  File.write(full_path, content)
end

TOML_POST = <<-MD
  +++
  title = "Hello from Hugo"
  date = "2024-06-15 10:00:00"
  description = "A test post"
  tags = ["crystal", "static-site"]
  draft = false
  slug = "hello-hugo"
  weight = "10"
  +++

  This is the body of the post.
  MD

YAML_POST = <<-MD
  ---
  title: "YAML Post"
  date: "2024-07-20 14:30:00"
  lastmod: "2024-08-01 09:00:00"
  description: "Written in YAML"
  tags:
    - yaml
    - hugo
  categories:
    - tutorials
  draft: false
  ---

  YAML content goes here.
  MD

DRAFT_POST = <<-MD
  +++
  title = "Secret Draft"
  date = "2024-05-01 08:00:00"
  draft = true
  +++

  This is a draft.
  MD

SHORTCODE_POST = <<-MD
  +++
  title = "Shortcode Post"
  date = "2024-09-01 12:00:00"
  +++

  Here is a figure shortcode: {{< figure src="image.png" >}}
  And a highlight: {{% highlight go %}}
  fmt.Println("hello")
  {{% /highlight %}}
  MD

INDEX_POST = <<-MD
  +++
  title = "Blog Section"
  description = "All blog posts"
  +++

  Welcome to the blog.
  MD

IMAGE_TOML_POST = <<-MD
  +++
  title = "Post with Image"
  date = "2024-10-01 00:00:00"
  images = ["https://example.com/hero.jpg", "https://example.com/thumb.jpg"]
  +++

  Image post body.
  MD

FEATURED_IMAGE_POST = <<-MD
  +++
  title = "Featured Image Post"
  date = "2024-10-02 00:00:00"
  featured_image = "https://example.com/featured.jpg"
  +++

  Featured image body.
  MD

SERIES_POST = <<-MD
  +++
  title = "Series Part 1"
  date = "2024-11-01 00:00:00"
  series = "My Series"
  +++

  Series content.
  MD

ALIASES_POST = <<-MD
  +++
  title = "Aliased Post"
  date = "2024-11-15 00:00:00"
  aliases = ["/old-url", "/another-old-url"]
  +++

  Aliased body.
  MD

EXPIRY_POST = <<-MD
  +++
  title = "Expiring Post"
  date = "2024-12-01 00:00:00"
  expiryDate = "2025-06-01 00:00:00"
  +++

  This post expires.
  MD

SUMMARY_POST = <<-MD
  +++
  title = "Summary Post"
  date = "2024-12-15 00:00:00"
  summary = "A summary instead of description"
  +++

  Summary body.
  MD

describe Hwaro::Services::Importers::HugoImporter do
  describe "#run" do
    it "imports a TOML frontmatter post" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/hello.md", TOML_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options(hugo_dir, output_dir))

        result.success.should be_true
        result.imported_count.should eq(1)
        result.skipped_count.should eq(0)

        file_path = File.join(output_dir, "posts", "hello-hugo.md")
        File.exists?(file_path).should be_true

        content = File.read(file_path)
        content.should contain("title = \"Hello from Hugo\"")
        content.should contain("date = \"2024-06-15T10:00:00Z\"")
        content.should contain("description = \"A test post\"")
        content.should contain("\"crystal\"")
        content.should contain("\"static-site\"")
        content.should contain("weight = 10")
        content.should contain("This is the body of the post.")
      end
    end

    it "imports a YAML frontmatter post with lastmod and categories" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/yaml-post.md", YAML_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options(hugo_dir, output_dir))

        result.success.should be_true
        result.imported_count.should eq(1)

        file_path = File.join(output_dir, "posts", "yaml-post.md")
        File.exists?(file_path).should be_true

        content = File.read(file_path)
        content.should contain("title = \"YAML Post\"")
        content.should contain("updated =")
        content.should contain("description = \"Written in YAML\"")
        content.should contain(%(tags = ["yaml", "hugo"]))
        content.should contain(%(categories = ["tutorials"]))
        content.should contain("YAML content goes here.")
      end
    end

    it "skips draft posts by default" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/draft.md", DRAFT_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options(hugo_dir, output_dir))

        result.imported_count.should eq(0)
        result.skipped_count.should eq(1)
      end
    end

    it "imports draft posts when drafts option is true" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/draft.md", DRAFT_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options(hugo_dir, output_dir, drafts: true))

        result.imported_count.should eq(1)

        file_path = File.join(output_dir, "posts", "draft.md")
        File.exists?(file_path).should be_true

        content = File.read(file_path)
        content.should contain("draft = true")
        content.should contain("title = \"Secret Draft\"")
      end
    end

    it "preserves directory structure" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "blog/tutorials/crystal-intro.md", TOML_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options(hugo_dir, output_dir))

        result.imported_count.should eq(1)

        # Should preserve the nested directory structure
        file_path = File.join(output_dir, "blog", "tutorials", "hello-hugo.md")
        File.exists?(file_path).should be_true
      end
    end

    it "handles _index.md files" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "blog/_index.md", INDEX_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options(hugo_dir, output_dir))

        result.imported_count.should eq(1)

        file_path = File.join(output_dir, "blog", "_index.md")
        File.exists?(file_path).should be_true

        content = File.read(file_path)
        content.should contain("title = \"Blog Section\"")
        content.should contain("Welcome to the blog.")
      end
    end

    it "returns error when content directory does not exist" do
      Dir.mktmpdir do |tmpdir|
        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options("/nonexistent/hugo", File.join(tmpdir, "output")))

        result.success.should be_false
        result.message.should contain("not found")
      end
    end

    it "extracts image from images array" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/image-post.md", IMAGE_TOML_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options(hugo_dir, output_dir))

        result.imported_count.should eq(1)

        file_path = File.join(output_dir, "posts", "image-post.md")
        content = File.read(file_path)
        content.should contain("image = \"https://example.com/hero.jpg\"")
      end
    end

    it "extracts featured_image as fallback" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/featured.md", FEATURED_IMAGE_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options(hugo_dir, output_dir))

        result.imported_count.should eq(1)

        file_path = File.join(output_dir, "posts", "featured.md")
        content = File.read(file_path)
        content.should contain("image = \"https://example.com/featured.jpg\"")
      end
    end

    it "maps series field" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/series.md", SERIES_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options(hugo_dir, output_dir))

        result.imported_count.should eq(1)

        file_path = File.join(output_dir, "posts", "series.md")
        content = File.read(file_path)
        content.should contain("series = \"My Series\"")
      end
    end

    it "maps aliases field" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/aliased.md", ALIASES_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options(hugo_dir, output_dir))

        result.imported_count.should eq(1)

        file_path = File.join(output_dir, "posts", "aliased.md")
        content = File.read(file_path)
        content.should contain("aliases = [\"/old-url\", \"/another-old-url\"]")
      end
    end

    it "maps expiryDate to expires" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/expiry.md", EXPIRY_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options(hugo_dir, output_dir))

        result.imported_count.should eq(1)

        file_path = File.join(output_dir, "posts", "expiry.md")
        content = File.read(file_path)
        content.should contain("expires = \"2025-06-01\"")
      end
    end

    it "uses summary when description is absent" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/summary.md", SUMMARY_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options(hugo_dir, output_dir))

        result.imported_count.should eq(1)

        file_path = File.join(output_dir, "posts", "summary.md")
        content = File.read(file_path)
        content.should contain("description = \"A summary instead of description\"")
      end
    end

    it "handles multiple files across directories" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/post1.md", TOML_POST)
        write_hugo_content(hugo_dir, "posts/post2.md", YAML_POST)
        write_hugo_content(hugo_dir, "pages/about.md", INDEX_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result = importer.run(make_hugo_options(hugo_dir, output_dir))

        result.success.should be_true
        result.imported_count.should eq(3)
      end
    end

    it "skips duplicate files on second run" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/hello.md", TOML_POST)
        output_dir = File.join(tmpdir, "output")

        importer = Hwaro::Services::Importers::HugoImporter.new
        result1 = importer.run(make_hugo_options(hugo_dir, output_dir))
        result1.imported_count.should eq(1)

        result2 = importer.run(make_hugo_options(hugo_dir, output_dir))
        result2.imported_count.should eq(0)
        result2.skipped_count.should eq(1)
      end
    end
  end

  # Regression: Hugo reads JSON front matter (an object at the top of the
  # file); the importer did not, so the object landed in the body and the
  # page lost its title, date, tags and draft flag.
  describe "JSON front matter" do
    it "maps JSON front matter like TOML and YAML" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/json.md",
          "{\n  \"title\": \"JSON FM\",\n  \"date\": \"2024-02-03\",\n  \"tags\": [\"j\", \"k\"],\n  \"draft\": true\n}\n\nJSON body\n")
        output_dir = File.join(tmpdir, "out")

        result = Hwaro::Services::Importers::HugoImporter.new.run(make_hugo_options(hugo_dir, output_dir, drafts: true))
        result.success.should be_true

        content = File.read(File.join(output_dir, "posts", "json.md"))
        content.should contain(%(title = "JSON FM"))
        content.should contain(%(date = "2024-02-03"))
        content.should contain(%(tags = ["j", "k"]))
        content.should contain("draft = true")
        content.should contain("JSON body")
        content.should_not contain(%("title": "JSON FM"))
      end
    end
  end

  # Regression: a leaf bundle's `slug` renames the bundle's URL segment in
  # Hugo (/posts/my-trip/), but the importer wrote `posts/trip/my-trip.md`
  # beside the copied resources, so the page moved to /posts/trip/my-trip/
  # and its relative images broke.
  describe "leaf bundle with slug" do
    it "keeps the bundle shape under the slugged directory" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/trip/index.md", "+++\ntitle = \"Trip\"\nslug = \"my-trip\"\n+++\n![p](photo.png)\n")
        write_hugo_content(hugo_dir, "posts/trip/photo.png", "png")
        write_hugo_content(hugo_dir, "top/index.md", "+++\ntitle = \"Top\"\nslug = \"renamed\"\n+++\nx\n")
        output_dir = File.join(tmpdir, "out")

        Hwaro::Services::Importers::HugoImporter.new.run(make_hugo_options(hugo_dir, output_dir)).success.should be_true

        File.exists?(File.join(output_dir, "posts", "my-trip", "index.md")).should be_true
        File.exists?(File.join(output_dir, "posts", "my-trip", "photo.png")).should be_true
        File.exists?(File.join(output_dir, "posts", "trip", "my-trip.md")).should be_false
        File.exists?(File.join(output_dir, "renamed", "index.md")).should be_true
      end
    end
  end

  # Regression: Hugo's `url` front matter (the page's whole published path)
  # was dropped, so an imported page moved and every link to it broke.
  describe "url front matter" do
    it "maps url to path, keeping a .html address as an alias" do
      Dir.mktmpdir do |tmpdir|
        hugo_dir = setup_hugo_site(tmpdir)
        write_hugo_content(hugo_dir, "posts/custom.md", "---\ntitle: Custom\nurl: /special/place/\n---\nx\n")
        write_hugo_content(hugo_dir, "posts/old.md", "---\ntitle: Old\nurl: /old/page.html\n---\nx\n")
        output_dir = File.join(tmpdir, "out")

        Hwaro::Services::Importers::HugoImporter.new.run(make_hugo_options(hugo_dir, output_dir)).success.should be_true

        File.read(File.join(output_dir, "posts", "custom.md")).should contain(%(path = "special/place"))
        old = File.read(File.join(output_dir, "posts", "old.md"))
        old.should contain(%(path = "old/page"))
        old.should contain(%(aliases = ["/old/page.html"]))
      end
    end
  end
end
