require "./support/build_helper"
require "../../src/content/hooks/image_hooks"

# =============================================================================
# Functional coverage for Hugo-style Markdown render hooks
# (templates/hooks/render-{link,image,heading,codeblock}.html).
#
# These drive the real Builder pipeline end to end (build_site) so the
# interaction with everything downstream of the raw HTML — internal link
# resolution, subpath prefixing, responsive images, TOC/anchor
# post-processing, mermaid, shortcodes, --cache invalidation, and feeds —
# is exercised the way a real site would hit it, not just the renderer in
# isolation (see spec/unit/render_hooks_spec.cr for that).
# =============================================================================

private def with_resize_map(map, &)
  prior = Hwaro::Content::Hooks::ImageHooks.resize_map
  Hwaro::Content::Hooks::ImageHooks.set_resize_map(map)
  begin
    yield
  ensure
    Hwaro::Content::Hooks::ImageHooks.set_resize_map(prior)
  end
end

describe "Render hooks: end-to-end overrides" do
  it "wraps an image in a <figure> via the image hook" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => %(+++\ntitle = "Home"\n+++\n![alt text](http://example.com/img.png "A caption"))},
      template_files: {
        "page.html"               => "<body>{{ content }}</body>",
        "hooks/render-image.html" => %(<figure><img src="{{ destination }}" alt="{{ alt }}" />{% if title is present %}<figcaption>{{ title }}</figcaption>{% endif %}</figure>),
      },
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<figure><img src="http://example.com/img.png" alt="alt text" /><figcaption>A caption</figcaption></figure>))
    end
  end

  it "renders links, headings, and codeblocks through their hooks in one page" do
    content = <<-MD
      +++
      title = "Home"
      +++
      [a link](http://example.com)

      ## A Heading

      ```python
      print(1)
      ```
      MD

    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => content},
      template_files: {
        "page.html"                   => "<body>{{ content }}</body>",
        "hooks/render-link.html"      => %(<a class="hook" href="{{ destination }}">{{ text }}</a>),
        "hooks/render-heading.html"   => %(<h{{ level }} id="{{ id }}" class="hook">{{ text }}</h{{ level }}>),
        "hooks/render-codeblock.html" => %(<pre class="hook"><code>{{ code }}</code></pre>),
      },
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<a class="hook" href="http://example.com">a link</a>))
      html.should contain(%(<h2 id="a-heading" class="hook">A Heading</h2>))
      html.should contain(%(<pre class="hook"><code>print(1)\n</code></pre>))
    end
  end
end

describe "Render hooks: link resolution interactions" do
  it "resolves an @/ internal link through the link hook" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "index.md" => %(+++\ntitle = "Home"\n+++\n[Other](@/other.md)),
        "other.md" => %(+++\ntitle = "Other"\n+++\nbody),
      },
      template_files: {
        "page.html"              => "<body>{{ content }}</body>",
        "hooks/render-link.html" => %(<a href="{{ destination }}">{{ text }}</a>),
      },
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<a href="/other/">Other</a>))
    end
  end

  it "prefixes a root-relative link with the subpath after the link hook renders it" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost/blog"
      TOML

    build_site(
      config,
      content_files: {"index.md" => %(+++\ntitle = "Home"\n+++\n[Posts](/posts/))},
      template_files: {
        "page.html"              => "<body>{{ content }}</body>",
        "hooks/render-link.html" => %(<a href="{{ destination }}">{{ text }}</a>),
      },
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<a href="/blog/posts/">Posts</a>))
    end
  end

  it "survives a shortcode placeholder inside link text" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => %(+++\ntitle = "Home"\n+++\n[{{ bold() }} link](http://example.com))},
      template_files: {
        "page.html"              => "<body>{{ content }}</body>",
        "shortcodes/bold.html"   => "<b>Bold</b>",
        "hooks/render-link.html" => %(<a class="hook" href="{{ destination }}">{{ text }}</a>),
      },
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<a class="hook" href="http://example.com"><b>Bold</b> link</a>))
    end
  end
end

describe "Render hooks: responsive images" do
  it "still applies srcset (from image_processing) and loading=lazy to a hook-rendered <img>" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [markdown]
      lazy_loading = true

      [image_processing]
      enabled = true
      TOML

    resize_map = {
      "/photo.png" => {400 => "/photo_400w.png", 800 => "/photo_800w.png"},
    }

    with_resize_map(resize_map) do
      build_site(
        config,
        content_files: {"index.md" => %(+++\ntitle = "Home"\n+++\n![alt](/photo.png))},
        template_files: {
          "page.html"               => "<body>{{ content }}</body>",
          "hooks/render-image.html" => %(<img src="{{ destination }}" alt="{{ alt }}" />),
        },
      ) do
        html = File.read("public/index.html")
        html.should contain(%(srcset="/photo_400w.png 400w, /photo_800w.png 800w"))
        html.should contain(%(loading="lazy"))
      end
    end
  end
