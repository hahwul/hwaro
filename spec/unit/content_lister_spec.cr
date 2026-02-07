require "../spec_helper"

describe Hwaro::Services::ContentLister do
  describe "#list_content" do
    it "returns empty array when content directory does not exist" do
      lister = Hwaro::Services::ContentLister.new("/nonexistent/path/content")
      result = lister.list_content(Hwaro::Services::ContentFilter::All)
      result.should eq([] of Hwaro::Services::ContentInfo)
    end

    it "returns all content files with All filter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "published.md"), "---\ntitle: Published Post\ndraft: false\n---\n\n# Published")
        File.write(File.join(content_dir, "draft.md"), "---\ntitle: Draft Post\ndraft: true\n---\n\n# Draft")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_content(Hwaro::Services::ContentFilter::All)

        result.size.should eq(2)
        titles = result.map(&.title)
        titles.should contain("Published Post")
        titles.should contain("Draft Post")
      end
    end

    it "returns only draft files with Drafts filter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "published.md"), "---\ntitle: Published Post\ndraft: false\n---\n\n# Published")
        File.write(File.join(content_dir, "draft.md"), "---\ntitle: Draft Post\ndraft: true\n---\n\n# Draft")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_content(Hwaro::Services::ContentFilter::Drafts)

        result.size.should eq(1)
        result.first.title.should eq("Draft Post")
        result.first.draft.should be_true
      end
    end

    it "returns only published files with Published filter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "published.md"), "---\ntitle: Published Post\ndraft: false\n---\n\n# Published")
        File.write(File.join(content_dir, "draft.md"), "---\ntitle: Draft Post\ndraft: true\n---\n\n# Draft")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_content(Hwaro::Services::ContentFilter::Published)

        result.size.should eq(1)
        result.first.title.should eq("Published Post")
        result.first.draft.should be_false
      end
    end

    it "returns empty array when no files match filter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "published.md"), "---\ntitle: Published\ndraft: false\n---\n\nContent")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_content(Hwaro::Services::ContentFilter::Drafts)

        result.should be_empty
      end
    end

    it "returns empty array when content directory is empty" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_content(Hwaro::Services::ContentFilter::All)

        result.should be_empty
      end
    end
  end

  describe "#list_all" do
    it "delegates to list_content with All filter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post1.md"), "---\ntitle: Post 1\ndraft: false\n---\n\n# Content")
        File.write(File.join(content_dir, "post2.md"), "---\ntitle: Post 2\ndraft: true\n---\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.size.should eq(2)
      end
    end
  end

  describe "#list_drafts" do
    it "delegates to list_content with Drafts filter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "published.md"), "---\ntitle: Published\ndraft: false\n---\n\n# Content")
        File.write(File.join(content_dir, "draft.md"), "---\ntitle: Draft\ndraft: true\n---\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_drafts

        result.size.should eq(1)
        result.first.title.should eq("Draft")
      end
    end
  end

  describe "#list_published" do
    it "delegates to list_content with Published filter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "published.md"), "---\ntitle: Published\ndraft: false\n---\n\n# Content")
        File.write(File.join(content_dir, "draft.md"), "---\ntitle: Draft\ndraft: true\n---\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_published

        result.size.should eq(1)
        result.first.title.should eq("Published")
      end
    end
  end

  describe "YAML frontmatter parsing" do
    it "parses title from YAML frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "---\ntitle: My Great Post\n---\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.size.should eq(1)
        result.first.title.should eq("My Great Post")
      end
    end

    it "parses draft status from YAML frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "---\ntitle: Draft Post\ndraft: true\n---\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.first.draft.should be_true
      end
    end

    it "defaults draft to false when not specified in YAML" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "---\ntitle: No Draft Key\n---\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.first.draft.should be_false
      end
    end

    it "parses date from YAML frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "---\ntitle: Dated Post\ndate: 2024-06-15\n---\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.first.date.should_not be_nil
      end
    end

    it "handles date with time component in YAML" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "---\ntitle: Timed Post\ndate: 2024-06-15 10:30:00\n---\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.first.date.should_not be_nil
      end
    end

    it "defaults title to Untitled when not specified" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "---\ndraft: false\n---\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.first.title.should eq("Untitled")
      end
    end
  end

  describe "TOML frontmatter parsing" do
    it "parses title from TOML frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"TOML Post\"\n+++\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.size.should eq(1)
        result.first.title.should eq("TOML Post")
      end
    end

    it "parses draft status from TOML frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"Draft\"\ndraft = true\n+++\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.first.draft.should be_true
      end
    end

    it "defaults draft to false when not specified in TOML" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"No Draft\"\n+++\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.first.draft.should be_false
      end
    end

    it "parses date from TOML frontmatter as string" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"Dated\"\ndate = \"2024-06-15 10:30:00\"\n+++\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.first.date.should_not be_nil
      end
    end
  end

  describe "no frontmatter" do
    it "handles files without any frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "# Just a heading\n\nNo frontmatter at all.")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.size.should eq(1)
        result.first.title.should eq("Untitled")
        result.first.draft.should be_false
        result.first.date.should be_nil
      end
    end
  end

  describe "nested directories" do
    it "finds files in subdirectories" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(File.join(content_dir, "blog"))
        FileUtils.mkdir_p(File.join(content_dir, "docs", "guides"))

        File.write(File.join(content_dir, "index.md"), "---\ntitle: Home\n---\n\nHome")
        File.write(File.join(content_dir, "blog", "post.md"), "---\ntitle: Blog Post\n---\n\nBlog")
        File.write(File.join(content_dir, "docs", "guides", "intro.md"), "---\ntitle: Guide\n---\n\nGuide")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.size.should eq(3)
        titles = result.map(&.title)
        titles.should contain("Home")
        titles.should contain("Blog Post")
        titles.should contain("Guide")
      end
    end
  end

  describe "sorting" do
    it "sorts results by date (newest first)" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "old.md"), "---\ntitle: Old Post\ndate: 2023-01-01\n---\n\nOld")
        File.write(File.join(content_dir, "new.md"), "---\ntitle: New Post\ndate: 2024-06-15\n---\n\nNew")
        File.write(File.join(content_dir, "mid.md"), "---\ntitle: Mid Post\ndate: 2024-03-01\n---\n\nMid")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.size.should eq(3)
        result[0].title.should eq("New Post")
        result[1].title.should eq("Mid Post")
        result[2].title.should eq("Old Post")
      end
    end
  end

  describe "mixed frontmatter formats" do
    it "handles a mix of YAML and TOML files" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "yaml_post.md"), "---\ntitle: YAML Post\ndraft: false\n---\n\n# YAML")
        File.write(File.join(content_dir, "toml_post.md"), "+++\ntitle = \"TOML Post\"\ndraft = true\n+++\n\n# TOML")
        File.write(File.join(content_dir, "no_fm.md"), "# No frontmatter\n\nPlain text.")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        result = lister.list_all

        result.size.should eq(3)

        yaml_item = result.find { |i| i.title == "YAML Post" }
        yaml_item.should_not be_nil
        yaml_item.not_nil!.draft.should be_false

        toml_item = result.find { |i| i.title == "TOML Post" }
        toml_item.should_not be_nil
        toml_item.not_nil!.draft.should be_true

        plain_item = result.find { |i| i.title == "Untitled" }
        plain_item.should_not be_nil
        plain_item.not_nil!.draft.should be_false
      end
    end
  end

  describe "#display" do
    it "does not raise for empty content directory" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        lister = Hwaro::Services::ContentLister.new(content_dir)
        # Should not raise
        lister.display(Hwaro::Services::ContentFilter::All)
      end
    end

    it "does not raise for non-existent directory" do
      lister = Hwaro::Services::ContentLister.new("/nonexistent/path/content")
      # Should not raise
      lister.display(Hwaro::Services::ContentFilter::All)
    end

    it "does not raise for populated directory" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "---\ntitle: Test Post\ndraft: false\ndate: 2024-01-15\n---\n\n# Content")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        # Should not raise for any filter type
        lister.display(Hwaro::Services::ContentFilter::All)
        lister.display(Hwaro::Services::ContentFilter::Drafts)
        lister.display(Hwaro::Services::ContentFilter::Published)
      end
    end
  end
end

describe Hwaro::Services::ContentFilter do
  it "has All variant" do
    Hwaro::Services::ContentFilter::All.should_not be_nil
  end

  it "has Drafts variant" do
    Hwaro::Services::ContentFilter::Drafts.should_not be_nil
  end

  it "has Published variant" do
    Hwaro::Services::ContentFilter::Published.should_not be_nil
  end
end

describe Hwaro::Services::ContentInfo do
  it "has default values" do
    info = Hwaro::Services::ContentInfo.new(path: "test.md")
    info.path.should eq("test.md")
    info.title.should eq("Untitled")
    info.draft.should be_false
    info.date.should be_nil
  end

  it "accepts custom values" do
    date = Time.utc(2024, 6, 15)
    info = Hwaro::Services::ContentInfo.new(
      path: "blog/post.md",
      title: "My Post",
      draft: true,
      date: date
    )
    info.path.should eq("blog/post.md")
    info.title.should eq("My Post")
    info.draft.should be_true
    info.date.should eq(date)
  end
end
