require "./support/build_helper"

# =============================================================================
# Build-time syntax highlighting ([highlight] mode = "server", the default)
#
# Tartrazine lexers tokenize fenced code blocks at build time and emit spans
# with Highlight.js-compatible classes, so hljs theme CSS keeps working while
# no JavaScript ships. mode = "client" opts back into browser-side Highlight.js.
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
  Hwaro::Content::Processors::SyntaxHighlighter.default_line_numbers = false
  Hwaro::Content::Processors::SyntaxHighlighter.default_copy = false
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

  it "client mode keeps JS injection and emits no spans" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [highlight]
      enabled = true
      mode = "client"
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

  it "warns and keeps the server default for an unknown mode value" do
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
      html.should_not contain("highlight.min.js")
      html.should contain(%(<span class="hljs-))
    end
  ensure
    reset_highlight_mode
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

# =============================================================================
# Fence options ({linenos=true, hl_lines="...", linenostart=N}) — F5
# =============================================================================

FENCE_OPTIONS_CONTENT = <<-MD
  +++
  title = "Code"
  +++
  ```python {linenos=true, hl_lines="2"}
  def main():
      return 42  # answer
  ```
  MD

describe "Fence options — server mode" do
  it "wraps lines with gutter numbers and marks the requested hl_lines" do
    build_site(
      SERVER_HIGHLIGHT_CONFIG,
      content_files: {"index.md" => FENCE_OPTIONS_CONTENT},
      template_files: {"page.html" => HIGHLIGHT_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<span class="line">))
      html.should contain(%(<span class="line hl">))
      html.should contain(%(<span class="ln" aria-hidden="true">1 </span>))
      html.should contain(%(<span class="ln" aria-hidden="true">2 </span>))
      # Pre-existing exact hljs-span assertions still hold inside line spans.
      html.should contain(%(<span class="hljs-keyword">def</span>))
      html.should contain(%(<span class="hljs-number">42</span>))
      html.should contain(%(<span class="hljs-comment"># answer</span>))
    end
  ensure
    reset_highlight_mode
  end

  it "re-opens a token's class on every physical line it spans" do
    content = <<-MD
      +++
      title = "Code"
      +++
      ```python {linenos=true}
      x = """abc
      def"""
      ```
      MD

    build_site(
      SERVER_HIGHLIGHT_CONFIG,
      content_files: {"index.md" => content},
      template_files: {"page.html" => HIGHLIGHT_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      code_lines = html.split("\n").select(&.includes?(%(<span class="line)))
      code_lines.size.should eq(2)
      code_lines.all?(&.includes?("hljs-string")).should be_true
    end
  ensure
    reset_highlight_mode
  end

  it "leaves mermaid fences on the legacy (no line-span) path even with linenos requested" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [highlight]
      enabled = true
      mode = "server"

      [markdown]
      mermaid = true
      TOML

    content = <<-MD
      +++
      title = "Diagram"
      +++
      ```mermaid {linenos=true}
      graph LR
        A --> B
      ```
      MD

    build_site(
      config,
      content_files: {"index.md" => content},
      template_files: {"page.html" => HIGHLIGHT_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<div class="mermaid">))
      html.should_not contain(%(<span class="line))
      html.should_not contain("<pre>")
    end
  ensure
    reset_highlight_mode
  end

  it "client mode emits data-* attributes on <pre> instead of line spans, and keeps the JS runtime" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [highlight]
      enabled = true
      mode = "client"
      TOML

    build_site(
      config,
      content_files: {"index.md" => FENCE_OPTIONS_CONTENT},
      template_files: {"page.html" => HIGHLIGHT_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain(%(data-linenos="true"))
      html.should contain(%(data-hl-lines="2"))
      html.should_not contain(%(<span class="line))
      html.should contain("highlight.min.js")
      # Body stays exactly the plain escaped legacy text — no hljs spans at all
      # (client mode never tokenizes).
      html.should contain(%(<code class="language-python hljs">def main():))
    end
  ensure
    reset_highlight_mode
  end

  it "[highlight] copy = true marks code blocks, ships the runtime once, and leaves mermaid alone" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [markdown]
      mermaid = true

      [highlight]
      enabled = true
      mode = "server"
      copy = true
      TOML

    content = <<-MD
      +++
      title = "Code"
      +++
      ```python
      def main():
          return 42
      ```

      ```mermaid
      graph LR
        A --> B
      ```
      MD

    build_site(
      config,
      content_files: {"index.md" => content},
      template_files: {"page.html" => HIGHLIGHT_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<pre data-copy="true">))
      # The inline runtime rides {{ highlight_js }} — exactly once per page.
      html.scan("code-copy-btn").size.should be > 0
      html.scan(%(pre[data-copy])).size.should eq(1)
      html.should_not contain("highlight.min.js")
      # Mermaid's <pre> stays bare, so postprocess_mermaid still rewrites it.
      html.should contain(%(<div class="mermaid">))
      html.should_not contain("language-mermaid")
    end
  ensure
    reset_highlight_mode
  end

  it "per-fence {copy=true} with the global default off ships the runtime only on opted-in pages" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [highlight]
      enabled = true
      mode = "server"
      TOML

    opted = <<-MD
      +++
      title = "Opted"
      +++
      ```python {copy=true}
      pass
      ```
      MD

    plain = <<-MD
      +++
      title = "Plain"
      +++
      ```python
      pass
      ```
      MD

    build_site(
      config,
      content_files: {"opted.md" => opted, "plain.md" => plain},
      template_files: {"page.html" => HIGHLIGHT_TEMPLATE},
      highlight: true,
    ) do
      # The opted-in page gets the runtime appended to its own
      # {{ highlight_js }} — the site-wide value ships nothing.
      opted_html = File.read("public/opted/index.html")
      opted_html.should contain(%(<pre data-copy="true">))
      opted_html.scan("code-copy-btn").size.should be > 0

      # Pages without an opted-in fence stay JavaScript-free.
      plain_html = File.read("public/plain/index.html")
      plain_html.should_not contain("data-copy")
      plain_html.should_not contain("code-copy-btn")
    end
  ensure
    reset_highlight_mode
  end

  it "the global [highlight] line_numbers default wraps a bare fence, and a per-block override opts out" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [highlight]
      enabled = true
      mode = "server"
      line_numbers = true
      TOML

    content = <<-MD
      +++
      title = "Code"
      +++
      ```python
      pass
      ```

      ```python {linenos=false}
      pass
      ```
      MD

    build_site(
      config,
      content_files: {"index.md" => content},
      template_files: {"page.html" => HIGHLIGHT_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      # The bare fence picks up the global default.
      html.should contain(%(<span class="ln" aria-hidden="true">1 </span>))
      # Exactly one wrapped block: the `{linenos=false}` fence opted out and
      # rendered through the byte-identical legacy path (no `.line` span).
      html.scan(/class="line"/).size.should eq(1)
    end
  ensure
    reset_highlight_mode
  end
end
