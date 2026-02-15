require "../spec_helper"

describe Hwaro::Services::FrontmatterConverter do
  describe "#detect_format" do
    converter = Hwaro::Services::FrontmatterConverter.new

    it "detects TOML frontmatter" do
      content = "+++\ntitle = \"Test\"\n+++\n\n# Content"
      converter.detect_format(content).should eq(Hwaro::Services::FrontmatterFormat::TOML)
    end

    it "detects YAML frontmatter" do
      content = "---\ntitle: Test\n---\n\n# Content"
      converter.detect_format(content).should eq(Hwaro::Services::FrontmatterFormat::YAML)
    end

    it "returns Unknown for content without frontmatter" do
      content = "# Just a heading\n\nSome text."
      converter.detect_format(content).should eq(Hwaro::Services::FrontmatterFormat::Unknown)
    end

    it "returns Unknown for empty content" do
      converter.detect_format("").should eq(Hwaro::Services::FrontmatterFormat::Unknown)
    end

    it "detects TOML with Windows line endings" do
      content = "+++\r\ntitle = \"Test\"\r\n+++\r\n\r\n# Content"
      converter.detect_format(content).should eq(Hwaro::Services::FrontmatterFormat::TOML)
    end

    it "detects YAML with Windows line endings" do
      content = "---\r\ntitle: Test\r\n---\r\n\r\n# Content"
      converter.detect_format(content).should eq(Hwaro::Services::FrontmatterFormat::YAML)
    end

    it "does not detect TOML if +++ is not at start" do
      content = "Some text\n+++\ntitle = \"Test\"\n+++\n"
      converter.detect_format(content).should eq(Hwaro::Services::FrontmatterFormat::Unknown)
    end

    it "does not detect YAML if --- is not at start" do
      content = "Some text\n---\ntitle: Test\n---\n"
      converter.detect_format(content).should eq(Hwaro::Services::FrontmatterFormat::Unknown)
    end
  end

  describe "#convert_file" do
    it "converts YAML file to TOML" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "test.md")
        File.write(file_path, "---\ntitle: Hello World\ndraft: false\n---\n\n# Content")

        result = converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::TOML)
        result.should be_true

        converted = File.read(file_path)
        converted.should start_with("+++\n")
        converted.should contain("title = \"Hello World\"")
        converted.should contain("draft = false")
        converted.should contain("+++\n")
        converted.should contain("# Content")
      end
    end

    it "converts TOML file to YAML" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "test.md")
        File.write(file_path, "+++\ntitle = \"Hello World\"\ndraft = false\n+++\n\n# Content")

        result = converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::YAML)
        result.should be_true

        converted = File.read(file_path)
        converted.should start_with("---\n")
        converted.should contain("title: Hello World")
        converted.should contain("draft: false")
        converted.should contain("---\n")
        converted.should contain("# Content")
      end
    end

    it "skips file already in target format (TOML)" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "test.md")
        original = "+++\ntitle = \"Already TOML\"\n+++\n\n# Content"
        File.write(file_path, original)

        result = converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::TOML)
        result.should be_false

        # File should remain unchanged
        File.read(file_path).should eq(original)
      end
    end

    it "skips file already in target format (YAML)" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "test.md")
        original = "---\ntitle: Already YAML\n---\n\n# Content"
        File.write(file_path, original)

        result = converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::YAML)
        result.should be_false

        File.read(file_path).should eq(original)
      end
    end

    it "skips file with unknown format" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "test.md")
        original = "# No frontmatter here\n\nJust content."
        File.write(file_path, original)

        result = converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::TOML)
        result.should be_false

        File.read(file_path).should eq(original)
      end
    end

    it "preserves body content after YAML to TOML conversion" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "test.md")
        body = "\n# My Post\n\nParagraph 1.\n\n## Section\n\nParagraph 2.\n"
        File.write(file_path, "---\ntitle: Test\n---\n#{body}")

        converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::TOML)

        converted = File.read(file_path)
        converted.should contain(body)
      end
    end

    it "preserves body content after TOML to YAML conversion" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "test.md")
        body = "\n# My Post\n\nParagraph 1.\n\n## Section\n\nParagraph 2.\n"
        File.write(file_path, "+++\ntitle = \"Test\"\n+++\n#{body}")

        converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::YAML)

        converted = File.read(file_path)
        converted.should contain(body)
      end
    end

    it "handles integer values in YAML to TOML conversion" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "test.md")
        File.write(file_path, "---\ntitle: Test\nweight: 10\n---\n\nContent")

        converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::TOML)

        converted = File.read(file_path)
        converted.should contain("weight = 10")
      end
    end

    it "handles boolean values in YAML to TOML conversion" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "test.md")
        File.write(file_path, "---\ntitle: Test\ndraft: true\n---\n\nContent")

        converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::TOML)

        converted = File.read(file_path)
        converted.should contain("draft = true")
      end
    end

    it "handles array values in YAML to TOML conversion" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "test.md")
        File.write(file_path, "---\ntitle: Test\ntags:\n  - crystal\n  - programming\n---\n\nContent")

        converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::TOML)

        converted = File.read(file_path)
        converted.should contain("tags = [\"crystal\", \"programming\"]")
      end
    end

    it "handles array values in TOML to YAML conversion" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "test.md")
        File.write(file_path, "+++\ntitle = \"Test\"\ntags = [\"crystal\", \"programming\"]\n+++\n\nContent")

        converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::YAML)

        converted = File.read(file_path)
        converted.should contain("crystal")
        converted.should contain("programming")
      end
    end

    it "handles string values with special characters in YAML to TOML conversion" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "test.md")
        File.write(file_path, "---\ntitle: 'He said \"hello\"'\n---\n\nContent")

        converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::TOML)

        converted = File.read(file_path)
        converted.should start_with("+++\n")
        converted.should contain("title")
        converted.should contain("+++\n")
      end
    end
  end

  describe "#convert_to_yaml" do
    it "converts TOML files in content directory to YAML" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post1.md"), "+++\ntitle = \"Post 1\"\n+++\n\n# Post 1")
        File.write(File.join(content_dir, "post2.md"), "+++\ntitle = \"Post 2\"\n+++\n\n# Post 2")

        converter = Hwaro::Services::FrontmatterConverter.new(content_dir)
        result = converter.convert_to_yaml

        result.success.should be_true
        result.converted_count.should eq(2)
        result.error_count.should eq(0)

        File.read(File.join(content_dir, "post1.md")).should start_with("---\n")
        File.read(File.join(content_dir, "post2.md")).should start_with("---\n")
      end
    end

    it "skips files already in YAML format" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "yaml_post.md"), "---\ntitle: Already YAML\n---\n\n# Post")
        File.write(File.join(content_dir, "toml_post.md"), "+++\ntitle = \"TOML Post\"\n+++\n\n# Post")

        converter = Hwaro::Services::FrontmatterConverter.new(content_dir)
        result = converter.convert_to_yaml

        result.converted_count.should eq(1)
        result.skipped_count.should eq(1)
      end
    end

    it "returns failure if content directory does not exist" do
      converter = Hwaro::Services::FrontmatterConverter.new("/nonexistent/path")
      result = converter.convert_to_yaml

      result.success.should be_false
      result.message.should contain("not found")
    end
  end

  describe "#convert_to_toml" do
    it "converts YAML files in content directory to TOML" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post1.md"), "---\ntitle: Post 1\n---\n\n# Post 1")
        File.write(File.join(content_dir, "post2.md"), "---\ntitle: Post 2\n---\n\n# Post 2")

        converter = Hwaro::Services::FrontmatterConverter.new(content_dir)
        result = converter.convert_to_toml

        result.success.should be_true
        result.converted_count.should eq(2)
        result.error_count.should eq(0)

        File.read(File.join(content_dir, "post1.md")).should start_with("+++\n")
        File.read(File.join(content_dir, "post2.md")).should start_with("+++\n")
      end
    end

    it "skips files already in TOML format" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "toml_post.md"), "+++\ntitle = \"Already TOML\"\n+++\n\n# Post")
        File.write(File.join(content_dir, "yaml_post.md"), "---\ntitle: YAML Post\n---\n\n# Post")

        converter = Hwaro::Services::FrontmatterConverter.new(content_dir)
        result = converter.convert_to_toml

        result.converted_count.should eq(1)
        result.skipped_count.should eq(1)
      end
    end

    it "returns failure if content directory does not exist" do
      converter = Hwaro::Services::FrontmatterConverter.new("/nonexistent/path")
      result = converter.convert_to_toml

      result.success.should be_false
      result.message.should contain("not found")
    end
  end

  describe "nested content files" do
    it "finds and converts files in subdirectories" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(File.join(content_dir, "blog"))
        FileUtils.mkdir_p(File.join(content_dir, "docs", "guides"))

        File.write(File.join(content_dir, "index.md"), "---\ntitle: Home\n---\n\nHome page")
        File.write(File.join(content_dir, "blog", "post.md"), "---\ntitle: Blog Post\n---\n\nPost content")
        File.write(File.join(content_dir, "docs", "guides", "intro.md"), "---\ntitle: Guide\n---\n\nGuide content")

        converter = Hwaro::Services::FrontmatterConverter.new(content_dir)
        result = converter.convert_to_toml

        result.success.should be_true
        result.converted_count.should eq(3)

        File.read(File.join(content_dir, "index.md")).should start_with("+++\n")
        File.read(File.join(content_dir, "blog", "post.md")).should start_with("+++\n")
        File.read(File.join(content_dir, "docs", "guides", "intro.md")).should start_with("+++\n")
      end
    end

    it "skips files without frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "no_fm.md"), "# Just a heading\n\nNo frontmatter here.")
        File.write(File.join(content_dir, "has_fm.md"), "---\ntitle: Has FM\n---\n\n# Content")

        converter = Hwaro::Services::FrontmatterConverter.new(content_dir)
        result = converter.convert_to_toml

        result.converted_count.should eq(1)
        result.skipped_count.should eq(1)
      end
    end
  end

  describe "round-trip conversion" do
    it "preserves data through YAML -> TOML -> YAML" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "test.md")

        original_body = "\n# Test Post\n\nSome content here.\n"
        File.write(file_path, "---\ntitle: Round Trip\ndraft: true\n---\n#{original_body}")

        # YAML -> TOML
        converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::TOML)
        intermediate = File.read(file_path)
        intermediate.should start_with("+++\n")
        intermediate.should contain("title = \"Round Trip\"")
        intermediate.should contain("draft = true")

        # TOML -> YAML
        converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::YAML)
        final = File.read(file_path)
        final.should start_with("---\n")
        final.should contain("Round Trip")
        final.should contain("draft: true")
        final.should contain(original_body)
      end
    end
  end

  describe "error handling" do
    it "handles file read errors gracefully" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "non_existent.md")

        # Should return false and not raise exception
        result = converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::TOML)
        result.should be_false
      end
    end

    it "handles file write errors gracefully" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "readonly.md")

        # Create a file with YAML frontmatter
        File.write(file_path, "---\ntitle: Test\n---\n\nContent")

        # Make it read-only
        File.chmod(file_path, 0o400)

        begin
          # Attempt to convert to TOML
          result = converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::TOML)
          result.should be_false
        ensure
          # Restore permissions so it can be cleaned up
          File.chmod(file_path, 0o600)
        end
      end
    end

    it "reports errors correctly in batch conversion" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        # Create one good file
        good_file = File.join(content_dir, "good.md")
        File.write(good_file, "---\ntitle: Good\n---\n\nGood content")

        # Create one bad file (read-only)
        bad_file = File.join(content_dir, "bad.md")
        File.write(bad_file, "---\ntitle: Bad\n---\n\nBad content")
        File.chmod(bad_file, 0o400)

        converter = Hwaro::Services::FrontmatterConverter.new(content_dir)

        begin
          result = converter.convert_to_toml

          result.success.should be_false
          result.converted_count.should eq(1) # The good file
          result.error_count.should eq(1)     # The bad file
        ensure
          File.chmod(bad_file, 0o600)
        end
      end
    end
  end
  describe "nested structure support" do
    it "converts nested YAML maps to TOML tables" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "nested.md")

        yaml_content = <<-YAML
