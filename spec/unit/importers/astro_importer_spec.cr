require "../../spec_helper"
require "../../../src/services/importers/astro_importer"

describe Hwaro::Services::Importers::AstroImporter do
  describe "#run" do
    it "imports a basic Astro content collection post" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "src", "content", "blog")
        FileUtils.mkdir_p(blog_dir)

        post_content = <<-ASTRO
          ---
          title: "My Astro Post"
          pubDate: 2024-04-10
          description: "An Astro blog post"
          tags:
            - astro
            - web
          heroImage: "/images/hero.jpg"
          ---
          Welcome to my Astro blog.
          ASTRO

        File.write(File.join(blog_dir, "my-astro-post.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "astro",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::AstroImporter.new
        result = importer.run(options)

        result.success.should be_true
        result.imported_count.should eq(1)

        output_file = File.join(output_dir, "blog", "my-astro-post.md")
        File.exists?(output_file).should be_true

        content = File.read(output_file)
        content.should contain("+++")
        content.should contain("title = \"My Astro Post\"")
        content.should contain("description = \"An Astro blog post\"")
        content.should contain("tags = [\"astro\", \"web\"]")
        content.should contain("image = \"/images/hero.jpg\"")
        content.should contain("Welcome to my Astro blog.")
      end
    end

    it "extracts src from a structured heroImage object" do
      # Astro's official starter blog ships `heroImage: { src, alt }` (a YAML
      # mapping), exercising the `when Hash` branch and the image["src"]?
      # YAML::Any indexing. A regression mapping the wrong key would silently
      # drop the cover image on every imported Astro post using that shape.
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "src", "content", "blog")
        FileUtils.mkdir_p(blog_dir)

        post_content = <<-ASTRO
          ---
          title: "Structured Hero"
          heroImage:
            src: /images/hero.jpg
            alt: Hero
          ---
          Content.
          ASTRO

        File.write(File.join(blog_dir, "structured-hero.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "astro",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::AstroImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)
        content = File.read(File.join(output_dir, "blog", "structured-hero.md"))
        content.should contain("image = \"/images/hero.jpg\"")
      end
    end

    it "emits no image when a structured heroImage object lacks src" do
      # Object with only `alt:` — no src to extract, so no image field and
      # no crash on the YAML::Any indexing path.
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "src", "content", "blog")
        FileUtils.mkdir_p(blog_dir)

        post_content = <<-ASTRO
          ---
          title: "Alt Only Hero"
          heroImage:
            alt: Just alt text
          ---
          Content.
          ASTRO

        File.write(File.join(blog_dir, "alt-only-hero.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "astro",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::AstroImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)
        content = File.read(File.join(output_dir, "blog", "alt-only-hero.md"))
        content.should_not contain("image =")
      end
    end

    it "maps pubDate to date" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "src", "content", "blog")
        FileUtils.mkdir_p(blog_dir)

        post_content = <<-ASTRO
          ---
          title: "Date Test"
          pubDate: 2024-05-20
          ---
          Content.
          ASTRO

        File.write(File.join(blog_dir, "date-test.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "astro",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::AstroImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "blog", "date-test.md"))
        content.should contain("date = \"2024-05-20 00:00:00\"")
      end
    end

    it "maps updatedDate to updated" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "src", "content", "blog")
        FileUtils.mkdir_p(blog_dir)

        post_content = <<-ASTRO
          ---
          title: "Updated Test"
          pubDate: 2024-01-01
          updatedDate: 2024-06-01
          ---
          Content.
          ASTRO

        File.write(File.join(blog_dir, "updated-test.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "astro",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::AstroImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "blog", "updated-test.md"))
        content.should contain("updated = \"2024-06-01 00:00:00\"")
      end
    end

    it "skips drafts when options.drafts is false" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "src", "content", "blog")
        FileUtils.mkdir_p(blog_dir)

        post_content = <<-ASTRO
          ---
          title: "Draft Post"
          draft: true
          ---
          Draft content.
          ASTRO

        File.write(File.join(blog_dir, "draft-post.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "astro",
          path: dir,
          output_dir: output_dir,
          drafts: false,
        )

        importer = Hwaro::Services::Importers::AstroImporter.new
        result = importer.run(options)

        result.imported_count.should eq(0)
        result.skipped_count.should eq(1)
      end
    end

    it "handles .mdx files" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "src", "content", "blog")
        FileUtils.mkdir_p(blog_dir)

        post_content = <<-ASTRO
          ---
          title: "MDX Post"
          pubDate: 2024-07-01
          ---
          Some content with standard markdown.
          ASTRO

        File.write(File.join(blog_dir, "mdx-post.mdx"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "astro",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::AstroImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)
      end
    end

    it "preserves collection name as section" do
      Dir.mktmpdir do |dir|
        docs_dir = File.join(dir, "src", "content", "docs")
        FileUtils.mkdir_p(docs_dir)

        post_content = <<-ASTRO
          ---
          title: "Documentation Page"
          ---
          Doc content.
          ASTRO

        File.write(File.join(docs_dir, "getting-started.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "astro",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::AstroImporter.new
        importer.run(options)

        File.exists?(File.join(output_dir, "docs", "getting-started.md")).should be_true
      end
    end

    it "returns error for missing src/content directory" do
      Dir.mktmpdir do |dir|
        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "astro",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::AstroImporter.new
        result = importer.run(options)

        result.success.should be_false
        result.message.should contain("not found")
      end
    end

    it "returns error result for non-existent directory" do
      options = Hwaro::Config::Options::ImportOptions.new(
        source_type: "astro",
        path: "/non/existent/path",
        output_dir: "/tmp/output",
      )

      importer = Hwaro::Services::Importers::AstroImporter.new
      result = importer.run(options)

      result.success.should be_false
      result.message.should contain("not found")
    end

    it "maps a singular author to the authors array" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "src", "content", "blog")
        FileUtils.mkdir_p(blog_dir)

        post_content = <<-ASTRO
          ---
          title: "Author Test"
          author: "Jane"
          ---
          Content.
          ASTRO

        File.write(File.join(blog_dir, "author-test.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "astro",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::AstroImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "blog", "author-test.md"))
        content.should contain("authors = [\"Jane\"]")
      end
    end
  end
end
