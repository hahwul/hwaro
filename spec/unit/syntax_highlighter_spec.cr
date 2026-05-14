require "../spec_helper"
require "../../src/content/processors/syntax_highlighter"

describe Hwaro::Content::Processors::SyntaxHighlighter do
  describe ".render" do
    it "renders markdown to HTML" do
      content = "# Hello\n\nWorld"
      html = Hwaro::Content::Processors::SyntaxHighlighter.render(content)
      html.should contain("<h1>")
      html.should contain("Hello")
      html.should contain("<p>")
      html.should contain("World")
    end

    it "renders code blocks with highlight classes when enabled" do
      content = "```ruby\nputs 'hello'\n```"
      html = Hwaro::Content::Processors::SyntaxHighlighter.render(content, highlight: true)
      html.should contain("language-ruby")
      html.should contain("hljs")
    end

    it "renders code blocks without hljs class when highlight disabled" do
      content = "```ruby\nputs 'hello'\n```"
      html = Hwaro::Content::Processors::SyntaxHighlighter.render(content, highlight: false)
      html.should contain("language-ruby")
      html.should_not contain("hljs")
    end

    it "renders code blocks without language" do
      content = "```\nsome code\n```"
      html = Hwaro::Content::Processors::SyntaxHighlighter.render(content)
      html.should contain("<pre>")
      html.should contain("<code>")
      html.should contain("some code")
    end

    it "processes tables via TableParser" do
      content = "| A | B |\n|---|---|\n| 1 | 2 |"
      html = Hwaro::Content::Processors::SyntaxHighlighter.render(content)
      html.should contain("<table>")
      html.should contain("<td>")
    end

    it "escapes HTML when safe mode is enabled" do
      content = "<script>alert('xss')</script>"
      html = Hwaro::Content::Processors::SyntaxHighlighter.render(content, safe: true)
      html.should_not contain("<script>")
    end

    it "passes through HTML when safe mode is disabled" do
      content = "<div>custom</div>"
      html = Hwaro::Content::Processors::SyntaxHighlighter.render(content, safe: false)
      html.should contain("<div>custom</div>")
    end
  end

  describe ".has_code_blocks?" do
    it "detects backtick code blocks" do
      Hwaro::Content::Processors::SyntaxHighlighter.has_code_blocks?("```ruby\ncode\n```").should be_true
    end

    it "detects tilde code blocks" do
      Hwaro::Content::Processors::SyntaxHighlighter.has_code_blocks?("~~~\ncode\n~~~").should be_true
    end

    it "returns false for content without code blocks" do
      Hwaro::Content::Processors::SyntaxHighlighter.has_code_blocks?("# Hello\n\nWorld").should be_false
    end

    it "returns false for empty string" do
      Hwaro::Content::Processors::SyntaxHighlighter.has_code_blocks?("").should be_false
    end

    it "detects inline backticks as potential code blocks with triple backticks" do
      Hwaro::Content::Processors::SyntaxHighlighter.has_code_blocks?("`code`").should be_false
    end
  end

  describe ".language_supported?" do
    it "returns true for common languages" do
      %w[ruby python javascript go rust crystal].each do |lang|
        Hwaro::Content::Processors::SyntaxHighlighter.language_supported?(lang).should be_true
      end
    end

    it "is case insensitive" do
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("Ruby").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("PYTHON").should be_true
    end

    it "returns false for unsupported languages" do
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("brainfuck").should be_false
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("nonexistent").should be_false
    end

    it "supports shell-related languages" do
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("bash").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("shell").should be_true
    end

    it "supports markup languages" do
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("html").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("xml").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("css").should be_true
    end

    it "supports config file formats" do
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("json").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("yaml").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.language_supported?("toml").should be_true
    end
  end

  describe ".theme_valid?" do
    it "returns true for default theme" do
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("default").should be_true
    end

    it "returns true for popular themes" do
      %w[github monokai atom-one-dark vs2015 nord].each do |theme|
        Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?(theme).should be_true
      end
    end

    it "is case insensitive" do
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("GitHub").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("MONOKAI").should be_true
    end

    it "returns false for invalid themes" do
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("nonexistent").should be_false
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("my-custom-theme").should be_false
    end

    it "supports dark variants" do
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("github-dark").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("atom-one-dark").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("tokyo-night-dark").should be_true
    end

    it "supports light variants" do
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("atom-one-light").should be_true
      Hwaro::Content::Processors::SyntaxHighlighter.theme_valid?("tokyo-night-light").should be_true
    end
  end

  describe "SUPPORTED_LANGUAGES" do
    it "contains a reasonable number of languages" do
      Hwaro::Content::Processors::SyntaxHighlighter::SUPPORTED_LANGUAGES.size.should be > 30
    end
  end

  describe "THEMES" do
    it "contains a reasonable number of themes" do
      Hwaro::Content::Processors::SyntaxHighlighter::THEMES.size.should be > 30
    end
  end
end

describe Hwaro::Content::Processors::HighlightingRenderer do
  it "adds hljs class to code blocks when highlighting enabled" do
    content = "```javascript\nconsole.log('hi')\n```"
    options = Markd::Options.new
    document = Markd::Parser.parse(content, options)
    renderer = Hwaro::Content::Processors::HighlightingRenderer.new(options, true)
    html = renderer.render(document)

    html.should contain("language-javascript")
    html.should contain("hljs")
  end

  it "adds language class without hljs when highlighting disabled" do
    content = "```python\nprint('hi')\n```"
    options = Markd::Options.new
    document = Markd::Parser.parse(content, options)
    renderer = Hwaro::Content::Processors::HighlightingRenderer.new(options, false)
    html = renderer.render(document)

    html.should contain("language-python")
    html.should_not contain("hljs")
  end

  it "escapes special characters in language names" do
    content = "```a<b>c\ncode\n```"
    options = Markd::Options.new
    document = Markd::Parser.parse(content, options)
    renderer = Hwaro::Content::Processors::HighlightingRenderer.new(options, true)
    html = renderer.render(document)

    html.should_not contain("language-a<b>c")
    html.should contain("&lt;")
  end
end