end

describe "Render hooks: heading ids, TOC, and anchors" do
  it "keeps TOC and anchor links intact and respects a custom {#id} through the heading hook" do
    content = <<-MD
      +++
      title = "Home"
      toc = true
      insert_anchor_links = true
      +++
      ## Intro

      ## Details {#my-id}
      MD

    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => content},
      template_files: {
        "page.html"                 => "<body>{{ toc }}{{ content }}</body>",
        "hooks/render-heading.html" => %(<h{{ level }} id="{{ id }}">{{ text }}</h{{ level }}>),
      },
    ) do
      html = File.read("public/index.html")

      # {#my-id} is respected verbatim (not re-slugified).
      html.should contain(%(<h2 id="my-id">Details))
      # TOC was built from the hook-rendered headings.
      html.should contain(%(<a href="#intro">Intro</a>))
      html.should contain(%(<a href="#my-id">Details</a>))
      # Anchor links ("after" style) were inserted into the hook's heading.
      html.should contain(%(<h2 id="my-id">Details <a class="anchor" href="#my-id" aria-hidden="true">))
    end
  end
end

# Regression: with `[markdown] attributes = true`, a generalized
# `{#id .class key=val}` block leaves a `<!--HATTR:...-->` marker resolved
# in a post-pass AFTER the hook renders. The heading hook used to only
# extract the narrow `<!--HID:-->` marker, so its `id` variable held the
# auto-slug — any `#{id}` anchor the template emitted pointed at a fragment
# the final tag didn't have. The image hook path dropped the block entirely
# because the marker landed after the hook's `<figure>` wrapper, not glued
# to the `<img>`.
ATTR_CONFIG = <<-TOML
  title = "Test Site"
  base_url = "http://localhost"
  [markdown]
  attributes = true
  TOML

