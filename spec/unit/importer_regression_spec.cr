require "../spec_helper"

# Regression specs for defects found by dogfooding `hwaro tool import` against
# hand-built fixtures for every supported source platform. One focused example
# per defect; the numbering matches the audit report.
describe "importer regressions" do
  # (1) A UTF-8 BOM defeated the `\A---` / `\A+++` anchors in every importer,
  # so the whole front matter leaked into the page body and every field was
  # lost. `hwaro build` already strips the BOM, so such a file built fine and
  # only broke on import.
  describe "UTF-8 BOM handling" do
    it "reads front matter from a BOM-prefixed Jekyll post" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "2024-09-09-bom.md"),
          "﻿---\ntitle: \"BOM Post\"\ndate: 2024-09-09\ntags: [x]\n---\n\nReal body.\n"
        )

        output_dir = File.join(dir, "out")
        importer = Hwaro::Services::Importers::JekyllImporter.new
        importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll", path: dir, output_dir: output_dir,
        ))

        content = File.read(File.join(output_dir, "posts", "bom.md"))
        content.should contain(%(title = "BOM Post"))
        content.should contain(%(tags = ["x"]))
        content.should contain("Real body.")
        content.should_not contain("---")
      end
    end

    it "reads front matter from a BOM-prefixed Hugo page" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "content", "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "bom.md"),
          "﻿+++\ntitle = \"Hugo BOM\"\ndate = \"2024-01-01\"\n+++\n\nHugo body.\n"
        )

        output_dir = File.join(dir, "out")
        importer = Hwaro::Services::Importers::HugoImporter.new
        importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "hugo", path: dir, output_dir: output_dir,
        ))

        content = File.read(File.join(output_dir, "posts", "bom.md"))
        content.should contain(%(title = "Hugo BOM"))
        content.should contain("Hugo body.")
      end
    end
  end

  # (2) Two source files can normalize to one destination. WordPress, Hugo,
  # Hexo, Obsidian and Astro had no de-dup, so the second was silently dropped
  # — or, under `--force`, silently CLOBBERED while still counting as imported.
  describe "destination collisions" do
    it "disambiguates two Hexo posts whose date prefixes strip to one slug" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "source", "_posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(File.join(posts_dir, "2020-05-05-note.md"), "---\ntitle: Old\n---\nold body\n")
        File.write(File.join(posts_dir, "2022-05-05-note.md"), "---\ntitle: New\n---\nnew body\n")

        output_dir = File.join(dir, "out")
        importer = Hwaro::Services::Importers::HexoImporter.new
        result = importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "hexo", path: dir, output_dir: output_dir,
        ))

        result.imported_count.should eq(2)
        written = Dir.glob(File.join(output_dir, "posts", "*.md")).sort
        # The reported count must match what is actually on disk.
        written.size.should eq(2)
        written.map { |p| File.basename(p) }.should eq(["note-1.md", "note.md"])
      end
    end

    it "does not let --force clobber a file the same run just wrote" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "src", "content", "blog")
        FileUtils.mkdir_p(File.join(blog_dir, "2023"))
        FileUtils.mkdir_p(File.join(blog_dir, "2024"))
        File.write(File.join(blog_dir, "2023", "recap.md"), "---\ntitle: Recap 2023\n---\nBody 2023.\n")
        File.write(File.join(blog_dir, "2024", "recap.md"), "---\ntitle: Recap 2024\n---\nBody 2024.\n")

        output_dir = File.join(dir, "out")
        importer = Hwaro::Services::Importers::AstroImporter.new
        result = importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "astro", path: dir, output_dir: output_dir, force: true,
        ))

        result.imported_count.should eq(2)
        Dir.glob(File.join(output_dir, "blog", "*.md")).size.should eq(2)
      end
    end

    it "stays idempotent when the same source is imported twice" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "source", "_posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(File.join(posts_dir, "2020-05-05-note.md"), "---\ntitle: Old\n---\nold body\n")
        File.write(File.join(posts_dir, "2022-05-05-note.md"), "---\ntitle: New\n---\nnew body\n")

        output_dir = File.join(dir, "out")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "hexo", path: dir, output_dir: output_dir,
        )
        Hwaro::Services::Importers::HexoImporter.new.run(options)
        second = Hwaro::Services::Importers::HexoImporter.new.run(options)

        # Everything already exists, so nothing is re-written and no `-2`
        # copies pile up on a re-import.
        second.imported_count.should eq(0)
        second.skipped_count.should eq(2)
        Dir.glob(File.join(output_dir, "posts", "*.md")).size.should eq(2)
      end
    end

    it "does not double-suffix importers that disambiguate their own slugs" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(File.join(posts_dir, "2023-01-01-recap.md"), "---\ntitle: R1\n---\nb1\n")
        File.write(File.join(posts_dir, "2024-01-01-recap.md"), "---\ntitle: R2\n---\nb2\n")

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::JekyllImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "jekyll", path: dir, output_dir: output_dir,
          ))

        # Jekyll re-attaches the date itself; the shared backstop must not
        # then append a redundant `-1`.
        names = Dir.glob(File.join(output_dir, "posts", "*.md")).map { |p| File.basename(p) }.sort!
        names.should eq(["recap-2024-01-01.md", "recap.md"])
      end
    end
  end

  # (3) A symlink cycle raised ELOOP straight out of the directory walk,
  # before the per-file rescue, aborting the whole import with zero files
  # written and a raw OS error.
  describe "symlinked directories" do
    it "skips a symlink cycle instead of aborting the import" do
      Dir.mktmpdir do |dir|
        notes_dir = File.join(dir, "notes")
        FileUtils.mkdir_p(notes_dir)
        File.write(File.join(notes_dir, "n.md"), "---\ntitle: N\n---\nbody\n")
        File.symlink("..", File.join(notes_dir, "loop"))

        output_dir = File.join(dir, "out")
        importer = Hwaro::Services::Importers::ObsidianImporter.new
        result = importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "obsidian", path: dir, output_dir: output_dir,
        ))

        result.success.should be_true
        result.imported_count.should eq(1)
        File.exists?(File.join(output_dir, "notes", "n.md")).should be_true
      end
    end
  end

  # (4) The Hugo importer preserved the page-bundle directory but wrote only
  # the `.md`, so every `![](cover.png)` in an imported bundle 404'd.
  describe "page bundle assets" do
    it "copies a Hugo leaf bundle's co-located assets" do
      Dir.mktmpdir do |dir|
        bundle_dir = File.join(dir, "content", "posts", "bundle")
        FileUtils.mkdir_p(bundle_dir)
        File.write(File.join(bundle_dir, "index.md"), "+++\ntitle = \"Bundle\"\n+++\n\n![feature](feature.png)\n")
        File.write(File.join(bundle_dir, "feature.png"), "notapng")

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::HugoImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "hugo", path: dir, output_dir: output_dir,
          ))

        File.exists?(File.join(output_dir, "posts", "bundle", "index.md")).should be_true
        File.exists?(File.join(output_dir, "posts", "bundle", "feature.png")).should be_true
      end
    end
  end

  # (5) By the time an outer list was converted the inner one was already
  # Markdown sitting inside the parent `<li>`, and it collapsed onto the
  # parent's line: `- b- b1`, `2. second1. s1`.
  describe "nested HTML lists" do
    it "indents a nested unordered list under its parent item" do
      markdown = Hwaro::Services::Importers::HtmlToMarkdown.convert(
        "<ul><li>a</li><li>b<ul><li>b1</li></ul></li><li>c</li></ul>"
      )
      markdown.should eq("- a\n- b\n  - b1\n- c")
    end

    it "indents a nested ordered list to the parent item's content column" do
      markdown = Hwaro::Services::Importers::HtmlToMarkdown.convert(
        "<ol><li>first</li><li>second<ol><li>s1</li></ol></li></ol>"
      )
      markdown.should eq("1. first\n2. second\n   1. s1")
    end
  end

  # (7) Hugo's `authors` list maps 1:1 onto hwaro's own `authors` front
  # matter, but the field mapper had no branch for it — losing author
  # attribution on every Hugo import.
  describe "Hugo authors" do
    it "carries the authors list across" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "content", "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(File.join(posts_dir, "a.md"), "+++\ntitle = \"A\"\nauthors = [\"Jane Doe\", \"Bob\"]\n+++\nBody.\n")

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::HugoImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "hugo", path: dir, output_dir: output_dir,
          ))

        File.read(File.join(output_dir, "posts", "a.md"))
          .should contain(%(authors = ["Jane Doe", "Bob"]))
      end
    end
  end

  # (8) The "skip a collection index" guard lived inside the title fallback,
  # so it never ran for a titled file: an 11ty homepage (which always has a
  # title) was buried at `content/posts/index.md`, and an untitled one was
  # dropped entirely.
  describe "Eleventy index pages" do
    it "maps the site root index.md to the content root regardless of title" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(File.join(dir, "index.md"), "---\ntitle: \"Home\"\n---\nHome body.\n")
        File.write(File.join(posts_dir, "one.md"), "---\ntitle: \"One\"\ndate: 2024-03-01\n---\nBody.\n")
        # A collection landing page has no hwaro equivalent and is skipped.
        File.write(File.join(posts_dir, "index.md"), "---\ntitle: \"Posts Landing\"\n---\nLanding.\n")

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::EleventyImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "eleventy", path: dir, output_dir: output_dir,
          ))

        File.read(File.join(output_dir, "index.md")).should contain("Home body.")
        File.exists?(File.join(output_dir, "posts", "one.md")).should be_true
        File.exists?(File.join(output_dir, "posts", "index.md")).should be_false
      end
    end

    it "keeps the site root index.md when it has no title" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "index.md"), "---\nlayout: base\n---\nHome body no title.\n")

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::EleventyImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "eleventy", path: dir, output_dir: output_dir,
          ))

        File.read(File.join(output_dir, "index.md")).should contain("Home body no title.")
      end
    end
  end

  # (11) `![[img.png|300]]` — the pipe segment on an IMAGE embed is Obsidian's
  # display size, not an alias, so it must not become the alt text.
  describe "Obsidian sized image embeds" do
    it "keeps the filename as alt text for a sized embed but honors a real alias" do
      Dir.mktmpdir do |dir|
        File.write(
          File.join(dir, "note.md"),
          "---\ntitle: Widths\n---\n![[diagram.png|300]] ![[photo.jpg|400x200]] ![[cover.png|A real caption]]\n"
        )

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::ObsidianImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "obsidian", path: dir, output_dir: output_dir,
          ))

        body = File.read(File.join(output_dir, "posts", "widths.md"))
        body.should contain("![diagram.png](diagram.png)")
        body.should contain("![photo.jpg](photo.jpg)")
        body.should contain("![A real caption](cover.png)")
      end
    end
  end
end
