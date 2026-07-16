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

  it "wraps a named code block with a filename label" do
    content = "```crystal {name=\"main.cr\"}\nputs 1\n```"
    options = Markd::Options.new
    document = Markd::Parser.parse(content, options)
    renderer = Hwaro::Content::Processors::HighlightingRenderer.new(options, true)
    html = renderer.render(document)

    html.should contain(%(<div class="code-block"><div class="code-filename">main.cr</div>))
    html.should contain("language-crystal")
    html.should contain("</pre></div>")
    # The label alone must not activate line wrapping or data-* attrs.
    html.should_not contain("data-linenos")
  end

  it "HTML-escapes the filename label" do
    content = "```crystal {name=x<b>y}\nputs 1\n```"
    options = Markd::Options.new
    document = Markd::Parser.parse(content, options)
    renderer = Hwaro::Content::Processors::HighlightingRenderer.new(options, true)
    html = renderer.render(document)

    html.should contain("x&lt;b&gt;y")
    html.should_not contain("<div class=\"code-filename\">x<b>")
  end

  it "renders unnamed code blocks without a wrapper" do
    content = "```crystal\nputs 1\n```"
    options = Markd::Options.new
    document = Markd::Parser.parse(content, options)
    renderer = Hwaro::Content::Processors::HighlightingRenderer.new(options, true)
    html = renderer.render(document)

    html.should_not contain("code-block")
    html.should_not contain("code-filename")
  end
end

private def reset_fence_options_state
  Hwaro::Content::Processors::SyntaxHighlighter.server_mode = false
  Hwaro::Content::Processors::SyntaxHighlighter.default_line_numbers = false
end

describe Hwaro::Content::Processors::FenceOptions do
  describe ".parse" do
    it "parses the full example (linenos, hl_lines, linenostart)" do
      lang, opts = Hwaro::Content::Processors::FenceOptions.parse(%(crystal {linenos=true, hl_lines="2-4 7", linenostart=5}))
      lang.should eq("crystal")
      opts = opts.not_nil!
      opts.linenos.should be_true
      opts.linenostart.should eq(5)
      opts.hl_lines.should eq([{2, 4}, {7, 7}])
    end

    it "parses the no-space form" do
      lang, opts = Hwaro::Content::Processors::FenceOptions.parse("crystal{linenos=true}")
      lang.should eq("crystal")
      opts.not_nil!.linenos.should be_true
    end

    it "parses an options block with no language" do
      lang, opts = Hwaro::Content::Processors::FenceOptions.parse("{linenos=true}")
      lang.should be_nil
      opts.not_nil!.linenos.should be_true
    end

    it "returns nil opts for an unrecognized key" do
      lang, opts = Hwaro::Content::Processors::FenceOptions.parse("crystal {foo=1}")
      opts.should be_nil
      lang.should eq("crystal")
    end

    it "parses a quoted name label" do
      lang, opts = Hwaro::Content::Processors::FenceOptions.parse(%(crystal {name="src/main file.cr"}))
      lang.should eq("crystal")
      opts.not_nil!.name.should eq("src/main file.cr")
    end

    it "accepts title as an alias for name" do
      _, opts = Hwaro::Content::Processors::FenceOptions.parse(%(crystal {title=main.cr}))
      opts.not_nil!.name.should eq("main.cr")
    end

    it "ignores an empty name value" do
      _, opts = Hwaro::Content::Processors::FenceOptions.parse(%(crystal {name=""}))
      opts.should be_nil
    end

    it "combines name with line options" do
      _, opts = Hwaro::Content::Processors::FenceOptions.parse(%(crystal {name="x.cr", linenos=true}))
      opts = opts.not_nil!
      opts.name.should eq("x.cr")
      opts.linenos.should be_true
    end

    it "returns nil opts for an unterminated brace" do
      _, opts = Hwaro::Content::Processors::FenceOptions.parse("crystal {linenos")
      opts.should be_nil
    end

    it "returns nil opts for a key with an empty value" do
      _, opts = Hwaro::Content::Processors::FenceOptions.parse("crystal {a=}")
      opts.should be_nil
    end

    it "returns nil opts for a malformed pair (no '=')" do
      _, opts = Hwaro::Content::Processors::FenceOptions.parse("crystal {a b}")
      opts.should be_nil
    end

    it "is case-insensitive on the linenos value" do
      _, opts = Hwaro::Content::Processors::FenceOptions.parse("crystal {linenos=TRUE}")
      opts.not_nil!.linenos.should be_true
    end

    it "rejects linenostart=0 as invalid (line numbers are 1-based)" do
      # A literal 0 used to be silently clamped up to 1 — renumbering from a
      # line the author never asked for — while negatives were rejected.
      # Now 0 is dropped like any other invalid value; with no other
      # recognized option the `{...}` block doesn't activate at all.
      lang, opts = Hwaro::Content::Processors::FenceOptions.parse("crystal {linenostart=0}")
      lang.should eq("crystal")
      opts.should be_nil
    end

    it "ignores linenostart=0 while honoring other options in the block" do
      _, opts = Hwaro::Content::Processors::FenceOptions.parse("crystal {linenos=true linenostart=0}")
      opts.not_nil!.linenos.should be_true
      opts.not_nil!.linenostart.should eq(1)
    end

    it "drops an hl_lines item containing 0" do
      _, opts = Hwaro::Content::Processors::FenceOptions.parse(%(crystal {hl_lines="0,3"}))
      opts.not_nil!.hl_lines.should eq([{3, 3}])
    end

    it "parses a bare (unquoted) hl_lines value" do
      _, opts = Hwaro::Content::Processors::FenceOptions.parse(%(crystal {hl_lines=3}))
      opts.not_nil!.hl_lines.should eq([{3, 3}])
    end

    it "ignores a reversed hl_lines range" do
      _, opts = Hwaro::Content::Processors::FenceOptions.parse(%(crystal {hl_lines="9-2"}))
      opts.should be_nil
    end

    it "stores a huge hl_lines range as a single tuple (no per-line memory blowup)" do
      _, opts = Hwaro::Content::Processors::FenceOptions.parse(%(crystal {hl_lines="1-100000"}))
      opts.not_nil!.hl_lines.should eq([{1, 100_000}])
    end
  end