describe "Render hooks: generalized {#id .class} attribute blocks" do
  it "passes the block's custom id to the heading hook so its anchors match the final id" do
    content = <<-MD
      +++
      title = "Home"
      +++
      ## Section Title {#custom-id .highlight data-index=3}
      MD

    build_site(
      ATTR_CONFIG,
      content_files: {"index.md" => content},
      template_files: {
        "page.html"                 => "<body>{{ content }}</body>",
        "hooks/render-heading.html" => %(<h{{ level }} id="{{ id }}"><a class="anchor" href="\#{{ id }}">#</a>{{ text }}</h{{ level }}>),
      },
    ) do
      html = File.read("public/index.html")
      # The hook's `id` is the block's custom id, so the anchor it emits
      # matches the id postprocess_attributes applies to the tag.
      html.should contain(%(<a class="anchor" href="#custom-id">#</a>))
      html.should_not contain("section-title")
      # The block's class / data-* still merge onto the hooked <h2>.
      html.should contain(%(id="custom-id"))
      html.should contain(%(class="highlight"))
      html.should contain(%(data-index="3"))
      html.should_not contain("HATTR")
    end
  end

  it "merges an image attribute block onto an <img> a render-image hook wraps" do
    content = <<-MD
      +++
      title = "Home"
      +++
      ![A diagram](http://example.com/d.png){.responsive width=800}
      MD

    build_site(
      ATTR_CONFIG,
      content_files: {"index.md" => content},
      template_files: {
        "page.html"               => "<body>{{ content }}</body>",
        "hooks/render-image.html" => %(<figure><img src="{{ destination }}" alt="{{ alt }}" loading="lazy" /></figure>),
      },
    ) do
      html = File.read("public/index.html")
      # Attributes applied to the hook-wrapped <img>, not silently dropped.
      html.should contain(%(<figure><img src="http://example.com/d.png" alt="A diagram" loading="lazy" class="responsive" width="800" /></figure>))
      html.should_not contain("HATTR")
    end
  end

  # A plain (marker-less) image must NOT reach forward across a block boundary
  # and absorb a *later* element's attribute marker. This can happen when a
  # non-conformant render-heading hook emits non-`<hN>` markup, leaving the
  # heading's HATTR marker unconsumed by the heading pass — the image's gap
  # must stop at the closing `</p>` rather than swallow the whole heading.
  it "does not let a plain image absorb a following heading's attribute block" do
    content = <<-MD
      +++
      title = "Home"
      +++
      ![plain image](a.png)

      ## Heading Title {#hid .cls}
      MD

    build_site(
      ATTR_CONFIG,
      content_files: {"index.md" => content},
      template_files: {
        "page.html" => "<body>{{ content }}</body>",
        # Deliberately non-conformant: emits a <div>, not an <hN>, so the
        # heading pass can't consume the marker.
        "hooks/render-heading.html" => %(<div class="h{{ level }}">{{ text }}</div>),
      },
    ) do
      html = File.read("public/index.html")
      # The image stays clean — the heading's id/class did not leak onto it.
      html.should contain(%(<img src="a.png" alt="plain image" />))
      html.should_not contain(%(id="hid"))
      html.should_not contain(%(class="cls"))
      html.should_not contain("HATTR")
    end
  end
end

MERMAID_CONTENT = <<-MD
  +++
  title = "Home"
  +++
  ```mermaid
  graph TD;
  ```

  ```python
  print(1)
  ```
  MD

describe "Render hooks: mermaid interaction" do
  it "renders a mermaid div for the mermaid fence and the hook for everything else, when mermaid = true" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [markdown]
      mermaid = true
      TOML

    build_site(
      config,
      content_files: {"index.md" => MERMAID_CONTENT},
      template_files: {
        "page.html"                   => "<body>{{ content }}</body>",
        "hooks/render-codeblock.html" => %(<pre class="hook">{{ lang }}:{{ code }}</pre>),
      },
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<div class="mermaid">graph TD;))
      html.should contain(%(<pre class="hook">python:print(1)))
      html.should_not contain(%(<pre class="hook">mermaid:))
    end
  end

  it "runs the codeblock hook for the mermaid fence too, when mermaid = false" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [markdown]
      mermaid = false
      TOML

    build_site(
      config,
      content_files: {"index.md" => MERMAID_CONTENT},
      template_files: {
        "page.html"                   => "<body>{{ content }}</body>",
        "hooks/render-codeblock.html" => %(<pre class="hook">{{ lang }}:{{ code }}</pre>),
      },
    ) do
      html = File.read("public/index.html")
      html.should_not contain(%(<div class="mermaid">))
      html.should contain(%(<pre class="hook">mermaid:graph TD;))
      html.should contain(%(<pre class="hook">python:print(1)))
    end
  end
end

describe "Render hooks: --cache invalidation on a hook template edit" do
  it "re-renders the page after templates/hooks/render-link.html changes (template_deps on)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates/hooks")
        File.write("templates/page.html", "<body>{{ content }}</body>")
        File.write("templates/hooks/render-link.html", %(<a class="v1" href="{{ destination }}">{{ text }}</a>))
        File.write("content/index.md", %(+++\ntitle = "Home"\n+++\n[x](http://example.com)))

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        builder.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)
        File.read("public/index.html").should contain(%(class="v1"))

        File.write("templates/hooks/render-link.html", %(<a class="v2" href="{{ destination }}">{{ text }}</a>))
        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.read("public/index.html").should contain(%(class="v2"))
      end
    end
  end

  it "re-renders the page after templates/hooks/render-link.html changes (template_deps off)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", "#{BASIC_CONFIG}\n[build]\ntemplate_deps = false\n")
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates/hooks")
        File.write("templates/page.html", "<body>{{ content }}</body>")
        File.write("templates/hooks/render-link.html", %(<a class="v1" href="{{ destination }}">{{ text }}</a>))
        File.write("content/index.md", %(+++\ntitle = "Home"\n+++\n[x](http://example.com)))

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        builder.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)
        File.read("public/index.html").should contain(%(class="v1"))

        File.write("templates/hooks/render-link.html", %(<a class="v2" href="{{ destination }}">{{ text }}</a>))
        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.read("public/index.html").should contain(%(class="v2"))
      end
    end
  end
end

describe "Render hooks: feeds" do
  it "includes hook-rendered markup in the full-content feed body" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"
      description = "desc"

      [feeds]
      enabled = true
      full_content = true
      TOML

    build_site(
      config,
      content_files: {"posts/hello.md" => %(+++\ntitle = "Hello"\n+++\n[a link](http://example.com))},
      template_files: {
        "page.html"              => "<body>{{ content }}</body>",
        "section.html"           => "<body>section</body>",
        "hooks/render-link.html" => %(<a class="hook" href="{{ destination }}">{{ text }}</a>),
      },
    ) do
      feed = File.read("public/rss.xml")
      feed.should contain(%(class="hook"))
    end
  end
end

describe "Render hooks: no hooks configured — byte identity" do
  it "renders exactly the stock <a>/<img>/<hN>/<pre><code> markup with no templates/hooks/ present" do
    content = <<-MD
      +++
      title = "Home"
      +++
      [a link](http://example.com "T")

      ![alt text](http://example.com/img.png)

      ## A Heading

      ```python
      print(1)
      ```
      MD

    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => content},
      template_files: {"page.html" => "<body>{{ content }}</body>"},
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<a href="http://example.com" title="T">a link</a>))
      html.should contain(%(<img src="http://example.com/img.png" alt="alt text" />))
      html.should contain(%(<h2 id="a-heading">A Heading</h2>))
      html.should contain(%(<pre><code class="language-python">print(1)\n</code></pre>))
    end
  end
end
