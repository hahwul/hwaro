require "../../spec_helper"

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

    it "flags missing title for EMPTY YAML frontmatter (symmetric with TOML)" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "empty-fm.md"), "---\n---\n# Body\n")

        issues = Hwaro::Services::ContentValidator.new(content_dir).run
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

    it "detects missing alt text on rendered raw HTML images" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "html-image.md"), "---\ntitle: Post\ndescription: Desc\n---\n\n<img src=\"/photo.png\">\n")

        issues = Hwaro::Services::ContentValidator.new(content_dir).run

        issue = issues.find { |i| i.id == "content-alt-text-missing" }
        issue.should_not be_nil
        issue.not_nil!.message.should eq("Image missing alt text: <img src=\"/photo.png\">")
      end
    end

    it "requires an alt attribute without scanning HTML code examples" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "html-images.md"), <<-MD
          ---
          title: Post
          description: Desc
          ---

          <img src="/good.png" alt="A photo">
          <img src="/empty.png" alt="">
          <img src="/decoy.png" data-alt="Not an alt attribute">

          ```html
          <img src="/example.png">
          ```
          MD
        )

        issues = Hwaro::Services::ContentValidator.new(content_dir).run

        # alt="" is a valid decorative image; only the data-alt decoy (no real
        # alt attribute) is missing one.
        alt_issues = issues.select { |i| i.id == "content-alt-text-missing" }
        alt_issues.map(&.message).should eq([%(Image missing alt text: <img src="/decoy.png" data-alt="Not an alt attribute">)])
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

    it "detects broken angle-bracket internal links" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "broken-angle.md"), "---\ntitle: Post\ndescription: Desc\n---\n\n[Link](<@/missing-page.md>)\n")

        issues = Hwaro::Services::ContentValidator.new(content_dir).run

        issues.any? { |i| i.id == "content-internal-link-broken" }.should be_true
      end
    end

    it "ignores Markdown link titles when resolving valid internal links" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "target.md"), "---\ntitle: Target\ndescription: Desc\n---\nTarget\n")
        File.write(File.join(content_dir, "source.md"), "---\ntitle: Source\ndescription: Desc\n---\n[Target](@/target.md \"A title\")\n")

        issues = Hwaro::Services::ContentValidator.new(content_dir).run

        issues.any? { |i| i.id == "content-internal-link-broken" }.should be_false
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

    it "works with JSON frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "json.md"), %({"title": "JSON Post", "description": "A JSON post", "date": "2024-01-15"}\n\n# Content\n))

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        errors_and_warnings = issues.select { |i| i.level == :error || i.level == :warning }
        errors_and_warnings.should be_empty
      end
    end

    it "detects JSON frontmatter parse errors" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "bad-json.md"), %({"title": "P", "bad": }\n\n# Content\n))

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-frontmatter-json-error" }.should be_true
      end
    end

    it "reports unbalanced JSON braces as a parse error" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        # File starts with `{` but never closes — we want a loud error, not a
        # silent fall-through to "no frontmatter".
        File.write(File.join(content_dir, "unbalanced.md"), %({"title": "Never closes\n\nbody\n))

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issue = issues.find { |i| i.id == "content-frontmatter-json-error" }
        issue.should_not be_nil
        issue.not_nil!.message.should contain("unbalanced braces")
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

    # The build warns "Empty internal link '@/'" (and fails under
    # `[links] broken_internal = "error"`); check-links reports it dead too.
    it "reports an @/ link with an empty path" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "empty-link.md"), "---\ntitle: Post\ndescription: Desc\n---\n\n[Link](@/)\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        broken = issues.select { |i| i.id == "content-internal-link-broken" }
        broken.map(&.message).should eq(["Possible broken internal link: @/ (empty link)"])
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

    # The build's resolver looks `@/` up by exact content path, so a section
    # is linked through its `_index.md`; `@/about` is left unresolved.
    it "validates internal links to a section through its _index.md path" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(File.join(content_dir, "about"))

        File.write(File.join(content_dir, "about", "_index.md"), "---\ntitle: About\ndescription: About\n---\n\nAbout\n")
        File.write(File.join(content_dir, "source.md"), "---\ntitle: Source\ndescription: S\n---\n\n[About](@/about/_index.md) [Guess](@/about)\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        broken = issues.select { |i| i.id == "content-internal-link-broken" }
        broken.size.should eq(1)
        broken[0].message.should eq("Possible broken internal link: @/about")
      end
    end

    it "handles out-of-range dates raising ArgumentError as content-date-invalid (regression)" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "bad-date.md"), "---\ntitle: Post\ndescription: Desc\ndate: 2024-02-30\n---\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-date-invalid" }.should be_true
      end
    end

    it "flags dates with trailing garbage suffix (regression)" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "garbage-date.md"), "---\ntitle: Post\ndescription: Desc\ndate: 2024-06-15 lol\n---\n\n# Content\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-date-invalid" }.should be_true
      end
    end

    it "runs alt-text and internal link checks on no-frontmatter files (regression)" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "no-frontmatter.md"), "# Heading\n\n![](missing-alt.png)\n\n[Link](@/nonexistent-link.md)\n")

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-alt-text-missing" }.should be_true
        issues.any? { |i| i.id == "content-internal-link-broken" }.should be_true
      end
    end

    it "skips unfollowable content symlinks instead of failing the run (regression)" do
      # `hwaro build` skips a symlink cycle in content/ with one warning; the
      # validator read the same path and turned every such link into an
      # author-fixable `content-read-error`, so `tool validate` exited 5 on a
      # tree that builds fine.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "good.md"), "---\ntitle: Good\ndescription: Desc\n---\n\n# Good\n")
        File.symlink("loop.md", File.join(content_dir, "loop.md"))
        File.symlink("gone.md", File.join(content_dir, "dangling.md"))

        issues = [] of Hwaro::Services::Issue
        output = with_captured_log do
          issues = Hwaro::Services::ContentValidator.new(content_dir).run
        end

        issues.any? { |i| i.id == "content-read-error" }.should be_false
        # The skip is announced, so the summary is short of a file the caller
        # can see on disk only where they were told about it.
        output.should contain("loop.md")
      end
    end

    it "excludes JSON frontmatter from body scans (regression)" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "json-fm.md"), %({"title": "Post", "description": "Desc", "some_field": "![](image.png)"}\n\n# Body\n))

        validator = Hwaro::Services::ContentValidator.new(content_dir)
        issues = validator.run
        issues.any? { |i| i.id == "content-alt-text-missing" }.should be_false
      end
    end
  end
end

private def validator_issues(body : String, files : Hash(String, String) = {} of String => String) : Array(Hwaro::Services::Issue)
  issues = [] of Hwaro::Services::Issue
  Dir.mktmpdir do |dir|
    content_dir = File.join(dir, "content")
    FileUtils.mkdir_p(content_dir)
    files.each do |path, text|
      full = File.join(content_dir, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, text)
    end
    File.write(File.join(content_dir, "source.md"), "---\ntitle: Source\ndescription: Desc\n---\n\n#{body}\n")
    issues = Hwaro::Services::ContentValidator.new(content_dir).run
  end
  issues.select { |i| i.file.try(&.ends_with?("source.md")) }
end

private def alt_messages(body : String) : Array(String)
  validator_issues(body).select { |i| i.id == "content-alt-text-missing" }.map(&.message)
end

private def broken_links(body : String, files : Hash(String, String) = {} of String => String) : Array(String)
  validator_issues(body, files).select { |i| i.id == "content-internal-link-broken" }.map(&.message)
end

describe "ContentValidator body scans ignore what the build does not render" do
  it "ignores an <img> inside a single-line HTML comment" do
    alt_messages(%(<!-- <img src="/old.png"> -->)).should be_empty
  end

  it "ignores an <img> inside a multi-line HTML comment" do
    alt_messages(%(<!--\n<img src="/old.png">\n-->)).should be_empty
  end

  it "keeps an <img> written after a comment on the same line" do
    alt_messages(%(<!-- note --> <img src="/real.png">)).should eq([%(Image missing alt text: <img src="/real.png">)])
  end

  it "ignores an <img> inside an indented code block" do
    alt_messages(%(Example:\n\n    <img src="/example.png">\n)).should be_empty
  end

  it "still checks an indented list-item continuation (rendered as HTML)" do
    alt_messages(%(- item\n    <img src="/listed.png">\n)).should eq([%(Image missing alt text: <img src="/listed.png">)])
  end

  it "ignores @/ links inside comments and indented code" do
    broken_links("<!-- [x](@/gone.md) -->\n\nText:\n\n    [y](@/gone-too.md)\n").should be_empty
  end
end

describe "ContentValidator raw HTML alt attribute" do
  it "accepts an explicit decorative alt=\"\"" do
    alt_messages(%(<img src="/spacer.png" alt="">)).should be_empty
  end

  it "accepts a bare alt attribute" do
    alt_messages(%(<img src="/spacer.png" alt>)).should be_empty
    alt_messages(%(<img alt src="/spacer.png">)).should be_empty
    alt_messages(%(<img src="/spacer.png" alt/>)).should be_empty
  end

  it "matches the alt attribute name case-insensitively" do
    alt_messages(%(<img src="/a.png" ALT="">)).should be_empty
  end

  it "does not mistake alt text inside another attribute's value for an alt attribute" do
    alt_messages(%(<img src="/a.png" title="x alt=y">)).size.should eq(1)
  end

  it "still flags an empty Markdown image alt" do
    alt_messages("![](/a.png)").should eq(["Image missing alt text: ![](/a.png)"])
  end
end

describe "ContentValidator @/ links resolve like the build" do
  target = "---\ntitle: T\ndescription: D\n---\nT\n"

  it "accepts the exact content path of a published page" do
    broken_links("[a](@/posts/p1.md) [b](@/posts/_index.md) [c](@/posts/p1.md#x)", {"posts/p1.md" => target, "posts/_index.md" => target}).should be_empty
  end

  it "does not guess an extension or a section index" do
    broken_links("[a](@/posts/p1) [b](@/posts/) [c](@/posts)", {"posts/p1.md" => target, "posts/_index.md" => target}).size.should eq(3)
  end

  it "does not normalize ./ or ../ segments" do
    broken_links("[a](@/./x.md) [b](@/posts/../x.md)", {"x.md" => target, "posts/p.md" => target}).size.should eq(2)
  end

  it "does not percent-decode the path" do
    broken_links("[a](@/my%20post.md)", {"my post.md" => target}).size.should eq(1)
  end

  it "is case-sensitive even on a case-insensitive filesystem" do
    broken_links("[a](@/UPPER.md)", {"upper.md" => target}).size.should eq(1)
  end

  it "does not resolve a link to a draft, future or expired page" do
    files = {
      "draft.md"   => "---\ntitle: D\ndraft: true\n---\n",
      "future.md"  => "---\ntitle: F\ndate: 2999-01-01\n---\n",
      "expired.md" => "---\ntitle: E\nexpires: 2000-01-01\n---\n",
    }
    messages = broken_links("[a](@/draft.md) [b](@/future.md) [c](@/expired.md)", files)
    messages.size.should eq(3)
    messages.first.should contain("draft")
  end

  it "does not resolve a link that escapes the content directory" do
    broken_links("[a](@/../README.md)", {"../README.md" => "readme"}).size.should eq(1)
  end
end
