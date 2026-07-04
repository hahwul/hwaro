require "./support/build_helper"

# =============================================================================
# Regression anchor: markdown syntax additions (F5 fence options, F9
# attributes, F10 inline markup) all ship behind new config flags that
# default to `false`. This spec locks in the literal HTML the pre-feature
# renderer produces for content that LOOKS LIKE it might trigger the new
# syntax (`++ins++`, `==mark==`, `~sub~`, `^sup^`, `{#id .class}` blocks) —
# with every new flag left at its default, none of it should be touched.
#
# These assertions were captured from a build running the code as it stood
# BEFORE any of the F5/F9/F10 work landed, and must keep passing after every
# commit in this series: any diff here means a flag-off code path stopped
# executing the exact pre-existing logic.
# =============================================================================

FLAGS_OFF_CONFIG = <<-TOML
  title = "Test Site"
  base_url = "http://localhost"

  [highlight]
  enabled = true
  mode = "client"
  TOML

FLAGS_OFF_CONTENT = <<-MD
  +++
  title = "Anchor"
  +++
  ++x++ ==y== ~z~ ^w^

  ## H {#a .b}

  ![i](p.png){.c}

  $==m==$

  ```text
  ++x++ ==y== ~z~ ^w^
  ## H {#a .b}
  ![i](p.png){.c}
  $==m==$
  ```

  ```crystal {linenos=true}
  def foo
    1
  end
  ```
  MD

FLAGS_OFF_TEMPLATE = "<body>{{ content }}</body>"

describe "Markdown syntax additions — flags-off byte identity" do
  it "leaves ++ins++ / ==mark== / ~sub~ / ^sup^ as literal paragraph text" do
    build_site(
      FLAGS_OFF_CONFIG,
      content_files: {"index.md" => FLAGS_OFF_CONTENT},
      template_files: {"page.html" => FLAGS_OFF_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain("<p>++x++ ==y== ~z~ ^w^</p>")
    end
  end

  it "leaves a heading with extra {#id .class}-like content untouched by heading_ids" do
    # `{#a .b}` is NOT the pure `{#id}` form HEADING_ID_RE matches, so it stays
    # in the heading text; TOC id generation still auto-slugs an id for it
    # (unrelated to the new `attributes` flag).
    build_site(
      FLAGS_OFF_CONFIG,
      content_files: {"index.md" => FLAGS_OFF_CONTENT},
      template_files: {"page.html" => FLAGS_OFF_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<h2 id="h-a-b">H {#a .b}</h2>))
    end
  end

  it "leaves an inline image with a trailing {.class}-like block as literal trailing text" do
    build_site(
      FLAGS_OFF_CONFIG,
      content_files: {"index.md" => FLAGS_OFF_CONTENT},
      template_files: {"page.html" => FLAGS_OFF_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<p><img src="p.png" alt="i" />{.c}</p>))
    end
  end

  it "leaves $==m==$ verbatim (math off, mark-lookalike untouched)" do
    build_site(
      FLAGS_OFF_CONFIG,
      content_files: {"index.md" => FLAGS_OFF_CONTENT},
      template_files: {"page.html" => FLAGS_OFF_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain("<p>$==m==$</p>")
    end
  end

  it "leaves fenced content containing new-syntax lookalikes byte-verbatim" do
    build_site(
      FLAGS_OFF_CONFIG,
      content_files: {"index.md" => FLAGS_OFF_CONTENT},
      template_files: {"page.html" => FLAGS_OFF_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain(<<-HTML
        <pre><code class="language-text hljs">++x++ ==y== ~z~ ^w^
        ## H {#a .b}
        ![i](p.png){.c}
        $==m==$
        </code></pre>
        HTML
      )
    end
  end

  it "a fence with a {linenos=true}-lookalike info string highlights normally with no line wrapping" do
    # `line_numbers` (highlight config) defaults to false, and this info
    # string produces valid fence options once F5 lands — but in CLIENT mode
    # (the default) the code body itself is untouched either way; only the
    # <pre> tag would gain new data-* attributes, which this assertion does
    # not probe. The class attribute and the escaped body stay byte-for-byte
    # identical to the pre-F5 renderer.
    build_site(
      FLAGS_OFF_CONFIG,
      content_files: {"index.md" => FLAGS_OFF_CONTENT},
      template_files: {"page.html" => FLAGS_OFF_TEMPLATE},
      highlight: true,
    ) do
      html = File.read("public/index.html")
      html.should contain(<<-HTML
        <code class="language-crystal hljs">def foo
          1
        end
        </code></pre>
        HTML
      )
    end
  end
end
