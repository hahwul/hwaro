require "../../spec_helper"
require "../../../src/services/importers/jekyll_importer"

describe Hwaro::Services::Importers::JekyllImporter do
  describe "#run" do
    it "imports a basic Jekyll post with YAML frontmatter" do
      Dir.mktmpdir do |dir|
        # Set up fake Jekyll directory
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-JEKYLL
          ---
          title: "Hello World"
          date: 2024-01-15
          layout: post
          categories:
            - ruby
            - web
          tags:
            - tutorial
          ---
          This is my first post.
          JEKYLL

        File.write(File.join(posts_dir, "2024-01-15-hello-world.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        result = importer.run(options)

        result.success.should be_true
        result.imported_count.should eq(1)
        result.skipped_count.should eq(0)
        result.error_count.should eq(0)

        output_file = File.join(output_dir, "posts", "hello-world.md")
        File.exists?(output_file).should be_true

        content = File.read(output_file)
        content.should contain("+++")
        content.should contain("title = \"Hello World\"")
        content.should contain("template = \"post\"")
        content.should contain(%(categories = ["ruby", "web"]))
        content.should contain(%(tags = ["tutorial"]))
        content.should contain("This is my first post.")
      end
    end

    it "extracts slug from Jekyll filename" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-JEKYLL
          ---
          title: "My Great Post"
          ---
          Content here.
          JEKYLL

        File.write(File.join(posts_dir, "2023-06-10-my-great-post.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        importer.run(options)

        File.exists?(File.join(output_dir, "posts", "my-great-post.md")).should be_true
      end
    end

    it "extracts date from filename when not in frontmatter" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-JEKYLL
          ---
          title: "No Date Post"
          ---
          Content.
          JEKYLL

        File.write(File.join(posts_dir, "2023-12-25-no-date-post.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "no-date-post.md"))
        content.should contain("date = \"2023-12-25 00:00:00\"")
      end
    end

    it "marks published: false as draft" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-JEKYLL
          ---
          title: "Unpublished Post"
          published: false
          ---
          Draft content.
          JEKYLL

        File.write(File.join(posts_dir, "2024-02-01-unpublished.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "unpublished.md"))
        content.should contain("draft = true")
      end
    end

    it "imports drafts when options.drafts is true" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        drafts_dir = File.join(dir, "_drafts")
        FileUtils.mkdir_p(posts_dir)
        FileUtils.mkdir_p(drafts_dir)

        File.write(File.join(posts_dir, "2024-01-01-published.md"), <<-JEKYLL
          ---
          title: "Published"
          ---
          Published content.
          JEKYLL
        )

        File.write(File.join(drafts_dir, "my-draft.md"), <<-JEKYLL
          ---
          title: "My Draft"
          ---
          Draft content.
          JEKYLL
        )

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
          drafts: true,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        result = importer.run(options)

        result.imported_count.should eq(2)

        draft_content = File.read(File.join(output_dir, "posts", "my-draft.md"))
        draft_content.should contain("draft = true")
        draft_content.should contain("title = \"My Draft\"")
      end
    end

    it "does not import drafts when options.drafts is false" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        drafts_dir = File.join(dir, "_drafts")
        FileUtils.mkdir_p(posts_dir)
        FileUtils.mkdir_p(drafts_dir)

        File.write(File.join(posts_dir, "2024-01-01-published.md"), <<-JEKYLL
          ---
          title: "Published"
          ---
          Content.
          JEKYLL
        )

        File.write(File.join(drafts_dir, "secret-draft.md"), <<-JEKYLL
          ---
          title: "Secret Draft"
          ---
          Secret.
          JEKYLL
        )

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
          drafts: false,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)
        File.exists?(File.join(output_dir, "posts", "secret-draft.md")).should be_false
      end
    end

    it "maps excerpt to description" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-JEKYLL
          ---
          title: "With Excerpt"
          excerpt: "A short summary of the post"
          ---
          Full content here.
          JEKYLL

        File.write(File.join(posts_dir, "2024-03-01-with-excerpt.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "with-excerpt.md"))
        content.should contain("description = \"A short summary of the post\"")
      end
    end

    it "maps header.image to image" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-JEKYLL
          ---
          title: "With Header Image"
          header:
            image: /assets/images/hero.jpg
          ---
          Content.
          JEKYLL

        File.write(File.join(posts_dir, "2024-04-01-with-image.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "with-image.md"))
        content.should contain("image = \"/assets/images/hero.jpg\"")
      end
    end

    it "keeps categories and tags as separate taxonomy fields" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-JEKYLL
          ---
          title: "Split Taxonomies"
          category: programming
          tags:
            - crystal
            - tutorial
          ---
          Content.
          JEKYLL

        File.write(File.join(posts_dir, "2024-05-01-split-taxonomies.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "split-taxonomies.md"))
        content.should contain(%(categories = ["programming"]))
        content.should contain(%(tags = ["crystal", "tutorial"]))
      end
    end

    it "handles .markdown file extension" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-JEKYLL
          ---
          title: "Markdown Extension"
          ---
          Content.
          JEKYLL

        File.write(File.join(posts_dir, "2024-06-01-markdown-ext.markdown"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)
        File.exists?(File.join(output_dir, "posts", "markdown-ext.md")).should be_true
      end
    end

    it "returns error result for non-existent directory" do
      options = Hwaro::Config::Options::ImportOptions.new(
        source_type: "jekyll",
        path: "/non/existent/path",
        output_dir: "/tmp/output",
      )

      importer = Hwaro::Services::Importers::JekyllImporter.new
      result = importer.run(options)

      result.success.should be_false
      result.message.should contain("not found")
    end

    it "returns success with zero imports when no posts exist" do
      Dir.mktmpdir do |dir|
        # No _posts directory
        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        result = importer.run(options)

        result.success.should be_true
        result.imported_count.should eq(0)
      end
    end

    it "skips file that already exists in output" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)

        File.write(File.join(posts_dir, "2024-01-01-existing.md"), <<-JEKYLL
          ---
          title: "Existing"
          ---
          Content.
          JEKYLL
        )

        output_dir = File.join(dir, "output")
        # Pre-create the output file
        FileUtils.mkdir_p(File.join(output_dir, "posts"))
        File.write(File.join(output_dir, "posts", "existing.md"), "already here")

        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        result = importer.run(options)

        result.imported_count.should eq(0)
        result.skipped_count.should eq(1)
      end
    end

    it "overwrites existing output file when force is true" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)

        File.write(File.join(posts_dir, "2024-01-01-existing.md"), <<-JEKYLL
          ---
          title: "Existing"
          ---
          Fresh content.
          JEKYLL
        )

        output_dir = File.join(dir, "output")
        FileUtils.mkdir_p(File.join(output_dir, "posts"))
        File.write(File.join(output_dir, "posts", "existing.md"), "stale")

        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
          force: true,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)
        result.skipped_count.should eq(0)

        content = File.read(File.join(output_dir, "posts", "existing.md"))
        content.should contain("Fresh content.")
        content.should_not contain("stale")
      end
    end

    it "imports multiple posts" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)

        3.times do |i|
          File.write(File.join(posts_dir, "2024-01-0#{i + 1}-post-#{i + 1}.md"), <<-JEKYLL
            ---
            title: "Post #{i + 1}"
            ---
            Content #{i + 1}.
            JEKYLL
          )
        end

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        result = importer.run(options)

        result.imported_count.should eq(3)
      end
    end

    it "handles post without frontmatter" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)

        File.write(File.join(posts_dir, "2024-07-01-no-frontmatter.md"), "Just plain content.\n")

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::JekyllImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)
        content = File.read(File.join(output_dir, "posts", "no-frontmatter.md"))
        content.should contain("+++")
        content.should contain("Just plain content.")
      end
    end
  end
end
