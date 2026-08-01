require "../spec_helper"

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
end
