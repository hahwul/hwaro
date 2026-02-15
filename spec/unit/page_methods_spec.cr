require "../spec_helper"

describe Hwaro::Models::Page do
  describe "#calculate_word_count" do
    it "counts words in raw content excluding front matter (TOML)" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "+++\ntitle = \"Test\"\n+++\n\nHello world this is a test."
      count = page.calculate_word_count
      count.should eq(6)
      page.word_count.should eq(6)
    end

    it "counts words in raw content excluding front matter (YAML)" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "---\ntitle: Test\n---\n\nOne two three four five."
      count = page.calculate_word_count
      count.should eq(5)
      page.word_count.should eq(5)
    end

    it "strips HTML tags before counting" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "<p>Hello</p> <strong>world</strong> <a href=\"#\">link</a>"
      count = page.calculate_word_count
      count.should eq(3)
    end

    it "strips markdown syntax elements" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "# Heading\n\n**bold** _italic_ `code` [link](url)"
      count = page.calculate_word_count
      # After stripping #*_`[]() we get: Heading bold italic code link url
      count.should eq(6)
    end

    it "returns 0 for empty content" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = ""
      count = page.calculate_word_count
      count.should eq(0)
    end

    it "returns 0 for content with only front matter" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "+++\ntitle = \"Only FM\"\n+++\n"
      count = page.calculate_word_count
      count.should eq(0)
    end

    it "handles multiple whitespace correctly" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "word1   word2\t\tword3\n\nword4"
      count = page.calculate_word_count
      count.should eq(4)
    end

    it "updates word_count property" do
      page = Hwaro::Models::Page.new("test.md")
      page.word_count.should eq(0)
      page.raw_content = "one two three"
      page.calculate_word_count
      page.word_count.should eq(3)
    end
  end

  describe "#calculate_reading_time" do
    it "calculates reading time based on word count" do
      page = Hwaro::Models::Page.new("test.md")
      # 400 words at 200 wpm = 2 minutes
      page.raw_content = (["word"] * 400).join(" ")
      time = page.calculate_reading_time
      time.should eq(2)
      page.reading_time.should eq(2)
    end

    it "rounds up to nearest minute" do
      page = Hwaro::Models::Page.new("test.md")
      # 250 words at 200 wpm = 1.25 -> ceil to 2
      page.raw_content = (["word"] * 250).join(" ")
      time = page.calculate_reading_time
      time.should eq(2)
    end

    it "returns 1 for very short content" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "Hello world"
      time = page.calculate_reading_time
      time.should eq(1)
    end

    it "returns 0 for empty content" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = ""
      time = page.calculate_reading_time
      time.should eq(0)
    end

    it "accepts custom words per minute" do
      page = Hwaro::Models::Page.new("test.md")
      # 300 words at 100 wpm = 3 minutes
      page.raw_content = (["word"] * 300).join(" ")
      time = page.calculate_reading_time(words_per_minute: 100)
      time.should eq(3)
    end

    it "recalculates word count if not yet calculated" do
      page = Hwaro::Models::Page.new("test.md")
      page.word_count.should eq(0)
      page.raw_content = (["word"] * 200).join(" ")
      page.calculate_reading_time
      page.word_count.should be > 0
    end

    it "uses existing word_count if already calculated" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = (["word"] * 600).join(" ")
      page.calculate_word_count
      page.word_count.should eq(600)
      # 600 words / 200 wpm = 3
      time = page.calculate_reading_time
      time.should eq(3)
    end
  end

  describe "#extract_summary" do
    it "extracts summary from content before <!-- more --> marker with TOML front matter" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "+++\ntitle = \"Test\"\n+++\n\nThis is the summary.\n\n<!-- more -->\n\nThis is the rest."
      summary = page.extract_summary
      summary.should_not be_nil
      summary.not_nil!.should eq("This is the summary.")
      page.summary.should eq("This is the summary.")
    end

    it "extracts summary from content before <!-- more --> marker with YAML front matter" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "---\ntitle: Test\n---\n\nSummary paragraph.\n\n<!-- more -->\n\nFull content."
      summary = page.extract_summary
      summary.should_not be_nil
      summary.not_nil!.should eq("Summary paragraph.")
    end

    it "extracts summary without front matter" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "This is the intro.\n\n<!-- more -->\n\nAnd here is more."
      summary = page.extract_summary
      summary.should_not be_nil
      summary.not_nil!.should eq("This is the intro.")
    end

    it "returns nil when no <!-- more --> marker exists" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "+++\ntitle = \"Test\"\n+++\n\nNo marker in this content."
      summary = page.extract_summary
      summary.should be_nil
    end

    it "handles <!-- more --> with varying whitespace" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "Summary text.\n\n<!--  more  -->\n\nRest of content."
      summary = page.extract_summary
      summary.should_not be_nil
      summary.not_nil!.should eq("Summary text.")
    end

    it "returns nil for empty content" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = ""
      summary = page.extract_summary
      summary.should be_nil
    end

    it "returns nil when summary portion is empty" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "+++\ntitle = \"Test\"\n+++\n\n<!-- more -->\n\nOnly after marker."
      summary = page.extract_summary
      # The content between front matter and marker is empty after strip
      summary.should be_nil
    end

    it "sets the summary property" do
      page = Hwaro::Models::Page.new("test.md")
      page.summary.should be_nil
      page.raw_content = "My summary.\n\n<!-- more -->\n\nRest."
      page.extract_summary
      page.summary.should eq("My summary.")
    end
  end

  describe "#generate_permalink" do
    it "generates permalink from base_url and page url" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/blog/my-post/"
      permalink = page.generate_permalink("https://example.com")
      permalink.should eq("https://example.com/blog/my-post/")
      page.permalink.should eq("https://example.com/blog/my-post/")
    end

    it "strips trailing slash from base_url" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/about/"
      permalink = page.generate_permalink("https://example.com/")
      permalink.should eq("https://example.com/about/")
    end

    it "handles url without leading slash" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "test/"
      permalink = page.generate_permalink("https://example.com")
      permalink.should eq("https://example.com/test/")
    end

    it "handles root url" do
      page = Hwaro::Models::Page.new("index.md")
      page.url = "/"
      permalink = page.generate_permalink("https://example.com")
      permalink.should eq("https://example.com/")
    end

    it "handles empty base_url" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      permalink = page.generate_permalink("")
      permalink.should eq("/test/")
    end

    it "updates the permalink property" do
      page = Hwaro::Models::Page.new("test.md")
      page.permalink.should be_nil
      page.url = "/foo/"
      page.generate_permalink("https://site.com")
      page.permalink.should eq("https://site.com/foo/")
    end
  end

  describe "#has_summary?" do
    it "returns true when summary is set" do
      page = Hwaro::Models::Page.new("test.md")
      page.summary = "A summary"
      page.has_summary?.should be_true
    end

    it "returns true when description is set" do
      page = Hwaro::Models::Page.new("test.md")
      page.description = "A description"
      page.has_summary?.should be_true
    end

    it "returns true when both summary and description are set" do
      page = Hwaro::Models::Page.new("test.md")
      page.summary = "Summary"
      page.description = "Description"
      page.has_summary?.should be_true
    end

    it "returns false when neither summary nor description is set" do
      page = Hwaro::Models::Page.new("test.md")
      page.has_summary?.should be_false
    end
  end

  describe "#effective_summary" do
    it "returns summary when set" do
      page = Hwaro::Models::Page.new("test.md")
      page.summary = "The summary"
      page.effective_summary.should eq("The summary")
    end

    it "falls back to description when summary is nil" do
      page = Hwaro::Models::Page.new("test.md")
      page.description = "The description"
      page.effective_summary.should eq("The description")
    end

    it "prefers summary over description" do
      page = Hwaro::Models::Page.new("test.md")
      page.summary = "Summary takes priority"
      page.description = "Description fallback"
      page.effective_summary.should eq("Summary takes priority")
    end

    it "returns nil when neither is set" do
      page = Hwaro::Models::Page.new("test.md")
      page.effective_summary.should be_nil
    end
  end

  describe "new properties defaults" do
    it "initializes authors as empty array" do
      page = Hwaro::Models::Page.new("test.md")
      page.authors.should eq([] of String)
    end

    it "can set authors" do
      page = Hwaro::Models::Page.new("test.md")
      page.authors = ["Alice", "Bob"]
      page.authors.should eq(["Alice", "Bob"])
    end

    it "initializes extra as empty hash" do
      page = Hwaro::Models::Page.new("test.md")
      page.extra.should eq({} of String => String | Bool | Int64 | Float64 | Array(String))
    end

    it "can set extra metadata" do
      page = Hwaro::Models::Page.new("test.md")
      page.extra["custom_key"] = "custom_value"
      page.extra["custom_key"].should eq("custom_value")
    end

    it "can store different types in extra" do
      page = Hwaro::Models::Page.new("test.md")
      page.extra["string_val"] = "hello"
      page.extra["bool_val"] = true
      page.extra["int_val"] = 42_i64
      page.extra["float_val"] = 3.14
      page.extra["array_val"] = ["a", "b"]

      page.extra["string_val"].should eq("hello")
      page.extra["bool_val"].should eq(true)
      page.extra["int_val"].should eq(42_i64)
      page.extra["float_val"].should eq(3.14)
      page.extra["array_val"].should eq(["a", "b"])
    end

    it "initializes summary as nil" do
      page = Hwaro::Models::Page.new("test.md")
      page.summary.should be_nil
    end

    it "can set summary" do
      page = Hwaro::Models::Page.new("test.md")
      page.summary = "A short summary"
      page.summary.should eq("A short summary")
    end

    it "initializes in_search_index as true" do
      page = Hwaro::Models::Page.new("test.md")
      page.in_search_index.should be_true
    end

    it "can set in_search_index to false" do
      page = Hwaro::Models::Page.new("test.md")
      page.in_search_index = false
      page.in_search_index.should be_false
    end

    it "initializes insert_anchor_links as false" do
      page = Hwaro::Models::Page.new("test.md")
      page.insert_anchor_links.should be_false
    end

    it "can set insert_anchor_links" do
      page = Hwaro::Models::Page.new("test.md")
      page.insert_anchor_links = true
      page.insert_anchor_links.should be_true
    end

    it "initializes word_count as 0" do
      page = Hwaro::Models::Page.new("test.md")
      page.word_count.should eq(0)
    end

    it "initializes reading_time as 0" do
      page = Hwaro::Models::Page.new("test.md")
      page.reading_time.should eq(0)
    end

    it "initializes permalink as nil" do
      page = Hwaro::Models::Page.new("test.md")
      page.permalink.should be_nil
    end

    it "initializes lower as nil" do
      page = Hwaro::Models::Page.new("test.md")
      page.lower.should be_nil
    end

    it "can set lower page reference" do
      page = Hwaro::Models::Page.new("current.md")
      prev_page = Hwaro::Models::Page.new("prev.md")
      prev_page.title = "Previous Post"
      page.lower = prev_page
      page.lower.should eq(prev_page)
      page.lower.not_nil!.title.should eq("Previous Post")
    end

    it "initializes higher as nil" do
      page = Hwaro::Models::Page.new("test.md")
      page.higher.should be_nil
    end

    it "can set higher page reference" do
      page = Hwaro::Models::Page.new("current.md")
      next_page = Hwaro::Models::Page.new("next.md")
      next_page.title = "Next Post"
      page.higher = next_page
      page.higher.should eq(next_page)
      page.higher.not_nil!.title.should eq("Next Post")
    end

    it "initializes ancestors as empty array" do
      page = Hwaro::Models::Page.new("test.md")
      page.ancestors.should eq([] of Hwaro::Models::Page)
    end

    it "can add ancestors" do
      page = Hwaro::Models::Page.new("blog/posts/deep.md")
      root = Hwaro::Models::Page.new("_index.md")
      root.title = "Home"
      blog = Hwaro::Models::Page.new("blog/_index.md")
      blog.title = "Blog"

      page.ancestors << root
      page.ancestors << blog
      page.ancestors.size.should eq(2)
      page.ancestors[0].title.should eq("Home")
      page.ancestors[1].title.should eq("Blog")
    end

    it "initializes assets as empty array" do
      page = Hwaro::Models::Page.new("test.md")
      page.assets.should eq([] of String)
    end

    it "can set assets" do
      page = Hwaro::Models::Page.new("test.md")
      page.assets = ["blog/image.png", "blog/data.json"]
      page.assets.size.should eq(2)
    end

    it "initializes translations as empty array" do
      page = Hwaro::Models::Page.new("test.md")
      page.translations.should eq([] of Hwaro::Models::TranslationLink)
    end
  end

  describe "#collect_assets" do
    it "returns empty array for non-index pages" do
      page = Hwaro::Models::Page.new("blog/post.md")
      page.is_index = false
      result = page.collect_assets("/tmp/nonexistent")
      result.should eq([] of String)
    end

    it "returns empty array when directory does not exist" do
      page = Hwaro::Models::Page.new("blog/index.md")
      page.is_index = true
      result = page.collect_assets("/tmp/nonexistent_dir_xyz_12345")
      result.should eq([] of String)
    end

    it "collects non-markdown files from page directory" do
      Dir.mktmpdir do |dir|
        content_dir = dir
        page_dir = File.join(dir, "blog")
        FileUtils.mkdir_p(page_dir)

        File.write(File.join(page_dir, "index.md"), "# Test")
        File.write(File.join(page_dir, "image.png"), "fake png")
        File.write(File.join(page_dir, "style.css"), "body {}")
        File.write(File.join(page_dir, "other.markdown"), "other md")

        page = Hwaro::Models::Page.new("blog/index.md")
        page.is_index = true

        assets = page.collect_assets(content_dir)
        assets.should contain("blog/image.png")
        assets.should contain("blog/style.css")
        assets.should_not contain("blog/index.md")
        assets.should_not contain("blog/other.markdown")
      end
    end
  end
