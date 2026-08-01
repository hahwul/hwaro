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

    # Review finding 2: the rename was announced at claim time, before the
    # existence check, so it asserted a write that never happened when the
    # disambiguated destination also already existed.
    it "does not announce a rename that never happens" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "source", "_posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(File.join(posts_dir, "2020-05-05-note.md"), "---\ntitle: Old\n---\nold\n")
        File.write(File.join(posts_dir, "2022-05-05-note.md"), "---\ntitle: New\n---\nnew\n")

        output_dir = File.join(dir, "out")
        out_posts = File.join(output_dir, "posts")
        FileUtils.mkdir_p(out_posts)
        File.write(File.join(out_posts, "note.md"), "PRE-EXISTING\n")
        File.write(File.join(out_posts, "note-1.md"), "PRE-EXISTING\n")

        log = with_captured_log do
          Hwaro::Services::Importers::HexoImporter.new.run(
            Hwaro::Config::Options::ImportOptions.new(
              source_type: "hexo", path: dir, output_dir: output_dir, verbose: true,
            ))
        end

        # Nothing was written, so no rename may be claimed.
        log.should_not contain("Renamed:")
        log.should_not contain("destination(s) renamed")
        File.read(File.join(out_posts, "note.md")).should contain("PRE-EXISTING")
        File.read(File.join(out_posts, "note-1.md")).should contain("PRE-EXISTING")
      end
    end

    it "reports collisions once, after the write actually lands" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "source", "_posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(File.join(posts_dir, "2020-05-05-note.md"), "---\ntitle: Old\n---\nold\n")
        File.write(File.join(posts_dir, "2022-05-05-note.md"), "---\ntitle: New\n---\nnew\n")

        output_dir = File.join(dir, "out")
        log = with_captured_log do
          Hwaro::Services::Importers::HexoImporter.new.run(
            Hwaro::Config::Options::ImportOptions.new(
              source_type: "hexo", path: dir, output_dir: output_dir,
            ))
        end

        # One summary line, not one warning per colliding file.
        log.scan(/destination\(s\) renamed/).size.should eq(1)
        log.should contain("1 destination(s) renamed")
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

    # Review finding 6a: assets were copied only when the `.md` write
    # succeeded, so a re-import of an existing post could never recover them
    # without `--force` (which also rewrites the author's content).
    it "copies bundle assets even when the markdown is skipped as existing" do
      Dir.mktmpdir do |dir|
        bundle_dir = File.join(dir, "content", "posts", "bundle")
        FileUtils.mkdir_p(bundle_dir)
        File.write(File.join(bundle_dir, "index.md"), "+++\ntitle = \"Bundle\"\n+++\n\n![f](feature.png)\n")
        File.write(File.join(bundle_dir, "feature.png"), "notapng")

        output_dir = File.join(dir, "out")
        out_bundle = File.join(output_dir, "posts", "bundle")
        FileUtils.mkdir_p(out_bundle)
        File.write(File.join(out_bundle, "index.md"), "+++\ntitle = \"Edited by hand\"\n+++\n\nkeep me\n")

        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "hugo", path: dir, output_dir: output_dir,
        )
        Hwaro::Services::Importers::HugoImporter.new.run(options)

        # The hand-edited markdown is untouched...
        File.read(File.join(out_bundle, "index.md")).should contain("keep me")
        # ...but the missing image is recovered without --force.
        File.exists?(File.join(out_bundle, "feature.png")).should be_true
      end
    end

    # Review finding 6b: the asset destination was computed from
    # `output_dir/section`, so a front-matter `slug` moved the `.md` while
    # the images stayed behind.
    it "copies bundle assets next to the markdown when a slug moves it" do
      Dir.mktmpdir do |dir|
        bundle_dir = File.join(dir, "content", "posts", "bundle")
        FileUtils.mkdir_p(bundle_dir)
        File.write(File.join(bundle_dir, "index.md"), "+++\ntitle = \"Bundle\"\nslug = \"renamed\"\n+++\n\n![f](feature.png)\n")
        File.write(File.join(bundle_dir, "feature.png"), "notapng")

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::HugoImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "hugo", path: dir, output_dir: output_dir,
          ))

        md = File.join(output_dir, "posts", "bundle", "renamed.md")
        File.exists?(md).should be_true
        # Asset lands in the directory the markdown was actually written to.
        File.exists?(File.join(File.dirname(md), "feature.png")).should be_true
      end
    end

    # Review finding 5: names from `Dir.each_child` are single components and
    # can never traverse; running them through `safe_filename_component` only
    # split on `\`, renaming a legitimate file and leaving the very reference
    # the copy exists to repair still broken.
    it "preserves a backslash in a legitimate asset filename" do
      Dir.mktmpdir do |dir|
        bundle_dir = File.join(dir, "content", "posts", "bundle")
        FileUtils.mkdir_p(bundle_dir)
        File.write(File.join(bundle_dir, "index.md"), "+++\ntitle = \"B\"\n+++\n\n![f](C:\\\\photo.png)\n")
        File.write(File.join(bundle_dir, "C:\\photo.png"), "notapng")

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::HugoImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "hugo", path: dir, output_dir: output_dir,
          ))

        File.exists?(File.join(output_dir, "posts", "bundle", "C:\\photo.png")).should be_true
        File.exists?(File.join(output_dir, "posts", "bundle", "photo.png")).should be_false
      end
    end

    # Review finding 7: `within_output_dir?` is lexical, so a symlinked
    # destination directory pointed the copy straight out of the tree.
    it "refuses to copy through a symlinked destination directory" do
      Dir.mktmpdir do |dir|
        bundle_dir = File.join(dir, "content", "posts", "bundle")
        FileUtils.mkdir_p(bundle_dir)
        File.write(File.join(bundle_dir, "index.md"), "+++\ntitle = \"B\"\n+++\n\n![f](feature.png)\n")
        File.write(File.join(bundle_dir, "feature.png"), "notapng")

        outside = File.join(dir, "outside")
        FileUtils.mkdir_p(outside)
        output_dir = File.join(dir, "out")
        FileUtils.mkdir_p(File.join(output_dir, "posts"))
        # `out/posts/bundle` is a symlink escaping the output directory.
        File.symlink(outside, File.join(output_dir, "posts", "bundle"))

        Hwaro::Services::Importers::HugoImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "hugo", path: dir, output_dir: output_dir,
          ))

        # Neither the asset nor the markdown may be written through the link.
        Dir.glob(File.join(outside, "*")).should be_empty
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

    # Review finding 1: skipping the collection index traded one bug for
    # author-content loss — a landing page carries real prose and has a real
    # hwaro destination, `content/<section>/_index.md`.
    it "maps a collection landing page to the section _index.md" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "blog")
        FileUtils.mkdir_p(blog_dir)
        File.write(File.join(dir, "index.md"), "---\ntitle: \"Home\"\n---\nHome body.\n")
        File.write(File.join(blog_dir, "index.md"), "---\ntitle: \"Blog Landing\"\n---\nEverything I have written about Crystal.\n")
        File.write(File.join(blog_dir, "one.md"), "---\ntitle: \"One\"\ndate: 2024-03-01\n---\nPost one.\n")

        output_dir = File.join(dir, "out")
        result = Hwaro::Services::Importers::EleventyImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "eleventy", path: dir, output_dir: output_dir,
          ))

        landing = File.join(output_dir, "blog", "_index.md")
        File.exists?(landing).should be_true
        content = File.read(landing)
        content.should contain(%(title = "Blog Landing"))
        content.should contain("Everything I have written about Crystal.")

        File.read(File.join(output_dir, "index.md")).should contain("Home body.")
        File.exists?(File.join(output_dir, "blog", "one.md")).should be_true
        # Nothing dropped, so nothing lands in the "skipped" bucket whose
        # remedies (--force / --drafts) would both have been wrong.
        result.skipped_count.should eq(0)
        result.imported_count.should eq(3)
      end
    end

    it "keeps an untitled collection landing page too" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "blog")
        FileUtils.mkdir_p(blog_dir)
        File.write(File.join(blog_dir, "index.md"), "---\nlayout: base\n---\nUntitled landing copy.\n")

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::EleventyImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "eleventy", path: dir, output_dir: output_dir,
          ))

        content = File.read(File.join(output_dir, "blog", "_index.md"))
        content.should contain("Untitled landing copy.")
        # Title falls back to the collection directory name.
        content.should contain(%(title = "Blog"))
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
