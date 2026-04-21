require "../../spec_helper"
require "../../../src/services/importers/hexo_importer"

describe Hwaro::Services::Importers::HexoImporter do
  describe "#run" do
    it "imports a basic Hexo post" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "source", "_posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-HEXO
          ---
          title: Hello Hexo
          date: 2024-02-20 10:30:00
          tags:
            - hexo
            - blog
          categories:
            - tech
          ---
          Welcome to my Hexo blog.
          HEXO

        File.write(File.join(posts_dir, "hello-hexo.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "hexo",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::HexoImporter.new
        result = importer.run(options)

        result.success.should be_true
        result.imported_count.should eq(1)

        output_file = File.join(output_dir, "posts", "hello-hexo.md")
        File.exists?(output_file).should be_true

        content = File.read(output_file)
        content.should contain("+++")
        content.should contain("title = \"Hello Hexo\"")
        content.should contain("tags = [\"hexo\", \"blog\", \"tech\"]")
        content.should contain("Welcome to my Hexo blog.")
      end
    end

    it "imports posts with date-prefixed filenames" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "source", "_posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-HEXO
          ---
          title: "Date Prefix Post"
          ---
          Content.
          HEXO

        File.write(File.join(posts_dir, "2024-03-15-date-prefix.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "hexo",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::HexoImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "date-prefix.md"))
        content.should contain("date = \"2024-03-15 00:00:00\"")
      end
    end

    it "removes <!-- more --> excerpt separator" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "source", "_posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-HEXO
          ---
          title: "Excerpt Post"
          ---
          This is the excerpt.

          <!-- more -->

          This is the rest of the content.
          HEXO

        File.write(File.join(posts_dir, "excerpt-post.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "hexo",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::HexoImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "excerpt-post.md"))
        content.should_not contain("<!-- more -->")
        content.should contain("This is the excerpt.")
        content.should contain("This is the rest of the content.")
      end
    end

    it "imports drafts when options.drafts is true" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "source", "_posts")
        drafts_dir = File.join(dir, "source", "_drafts")
        FileUtils.mkdir_p(posts_dir)
        FileUtils.mkdir_p(drafts_dir)

        File.write(File.join(posts_dir, "published.md"), <<-HEXO
          ---
          title: "Published"
          ---
          Published content.
          HEXO
        )

        File.write(File.join(drafts_dir, "draft.md"), <<-HEXO
          ---
          title: "My Draft"
          ---
          Draft content.
          HEXO
        )

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "hexo",
          path: dir,
          output_dir: output_dir,
          drafts: true,
        )

        importer = Hwaro::Services::Importers::HexoImporter.new
        result = importer.run(options)

        result.imported_count.should eq(2)

        draft_content = File.read(File.join(output_dir, "posts", "draft.md"))
        draft_content.should contain("draft = true")
      end
    end

    it "does not import drafts when options.drafts is false" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "source", "_posts")
        drafts_dir = File.join(dir, "source", "_drafts")
        FileUtils.mkdir_p(posts_dir)
        FileUtils.mkdir_p(drafts_dir)

        File.write(File.join(posts_dir, "published.md"), <<-HEXO
          ---
          title: "Published"
          ---
          Content.
          HEXO
        )

        File.write(File.join(drafts_dir, "secret.md"), <<-HEXO
          ---
          title: "Secret"
          ---
          Secret.
          HEXO
        )

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "hexo",
          path: dir,
          output_dir: output_dir,
          drafts: false,
        )

        importer = Hwaro::Services::Importers::HexoImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)
      end
    end

    it "maps updated field" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "source", "_posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-HEXO
          ---
          title: "Updated Post"
          date: 2024-01-01
          updated: 2024-06-15
          ---
          Content.
          HEXO

        File.write(File.join(posts_dir, "updated-post.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "hexo",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::HexoImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "updated-post.md"))
        content.should contain("updated = \"2024-06-15 00:00:00\"")
      end
    end

    it "handles nested categories" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "source", "_posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-HEXO
          ---
          title: "Nested Categories"
          categories:
            - - tech
              - web
            - design
          tags:
            - frontend
          ---
          Content.
          HEXO

        File.write(File.join(posts_dir, "nested-cats.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "hexo",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::HexoImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "nested-cats.md"))
        content.should contain("\"frontend\"")
        content.should contain("\"tech\"")
        content.should contain("\"web\"")
        content.should contain("\"design\"")
      end
    end

    it "returns error result for non-existent directory" do
      options = Hwaro::Config::Options::ImportOptions.new(
        source_type: "hexo",
        path: "/non/existent/path",
        output_dir: "/tmp/output",
      )

      importer = Hwaro::Services::Importers::HexoImporter.new
      result = importer.run(options)

      result.success.should be_false
      result.message.should contain("not found")
    end
  end
end
