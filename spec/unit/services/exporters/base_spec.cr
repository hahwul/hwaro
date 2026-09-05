require "../../../spec_helper"
require "../../../../src/services/exporters/base"

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

  def test_write_file(path : String, content : String, output_dir : String, verbose : Bool = false) : Bool
    write_file(path, content, output_dir, verbose)
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
    it "parses TOML frontmatter into a YAML::Any fields hash preserving types" do
      raw = "+++\ntitle = \"Hello\"\ndraft = false\ntags = [\"a\", \"b\"]\nweight = 5\n+++\n\nbody text"
      fields, body = TestExporter.new.test_parse_content(raw)

      fields["title"].should eq("Hello")
      fields["draft"].should be_false
      fields["tags"].as_a.map(&.as_s).sort!.should eq(["a", "b"])
      fields["weight"].should eq(5)
      body.should eq("body text")
    end

    it "parses YAML frontmatter into a YAML::Any fields hash preserving types" do
      raw = "---\ntitle: Hello\ndraft: true\ntags:\n  - a\n  - b\nweight: 7\n---\n\nbody text"
      fields, body = TestExporter.new.test_parse_content(raw)

      fields["title"].should eq("Hello")
      fields["draft"].should be_true
      fields["tags"].as_a.map(&.as_s).sort!.should eq(["a", "b"])
      fields["weight"].should eq(7)
      body.should eq("body text")
    end

    it "preserves nested tables and non-string arrays" do
      raw = "+++\ntitle = \"X\"\nnumbers = [1, 2, 3]\n[extra]\nsubtitle = \"hi\"\n[taxonomies]\ncategories = [\"tech\"]\n+++\n\nbody"
      fields, _ = TestExporter.new.test_parse_content(raw)

      fields["numbers"].as_a.map(&.as_i64).should eq([1, 2, 3])
      fields["extra"].as_h.size.should eq(1)
      fields["extra"]["subtitle"].should eq("hi")
      fields["taxonomies"]["categories"].as_a.first.should eq("tech")
    end

    it "does not overflow on integers beyond Int32 range" do
      raw = "---\ntitle: X\nid: 99999999999\n---\n\nbody"
      fields, _ = TestExporter.new.test_parse_content(raw)
      fields["id"].should eq(99999999999_i64)
    end

    it "returns the raw content unchanged when there is no frontmatter" do
      raw = "no frontmatter here\njust body"
      fields, body = TestExporter.new.test_parse_content(raw)
      fields.should be_empty
      body.should eq(raw)
    end

    it "raises on malformed TOML frontmatter instead of exporting stripped metadata" do
      raw = "+++\nnot valid toml = =\n+++\n\nbody"
      expect_raises(TOML::ParseException) do
        TestExporter.new.test_parse_content(raw)
      end
    end

    it "treats a leading --- pair around non-mapping text as body, not frontmatter" do
      raw = "---\nIntro paragraph between two rules.\n---\n\nRest of document."
      fields, body = TestExporter.new.test_parse_content(raw)
      fields.should be_empty
      body.should eq(raw)
    end

    it "preserves empty arrays in frontmatter" do
      raw = "+++\ntitle = \"X\"\ntags = []\n+++\n\nbody"
      fields, _ = TestExporter.new.test_parse_content(raw)
      fields["title"].should eq("X")
      fields["tags"].as_a.should be_empty
    end

    it "formats TOML Time values as frontmatter date strings" do
      # toml.cr normalizes offset datetimes to UTC at parse time; the value
      # should be re-emitted as an RFC 3339 string.
      raw = "+++\ntitle = \"X\"\ndate = 2026-04-17T09:30:45+09:00\n+++\n\nbody"
      fields, _ = TestExporter.new.test_parse_content(raw)
      fields["title"].should eq("X")
      fields["date"].as_s.should match(/^2026-04-1[67]T\d{2}:\d{2}:\d{2}(?:Z|[+\-]\d{2}:\d{2})$/)
    end

    it "formats YAML Time values preserving the authored offset" do
      raw = "---\ntitle: X\ndate: 2026-04-17T09:30:45+09:00\n---\n\nbody"
      fields, _ = TestExporter.new.test_parse_content(raw)
      fields["title"].should eq("X")
      fields["date"].as_s.should eq("2026-04-17T09:30:45+09:00")
    end
  end

  describe "#write_file" do
    it "creates parent directories and writes the content" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "deeply", "nested", "out.md")
        TestExporter.new.test_write_file(path, "hello", dir).should be_true
        File.exists?(path).should be_true
        File.read(path).should eq("hello")
      end
    end

    it "overwrites an existing file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.md")
        File.write(path, "old")
        TestExporter.new.test_write_file(path, "new", dir).should be_true
        File.read(path).should eq("new")
      end
    end

    # Second, independent layer under `ExportCommand`'s `--output` check: the
    # command only ever validates the directory the user typed, while the
    # destinations reaching here are that directory string-joined with a
    # content-derived relative path. A `..` surviving in the relative half
    # used to reach `File.write` unchecked, so an exporter could overwrite a
    # file outside its own destination.
    it "refuses a destination that escapes the output directory" do
      Dir.mktmpdir do |dir|
        output_dir = File.join(dir, "export")
        Dir.mkdir(output_dir)
        outside = File.join(dir, "source.md")
        File.write(outside, "original")

        escaping = File.join(output_dir, "..", "source.md")
        TestExporter.new.test_write_file(escaping, "clobbered", output_dir).should be_false
        File.read(outside).should eq("original")
      end
    end

    it "accepts a destination nested inside the output directory" do
      Dir.mktmpdir do |dir|
        output_dir = File.join(dir, "export")
        path = File.join(output_dir, "content", "posts", "a.md")
        TestExporter.new.test_write_file(path, "kept", output_dir).should be_true
        File.read(path).should eq("kept")
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

    it "strips .md before an anchor fragment" do
      out = TestExporter.new.test_rewrite_internal_links(
        "see [x](@/guide/intro.md#setup) here"
      )
      out.should eq("see [x](/guide/intro#setup) here")
    end

    it "strips _index before an anchor fragment" do
      out = TestExporter.new.test_rewrite_internal_links(
        "[s](@/blog/_index.md#latest)"
      )
      out.should eq("[s](/blog/#latest)")
    end

    it "strips .md before a query string" do
      out = TestExporter.new.test_rewrite_internal_links(
        "[x](@/page.md?ref=home)"
      )
      out.should eq("[x](/page?ref=home)")
    end
  end

  # Regression: `tool export` stored `-o` verbatim, so `-o .` / `-o ""` /
  # `-o content` made the destination collapse back onto the source file and
  # the exporter rewrote the project's own content/ in place, exit 0.
  #
  # Characterisation coverage for API this guard introduced: `guard_output_dir!`
  # does not exist before the fix, so these examples cannot be run against the
  # pre-fix tree. The end-to-end pre-fix proof for the same defect lives in
  # spec/unit/export_command_spec.cr ("refuses to export into the project
  # directory" / "refuses to export into the content directory"), which drives
  # the CLI and fails without the guard.
  describe ".guard_output_dir!" do
    it "accepts a dedicated sibling directory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          # An accepting example must assert acceptance, not merely "did not
          # raise" — an empty method body passes that.
          accepted = begin
            Hwaro::Services::Exporters::Base.guard_output_dir!("export", "content")
            true
          rescue Hwaro::HwaroError
            false
          end
          accepted.should be_true
        end
      end
    end

    it "accepts a directory outside the project, including another repo root" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "project", "content"))
        FileUtils.mkdir_p(File.join(dir, "hugo-site", ".git"))
        Dir.cd(File.join(dir, "project")) do
          accepted = begin
            Hwaro::Services::Exporters::Base.guard_output_dir!(File.join(dir, "hugo-site"), "content")
            true
          rescue Hwaro::HwaroError
            false
          end
          accepted.should be_true
        end
      end
    end

    it "rejects the project directory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          ex = expect_raises(Hwaro::HwaroError) do
            Hwaro::Services::Exporters::Base.guard_output_dir!(".", "content")
          end
          ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
          ex.message.to_s.should contain("project directory")
        end
      end
    end

    it "rejects an empty output directory the same way as \".\"" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          ex = expect_raises(Hwaro::HwaroError) do
            Hwaro::Services::Exporters::Base.guard_output_dir!("", "content")
          end
          ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        end
      end
    end

    it "rejects the content directory itself" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          ex = expect_raises(Hwaro::HwaroError) do
            Hwaro::Services::Exporters::Base.guard_output_dir!("content", "content")
          end
          ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        end
      end
    end

    it "rejects other project input directories" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          %w[templates static data i18n themes].each do |input_dir|
            ex = expect_raises(Hwaro::HwaroError) do
              Hwaro::Services::Exporters::Base.guard_output_dir!(input_dir, "content")
            end
            # Per-value assertions: a bare expect_raises passes even when four
            # of the five are refused for the wrong reason.
            ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
            ex.message.to_s.should contain(input_dir.inspect)
          end
        end
      end
    end

    it "rejects an output directory that contains the content directory" do
      # `<output>/content/<rel>` (Hugo) lands back on the sources when the
      # output directory is an ancestor of the content directory.
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "site", "content"))
        Dir.cd(dir) do
          ex = expect_raises(Hwaro::HwaroError) do
            Hwaro::Services::Exporters::Base.guard_output_dir!("site", File.join("site", "content"))
          end
          ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        end
      end
    end

    it "rejects the filesystem root" do
      # Hermetic like its siblings: the second argument is resolved against the
      # process working directory, so without a mktmpdir + cd this example's
      # result depends on wherever the suite happens to be running from.
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          ex = expect_raises(Hwaro::HwaroError) do
            Hwaro::Services::Exporters::Base.guard_output_dir!("/", "content")
          end
          ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
          ex.message.to_s.should contain("filesystem root")
        end
      end
    end

    # The guard compared LEXICAL paths, so a symlink was the way past every
    # rule above: `ln -s . selfdir` + `-o selfdir` read as a dedicated sibling
    # directory while naming the project root, and the exporter rewrote
    # content/ in place (YAML front matter → TOML, comment lines dropped,
    # `@/x.md#i` links rewritten) — irreversible, exit 0. The build guard
    # already resolved symlinks; this one must too.
    it "rejects a symlink pointing at the project directory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          File.symlink(".", "selfdir")
          ex = expect_raises(Hwaro::HwaroError) do
            Hwaro::Services::Exporters::Base.guard_output_dir!("selfdir", "content")
          end
          ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
          ex.message.to_s.should contain("project directory")
        end
      end
    end

    it "rejects a symlink pointing at the content directory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          File.symlink("content", "clink")
          ex = expect_raises(Hwaro::HwaroError) do
            Hwaro::Services::Exporters::Base.guard_output_dir!("clink", "content")
          end
          ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
          ex.message.to_s.should contain("content directory")
        end
      end
    end

    it "rejects a destination inside a symlink pointing at a protected input directory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("templates")
          File.symlink("templates", "tlink")
          ex = expect_raises(Hwaro::HwaroError) do
            Hwaro::Services::Exporters::Base.guard_output_dir!(File.join("tlink", "out"), "content")
          end
          ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
          ex.message.to_s.should contain("templates")
        end
      end
    end
  end
end
