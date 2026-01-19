require "../spec_helper"

describe Hwaro::Content::Processors::Registry do
  it "has markdown processor registered by default" do
    Hwaro::Content::Processors::Registry.has?("markdown").should be_true
  end

  it "has html processor registered" do
    Hwaro::Content::Processors::Registry.has?("html").should be_true
  end

  it "can list all processor names" do
    names = Hwaro::Content::Processors::Registry.names
    names.should contain("markdown")
    names.should contain("html")
  end
end

describe Hwaro::Processor::Markdown do
  describe "parse" do
    it "captures front matter keys for taxonomy detection" do
      content = <<-MARKDOWN
      +++
      title = "Post"
      tags = ["a"]
      categories = []
      +++

      # Content
      MARKDOWN

      result = Hwaro::Processor::Markdown.parse(content)
      result[:front_matter_keys].should contain("tags")
      result[:front_matter_keys].should contain("categories")
    end

    it "keeps empty taxonomy arrays for configured keys" do
      content = <<-MARKDOWN
      ---
      title: Post
      categories: []
      ---

      # Content
      MARKDOWN

      result = Hwaro::Processor::Markdown.parse(content)
      result[:taxonomies].has_key?("categories").should be_true
      result[:taxonomies]["categories"].should eq([] of String)
    end

    it "parses TOML frontmatter with in_sitemap" do
      content = <<-MARKDOWN
      +++
      title = "Test Page"
      draft = false
      in_sitemap = false
      +++

      # Content
      MARKDOWN

      result = Hwaro::Processor::Markdown.parse(content)
      result[:title].should eq("Test Page")
      result[:draft].should eq(false)
      result[:in_sitemap].should eq(false)
    end

    it "defaults in_sitemap to true when not specified in TOML" do
      content = <<-MARKDOWN
      +++
      title = "Test Page"
      +++

      # Content
      MARKDOWN

      result = Hwaro::Processor::Markdown.parse(content)
      result[:in_sitemap].should eq(true)
    end

    it "parses YAML frontmatter with in_sitemap" do
      content = <<-MARKDOWN
      ---
      title: Test Page
      draft: false
      in_sitemap: false
      ---

      # Content
      MARKDOWN

      result = Hwaro::Processor::Markdown.parse(content)
      result[:title].should eq("Test Page")
      result[:draft].should eq(false)
      result[:in_sitemap].should eq(false)
    end

    it "defaults in_sitemap to true when not specified in YAML" do
      content = <<-MARKDOWN
      ---
      title: Test Page
      ---

      # Content
      MARKDOWN

      result = Hwaro::Processor::Markdown.parse(content)
      result[:in_sitemap].should eq(true)
    end

    it "handles in_sitemap explicitly set to true in TOML" do
      content = <<-MARKDOWN
      +++
      title = "Test Page"
      in_sitemap = true
      +++

      # Content
      MARKDOWN

      result = Hwaro::Processor::Markdown.parse(content)
      result[:in_sitemap].should eq(true)
    end

    it "handles in_sitemap explicitly set to true in YAML" do
      content = <<-MARKDOWN
      ---
      title: Test Page
      in_sitemap: true
      ---

      # Content
      MARKDOWN

      result = Hwaro::Processor::Markdown.parse(content)
      result[:in_sitemap].should eq(true)
    end

    it "parses pagination settings from TOML frontmatter" do
      content = <<-MARKDOWN
      +++
      title = "Wiki"
      paginate = 5
      pagination_enabled = true
      +++

      # Wiki Section
      MARKDOWN

      result = Hwaro::Processor::Markdown.parse(content)
      result[:paginate].should eq(5)
      result[:pagination_enabled].should eq(true)
    end

    it "parses pagination settings from YAML frontmatter" do
      content = <<-MARKDOWN
      ---
      title: Wiki
      paginate: 10
      pagination_enabled: false
      ---

      # Wiki Section
      MARKDOWN

      result = Hwaro::Processor::Markdown.parse(content)
      result[:paginate].should eq(10)
      result[:pagination_enabled].should eq(false)
    end

    it "defaults pagination settings to nil when not specified" do
      content = <<-MARKDOWN
      +++
      title = "Test Page"
      +++

      # Content
      MARKDOWN

      result = Hwaro::Processor::Markdown.parse(content)
      result[:paginate].should be_nil
      result[:pagination_enabled].should be_nil
    end
  end
end
