require "../spec_helper"

describe Hwaro::Content::Search do
  describe ".generate" do
    it "does not generate search index when disabled" do
      config = Hwaro::Models::Config.new
      config.search.enabled = false

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate([] of Hwaro::Models::Page, config, output_dir)
        File.exists?(File.join(output_dir, "search.json")).should be_false
      end
    end

    it "generates search index when enabled" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.format = "fuse_json"
      config.search.fields = ["title", "url"]

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test Page"
      page.url = "/test/"
      page.draft = false
      page.raw_content = "Test content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate([page], config, output_dir)

        search_path = File.join(output_dir, "search.json")
        File.exists?(search_path).should be_true

        content = File.read(search_path)
        content.should contain("Test Page")
        content.should contain("/test/")
      end
    end

    it "excludes draft pages from search index" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.fields = ["title", "url"]

      page1 = Hwaro::Models::Page.new("published.md")
      page1.title = "Published"
      page1.url = "/published/"
      page1.draft = false
      page1.raw_content = "Content"

      page2 = Hwaro::Models::Page.new("draft.md")
      page2.title = "Draft"
      page2.url = "/draft/"
      page2.draft = true
      page2.raw_content = "Draft content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate([page1, page2], config, output_dir)

        content = File.read(File.join(output_dir, "search.json"))
        content.should contain("Published")
        content.should_not contain("Draft")
      end
    end

    it "excludes pages matching exclude patterns" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.fields = ["title", "url"]
      config.search.exclude = ["/private", "/drafts"]

      page1 = Hwaro::Models::Page.new("public.md")
      page1.title = "Public"
      page1.url = "/public/"
      page1.draft = false
      page1.raw_content = "Content"

      page2 = Hwaro::Models::Page.new("private.md")
      page2.title = "Private"
      page2.url = "/private/doc"
      page2.draft = false
      page2.raw_content = "Private Content"

      page3 = Hwaro::Models::Page.new("drafts.md")
      page3.title = "Drafts"
      page3.url = "/drafts/wip"
      page3.draft = false
      page3.raw_content = "WIP Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate([page1, page2, page3], config, output_dir)

        content = File.read(File.join(output_dir, "search.json"))
        content.should contain("Public")
        content.should_not contain("Private")
        content.should_not contain("Drafts")
      end
    end

    it "uses custom filename" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.filename = "custom-search.json"
      config.search.fields = ["title"]

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.draft = false
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate([page], config, output_dir)
        File.exists?(File.join(output_dir, "custom-search.json")).should be_true
      end
    end

    it "generates JavaScript format when configured" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.format = "fuse_javascript"
      config.search.filename = "search.js"
      config.search.fields = ["title"]

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.draft = false
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate([page], config, output_dir)

        content = File.read(File.join(output_dir, "search.js"))
        content.should start_with("var searchData = ")
      end
    end

    it "generates elasticlunr_json format when configured" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.format = "elasticlunr_json"
      config.search.filename = "search.json"
      config.search.fields = ["title"]

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.draft = false
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate([page], config, output_dir)

        search_path = File.join(output_dir, "search.json")
        File.exists?(search_path).should be_true
        content = File.read(search_path)
        content.should contain("Test")
      end
    end

    it "generates elasticlunr_javascript format when configured" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.format = "elasticlunr_javascript"
      config.search.filename = "search.js"
      config.search.fields = ["title"]

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.draft = false
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate([page], config, output_dir)

        content = File.read(File.join(output_dir, "search.js"))
        content.should start_with("var searchData = ")
      end
    end

    it "includes all configured fields" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.fields = ["title", "content", "tags", "url", "section", "description"]

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test Page"
      page.url = "/blog/test/"
      page.section = "blog"
      page.description = "A test description"
      page.tags = ["crystal", "testing"]
      page.draft = false
      page.raw_content = "# Heading\n\nSome **markdown** content."

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate([page], config, output_dir)

        content = File.read(File.join(output_dir, "search.json"))
        content.should contain("Test Page")
        content.should contain("/blog/test/")
        content.should contain("blog")
        content.should contain("A test description")
        content.should contain("crystal")
        content.should contain("testing")
        # Content should be plain text (HTML stripped)
        content.should_not contain("<h1>")
        content.should_not contain("<strong>")
      end
    end

    it "always includes URL even if not in fields list" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.fields = ["title"]

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.draft = false
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate([page], config, output_dir)

        content = File.read(File.join(output_dir, "search.json"))
        content.should contain("/test/")
      end
    end

    it "handles empty pages array" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.fields = ["title"]

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate([] of Hwaro::Models::Page, config, output_dir)
        # Should not create file when no pages
        File.exists?(File.join(output_dir, "search.json")).should be_false
      end
    end

    it "handles description field when nil" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.fields = ["title", "description"]

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.description = nil
      page.draft = false
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate([page], config, output_dir)

        content = File.read(File.join(output_dir, "search.json"))
        # Should have empty description, not crash
        content.should contain("\"description\":\"\"")
      end
    end

    it "strips HTML from content field" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.fields = ["content"]

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.draft = false
      page.raw_content = "<p>Hello <strong>World</strong></p>"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate([page], config, output_dir)

        content = File.read(File.join(output_dir, "search.json"))
        content.should_not contain("<p>")
        content.should_not contain("<strong>")
        content.should_not contain("</p>")
      end
    end

    it "handles multiple pages" do
      config = Hwaro::Models::Config.new
      config.search.enabled = true
      config.search.fields = ["title", "url"]

      pages = (1..3).map do |i|
        page = Hwaro::Models::Page.new("page#{i}.md")
        page.title = "Page #{i}"
        page.url = "/page#{i}/"
        page.draft = false
        page.raw_content = "Content #{i}"
        page
      end

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Search.generate(pages, config, output_dir)

        content = File.read(File.join(output_dir, "search.json"))
        content.should contain("Page 1")
        content.should contain("Page 2")
        content.should contain("Page 3")
        content.should contain("/page1/")
        content.should contain("/page2/")
        content.should contain("/page3/")
      end
    end
  end
end

describe Hwaro::Models::SearchConfig do
  it "has default values" do
    config = Hwaro::Models::SearchConfig.new
    config.enabled.should eq(false)
    config.format.should eq("fuse_json")
    config.fields.should eq(["title", "content"])
    config.filename.should eq("search.json")
  end
end