end

describe Hwaro::Content::Processors::LineWrapper do
  describe ".split_lines" do
    it "re-opens a span class that carries a token value across a newline" do
      html = %(<span class="hljs-string">a\nb</span>)
      lines = Hwaro::Content::Processors::LineWrapper.split_lines(html)
      lines.should eq([%(<span class="hljs-string">a</span>), %(<span class="hljs-string">b</span>)])
    end

    it "does not emit an empty re-opened span for a token whose value ends exactly at a newline" do
      html = %(<span class="hljs-string">line1\n</span>line2)
      lines = Hwaro::Content::Processors::LineWrapper.split_lines(html)
      lines.should eq([%(<span class="hljs-string">line1</span>), "line2"])
    end

    it "splits bare (unspanned) text on newlines" do
      lines = Hwaro::Content::Processors::LineWrapper.split_lines("a\nb\nc")
      lines.should eq(["a", "b", "c"])
    end

    it "keeps the last line when there is no trailing newline" do
      lines = Hwaro::Content::Processors::LineWrapper.split_lines("line1\nline2")
      lines.should eq(["line1", "line2"])
    end

    it "drops the trailing empty element when input ends with a newline" do
      lines = Hwaro::Content::Processors::LineWrapper.split_lines("line1\nline2\n")
      lines.should eq(["line1", "line2"])
    end
  end

  describe ".wrap" do
    it "numbers lines starting from linenostart" do
      opts = Hwaro::Content::Processors::FenceOptions::Options.new
      result = Hwaro::Content::Processors::LineWrapper.wrap("a\nb\n", true, 5, opts)
      result.should contain(%(<span class="line"><span class="ln" aria-hidden="true">5 </span>a</span>\n))
      result.should contain(%(<span class="line"><span class="ln" aria-hidden="true">6 </span>b</span>\n))
    end

    it "pads the gutter width when crossing a digit boundary (9 -> 10)" do
      opts = Hwaro::Content::Processors::FenceOptions::Options.new
      result = Hwaro::Content::Processors::LineWrapper.wrap("a\nb\n", true, 9, opts)
      result.should contain(%(<span class="ln" aria-hidden="true"> 9 </span>))
      result.should contain(%(<span class="ln" aria-hidden="true">10 </span>))
    end

    it "highlights physical lines independent of linenostart" do
      opts = Hwaro::Content::Processors::FenceOptions::Options.new(hl_lines: [{1, 1}])
      result = Hwaro::Content::Processors::LineWrapper.wrap("a\nb\n", true, 5, opts)
      result.should contain(%(<span class="line hl"><span class="ln" aria-hidden="true">5 </span>a</span>\n))
      result.should contain(%(<span class="line"><span class="ln" aria-hidden="true">6 </span>b</span>\n))
    end
  end
