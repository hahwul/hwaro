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

    it "handles posts without date (no date prefix)" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "no-date.md"), "+++\ntitle = \"No Date\"\n+++\n\nContent\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        # Should be in _posts without date prefix
        File.exists?(File.join(output_dir, "_posts", "no-date.md")).should be_true
      end
    end

    it "handles short date strings without crashing" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "short-date.md"), "+++\ntitle = \"Post\"\ndate = \"2024\"\n+++\n\nContent\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        result = exporter.run(options)

        # Should not crash, exported without date prefix
        result.exported_count.should eq(1)
        File.exists?(File.join(output_dir, "_posts", "short-date.md")).should be_true
      end
    end

    it "converts YAML frontmatter to YAML" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "yaml.md"), "---\ntitle: YAML Post\ndate: \"2024-05-20\"\ntags:\n  - ruby\n---\n\nContent\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        result = exporter.run(options)

        result.exported_count.should eq(1)
        content = File.read(File.join(output_dir, "_posts", "2024-05-20-yaml.md"))
        content.should contain("---")
        content.should contain("title:")
        content.should contain("- ruby")
      end
    end

    it "removes date prefix from draft filenames" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "draft.md"), "+++\ntitle = \"Draft\"\ndraft = true\ndate = \"2024-06-15\"\n+++\n\nDraft\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir, drafts: true)
        exporter.run(options)

        # Draft should not have date prefix
        File.exists?(File.join(output_dir, "_drafts", "draft.md")).should be_true
        File.exists?(File.join(output_dir, "_drafts", "2024-06-15-draft.md")).should be_false
      end
    end

    it "exports posts in subdirectories" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "blog"))

        File.write(File.join(content_dir, "blog", "post.md"), "+++\ntitle = \"Blog Post\"\ndate = \"2024-03-10\"\n+++\n\nContent\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        File.exists?(File.join(output_dir, "_posts", "blog", "2024-03-10-post.md")).should be_true
      end
    end

    it "rewrites @/ internal links" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\n+++\n\n[About](@/about/_index.md)\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        files = Dir.glob(File.join(output_dir, "_posts", "*.md"))
        content = File.read(files.first)
        content.should_not contain("@/")
      end
    end

    it "includes categories in YAML frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "---\ntitle: Post\ndate: \"2024-01-01\"\ncategories:\n  - tech\n  - blog\n---\n\nContent\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        files = Dir.glob(File.join(output_dir, "_posts", "*.md"))
        content = File.read(files.first)
        content.should contain("categories:")
        content.should contain("- tech")
      end
    end
  end
end
