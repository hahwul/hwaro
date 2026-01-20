require "../spec_helper"

describe Hwaro::Content::Processors::SyntaxHighlighter do
  describe "render" do
    it "renders code blocks with language class and hljs class when highlight is enabled" do
      content = <<-MARKDOWN
      ```ruby
      puts "hello"
      ```
      MARKDOWN

      html = Hwaro::Content::Processors::SyntaxHighlighter.render(content, highlight: true)
      html.should contain("language-ruby")
      html.should contain("hljs")
      html.should contain("<pre>")
      html.should contain("<code")
    end

    it "renders code blocks with language class only when highlight is disabled" do
      content = <<-MARKDOWN
      ```ruby
      puts "hello"
      ```
      MARKDOWN

      html = Hwaro::Content::Processors::SyntaxHighlighter.render(content, highlight: false)
      html.should contain("language-ruby")
      html.should_not contain("hljs")
    end

    it "renders code blocks without language class when no language specified" do
      content = <<-MARKDOWN
      ```
      plain text
      ```
      MARKDOWN

      html = Hwaro::Content::Processors::SyntaxHighlighter.render(content, highlight: true)
      html.should contain("<code>")
      html.should_not contain("language-")
    end

    it "escapes special characters in language names" do
      content = <<-MARKDOWN
      ```c++
      int main() {}
      ```
      MARKDOWN

      html = Hwaro::Content::Processors::SyntaxHighlighter.render(content, highlight: true)
      html.should contain("language-c++")
    end
  end

  describe "has_code_blocks?" do
    it "returns true for fenced code blocks with triple backticks" do
      content = "Some text\n```ruby\ncode\n```"
      Hwaro::Content::Processors::SyntaxHighlighter.has_code_blocks?(content).should be_true
    end

    it "returns true for fenced code blocks with tildes" do
      content = "Some text\n~~~python\ncode\n~~~"
      Hwaro::Content::Processors::SyntaxHighlighter.has_code_blocks?(content).should be_true
    end

    it "returns false for content without code blocks" do
      content = "Just some regular text"
      Hwaro::Content::Processors::SyntaxHighlighter.has_code_blocks?(content).should be_false
    end
  end

  describe "language_supported?" do
    it "returns true for supported languages" do
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("ruby").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("python").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("javascript").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("crystal").should be_true
    end

    it "returns false for unsupported languages" do
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("unknown_lang").should be_false
    end
  end

  describe "theme_valid?" do
    it "returns true for valid themes" do
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("github").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("monokai").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("atom-one-dark").should be_true
    end

    it "returns false for invalid themes" do
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("invalid_theme").should be_false
    end
  end
end

describe Hwaro::Models::HighlightConfig do
  it "has default values" do
    config = Hwaro::Models::HighlightConfig.new
    config.enabled.should be_true
    config.theme.should eq("github")
    config.use_cdn.should be_true
  end

  describe "css_tag" do
    it "returns CDN link when use_cdn is true" do
      config = Hwaro::Models::HighlightConfig.new
      config.css_tag.should contain("cdnjs.cloudflare.com")
      config.css_tag.should contain("github.min.css")
    end

    it "returns local link when use_cdn is false" do
      config = Hwaro::Models::HighlightConfig.new
      config.use_cdn = false
      config.css_tag.should contain("/assets/css/highlight/")
      config.css_tag.should_not contain("cdnjs.cloudflare.com")
    end

    it "returns empty string when disabled" do
      config = Hwaro::Models::HighlightConfig.new
      config.enabled = false
      config.css_tag.should eq("")
    end
  end

  describe "js_tag" do
    it "returns CDN script when use_cdn is true" do
      config = Hwaro::Models::HighlightConfig.new
      config.js_tag.should contain("cdnjs.cloudflare.com")
      config.js_tag.should contain("highlight.min.js")
      config.js_tag.should contain("hljs.highlightAll()")
    end

    it "returns local script when use_cdn is false" do
      config = Hwaro::Models::HighlightConfig.new
      config.use_cdn = false
      config.js_tag.should contain("/assets/js/highlight.min.js")
      config.js_tag.should_not contain("cdnjs.cloudflare.com")
    end

    it "returns empty string when disabled" do
      config = Hwaro::Models::HighlightConfig.new
      config.enabled = false
      config.js_tag.should eq("")
    end
  end

  describe "tags" do
    it "returns combined CSS and JS tags" do
      config = Hwaro::Models::HighlightConfig.new
      tags = config.tags
      tags.should contain("stylesheet")
      tags.should contain("highlight.min.js")
    end

    it "returns empty string when disabled" do
      config = Hwaro::Models::HighlightConfig.new
      config.enabled = false
      config.tags.should eq("")
    end
  end
end

describe Hwaro::Config::Options::BuildOptions do
  it "has highlight enabled by default" do
    options = Hwaro::Config::Options::BuildOptions.new
    options.highlight.should be_true
  end

  it "accepts custom highlight value" do
    options = Hwaro::Config::Options::BuildOptions.new(highlight: false)
    options.highlight.should be_false
  end
end

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
