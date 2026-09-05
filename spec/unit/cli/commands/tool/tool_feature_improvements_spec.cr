require "../../../../spec_helper"

# Service-level specs for the tool feature-improvement batch:
# import/export dry-run + per-file manifests, convert --dry-run,
# list sorting/limiting. CLI flag wiring is covered by the functional
# suite in spec/functional/cli_tool_subcommands_spec.cr.
describe "tool feature improvements" do
  describe "importer dry run" do
    it "counts and records would-be imports without writing anything" do
      Dir.mktmpdir do |dir|
        posts = File.join(dir, "site", "_posts")
        FileUtils.mkdir_p(posts)
        File.write(File.join(posts, "2024-01-01-hello.md"), "---\ntitle: Hello\n---\n\nBody\n")
        output = File.join(dir, "content")

        importer = Hwaro::Services::Importers::JekyllImporter.new
        importer.dry_run = true
        result = importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll", path: File.join(dir, "site"), output_dir: output, dry_run: true))

        result.success.should be_true
        result.imported_count.should eq(1)
        Dir.exists?(output).should be_false
        importer.file_actions.size.should eq(1)
        importer.file_actions.first.action.should eq("imported")
        importer.file_actions.first.path.should end_with(".md")
      end
    end
  end

  describe "importer manifest" do
    it "records imported on the first run and skipped on an idempotent re-run" do
      Dir.mktmpdir do |dir|
        posts = File.join(dir, "site", "_posts")
        FileUtils.mkdir_p(posts)
        File.write(File.join(posts, "2024-01-01-hello.md"), "---\ntitle: Hello\n---\n\nBody\n")
        output = File.join(dir, "content")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll", path: File.join(dir, "site"), output_dir: output)

        first = Hwaro::Services::Importers::JekyllImporter.new
        first.run(options)
        first.file_actions.map(&.action).should eq(["imported"])

        second = Hwaro::Services::Importers::JekyllImporter.new
        result = second.run(options)
        result.skipped_count.should eq(1)
        second.file_actions.map(&.action).should eq(["skipped"])
      end
    end

    it "lists page-bundle assets in the manifest alongside the document" do
      Dir.mktmpdir do |dir|
        bundle = File.join(dir, "site", "content", "posts", "bundle")
        FileUtils.mkdir_p(bundle)
        File.write(File.join(bundle, "index.md"), "+++\ntitle = \"Bundle\"\n+++\n\n![cover](cover.png)\n")
        File.write(File.join(bundle, "cover.png"), "notapng")
        output = File.join(dir, "content")

        importer = Hwaro::Services::Importers::HugoImporter.new
        importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "hugo", path: File.join(dir, "site"), output_dir: output))

        asset = importer.file_actions.find(&.path.ends_with?("cover.png"))
        asset.should_not be_nil
        asset.not_nil!.action.should eq("imported")
        importer.file_actions.any?(&.path.ends_with?("index.md")).should be_true
      end
    end

    it "refuses a pre-existing symlinked-outside section directory in dry run too" do
      Dir.mktmpdir do |dir|
        posts = File.join(dir, "site", "_posts")
        FileUtils.mkdir_p(posts)
        File.write(File.join(posts, "2024-01-01-hello.md"), "---\ntitle: Hello\n---\n\nBody\n")

        outside = File.join(dir, "outside")
        output = File.join(dir, "content")
        FileUtils.mkdir_p(outside)
        FileUtils.mkdir_p(output)
        # The importer writes into <output>/posts — make that a symlink out
        # of the tree, the exact case the real run refuses.
        File.symlink(outside, File.join(output, "posts"))

        importer = Hwaro::Services::Importers::JekyllImporter.new
        importer.dry_run = true
        result = importer.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll", path: File.join(dir, "site"), output_dir: output, dry_run: true))

        result.imported_count.should eq(0)
        importer.file_actions.should be_empty
        Dir.children(outside).should be_empty
      end
    end

    it "records overwritten when --force replaces an existing file" do
      Dir.mktmpdir do |dir|
        posts = File.join(dir, "site", "_posts")
        FileUtils.mkdir_p(posts)
        File.write(File.join(posts, "2024-01-01-hello.md"), "---\ntitle: Hello\n---\n\nBody\n")
        output = File.join(dir, "content")
        Hwaro::Services::Importers::JekyllImporter.new.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll", path: File.join(dir, "site"), output_dir: output))

        forced = Hwaro::Services::Importers::JekyllImporter.new
        forced.run(Hwaro::Config::Options::ImportOptions.new(
          source_type: "jekyll", path: File.join(dir, "site"), output_dir: output, force: true))
        forced.file_actions.map(&.action).should eq(["overwritten"])
      end
    end
  end

  describe "exporter dry run and manifest" do
    it "counts and records would-be exports without writing anything" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "content", "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(File.join(posts_dir, "a.md"), "+++\ntitle = \"A\"\ndate = \"2024-01-01\"\n+++\n\nBody\n")
        output = File.join(dir, "export")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        exporter.dry_run = true
        result = exporter.run(Hwaro::Config::Options::ExportOptions.new(
          target_type: "jekyll", content_dir: File.join(dir, "content"), output_dir: output, dry_run: true))

        result.success.should be_true
        result.exported_count.should eq(1)
        Dir.exists?(output).should be_false
        exporter.file_actions.map(&.action).should eq(["exported"])
      end
    end

    it "marks destinations that already existed as overwritten" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "content", "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(File.join(posts_dir, "a.md"), "+++\ntitle = \"A\"\ndate = \"2024-01-01\"\n+++\n\nBody\n")
        output = File.join(dir, "export")
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "jekyll", content_dir: File.join(dir, "content"), output_dir: output)

        Hwaro::Services::Exporters::JekyllExporter.new.run(options)

        again = Hwaro::Services::Exporters::JekyllExporter.new
        again.run(options)
        again.file_actions.map(&.action).should eq(["overwritten"])
      end
    end
  end

  describe "convert dry run" do
    it "reports the conversion without touching the file" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        path = File.join(content_dir, "a.md")
        original = "---\ntitle: A\n---\n\nBody\n"
        File.write(path, original)

        converter = Hwaro::Services::FrontmatterConverter.new(content_dir, dry_run: true)
        result = converter.convert_to_toml

        result.success.should be_true
        result.dry_run.should be_true
        result.converted_count.should eq(1)
        File.read(path).should eq(original)
      end
    end
  end

  describe "content lister sorting" do
    it "sorts by title, path, honors reverse and limit" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "b.md"), "+++\ntitle = \"Beta\"\ndate = \"2024-02-01\"\n+++\n\nB\n")
        File.write(File.join(content_dir, "a.md"), "+++\ntitle = \"alpha\"\ndate = \"2024-01-01\"\n+++\n\nA\n")
        File.write(File.join(content_dir, "c.md"), "+++\ntitle = \"Gamma\"\n+++\n\nC\n")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        all = Hwaro::Services::ContentFilter::All

        # Case-sensitive, matching the template engine's `sort_by="title"`
        # ordering (SortUtils.compare_by_title): uppercase sorts before
        # lowercase in ASCII.
        by_title = lister.list_content(all, Hwaro::Services::ContentSort::Title)
        by_title.map(&.title).should eq(["Beta", "Gamma", "alpha"])

        by_path = lister.list_content(all, Hwaro::Services::ContentSort::Path)
        by_path.map(&.path).should eq(by_path.map(&.path).sort!)

        by_date = lister.list_content(all, Hwaro::Services::ContentSort::Date)
        by_date.map(&.title).should eq(["Beta", "alpha", "Gamma"])

        # Expectation changed: undated entries ("Gamma") stay pinned AFTER
        # dated ones even in reverse — undated means "date unknown", not
        # "older than 1970" — so reverse now yields oldest-dated first with
        # undated last instead of undated first.
        reversed = lister.list_content(all, Hwaro::Services::ContentSort::Date, reverse: true)
        reversed.map(&.title).should eq(["alpha", "Beta", "Gamma"])

        limited = lister.list_content(all, Hwaro::Services::ContentSort::Date, limit: 2)
        limited.map(&.title).should eq(["Beta", "alpha"])
      end
    end
  end
end
