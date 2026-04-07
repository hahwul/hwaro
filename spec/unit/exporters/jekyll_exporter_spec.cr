require "../../spec_helper"

describe Hwaro::Services::Exporters::JekyllExporter do
  describe "#run" do
    it "returns failure when no content files found" do
      exporter = Hwaro::Services::Exporters::JekyllExporter.new
      options = Hwaro::Config::Options::ExportOptions.new(
        target_type: "jekyll",
        content_dir: "/nonexistent/content",
        output_dir: "/tmp/export",
      )
      result = exporter.run(options)
      result.success.should be_false
    end

    it "exports with YAML frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"My Post\"\ndate = \"2024-01-15\"\ndescription = \"A post\"\ntags = [\"crystal\"]\n+++\n\nHello world\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "jekyll",
          content_dir: content_dir,
          output_dir: output_dir,
        )
        result = exporter.run(options)

        result.success.should be_true
        result.exported_count.should eq(1)

        # Should be in _posts with date prefix
        posts_dir = File.join(output_dir, "_posts")
        Dir.exists?(posts_dir).should be_true

        files = Dir.glob(File.join(posts_dir, "*.md"))
        files.size.should eq(1)

        content = File.read(files.first)
        content.should contain("---")
        content.should contain("title:")
        content.should_not contain("+++")
      end
    end

    it "uses date-prefixed filenames for posts" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "my-post.md"), "+++\ntitle = \"My Post\"\ndate = \"2024-03-15\"\n+++\n\nContent\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "jekyll",
          content_dir: content_dir,
          output_dir: output_dir,
        )
        exporter.run(options)

        File.exists?(File.join(output_dir, "_posts", "2024-03-15-my-post.md")).should be_true
      end
    end

    it "converts draft to published: false" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "draft.md"), "+++\ntitle = \"Draft\"\ndraft = true\ndate = \"2024-01-01\"\n+++\n\nDraft content\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "jekyll",
          content_dir: content_dir,
          output_dir: output_dir,
          drafts: true,
        )
        exporter.run(options)

        # Drafts go to _drafts directory
        drafts_dir = File.join(output_dir, "_drafts")
        Dir.exists?(drafts_dir).should be_true
        files = Dir.glob(File.join(drafts_dir, "*.md"))
        files.size.should eq(1)

        content = File.read(files.first)
        content.should contain("published: false")
      end
    end

    it "skips drafts by default" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "draft.md"), "+++\ntitle = \"Draft\"\ndraft = true\n+++\n\nDraft\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "jekyll",
          content_dir: content_dir,
          output_dir: output_dir,
          drafts: false,
        )
        result = exporter.run(options)

        result.skipped_count.should eq(1)
        result.exported_count.should eq(0)
      end
    end

    it "exports section index files as pages" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "about"))

        File.write(File.join(content_dir, "about", "_index.md"), "+++\ntitle = \"About\"\n+++\n\nAbout page\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "jekyll",
          content_dir: content_dir,
          output_dir: output_dir,
        )
        exporter.run(options)

        File.exists?(File.join(output_dir, "about", "index.md")).should be_true
      end
    end
  end
end