end

describe Hwaro::Models::TranslationLink do
  describe "#initialize" do
    it "creates a translation link with required properties" do
      link = Hwaro::Models::TranslationLink.new(
        code: "ko",
        url: "/ko/about/",
        title: "소개"
      )
      link.code.should eq("ko")
      link.url.should eq("/ko/about/")
      link.title.should eq("소개")
      link.is_current.should be_false
      link.is_default.should be_false
    end

    it "accepts optional is_current and is_default" do
      link = Hwaro::Models::TranslationLink.new(
        code: "en",
        url: "/about/",
        title: "About",
        is_current: true,
        is_default: true
      )
      link.is_current.should be_true
      link.is_default.should be_true
    end
  end
end

describe "#redirect_to" do
  it "initializes as nil" do
    page = Hwaro::Models::Page.new("test.md")
    page.redirect_to.should be_nil
  end

  it "can be set" do
    page = Hwaro::Models::Page.new("test.md")
    page.redirect_to = "/some/path"
    page.redirect_to.should eq("/some/path")
  end
end

describe "#has_redirect?" do
  it "returns false when redirect_to is nil" do
    page = Hwaro::Models::Page.new("test.md")
    page.has_redirect?.should be_false
  end

  it "returns false when redirect_to is empty" do
    page = Hwaro::Models::Page.new("test.md")
    page.redirect_to = ""
    page.has_redirect?.should be_false
  end

  it "returns true when redirect_to is set" do
    page = Hwaro::Models::Page.new("test.md")
    page.redirect_to = "/target"
    page.has_redirect?.should be_true
  end
end
