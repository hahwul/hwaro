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

    it "flattens nested YAML array tags (tags: [[a, b]])" do
      Dir.mktmpdir do |dir|
        # Obsidian users (via plugins or shorthand) can write nested arrays
        # for tags. Previously the inner array was stringified to a JSON
        # literal ('["a", "b"]') and landed as a single bogus tag.
        post_content = <<-OBSIDIAN
          ---
          title: "Nested Tags"
          tags: [[misc, research], [project/alpha]]
          aliases: [[alt-name, other-name]]
          ---
          Body.
          OBSIDIAN

        File.write(File.join(dir, "nested.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::ObsidianImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)

        content = File.read(File.join(output_dir, "posts", "nested-tags.md"))
        content.should contain(%(tags = ["misc", "research", "project/alpha"]))
        content.should contain(%(aliases = ["alt-name", "other-name"]))
        # Guard against the previous bug form: a tag value of `["misc"]`
        # (stringified JSON), which serializes to the escaped quote below.
        content.should_not contain(%q(\"misc))
      end
    end

    it "converts wiki-links to absolute site URLs when the target exists in the vault" do
      # `[[Other Page]]` used to produce `[Other Page](other-page)`, which the
      # browser resolved relative to the *current* page (e.g.
      # `/posts/wiki-links/other-page`) — guaranteed 404 because the actual
      # target lives at `/posts/other-page/`. The importer now pre-scans the
      # whole vault and emits absolute paths instead.
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "wiki-links.md"), <<-OBSIDIAN)
          ---
          title: "Wiki Links"
          ---
          See [[Other Page]] for details.
          Also check [[Long Page Name|short name]].
          Anchor: [[Long Page Name#Subsection]].
          Unknown target: [[Ghost]].
          OBSIDIAN
        File.write(File.join(dir, "other-page.md"), <<-OBSIDIAN)
          ---
          title: "Other Page"
          ---
          Body.
          OBSIDIAN
        File.write(File.join(dir, "long-page-name.md"), <<-OBSIDIAN)
          ---
          title: "Long Page Name"
          ---
          ## Subsection
          Body.
          OBSIDIAN

        output_dir = File.join(dir, "output")
        importer = Hwaro::Services::Importers::ObsidianImporter.new
        importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
        ))

        content = File.read(File.join(output_dir, "posts", "wiki-links.md"))
        content.should contain("[Other Page](/posts/other-page/)")
        content.should contain("[short name](/posts/long-page-name/)")
        # Anchor should survive — the inline-tag stripper previously ate it.
        content.should contain("[Long Page Name#Subsection](/posts/long-page-name/#subsection)")
        # Unknown targets fall back to a slug rather than dropping the link,
        # so the author still has *something* to fix up manually.
        content.should contain("[Ghost](ghost)")
      end
    end

    it "resolves wiki-links via the front-matter `aliases:` list" do
      # Obsidian's killer feature for wiki-links is renaming a note without
      # breaking inbound links — the alias list keeps the old names valid.
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "linker.md"), <<-OBSIDIAN)
          ---
          title: "Linker"
          ---
          Follow [[Old Name]] please.
          OBSIDIAN
        File.write(File.join(dir, "new-page.md"), <<-OBSIDIAN)
          ---
          title: "New Page"
          aliases:
            - Old Name
          ---
          Body.
          OBSIDIAN

        output_dir = File.join(dir, "output")
        importer = Hwaro::Services::Importers::ObsidianImporter.new
        importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
        ))

        content = File.read(File.join(output_dir, "posts", "linker.md"))
        content.should contain("[Old Name](/posts/new-page/)")
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

    it "extracts inline tags from body into frontmatter" do
      Dir.mktmpdir do |dir|
        post_content = <<-OBSIDIAN
          ---
          title: "Tagged Note"
          ---
          Some content with #crystal and #programming tags.
          OBSIDIAN

        File.write(File.join(dir, "tagged-note.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::ObsidianImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "tagged-note.md"))
        content.should contain("tags = [\"crystal\", \"programming\"]")
      end
    end

    it "preserves markdown headings when removing inline tags" do
      Dir.mktmpdir do |dir|
        post_content = <<-OBSIDIAN
          ---
          title: "Headings"
          ---
          ## Section One

          Content with #tag here.

          ### Sub Section

          More content.
          OBSIDIAN

        File.write(File.join(dir, "headings.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::ObsidianImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "headings.md"))
        content.should contain("## Section One")
        content.should contain("### Sub Section")
      end
    end

    it "handles non-image embeds and target note with alt/width option" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "embed-test.md"), <<-OBSIDIAN)
          ---
          title: "Embed Test"
          ---
          Image embed with width: ![[photo.png|400]]
          Note embed: ![[other-page]]
          Note embed with section: ![[other-page#Section]]
          Note embed with alias: ![[other-page|Some Display]]
          OBSIDIAN
        File.write(File.join(dir, "other-page.md"), <<-OBSIDIAN)
          ---
          title: "Other Page"
          ---
          Body.
          OBSIDIAN

        output_dir = File.join(dir, "output")
        importer = Hwaro::Services::Importers::ObsidianImporter.new
        importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
        ))

        content = File.read(File.join(output_dir, "posts", "embed-test.md"))
        content.should contain("Image embed with width: ![400](photo.png)")
        content.should contain("Note embed: [other-page](/posts/other-page/)")
        content.should contain("Note embed with section: [other-page#Section](/posts/other-page/#section)")
        content.should contain("Note embed with alias: [Some Display](/posts/other-page/)")
      end
    end

    it "slugifies section path segments for folders with spaces" do
      Dir.mktmpdir do |dir|
        subdir = File.join(dir, "Daily Notes")
        FileUtils.mkdir_p(subdir)
        File.write(File.join(subdir, "my-note.md"), <<-OBSIDIAN)
          ---
          title: "My Note"
          ---
          See [[Daily Notes/my-note]].
          OBSIDIAN

        output_dir = File.join(dir, "output")
        importer = Hwaro::Services::Importers::ObsidianImporter.new
        importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
        ))

        # Check file was written under slugified section
        output_file = File.join(output_dir, "daily-notes", "my-note.md")
        File.exists?(output_file).should be_true

        # Check URL was resolved correctly via slugified section
        content = File.read(output_file)
        content.should contain("[Daily Notes/my-note](/daily-notes/my-note/)")
      end
    end

    it "ignores embeds, wiki-links, and tags inside fenced code blocks and inline code" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "code-blocks.md"), <<-OBSIDIAN)
          ---
          title: "Code Blocks"
          ---
          ```
          Keep ![[photo.png]] as is.
          Keep [[other-page]] as is.
          Keep #tag as is.
          ```
          Inline `[[other-page]]` and `![[photo.png]]` and `#tag`.
          4-space indented code:
              #tag
              [[other-page]]
          OBSIDIAN

        output_dir = File.join(dir, "output")
        importer = Hwaro::Services::Importers::ObsidianImporter.new
        importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
        ))

        content = File.read(File.join(output_dir, "posts", "code-blocks.md"))
        content.should contain("Keep ![[photo.png]] as is.")
        content.should contain("Keep [[other-page]] as is.")
        content.should contain("Keep #tag as is.")
        content.should contain("Inline `[[other-page]]` and `![[photo.png]]` and `#tag`.")
        content.should contain("    #tag")
        content.should contain("    [[other-page]]")
      end
    end

    it "excludes drafts from the link map when drafts: false" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "linker.md"), <<-OBSIDIAN)
          ---
          title: "Linker"
          ---
          See [[draft-note]].
          OBSIDIAN
        File.write(File.join(dir, "draft-note.md"), <<-OBSIDIAN)
          ---
          title: "Draft Note"
          draft: true
          ---
          Draft.
          OBSIDIAN

        output_dir = File.join(dir, "output")
        importer = Hwaro::Services::Importers::ObsidianImporter.new
        importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian",
          path: dir,
          output_dir: output_dir,
          drafts: false,
        ))

        content = File.read(File.join(output_dir, "posts", "linker.md"))
        # Since draft-note was skipped, resolving [[draft-note]] should fall back to relative slug, not '/posts/draft-note/'
        content.should contain("[draft-note](draft-note)")
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
