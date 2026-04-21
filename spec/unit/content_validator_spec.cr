require "../spec_helper"

describe Hwaro::Services::ContentValidator do
  describe "#run" do
    it "raises HwaroError(HWARO_E_CONTENT) when content directory does not exist" do
      validator = Hwaro::Services::ContentValidator.new("/nonexistent/path/content")
      err = expect_raises(Hwaro::HwaroError) { validator.run }
      err.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
      err.exit_code.should eq(5)
      (err.message || "").should contain("/nonexistent/path/content")
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

    it "detects invalid date format" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "bad-date.md"), "---\ntitle: Post\ndescription: Desc\ndate: not-a-date\n---\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-date-invalid" }.should be_true
      end
    end

    it "accepts various valid date formats" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "d1.md"), "---\ntitle: P1\ndescription: D\ndate: \"2024-01-15\"\n---\n\nA\n")
        File.write(File.join(content_dir, "d2.md"), "---\ntitle: P2\ndescription: D\ndate: \"2024-01-15 10:30:00\"\n---\n\nA\n")
        File.write(File.join(content_dir, "d3.md"), "---\ntitle: P3\ndescription: D\ndate: \"2024-01-15T10:30:00\"\n---\n\nA\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-date-invalid" }.should be_false
      end
    end

    it "detects YAML frontmatter parse errors" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "bad-yaml.md"), "---\ntitle: [invalid yaml\n---\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-frontmatter-yaml-error" }.should be_true
      end
    end

    it "does not warn on all-lowercase tags" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "good-tags.md"), "---\ntitle: Post\ndescription: Desc\ntags:\n  - crystal\n  - web-dev\n---\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-tag-mixed-case" }.should be_false
      end
    end

    it "does not warn on all-uppercase tags" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "upper-tags.md"), "---\ntitle: Post\ndescription: Desc\ntags:\n  - AWS\n  - CLI\n---\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-tag-mixed-case" }.should be_false
      end
    end

    it "detects multiple images missing alt text" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "multi.md"), "---\ntitle: Post\ndescription: Desc\n---\n\n![](a.png)\n\nText\n\n![](b.png)\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        alt_issues = issues.select { |i| i.id == "content-alt-text-missing" }
        alt_issues.size.should eq(2)
      end
    end

    it "handles internal links with anchors" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "target.md"), "---\ntitle: Target\ndescription: T\n---\n\nContent\n")
        File.write(File.join(content_dir, "source.md"), "---\ntitle: Source\ndescription: S\n---\n\n[Link](@/target.md#section)\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-internal-link-broken" }.should be_false
      end
    end

    it "handles internal links with query params" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "target.md"), "---\ntitle: Target\ndescription: T\n---\n\nContent\n")
        File.write(File.join(content_dir, "source.md"), "---\ntitle: Source\ndescription: S\n---\n\n[Link](@/target.md?ref=home)\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-internal-link-broken" }.should be_false
      end
    end

    it "skips @/ links with empty path" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "empty-link.md"), "---\ntitle: Post\ndescription: Desc\n---\n\n[Link](@/)\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-internal-link-broken" }.should be_false
      end
    end

    it "does not flag external links" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "ext.md"), "---\ntitle: Post\ndescription: Desc\n---\n\n[Google](https://google.com)\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-internal-link-broken" }.should be_false
      end
    end

    it "handles files with no frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "no-fm.md"), "# Just markdown\n\nNo frontmatter here.\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.level == :error }.should be_false
      end
    end

    it "handles .markdown extension files" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.markdown"), "---\ntitle: Markdown Ext\ndescription: Desc\n---\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        errors_and_warnings = issues.select { |i| i.level == :error || i.level == :warning }
        errors_and_warnings.should be_empty
      end
    end

    it "detects mixed-case tags in TOML frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "toml-tags.md"), "+++\ntitle = \"Post\"\ndescription = \"Desc\"\ntags = [\"Crystal\", \"web\"]\n+++\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-tag-mixed-case" && i.message.includes?("Crystal") }.should be_true
      end
    end

    it "ignores images in inline code" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "inline-code.md"), "---\ntitle: Post\ndescription: Desc\n---\n\nUse `![](example.png)` for images.\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-alt-text-missing" }.should be_false
      end
    end

    it "ignores @/ links in code blocks" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "code-link.md"), "---\ntitle: Post\ndescription: Desc\n---\n\n```md\n[Link](@/nonexistent.md)\n```\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-internal-link-broken" }.should be_false
      end
    end

    it "validates internal link to section directory with _index.md" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(File.join(content_dir, "about"))

        File.write(File.join(content_dir, "about", "_index.md"), "---\ntitle: About\ndescription: About\n---\n\nAbout\n")
        File.write(File.join(content_dir, "source.md"), "---\ntitle: Source\ndescription: S\n---\n\n[About](@/about)\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-internal-link-broken" }.should be_false
      end
    end
  end
end
