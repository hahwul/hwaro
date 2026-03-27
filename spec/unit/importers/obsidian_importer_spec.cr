require "../../spec_helper"
require "../../../src/services/importers/obsidian_importer"

describe Hwaro::Services::Importers::ObsidianImporter do
  describe "#run" do
    it "imports a basic Obsidian note with YAML frontmatter" do
      Dir.mktmpdir do |dir|
        post_content = <<-OBSIDIAN
        ---
        title: "My Note"
        date: 2024-06-01
        tags:
          - pkm
          - notes
        ---
        This is my Obsidian note.
        OBSIDIAN

        File.write(File.join(dir, "my-note.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::ObsidianImporter.new
        result = importer.run(options)

        result.success.should be_true
        result.imported_count.should eq(1)

        output_file = File.join(output_dir, "posts", "my-note.md")
        File.exists?(output_file).should be_true

        content = File.read(output_file)
        content.should contain("+++")
        content.should contain("title = \"My Note\"")
        content.should contain("tags = [\"pkm\", \"notes\"]")
      end
    end

    it "converts wiki-links to standard markdown links" do
      Dir.mktmpdir do |dir|
        post_content = <<-OBSIDIAN
        ---
        title: "Wiki Links"
        ---
        See [[Other Page]] for details.
        Also check [[Long Page Name|short name]].
        OBSIDIAN

        File.write(File.join(dir, "wiki-links.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::ObsidianImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "wiki-links.md"))
        content.should contain("[Other Page](other-page)")
        content.should contain("[short name](long-page-name)")
      end
    end

    it "converts image embeds to standard markdown" do
      Dir.mktmpdir do |dir|
        post_content = <<-OBSIDIAN
        ---
        title: "Embeds"
        ---
        Here is an image: ![[photo.png]]
        OBSIDIAN

        File.write(File.join(dir, "embeds.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::ObsidianImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "embeds.md"))
        content.should contain("![photo.png](photo.png)")
      end
    end

    it "skips hidden directories like .obsidian" do
      Dir.mktmpdir do |dir|
        obsidian_dir = File.join(dir, ".obsidian")
        FileUtils.mkdir_p(obsidian_dir)

        File.write(File.join(dir, "real-note.md"), "# Real Note\nContent.")
        File.write(File.join(obsidian_dir, "config.md"), "# Config\nNot a note.")

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::ObsidianImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)
      end
    end

    it "skips drafts when options.drafts is false" do
      Dir.mktmpdir do |dir|
        post_content = <<-OBSIDIAN
        ---
        title: "Draft Note"
        draft: true
        ---
        Draft content.
        OBSIDIAN

        File.write(File.join(dir, "draft-note.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
          drafts: false,
        )

        importer = Hwaro::Services::Importers::ObsidianImporter.new
        result = importer.run(options)

        result.imported_count.should eq(0)
        result.skipped_count.should eq(1)
      end
    end

    it "imports drafts when options.drafts is true" do
      Dir.mktmpdir do |dir|
        post_content = <<-OBSIDIAN
        ---
        title: "Draft Note"
        draft: true
        ---
        Draft content.
        OBSIDIAN

        File.write(File.join(dir, "draft-note.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
          drafts: true,
        )

        importer = Hwaro::Services::Importers::ObsidianImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)

        content = File.read(File.join(output_dir, "posts", "draft-note.md"))
        content.should contain("draft = true")
      end
    end

    it "preserves vault folder structure as sections" do
      Dir.mktmpdir do |dir|
        subdir = File.join(dir, "projects")
        FileUtils.mkdir_p(subdir)

        File.write(File.join(subdir, "my-project.md"), <<-OBSIDIAN
        ---
        title: "My Project"
        ---
        Project notes.
        OBSIDIAN
        )

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::ObsidianImporter.new
        importer.run(options)

        File.exists?(File.join(output_dir, "projects", "my-project.md")).should be_true
      end
    end

    it "returns error result for non-existent directory" do
      options = Hwaro::Config::Options::ImportOptions.new(
        source_type: "obsidian",
        path: "/non/existent/path",
        output_dir: "/tmp/output",
      )

      importer = Hwaro::Services::Importers::ObsidianImporter.new
      result = importer.run(options)

      result.success.should be_false
      result.message.should contain("not found")
    end
  end
end
