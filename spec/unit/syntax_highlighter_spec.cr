require "../spec_helper"

describe Hwaro::Content::Processors::SyntaxHighlighter do
  describe ".highlight" do
    it "returns empty string unchanged" do
      result = Hwaro::Content::Processors::SyntaxHighlighter.highlight("")
      result.should eq("")
    end

    it "returns HTML without code blocks unchanged" do
      html = "<p>Hello World</p>"
      result = Hwaro::Content::Processors::SyntaxHighlighter.highlight(html)
      result.should eq(html)
    end

    it "highlights code blocks with language class" do
      html = %(<pre><code class="language-crystal">puts "Hello"</code></pre>)
      result = Hwaro::Content::Processors::SyntaxHighlighter.highlight(html, theme: "monokai")
      result.should contain("puts")
      # The highlighted code should contain span elements for syntax coloring
      result.should contain("<span")
    end

    it "handles HTML entities in code" do
      html = %(<pre><code class="language-html">&lt;div&gt;test&lt;/div&gt;</code></pre>)
      result = Hwaro::Content::Processors::SyntaxHighlighter.highlight(html, theme: "monokai")
      result.should contain("<span")
    end

    it "preserves non-code-block HTML" do
      html = %(<p>Before</p><pre><code class="language-ruby">puts "hi"</code></pre><p>After</p>)
      result = Hwaro::Content::Processors::SyntaxHighlighter.highlight(html, theme: "monokai")
      result.should contain("<p>Before</p>")
      result.should contain("<p>After</p>")
    end

    it "handles multiple code blocks" do
      html = %(<pre><code class="language-ruby">puts "a"</code></pre><pre><code class="language-python">print("b")</code></pre>)
      result = Hwaro::Content::Processors::SyntaxHighlighter.highlight(html, theme: "monokai")
      result.should contain("puts")
      result.should contain("print")
    end
  end

  describe ".highlight_code" do
    it "highlights code with specified language" do
      code = %q{def hello
  puts "Hello, World!"
end}
      result = Hwaro::Content::Processors::SyntaxHighlighter.highlight_code(code, "ruby", theme: "monokai")
      result.should contain("<span")
      result.should contain("def")
    end

    it "falls back gracefully for unknown languages" do
      code = "some code"
      # This should not raise an exception
      result = Hwaro::Content::Processors::SyntaxHighlighter.highlight_code(code, "unknownlanguage123", theme: "monokai")
      result.should contain("some code")
    end
  end
end

describe Hwaro::Models::HighlightConfig do
  it "has default values" do
    config = Hwaro::Models::HighlightConfig.new
    config.enabled.should eq(true)
    config.theme.should eq("monokai")
    config.line_numbers.should eq(false)
  end

  it "can be customized" do
    config = Hwaro::Models::HighlightConfig.new
    config.enabled = false
    config.theme = "github"
    config.line_numbers = true

    config.enabled.should eq(false)
    config.theme.should eq("github")
    config.line_numbers.should eq(true)
  end
end

describe Hwaro::Models::Config do
  it "has default highlight configuration" do
    config = Hwaro::Models::Config.new
    config.highlight.enabled.should eq(true)
    config.highlight.theme.should eq("monokai")
    config.highlight.line_numbers.should eq(false)
  end
end
