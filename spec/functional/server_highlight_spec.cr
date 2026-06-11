require "./support/build_helper"

# =============================================================================
# Build-time syntax highlighting ([highlight] mode = "server")
#
# Tartrazine lexers tokenize fenced code blocks at build time and emit spans
# with Highlight.js-compatible classes, so hljs theme CSS keeps working while
# no JavaScript ships. mode = "client" (default) keeps the previous behavior.
# =============================================================================

SERVER_HIGHLIGHT_CONFIG = <<-TOML
  title = "Test Site"
  base_url = "http://localhost"

  [highlight]
  enabled = true
  mode = "server"
  TOML

CODE_CONTENT = <<-MD
  +++
  title = "Code"
  +++
  ```python
  def main():
      return 42  # answer
  ```
  MD

HIGHLIGHT_TEMPLATE = "<head>{{ highlight_css }}{{ highlight_js }}</head><body>{{ content }}</body>"

private def reset_highlight_mode
  Hwaro::Content::Processors::SyntaxHighlighter.server_mode = false
end

describe "Server-side syntax highlighting" do
  it "emits hljs-class spans and no Highlight.js script tag" do
    build_site(
      SERVER_HIGHLIGHT_CONFIG,
      content_files: {"index.md" => CODE_CONTENT},
      template_files: {"page.html" => HIGHLIGHT_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<span class="hljs-keyword">def</span>))
      html.should contain(%(<span class="hljs-number">42</span>))
      html.should contain(%(<span class="hljs-comment"># answer</span>))
      # Theme CSS still loads; the JS runtime does not
      html.should contain("styles/github.min.css")
      html.should_not contain("highlight.min.js")
      html.should_not contain("hljs.highlightAll")
    end
  ensure
    reset_highlight_mode
  end

  it "keeps the language-* and hljs classes on the code element" do
    build_site(
      SERVER_HIGHLIGHT_CONFIG,
      content_files: {"index.md" => CODE_CONTENT},
      template_files: {"page.html" => HIGHLIGHT_TEMPLATE},
      highlight: true,
    ) do
      File.read("public/index.html").should contain(%(<code class="language-python hljs">))
    end
  ensure
    reset_highlight_mode
  end

  it "falls back to plain escaped output for unknown languages" do
    content = <<-MD
      +++
      title = "Code"
      +++
      ```nosuchlang
      plain <tag> & text
      ```
      MD

    build_site(
      SERVER_HIGHLIGHT_CONFIG,
      content_files: {"index.md" => content},
      template_files: {"page.html" => HIGHLIGHT_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain("plain &lt;tag&gt; &amp; text")
      html.should_not contain(%(<span class="hljs-))
    end
  ensure
    reset_highlight_mode
  end

  it "escapes HTML inside highlighted code" do
    content = <<-MD
      +++
      title = "Code"
      +++
      ```python
      s = "<script>alert(1)</script>"
      ```
      MD

    build_site(
      SERVER_HIGHLIGHT_CONFIG,
      content_files: {"index.md" => content},
      template_files: {"page.html" => HIGHLIGHT_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should_not contain("<script>alert(1)</script>")
      html.should contain("&lt;script&gt;")
    end
  ensure
    reset_highlight_mode
  end

  it "client mode (default) keeps JS injection and emits no spans" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [highlight]
      enabled = true
      TOML

    build_site(
      config,
      content_files: {"index.md" => CODE_CONTENT},
      template_files: {"page.html" => HIGHLIGHT_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain("highlight.min.js")
      html.should contain(%(<code class="language-python hljs">))
      html.should_not contain(%(<span class="hljs-))
    end
  end

  it "warns and falls back to client mode for an unknown mode value" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [highlight]
      enabled = true
      mode = "spaceship"
      TOML

    build_site(
      config,
      content_files: {"index.md" => CODE_CONTENT},
      template_files: {"page.html" => HIGHLIGHT_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain("highlight.min.js")
      html.should_not contain(%(<span class="hljs-))
    end
  end
end

describe "ServerHighlighter token mapping" do
  it "maps specific token types before generic prefixes" do
    Hwaro::Content::Processors::ServerHighlighter::TOKEN_CLASSES["KeywordType"].should eq("hljs-type")
    Hwaro::Content::Processors::ServerHighlighter::TOKEN_CLASSES["KeywordConstant"].should eq("hljs-literal")
    Hwaro::Content::Processors::ServerHighlighter::TOKEN_CLASSES["Keyword"].should eq("hljs-keyword")
    Hwaro::Content::Processors::ServerHighlighter::TOKEN_CLASSES["CommentPreproc"].should eq("hljs-meta")
    Hwaro::Content::Processors::ServerHighlighter::TOKEN_CLASSES["Comment"].should eq("hljs-comment")
    Hwaro::Content::Processors::ServerHighlighter::TOKEN_CLASSES["LiteralStringRegex"].should eq("hljs-regexp")
    Hwaro::Content::Processors::ServerHighlighter::TOKEN_CLASSES["Text"].should be_nil
  end

  it "highlights code directly and escapes values" do
    html = Hwaro::Content::Processors::ServerHighlighter.highlight("x = 1 < 2", "python").not_nil!
    html.should contain("&lt;")
    html.should contain(%(<span class="hljs-number">1</span>))
  end

  it "returns nil for unknown languages" do
    Hwaro::Content::Processors::ServerHighlighter.highlight("x", "definitely-not-a-language").should be_nil
  end
end
