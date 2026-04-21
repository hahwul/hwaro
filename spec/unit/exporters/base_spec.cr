require "../../spec_helper"
require "../../../src/services/exporters/base"

# A minimal concrete subclass to exercise Base's protected helpers.
private class TestExporter < Hwaro::Services::Exporters::Base
  def run(options : Hwaro::Config::Options::ExportOptions) : Hwaro::Services::Exporters::ExportResult
    Hwaro::Services::Exporters::ExportResult.new
  end

  def test_scan_content_files(content_dir : String) : Array(String)
    scan_content_files(content_dir)
  end

  def test_parse_content(content : String)
    parse_content(content)
  end

  def test_write_file(path : String, content : String, verbose : Bool = false)
    write_file(path, content, verbose)
  end

  def test_rewrite_internal_links(body : String) : String
    rewrite_internal_links(body)
  end
end

describe Hwaro::Services::Exporters::ExportResult do
  it "defaults all counters to 0 and success to true" do
    r = Hwaro::Services::Exporters::ExportResult.new
    r.success.should be_true
    r.message.should eq("")
    r.exported_count.should eq(0)
    r.skipped_count.should eq(0)
    r.error_count.should eq(0)
  end

  it "accepts custom counters and message" do
    r = Hwaro::Services::Exporters::ExportResult.new(
      success: false,
      message: "boom",
      exported_count: 3,
      skipped_count: 1,
      error_count: 2,
    )
    r.success.should be_false
    r.message.should eq("boom")
    r.exported_count.should eq(3)
    r.skipped_count.should eq(1)
    r.error_count.should eq(2)
  end
end

describe Hwaro::Services::Exporters::Base do
  describe "#scan_content_files" do
    it "returns an empty array when the content dir is missing" do
      Dir.mktmpdir do |dir|
        TestExporter.new.test_scan_content_files(File.join(dir, "missing")).should be_empty
      end
    end

    it "returns an empty array when the content dir is empty" do
      Dir.mktmpdir do |dir|
        TestExporter.new.test_scan_content_files(dir).should be_empty
      end
    end

    it "collects .md and .markdown files (sorted) and skips other extensions" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "blog"))
        File.write(File.join(dir, "blog", "post.md"), "x")
        File.write(File.join(dir, "blog", "alpha.markdown"), "x")
        File.write(File.join(dir, "blog", "image.png"), "x")
        File.write(File.join(dir, "about.md"), "x")

        files = TestExporter.new.test_scan_content_files(dir)
        files.size.should eq(3)
        files.should eq(files.sort)
        files.any?(&.ends_with?("post.md")).should be_true
        files.any?(&.ends_with?("alpha.markdown")).should be_true
        files.any?(&.ends_with?("about.md")).should be_true
        files.any?(&.ends_with?(".png")).should be_false
      end
    end
  end

  describe "#parse_content" do
    it "parses TOML frontmatter into a string fields hash" do
      raw = "+++\ntitle = \"Hello\"\ndraft = false\ntags = [\"a\", \"b\"]\nweight = 5\n+++\n\nbody text"
      fields, body = TestExporter.new.test_parse_content(raw)

      fields["title"].should eq("Hello")
      fields["draft"].should be_false
      fields["tags"].as(Array(String)).sort.should eq(["a", "b"])
      fields["weight"].should eq("5")
      body.should eq("body text")
    end

    it "parses YAML frontmatter into a string fields hash" do
      raw = "---\ntitle: Hello\ndraft: true\ntags:\n  - a\n  - b\nweight: 7\n---\n\nbody text"
      fields, body = TestExporter.new.test_parse_content(raw)

      fields["title"].should eq("Hello")
      fields["draft"].should be_true
      fields["tags"].as(Array(String)).sort.should eq(["a", "b"])
      fields["weight"].should eq("7")
      body.should eq("body text")
    end

    it "returns the raw content unchanged when there is no frontmatter" do
      raw = "no frontmatter here\njust body"
      fields, body = TestExporter.new.test_parse_content(raw)
      fields.should be_empty
      body.should eq(raw)
    end

    it "returns empty fields when TOML frontmatter is malformed" do
      raw = "+++\nnot valid toml = =\n+++\n\nbody"
      fields, body = TestExporter.new.test_parse_content(raw)
      fields.should be_empty
      body.should eq("body")
    end

    it "skips empty arrays in frontmatter" do
      raw = "+++\ntitle = \"X\"\ntags = []\n+++\n\nbody"
      fields, _ = TestExporter.new.test_parse_content(raw)
      fields["title"].should eq("X")
      fields.has_key?("tags").should be_false
    end

    it "formats TOML Time values as ISO8601 with offset" do
      # TOML's native datetime values land in the special Time branch in
      # exporters/base.cr — the value should be re-emitted as
      # "%Y-%m-%dT%H:%M:%S%:z".
      raw = "+++\ntitle = \"X\"\ndate = 2026-04-17T09:30:45+09:00\n+++\n\nbody"
      fields, _ = TestExporter.new.test_parse_content(raw)
      fields["title"].should eq("X")
      fields["date"].as(String).should match(/^2026-04-17T\d{2}:\d{2}:\d{2}[+\-]\d{2}:\d{2}$/)
    end

    it "formats YAML Time values as ISO8601 with offset" do
      # YAML's native ISO 8601 datetime triggers value.as_time? in the
      # YAML branch; should also be re-emitted via the same format.
      raw = "---\ntitle: X\ndate: 2026-04-17T09:30:45Z\n---\n\nbody"
      fields, _ = TestExporter.new.test_parse_content(raw)
      fields["title"].should eq("X")
      fields["date"].as(String).should match(/^2026-04-17T\d{2}:\d{2}:\d{2}[+\-]\d{2}:\d{2}$/)
    end
  end

  describe "#write_file" do
    it "creates parent directories and writes the content" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "deeply", "nested", "out.md")
        TestExporter.new.test_write_file(path, "hello")
        File.exists?(path).should be_true
        File.read(path).should eq("hello")
      end
    end

    it "overwrites an existing file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.md")
        File.write(path, "old")
        TestExporter.new.test_write_file(path, "new")
        File.read(path).should eq("new")
      end
    end
  end

  describe "#rewrite_internal_links" do
    it "rewrites @/path/to/page.md to /path/to/page" do
      out = TestExporter.new.test_rewrite_internal_links(
        "see [docs](@/guide/intro.md) for more"
      )
      out.should eq("see [docs](/guide/intro) for more")
    end

    it "strips trailing _index from section index links" do
      out = TestExporter.new.test_rewrite_internal_links(
        "see [section](@/blog/_index.md) for posts"
      )
      out.should eq("see [section](/blog/) for posts")
    end

    it "leaves regular markdown links untouched" do
      input = "see [external](https://example.com) and [relative](./x.md)"
      TestExporter.new.test_rewrite_internal_links(input).should eq(input)
    end

    it "rewrites multiple internal links in one pass" do
      out = TestExporter.new.test_rewrite_internal_links(
        "[a](@/a.md) and [b](@/b.md)"
      )
      out.should eq("[a](/a) and [b](/b)")
    end
  end
end
