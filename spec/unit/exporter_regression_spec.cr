require "../spec_helper"

# Exposes the bundle-asset copy failure path deterministically: a bundle
# directory that becomes unlistable mid-run (permissions, NFS hiccup) makes
# `Dir.children` raise inside `copy_bundle_assets` after the post itself was
# already written.
private class BundleListFailHugoExporter < Hwaro::Services::Exporters::HugoExporter
  protected def copy_bundle_assets(source_dir : String, dest_dir : String, output_dir : String, verbose : Bool = false) : Int32
    raise File::Error.new("Permission denied", file: source_dir)
  end
end

# Regression specs for defects found by dogfooding `hwaro tool export`.
# Numbering matches the audit report.
describe "exporter regressions" do
  # (1) A UTF-8 BOM defeated the frontmatter anchors, producing an empty
  # frontmatter block with the whole document — raw fences and all — dumped
  # into the body. Having lost `date`, the post was also misfiled as a page
  # instead of landing in `_posts/`.
  describe "UTF-8 BOM handling" do
    it "exports a BOM-prefixed post to _posts with its frontmatter intact" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "content", "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "bom.md"),
          "﻿+++\ntitle = \"Site BOM\"\ndate = \"2024-01-01\"\ntags = [\"x\"]\n+++\n\nSite body.\n"
        )

        output_dir = File.join(dir, "export")
        Hwaro::Services::Exporters::JekyllExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "jekyll",
            content_dir: File.join(dir, "content"),
            output_dir: output_dir,
          ))

        out_file = File.join(output_dir, "_posts", "2024-01-01-bom.md")
        File.exists?(out_file).should be_true
        content = File.read(out_file)
        content.should contain("title: Site BOM")
        content.should contain("Site body.")
        content.should_not contain("+++")
      end
    end
  end

  # (4) The Hugo exporter preserved the bundle layout but never wrote the
  # bundle's resources, so every image in an exported post pointed at a file
  # that did not exist.
  describe "page bundle assets" do
    it "copies a leaf bundle's co-located assets into the export" do
      Dir.mktmpdir do |dir|
        bundle_dir = File.join(dir, "content", "posts", "bundle")
        FileUtils.mkdir_p(bundle_dir)
        File.write(File.join(bundle_dir, "index.md"), "+++\ntitle = \"Bundle\"\n+++\n\n![cover](cover.png)\n")
        File.write(File.join(bundle_dir, "cover.png"), "notapng")

        output_dir = File.join(dir, "export")
        Hwaro::Services::Exporters::HugoExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "hugo",
            content_dir: File.join(dir, "content"),
            output_dir: output_dir,
          ))

        File.exists?(File.join(output_dir, "content", "posts", "bundle", "index.md")).should be_true
        File.exists?(File.join(output_dir, "content", "posts", "bundle", "cover.png")).should be_true
      end
    end

    # Review finding 7: `within_output_dir?` is lexical, so a symlinked
    # destination directory pointed the copy straight out of the tree.
    it "refuses to copy through a symlinked destination directory" do
      Dir.mktmpdir do |dir|
        bundle_dir = File.join(dir, "content", "posts", "bundle")
        FileUtils.mkdir_p(bundle_dir)
        File.write(File.join(bundle_dir, "index.md"), "+++\ntitle = \"Bundle\"\n+++\n\n![cover](cover.png)\n")
        File.write(File.join(bundle_dir, "cover.png"), "notapng")

        outside = File.join(dir, "outside")
        FileUtils.mkdir_p(outside)
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(output_dir, "content", "posts"))
        File.symlink(outside, File.join(output_dir, "content", "posts", "bundle"))

        Hwaro::Services::Exporters::HugoExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "hugo",
            content_dir: File.join(dir, "content"),
            output_dir: output_dir,
          ))

        Dir.glob(File.join(outside, "*.png")).should be_empty
      end
    end

    # Review finding 5: the exporter must agree with the importer twin —
    # names from `Dir.each_child` are single components, so no sanitising.
    it "preserves a backslash in a legitimate asset filename" do
      Dir.mktmpdir do |dir|
        bundle_dir = File.join(dir, "content", "posts", "bundle")
        FileUtils.mkdir_p(bundle_dir)
        File.write(File.join(bundle_dir, "index.md"), "+++\ntitle = \"Bundle\"\n+++\n\n![c](C:\\\\photo.png)\n")
        File.write(File.join(bundle_dir, "C:\\photo.png"), "notapng")

        output_dir = File.join(dir, "export")
        Hwaro::Services::Exporters::HugoExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "hugo",
            content_dir: File.join(dir, "content"),
            output_dir: output_dir,
          ))

        File.exists?(File.join(output_dir, "content", "posts", "bundle", "C:\\photo.png")).should be_true
      end
    end
  end

  # (9) Hwaro's `template` is Jekyll's `layout` — the exact inverse of the
  # Jekyll importer's mapping. Passing the key through verbatim meant Jekyll
  # ignored it and a re-import dropped it entirely.
  describe "template to layout mapping" do
    it "emits layout: and round-trips back through the Jekyll importer" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "content", "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "t.md"),
          "+++\ntitle = \"T\"\ndate = \"2024-01-01\"\ntemplate = \"post.html\"\n+++\nBody.\n"
        )

        export_dir = File.join(dir, "export")
        Hwaro::Services::Exporters::JekyllExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "jekyll",
            content_dir: File.join(dir, "content"),
            output_dir: export_dir,
          ))

        exported = File.read(File.join(export_dir, "_posts", "2024-01-01-t.md"))
        exported.should contain("layout: post.html")
        exported.should_not contain("template:")

        back_dir = File.join(dir, "back")
        Hwaro::Services::Importers::JekyllImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "jekyll", path: export_dir, output_dir: back_dir,
          ))

        File.read(File.join(back_dir, "posts", "t.md")).should contain(%(template = "post.html"))
      end
    end
  end

  # (10) Crystal's `String#inspect` escapes a non-printable ASTRAL codepoint
  # as `\u{E0001}`; YAML only accepts fixed-width `\uXXXX` / `\UXXXXXXXX`, so
  # the exported post failed to load in Jekyll.
  describe "YAML scalar escaping" do
    it "emits a fixed-width escape for a non-printable astral codepoint" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(
          File.join(content_dir, "hi.md"),
          "+++\ntitle = \"T\u{E0001}X\"\ndate = \"2024-01-01\"\n+++\n\nBody.\n"
        )

        output_dir = File.join(dir, "export")
        Hwaro::Services::Exporters::JekyllExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "jekyll",
            content_dir: content_dir,
            output_dir: output_dir,
          ))

        content = File.read(File.join(output_dir, "hi.md"))
        content.should contain(%(title: "T\\U000E0001X"))
        content.should_not contain("\\u{")
      end
    end

    it "leaves a literal backslash-u sequence in the source text intact" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(
          File.join(content_dir, "lit.md"),
          "+++\ntitle = \"Literal \\\\u{41} backslash\"\ndate = \"2024-01-02\"\n+++\n\nBody.\n"
        )

        output_dir = File.join(dir, "export")
        Hwaro::Services::Exporters::JekyllExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "jekyll",
            content_dir: content_dir,
            output_dir: output_dir,
          ))

        # The escaped backslash must survive: rewriting it to `\U00000041`
        # would silently turn the author's literal text into an "A".
        File.read(File.join(output_dir, "lit.md"))
          .should contain(%(title: "Literal \\\\u{41} backslash"))
      end
    end
  end

  # Stability audit 2026-08-23. Non-string values of the explicitly handled
  # Jekyll keys were silently dropped: `as_s?` returned nil so nothing was
  # emitted, and the passthrough skipped every handled key by name.
  describe "non-string handled keys (Jekyll)" do
    it "stringifies scalar non-string values and passes a hash-valued tags through" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "content", "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "nn.md"),
          "+++\ntitle = 123\ndescription = 4.5\nimage = true\ndate = \"2024-01-01\"\n\n[tags]\nname = \"x\"\n+++\n\nBody.\n"
        )

        output_dir = File.join(dir, "export")
        Hwaro::Services::Exporters::JekyllExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "jekyll",
            content_dir: File.join(dir, "content"),
            output_dir: output_dir,
          ))

        content = File.read(File.join(output_dir, "_posts", "2024-01-01-nn.md"))
        content.should contain(%(title: "123"))
        content.should contain(%(description: "4.5"))
        content.should contain(%(image: "true"))
        # A hash cannot be a tag list; it must survive via the passthrough
        # instead of being swallowed.
        content.should contain("tags:")
        content.should contain("name: x")
      end
    end

    it "passes a non-bool draft value through instead of swallowing it" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "content", "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "d.md"),
          "+++\ntitle = \"D\"\ndate = \"2024-01-01\"\ndraft = \"yes\"\n+++\n\nBody.\n"
        )

        output_dir = File.join(dir, "export")
        Hwaro::Services::Exporters::JekyllExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "jekyll",
            content_dir: File.join(dir, "content"),
            output_dir: output_dir,
          ))

        # A string draft is not translatable to `published: false` (only
        # `draft = true` is a Jekyll draft) — but it must not vanish either.
        content = File.read(File.join(output_dir, "_posts", "2024-01-01-d.md"))
        content.should match(/draft: "?yes"?/)
        content.should_not contain("published: false")
      end
    end

    # Review follow-up: the template→layout and draft→published translations
    # never claimed their TARGET keys, so an authored `published`/`layout`
    # re-emerged from the passthrough as a duplicate YAML key — and under
    # Jekyll's last-wins loader an authored `published: true` republished
    # the draft.
    it "does not emit duplicate keys for authored published/layout" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "content", "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "dup.md"),
          "+++\ntitle = \"Dup\"\ndate = \"2024-01-01\"\ndraft = true\npublished = true\ntemplate = \"post\"\nlayout = \"custom\"\n+++\n\nBody.\n"
        )

        output_dir = File.join(dir, "export")
        Hwaro::Services::Exporters::JekyllExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "jekyll",
            content_dir: File.join(dir, "content"),
            output_dir: output_dir,
            drafts: true,
          ))

        content = File.read(File.join(output_dir, "_drafts", "dup.md"))
        # The draft flag is hwaro's source of truth: exactly one published
        # line, and it says false.
        content.scan(/^published:/m).size.should eq(1)
        content.should contain("published: false")
        # Authored layout wins; the unrenamed template passes through, so
        # nothing is lost and no key is doubled.
        content.scan(/^layout:/m).size.should eq(1)
        content.should contain("layout: custom")
        content.should contain(%(template: post))
      end
    end
  end

  # Stability audit 2026-08-23. `date` was interpolated raw into the YAML,
  # so a date string containing a newline injected frontmatter keys.
  describe "date YAML injection (Jekyll)" do
    it "does not let a newline in date inject frontmatter keys" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "content", "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "evil.md"),
          "+++\ntitle = \"E\"\ndate = \"2024-01-01\\nmalicious: true\"\n+++\n\nBody.\n"
        )

        output_dir = File.join(dir, "export")
        Hwaro::Services::Exporters::JekyllExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "jekyll",
            content_dir: File.join(dir, "content"),
            output_dir: output_dir,
          ))

        content = File.read(File.join(output_dir, "_posts", "2024-01-01-evil.md"))
        content.lines.none?(&.starts_with?("malicious:")).should be_true
        content.should contain(%(date: "2024-01-01\\nmalicious: true"))
      end
    end

    it "keeps emitting a well-formed date raw" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "content", "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "ok.md"),
          "+++\ntitle = \"OK\"\ndate = \"2024-01-01\"\n+++\n\nBody.\n"
        )

        output_dir = File.join(dir, "export")
        Hwaro::Services::Exporters::JekyllExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "jekyll",
            content_dir: File.join(dir, "content"),
            output_dir: output_dir,
          ))

        File.read(File.join(output_dir, "_posts", "2024-01-01-ok.md"))
          .should contain("date: 2024-01-01\n")
      end
    end
  end

  # Stability audit 2026-08-23. The Hugo key renames (`updated`→`lastmod`,
  # `image`→`images`) clobbered a coexisting authored target key depending on
  # source order. The authored target must win, like `flatten_taxonomies` —
  # and (review follow-up) the blocked source key passes through under its
  # own name instead of being dropped: Hugo accepts arbitrary page params.
  describe "Hugo rename vs authored target key" do
    it "keeps an authored lastmod over a renamed updated" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(
          File.join(content_dir, "p.md"),
          "+++\ntitle = \"P\"\nlastmod = \"2024-07-01\"\nupdated = \"2024-06-01\"\n+++\n\nBody.\n"
        )

        output_dir = File.join(dir, "export")
        Hwaro::Services::Exporters::HugoExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "hugo",
            content_dir: content_dir,
            output_dir: output_dir,
          ))

        content = File.read(File.join(output_dir, "content", "p.md"))
        content.should contain(%(lastmod = "2024-07-01"))
        content.should contain(%(updated = "2024-06-01"))
      end
    end

    it "keeps an authored images over a renamed image" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(
          File.join(content_dir, "q.md"),
          "+++\ntitle = \"Q\"\nimages = [\"a.jpg\", \"b.jpg\"]\nimage = \"c.jpg\"\n+++\n\nBody.\n"
        )

        output_dir = File.join(dir, "export")
        Hwaro::Services::Exporters::HugoExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "hugo",
            content_dir: content_dir,
            output_dir: output_dir,
          ))

        content = File.read(File.join(output_dir, "content", "q.md"))
        content.should contain(%(images = ["a.jpg", "b.jpg"]))
        content.should contain(%(image = "c.jpg"))
      end
    end
  end

  # Stability audit 2026-08-23. A run with per-file errors still reported
  # success (and exited 0) as long as one file exported.
  describe "partial-failure result" do
    it "reports failure when any file errors even if others exported (Hugo)" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "good.md"), "+++\ntitle = \"G\"\n+++\n\nBody.\n")
        File.write(File.join(content_dir, "bad.md"), "+++\ntitle = = broken\n+++\n\nBody.\n")

        result = Hwaro::Services::Exporters::HugoExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "hugo",
            content_dir: content_dir,
            output_dir: File.join(dir, "export"),
          ))

        result.exported_count.should eq(1)
        result.error_count.should eq(1)
        result.success.should be_false
      end
    end

    it "reports failure when any file errors even if others exported (Jekyll)" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "good.md"), "+++\ntitle = \"G\"\n+++\n\nBody.\n")
        File.write(File.join(content_dir, "bad.md"), "+++\ntitle = = broken\n+++\n\nBody.\n")

        result = Hwaro::Services::Exporters::JekyllExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "jekyll",
            content_dir: content_dir,
            output_dir: File.join(dir, "export"),
          ))

        result.exported_count.should eq(1)
        result.error_count.should eq(1)
        result.success.should be_false
      end
    end
  end

  # Stability audit 2026-08-23. `write_file` checked containment only
  # lexically, so a pre-existing symlinked directory inside the destination
  # routed the post write outside the output directory.
  describe "write_file symlinked destination directory" do
    it "refuses to write a post through a symlinked directory inside the destination" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "content", "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "p.md"),
          "+++\ntitle = \"P\"\ndate = \"2024-01-01\"\n+++\n\nBody.\n"
        )

        outside = File.join(dir, "outside")
        FileUtils.mkdir_p(outside)
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(output_dir)
        File.symlink(outside, File.join(output_dir, "_posts"))

        result = Hwaro::Services::Exporters::JekyllExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "jekyll",
            content_dir: File.join(dir, "content"),
            output_dir: output_dir,
          ))

        Dir.glob(File.join(outside, "*.md")).should be_empty
        result.exported_count.should eq(0)
      end
    end

    # Review follow-up: copy_bundle_assets resolve-checked the destination
    # DIRECTORY but not the destination FILE, so a pre-existing symlink leaf
    # inside the tree let File.copy write through it to an outside path.
    it "refuses to copy a bundle asset over a symlink leaf pointing outside" do
      Dir.mktmpdir do |dir|
        bundle_dir = File.join(dir, "content", "posts", "bundle")
        FileUtils.mkdir_p(bundle_dir)
        File.write(File.join(bundle_dir, "index.md"), "+++\ntitle = \"B\"\ndate = \"2024-01-01\"\n+++\n\nBody.\n")
        File.write(File.join(bundle_dir, "cover.png"), "png-bytes")

        outside_target = File.join(dir, "victim.txt")
        File.write(outside_target, "original")

        output_dir = File.join(dir, "export")
        # Hugo keeps the bundle layout: content/posts/bundle/cover.png.
        dest_bundle = File.join(output_dir, "content", "posts", "bundle")
        FileUtils.mkdir_p(dest_bundle)
        File.symlink(outside_target, File.join(dest_bundle, "cover.png"))

        Hwaro::Services::Exporters::HugoExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "hugo",
            content_dir: File.join(dir, "content"),
            output_dir: output_dir,
          ))

        File.read(outside_target).should eq("original")
      end
    end
  end

  # Stability audit 2026-08-23. If listing the bundle directory raised after
  # the post was written, the exception escaped `export_file`, so the run's
  # counts and manifest disagreed with what was on disk.
  describe "Hugo bundle-asset copy failure" do
    it "still counts the post as exported when bundle assets cannot be listed" do
      Dir.mktmpdir do |dir|
        bundle_dir = File.join(dir, "content", "posts", "bundle")
        FileUtils.mkdir_p(bundle_dir)
        File.write(File.join(bundle_dir, "index.md"), "+++\ntitle = \"B\"\n+++\n\nBody.\n")

        output_dir = File.join(dir, "export")
        result = BundleListFailHugoExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "hugo",
            content_dir: File.join(dir, "content"),
            output_dir: output_dir,
          ))

        result.exported_count.should eq(1)
        result.error_count.should eq(0)
        result.success.should be_true
        File.exists?(File.join(output_dir, "content", "posts", "bundle", "index.md")).should be_true
      end
    end
  end
end
