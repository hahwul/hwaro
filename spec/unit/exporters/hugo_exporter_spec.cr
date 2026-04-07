require "../../spec_helper"

describe Hwaro::Services::Exporters::HugoExporter do
  describe "#run" do
    it "returns failure when no content files found" do
      exporter = Hwaro::Services::Exporters::HugoExporter.new
      options = Hwaro::Config::Options::ExportOptions.new(
        target_type: "hugo",
        content_dir: "/nonexistent/content",
        output_dir: "/tmp/export",
      )
      result = exporter.run(options)
      result.success.should be_false
    end

    it "exports TOML frontmatter content" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"My Post\"\ndate = 2024-01-15T10:00:00Z\ndescription = \"A post\"\ntags = [\"crystal\", \"web\"]\n+++\n\nHello world\n")

        exporter = Hwaro::Services::Exporters::HugoExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "hugo",
          content_dir: content_dir,
          output_dir: output_dir,
        )
        result = exporter.run(options)

        result.success.should be_true
        result.exported_count.should eq(1)

        out_file = File.join(output_dir, "content", "post.md")
        File.exists?(out_file).should be_true
        content = File.read(out_file)
        content.should contain("title = \"My Post\"")
        content.should contain("+++")
      end
    end

    it "exports YAML frontmatter content" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "---\ntitle: YAML Post\ndescription: A post\ndate: \"2024-01-15\"\n---\n\nHello world\n")

        exporter = Hwaro::Services::Exporters::HugoExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "hugo",
          content_dir: content_dir,
          output_dir: output_dir,
        )
        result = exporter.run(options)

        result.success.should be_true
        result.exported_count.should eq(1)
      end
    end

    it "skips drafts by default" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "draft.md"), "+++\ntitle = \"Draft\"\ndraft = true\n+++\n\nDraft content\n")

        exporter = Hwaro::Services::Exporters::HugoExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "hugo",
          content_dir: content_dir,
          output_dir: output_dir,
          drafts: false,
        )
        result = exporter.run(options)

        result.skipped_count.should eq(1)
        result.exported_count.should eq(0)
      end
    end

    it "includes drafts when requested" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "draft.md"), "+++\ntitle = \"Draft\"\ndraft = true\n+++\n\nDraft content\n")

        exporter = Hwaro::Services::Exporters::HugoExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "hugo",
          content_dir: content_dir,
          output_dir: output_dir,
          drafts: true,
        )
        result = exporter.run(options)

        result.exported_count.should eq(1)
      end
    end

    it "preserves directory structure" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "blog"))

        File.write(File.join(content_dir, "blog", "post.md"), "+++\ntitle = \"Blog Post\"\ndescription = \"A post\"\n+++\n\nContent\n")

        exporter = Hwaro::Services::Exporters::HugoExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "hugo",
          content_dir: content_dir,
          output_dir: output_dir,
        )
        result = exporter.run(options)

        File.exists?(File.join(output_dir, "content", "blog", "post.md")).should be_true
      end
    end

    it "maps updated to lastmod" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"Post\"\nupdated = \"2024-06-01\"\n+++\n\nContent\n")

        exporter = Hwaro::Services::Exporters::HugoExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "hugo",
          content_dir: content_dir,
          output_dir: output_dir,
        )
        exporter.run(options)

        content = File.read(File.join(output_dir, "content", "post.md"))
        content.should contain("lastmod")
      end
    end

    it "maps image to images array" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"Post\"\nimage = \"cover.jpg\"\n+++\n\nContent\n")

        exporter = Hwaro::Services::Exporters::HugoExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "hugo", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        content = File.read(File.join(output_dir, "content", "post.md"))
        content.should contain("images = [\"cover.jpg\"]")
      end
    end

    it "maps expires to expiryDate" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"Post\"\nexpires = \"2025-12-31\"\n+++\n\nContent\n")

        exporter = Hwaro::Services::Exporters::HugoExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "hugo", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        content = File.read(File.join(output_dir, "content", "post.md"))
        content.should contain("expiryDate")
      end
    end

    it "rewrites @/ internal links" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"Post\"\n+++\n\n[About](@/about/_index.md)\n")

        exporter = Hwaro::Services::Exporters::HugoExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "hugo", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        content = File.read(File.join(output_dir, "content", "post.md"))
        content.should_not contain("@/")
        content.should contain("[About]")
      end
    end

    it "exports files without draft field as published" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "pub.md"), "+++\ntitle = \"Published\"\n+++\n\nContent\n")

        exporter = Hwaro::Services::Exporters::HugoExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "hugo", content_dir: content_dir, output_dir: output_dir, drafts: false)
        result = exporter.run(options)

        result.exported_count.should eq(1)
        result.skipped_count.should eq(0)
      end
    end

    it "exports tags correctly" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"Post\"\ntags = [\"go\", \"web\"]\n+++\n\nContent\n")

        exporter = Hwaro::Services::Exporters::HugoExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "hugo", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        content = File.read(File.join(output_dir, "content", "post.md"))
        content.should contain("tags = [\"go\", \"web\"]")
      end
    end

    it "handles mixed published and draft files" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "pub.md"), "+++\ntitle = \"Pub\"\n+++\n\nA\n")
        File.write(File.join(content_dir, "draft.md"), "+++\ntitle = \"Draft\"\ndraft = true\n+++\n\nB\n")

        exporter = Hwaro::Services::Exporters::HugoExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "hugo", content_dir: content_dir, output_dir: output_dir, drafts: false)
        result = exporter.run(options)

        result.exported_count.should eq(1)
        result.skipped_count.should eq(1)
      end
    end
  end
end
