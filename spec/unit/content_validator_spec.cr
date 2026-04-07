require "../spec_helper"

describe Hwaro::Services::ContentValidator do
  describe "#run" do
    it "returns empty array when content directory does not exist" do
      validator = Hwaro::Services::ContentValidator.new("/nonexistent/path/content")
      result = validator.run
      result.should eq([] of Hwaro::Services::Issue)
    end

    it "returns no issues for well-formed content" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "good.md"), <<-MD
        ---
        title: Good Post
        description: A well-formed post
        date: 2024-01-15
        tags:
          - crystal
          - testing
        ---

        # Good Post

        This is a good post with ![alt text](image.png).
        MD
        )

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        # Should only have info-level issues at most (no errors or warnings)
        errors_and_warnings = issues.select { |i| i.level == :error || i.level == :warning }
        errors_and_warnings.should be_empty
      end
    end

    it "detects missing title" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "no-title.md"), "---\ndescription: Has desc\n---\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-title-missing" }.should be_true
      end
    end

    it "detects Untitled title" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "untitled.md"), "---\ntitle: Untitled\ndescription: Has desc\n---\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-title-missing" && i.message.includes?("Untitled") }.should be_true
      end
    end

    it "detects missing description" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "no-desc.md"), "---\ntitle: My Post\n---\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-description-missing" }.should be_true
      end
    end

    it "reports draft status as info" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "draft.md"), "---\ntitle: Draft\ndescription: A draft\ndraft: true\n---\n\n# Draft\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        draft_issue = issues.find { |i| i.id == "content-draft" }
        draft_issue.should_not be_nil
        draft_issue.not_nil!.level.should eq(:info)
      end
    end

    it "detects missing image alt text" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "no-alt.md"), "---\ntitle: Post\ndescription: Desc\n---\n\n![](image.png)\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-alt-text-missing" }.should be_true
      end
    end

    it "ignores images with alt text in code blocks" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "code.md"), <<-MD
        ---
        title: Post
        description: Desc
        ---

        ```markdown
        ![](example.png)
        ```
        MD
        )

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-alt-text-missing" }.should be_false
      end
    end

    it "detects broken internal links" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "broken-link.md"), "---\ntitle: Post\ndescription: Desc\n---\n\n[Link](@/nonexistent.md)\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-internal-link-broken" }.should be_true
      end
    end

    it "accepts valid internal links" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "target.md"), "---\ntitle: Target\ndescription: Target\n---\n\nTarget content\n")
        File.write(File.join(content_dir, "source.md"), "---\ntitle: Source\ndescription: Source\n---\n\n[Link](@/target.md)\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-internal-link-broken" }.should be_false
      end
    end

    it "detects TOML frontmatter parse errors" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "bad-toml.md"), "+++\ntitle = [invalid\n+++\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-frontmatter-toml-error" }.should be_true
      end
    end

    it "detects mixed-case tags" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "mixed-tags.md"), "---\ntitle: Post\ndescription: Desc\ntags:\n  - Crystal\n  - web-dev\n---\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-tag-mixed-case" && i.message.includes?("Crystal") }.should be_true
      end
    end

    it "works with TOML frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "toml.md"), "+++\ntitle = \"TOML Post\"\ndescription = \"A TOML post\"\ndate = 2024-01-15T10:00:00Z\n+++\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        errors_and_warnings = issues.select { |i| i.level == :error || i.level == :warning }
        errors_and_warnings.should be_empty
      end
    end
  end
end
