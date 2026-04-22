require "../../spec_helper"

# Concrete test implementation of the abstract Base class
class TestImporter < Hwaro::Services::Importers::Base
  def run(options : Hwaro::Config::Options::ImportOptions) : Hwaro::Services::Importers::ImportResult
    Hwaro::Services::Importers::ImportResult.new(success: true, message: "ok")
  end

  # Expose protected methods for testing
  def test_generate_frontmatter(fields)
    generate_frontmatter(fields)
  end

  def test_slugify(title)
    slugify(title)
  end

  def test_parse_date(date_str)
    parse_date(date_str)
  end

  def test_format_date(time)
    format_date(time)
  end

  def test_write_content_file(output_dir, section, slug, frontmatter, body, verbose = false, force = false)
    write_content_file(output_dir, section, slug, frontmatter, body, verbose, force)
  end
end

describe Hwaro::Services::Importers::Base do
  describe "#generate_frontmatter" do
    it "generates TOML frontmatter with string values" do
      importer = TestImporter.new
      result = importer.test_generate_frontmatter({
        "title" => "My Post".as((String | Bool | Array(String))?),
        "date"  => "2024-01-15".as((String | Bool | Array(String))?),
      })
      result.should contain("+++")
      result.should contain(%(title = "My Post"))
      result.should contain(%(date = "2024-01-15"))
    end

    it "generates TOML frontmatter with bool values" do
      importer = TestImporter.new
      result = importer.test_generate_frontmatter({
        "draft" => true.as((String | Bool | Array(String))?),
      })
      result.should contain("draft = true")
    end

    it "generates TOML frontmatter with array values" do
      importer = TestImporter.new
      result = importer.test_generate_frontmatter({
        "tags" => ["crystal", "web"].as((String | Bool | Array(String))?),
      })
      result.should contain(%(tags = ["crystal", "web"]))
    end

    it "skips nil and empty values" do
      importer = TestImporter.new
      result = importer.test_generate_frontmatter({
        "title" => "Valid".as((String | Bool | Array(String))?),
        "desc"  => nil.as((String | Bool | Array(String))?),
        "empty" => "".as((String | Bool | Array(String))?),
      })
      result.should contain("title")
      result.should_not contain("desc")
      result.should_not contain("empty")
    end
  end

  describe "#slugify" do
    it "converts title to slug" do
      importer = TestImporter.new
      importer.test_slugify("Hello World").should eq("hello-world")
    end
  end

  describe "#parse_date" do
    it "parses ISO date" do
      importer = TestImporter.new
      time = importer.test_parse_date("2024-01-15")
      time.should_not be_nil
      time.not_nil!.year.should eq(2024)
      time.not_nil!.month.should eq(1)
      time.not_nil!.day.should eq(15)
    end

    it "parses datetime" do
      importer = TestImporter.new
      time = importer.test_parse_date("2024-01-15 10:30:00")
      time.should_not be_nil
      time.not_nil!.hour.should eq(10)
    end

    it "returns nil for invalid date" do
      importer = TestImporter.new
      importer.test_parse_date("not-a-date").should be_nil
    end
  end

  describe "#write_content_file" do
    it "writes a markdown file" do
      Dir.mktmpdir do |dir|
        importer = TestImporter.new
        result = importer.test_write_content_file(dir, "posts", "hello-world", "+++\ntitle = \"Hello\"\n+++", "Content here")
        result.should be_true

        path = File.join(dir, "posts", "hello-world.md")
        File.exists?(path).should be_true
        content = File.read(path)
        content.should contain("title = \"Hello\"")
        content.should contain("Content here")
      end
    end

    it "skips existing files" do
      Dir.mktmpdir do |dir|
        importer = TestImporter.new
        importer.test_write_content_file(dir, "", "existing", "+++\n+++", "First")
        result = importer.test_write_content_file(dir, "", "existing", "+++\n+++", "Second")
        result.should be_false

        content = File.read(File.join(dir, "existing.md"))
        content.should contain("First")
        content.should_not contain("Second")
      end
    end

    it "overwrites existing files when force is true" do
      Dir.mktmpdir do |dir|
        importer = TestImporter.new
        importer.test_write_content_file(dir, "", "existing", "+++\n+++", "First")
        result = importer.test_write_content_file(dir, "", "existing", "+++\n+++", "Second", false, true)
        result.should be_true

        content = File.read(File.join(dir, "existing.md"))
        content.should contain("Second")
        content.should_not contain("First")
      end
    end
  end

  describe "#format_date" do
    it "formats a Time as 'YYYY-MM-DD HH:MM:SS'" do
      t = Time.utc(2026, 4, 17, 9, 30, 45)
      TestImporter.new.test_format_date(t).should eq("2026-04-17 09:30:45")
    end

    it "round-trips with parse_date for the standard space-separated format" do
      importer = TestImporter.new
      original = "2026-04-17 09:30:45"
      parsed = importer.test_parse_date(original).not_nil!
      importer.test_format_date(parsed).should eq(original)
    end

    it "respects timezone-aware times by formatting in the same instant" do
      # Time#to_s with the standard format renders local components — for a
      # UTC Time the output should match the components as constructed.
      t = Time.utc(2026, 12, 31, 23, 59, 59)
      TestImporter.new.test_format_date(t).should eq("2026-12-31 23:59:59")
    end
  end
end

describe Hwaro::Services::Importers::ImportResult do
  it "defaults all counters to 0 and success to true" do
    r = Hwaro::Services::Importers::ImportResult.new
    r.success.should be_true
    r.message.should eq("")
    r.imported_count.should eq(0)
    r.skipped_count.should eq(0)
    r.error_count.should eq(0)
  end

  it "accepts custom counters and message" do
    r = Hwaro::Services::Importers::ImportResult.new(
      success: false,
      message: "import failed",
      imported_count: 7,
      skipped_count: 2,
      error_count: 1,
    )
    r.success.should be_false
    r.message.should eq("import failed")
    r.imported_count.should eq(7)
    r.skipped_count.should eq(2)
    r.error_count.should eq(1)
  end
end