title: Nested Test
owner:
  name: John Doe
  details:
    age: 30
    city: New York
YAML
        File.write(file_path, "---\n#{yaml_content}\n---\n\nContent")

        result = converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::TOML)
        result.should be_true

        converted = File.read(file_path)

        # Parse the result to verify validity
        toml_content = converted.match(/\+\+\+\n(.*?)\n\+\+\+/m).try(&.[1])
        toml_content.should_not be_nil

        toml = TOML.parse(toml_content.not_nil!)
        toml["owner"]["name"].as_s.should eq("John Doe")
        toml["owner"]["details"]["age"].as_i.should eq(30)
        toml["owner"]["details"]["city"].as_s.should eq("New York")
      end
    end

    it "converts array of maps to TOML array of tables" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        file_path = File.join(dir, "array_tables.md")

        yaml_content = <<-YAML
title: Array Tables
servers:
  - name: alpha
    ip: 10.0.0.1
  - name: beta
    ip: 10.0.0.2
YAML
        File.write(file_path, "---\n#{yaml_content}\n---\n\nContent")

        result = converter.convert_file(file_path, Hwaro::Services::FrontmatterFormat::TOML)
        result.should be_true

        converted = File.read(file_path)

        toml_content = converted.match(/\+\+\+\n(.*?)\n\+\+\+/m).try(&.[1])
        toml_content.should_not be_nil

        toml = TOML.parse(toml_content.not_nil!)
        servers = toml["servers"].as_a
        servers.size.should eq(2)
        servers[0]["name"].as_s.should eq("alpha")
        servers[0]["ip"].as_s.should eq("10.0.0.1")
        servers[1]["name"].as_s.should eq("beta")
      end
    end
  end
end

describe Hwaro::Services::FrontmatterFormat do
  it "has YAML variant" do
    Hwaro::Services::FrontmatterFormat::YAML.should_not be_nil
  end

  it "has TOML variant" do
    Hwaro::Services::FrontmatterFormat::TOML.should_not be_nil
  end

  it "has Unknown variant" do
    Hwaro::Services::FrontmatterFormat::Unknown.should_not be_nil
  end
end

describe Hwaro::Services::ConversionResult do
  it "has default values" do
    result = Hwaro::Services::ConversionResult.new
    result.success.should be_true
    result.message.should eq("")
    result.converted_count.should eq(0)
    result.skipped_count.should eq(0)
    result.error_count.should eq(0)
  end

  it "accepts custom values" do
    result = Hwaro::Services::ConversionResult.new(
      success: false,
      message: "Something failed",
      converted_count: 5,
      skipped_count: 3,
      error_count: 1
    )
    result.success.should be_false
    result.message.should eq("Something failed")
    result.converted_count.should eq(5)
    result.skipped_count.should eq(3)
    result.error_count.should eq(1)
  end
end
