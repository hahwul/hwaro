require "../../spec_helper"
require "../../../src/services/importers/notion_importer"

describe Hwaro::Services::Importers::NotionImporter do
  describe "#run" do
    it "imports a Notion markdown export with YAML frontmatter" do
      Dir.mktmpdir do |dir|
        post_content = <<-NOTION
          ---
          title: "My Notion Page"
          date: 2024-03-15
          tags:
            - notion
            - productivity
          ---
          This is exported from Notion.
          NOTION

        File.write(File.join(dir, "my-notion-page.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "notion",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::NotionImporter.new
        result = importer.run(options)

        result.success.should be_true
        result.imported_count.should eq(1)

        output_file = File.join(output_dir, "posts", "my-notion-page.md")
        File.exists?(output_file).should be_true

        content = File.read(output_file)
        content.should contain("+++")
        content.should contain("title = \"My Notion Page\"")
        content.should contain("tags = [\"notion\", \"productivity\"]")
        content.should contain("This is exported from Notion.")
      end
    end

    it "extracts title from H1 heading when no frontmatter" do
      Dir.mktmpdir do |dir|
        post_content = "# My Page Title\n\nSome content here."
        File.write(File.join(dir, "page.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "notion",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::NotionImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "page.md"))
        content.should contain("title = \"My Page Title\"")
        content.should contain("Some content here.")
      end
    end

    it "strips Notion hex ID from filename for slug" do
      Dir.mktmpdir do |dir|
        post_content = "# Test Page\n\nContent."
        File.write(File.join(dir, "Test Page abc123def456789a.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "notion",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::NotionImporter.new
        importer.run(options)

        output_file = File.join(output_dir, "posts", "test-page.md")
        File.exists?(output_file).should be_true
      end
    end

    it "recursively scans subdirectories" do
      Dir.mktmpdir do |dir|
        subdir = File.join(dir, "Subpage")
        FileUtils.mkdir_p(subdir)

        File.write(File.join(dir, "page1.md"), "# Page 1\nContent 1.")
        File.write(File.join(subdir, "page2.md"), "# Page 2\nContent 2.")

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "notion",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::NotionImporter.new
        result = importer.run(options)

        result.imported_count.should eq(2)
      end
    end

    it "returns error result for non-existent directory" do
      options = Hwaro::Config::Options::ImportOptions.new(
        source_type: "notion",
        path: "/non/existent/path",
        output_dir: "/tmp/output",
      )

      importer = Hwaro::Services::Importers::NotionImporter.new
      result = importer.run(options)

      result.success.should be_false
      result.message.should contain("not found")
    end

    it "converts Notion bookmark embeds to standard links" do
      Dir.mktmpdir do |dir|
        post_content = "# Bookmarks\n\n[bookmark](https://example.com)\n\nMore text."
        File.write(File.join(dir, "bookmarks.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "notion",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::NotionImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "bookmarks.md"))
        content.should contain("[https://example.com](https://example.com)")
        content.should_not contain("[bookmark]")
      end
    end

    it "returns success with zero imports when no files exist" do
      Dir.mktmpdir do |dir|
        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "notion",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::NotionImporter.new
        result = importer.run(options)

        result.success.should be_true
        result.imported_count.should eq(0)
      end
    end
  end
end