end

describe "fence options rendering (server mode)" do
  it "wraps plain escaped lines for options on an unrecognized language" do
    Hwaro::Content::Processors::SyntaxHighlighter.server_mode = true
    content = "```nosuchlang {linenos=true}\nplain <tag>\n```"
    html = Hwaro::Content::Processors::SyntaxHighlighter.render(content, highlight: true)
    html.should contain(%(<span class="line"><span class="ln" aria-hidden="true">1 </span>plain &lt;tag&gt;</span>))
    html.should_not contain("hljs-")
  ensure
    reset_fence_options_state
  end

  it "strips the options block from the <code> class for the no-space form" do
    Hwaro::Content::Processors::SyntaxHighlighter.server_mode = true
    html = Hwaro::Content::Processors::SyntaxHighlighter.render(
      "```python{linenos=true}\ndef f():\n    pass\n```", highlight: true)
    html.should contain(%(class="language-python hljs"))
    html.should_not contain("language-python{linenos")
  ensure
    reset_fence_options_state
  end

  it "emits no language class for a language-less options fence" do
    Hwaro::Content::Processors::SyntaxHighlighter.server_mode = true
    html = Hwaro::Content::Processors::SyntaxHighlighter.render(
      "```{linenos=true}\nplain\n```", highlight: true)
    html.should_not contain("language-{linenos")
    html.should_not contain("language-")
  ensure
    reset_fence_options_state
  end

  it "an explicit {linenos=false} fully cancels the global default" do
    Hwaro::Content::Processors::SyntaxHighlighter.server_mode = true
    Hwaro::Content::Processors::SyntaxHighlighter.default_line_numbers = true
    opted_out = Hwaro::Content::Processors::SyntaxHighlighter.render(
      "```python {linenos=false}\ndef f():\n    pass\n```", highlight: true)
    Hwaro::Content::Processors::SyntaxHighlighter.default_line_numbers = false
    baseline = Hwaro::Content::Processors::SyntaxHighlighter.render(
      "```python\ndef f():\n    pass\n```", highlight: true)
    opted_out.should eq(baseline)
  ensure
    reset_fence_options_state
  end

  it "leaves an indented code block untouched by the global line_numbers default" do
    Hwaro::Content::Processors::SyntaxHighlighter.server_mode = true
    Hwaro::Content::Processors::SyntaxHighlighter.default_line_numbers = true
    html = Hwaro::Content::Processors::SyntaxHighlighter.render("    indented code\n    more code\n", highlight: true)
    html.should_not contain(%(<span class="line"))
  ensure
    reset_fence_options_state
  end
end

describe Hwaro::Content::Processors::ServerHighlighter do
  describe ".highlight" do
    it "escapes HTML special characters in highlighted output" do
      html = Hwaro::Content::Processors::ServerHighlighter.highlight(%q(puts "<b>&"), "crystal")
      html.should_not be_nil
      html.not_nil!.should contain("&lt;b&gt;")
      html.not_nil!.should_not contain("<b>")
    end

    it "sanitizes invalid UTF-8 in tokenized output to U+FFFD like HTML.escape" do
      # The tokenizer's Error fallback emits unmatched input one BYTE at a
      # time, so a multi-byte character no rule matches arrives as lone
      # lead/continuation bytes — an invalid-UTF-8 token value. The old
      # unconditional HTML.escape replaced those bytes with U+FFFD; the
      # needs_html_escape? fast path must preserve that instead of copying
      # the raw bytes into the output HTML.
      code = String.new(Bytes[0x68_u8, 0x69_u8, 0x20_u8, 0xE2_u8, 0x0A_u8]) # "hi " + lone lead byte + "\n"
      html = Hwaro::Content::Processors::ServerHighlighter.highlight(code, "json")
      html.should_not be_nil
      html.not_nil!.valid_encoding?.should be_true
      # The lone 0xE2 must surface as U+FFFD — this both pins the
      # sanitization and proves the invalid-byte path was exercised.
      html.not_nil!.should contain("�")
    end
  end
end
