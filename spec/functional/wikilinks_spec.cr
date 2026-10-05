require "../support/build_helper"

# =============================================================================
# `[markdown] wikilinks` (wikilinks, image embeds, foldable callouts) and
# `[content] backlinks` (page.backlinks) through real builds, including the
# warm `--cache` and serve paths that must re-render a page whose backlinks
# moved.
# =============================================================================

private WIKI_CONFIG = <<-TOML
  title = "Vault"
  base_url = "http://localhost"

  [markdown]
  wikilinks = true

  [content]
  backlinks = true
  TOML

private WIKI_TEMPLATES = {
  "page.html"    => "{{ content }}|BL:{% for b in page.backlinks %}{{ b.title }};{% endfor %}",
  "section.html" => "{{ content }}",
}

private def wiki_main(dir : String, path : String) : String
  File.read(File.join(dir, "public", path, "index.html"))
end

private def wiki_build(cache : Bool = false, serve : Bool = false) : {Hwaro::Core::Build::Builder, Hwaro::Config::Options::BuildOptions}
  options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: cache, highlight: false)
  options.serve_mode = serve
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder.run(options)
  {builder, options}
end

# B lists its backlinks; A links to B; `pad` pages keep A and B out of each
# other's prev/next, so the reading-order rule can't be what re-renders B.
private def write_backlink_site
  File.write("config.toml", WIKI_CONFIG)
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", WIKI_TEMPLATES["page.html"])
  FileUtils.mkdir_p("content")
  File.write("content/a.md", "---\ntitle: A\ndate: 2024-01-01\n---\nSee [[b]].\n")
  File.write("content/b.md", "---\ntitle: B\ndate: 2024-01-09\n---\nB body\n")
  3.times { |i| File.write("content/pad#{i}.md", "---\ntitle: Pad #{i}\ndate: 2024-01-0#{i + 3}\n---\npad\n") }
end

describe "wikilinks build" do
  it "renders every form, with heading fragments equal to the heading ids (broken_anchors = error)" do
    build_site(
      WIKI_CONFIG + "\n[links]\nbroken_anchors = \"error\"\nbroken_internal = \"error\"\n",
      content_files: {
        "notes/setup.md" => "---\ntitle: Setup\n---\n## Install the Tool\n\nText\n",
        "notes/src.md"   => "---\ntitle: Src\n---\n[[Setup]] [[setup|go]] [[Setup#Install the Tool]] [[notes/setup#Install the Tool|x]] [[#Local]]\n\n## Local\n\n`[[Setup]]`\n\n```\n[[Setup]]\n```\n",
      },
      template_files: WIKI_TEMPLATES,
    ) do |dir|
      html = wiki_main(dir, "notes/src")
      html.should contain(%(<a href="/notes/setup/">Setup</a>))
      html.should contain(%(<a href="/notes/setup/">go</a>))
      html.should contain(%(<a href="/notes/setup/#install-the-tool">Setup &gt; Install the Tool</a>))
      html.should contain(%(<a href="/notes/setup/#install-the-tool">x</a>))
      html.should contain(%(<a href="#local">Local</a>))
      html.should contain(%(<code>[[Setup]]</code>))
      html.should contain("<pre><code>[[Setup]]\n</code></pre>")
      wiki_main(dir, "notes/setup").should contain(%(id="install-the-tool"))
    end
  end

  it "fails broken_anchors = error on a wikilink to a missing heading" do
    ex = expect_raises(Hwaro::HwaroError) do
      build_site(
        WIKI_CONFIG + "\n[links]\nbroken_anchors = \"error\"\n",
        content_files: {
          "setup.md" => "---\ntitle: Setup\n---\n## Real\n",
          "src.md"   => "---\ntitle: Src\n---\n[[Setup#Nope]]\n",
        },
        template_files: WIKI_TEMPLATES,
      ) { }
    end
    ex.message.not_nil!.should contain(%(src.md → @/setup.md#nope → missing id "nope"))
  end

  it "warns about an unresolved wikilink and renders it as a missing span" do
    log = with_captured_log do
      build_site(
        WIKI_CONFIG,
        content_files: {"src.md" => "---\ntitle: Src\n---\n[[Ghost|Boo]]\n"},
        template_files: WIKI_TEMPLATES,
      ) do |dir|
        wiki_main(dir, "src").should contain(%(<span class="wikilink wikilink-missing">Boo</span>))
      end
    end
    log.should contain("Wikilink '[[Ghost|Boo]]' in 'src.md' could not be resolved: page not found.")
  end

  it "fails broken_internal = error on an unresolved wikilink" do
    ex = expect_raises(Hwaro::HwaroError) do
      build_site(
        WIKI_CONFIG + "\n[links]\nbroken_internal = \"error\"\n",
        content_files: {"src.md" => "---\ntitle: Src\n---\n[[Ghost]] ![[gone.png]]\n"},
        template_files: WIKI_TEMPLATES,
      ) { }
    end
    message = ex.message.not_nil!
    message.should contain("2 broken internal links")
    message.should contain("src.md → [[Ghost]] (page not found)")
    message.should contain("src.md → ![[gone.png]] (file not found)")
  end

  it "warns once about an ambiguous target, naming every candidate" do
    log = with_captured_log do
      build_site(
        WIKI_CONFIG,
        content_files: {
          "a/setup.md" => "---\ntitle: A Setup\n---\n",
          "b/setup.md" => "---\ntitle: B Setup\n---\n",
          "src.md"     => "---\ntitle: Src\n---\n[[setup]] and [[setup]]\n",
        },
        template_files: WIKI_TEMPLATES,
      ) do |dir|
        wiki_main(dir, "src").should contain(%(<a href="/a/setup/">setup</a>))
      end
    end
    log.scan("Ambiguous wikilink '[[setup]]' in 'src.md' matches a/setup.md, b/setup.md; using 'a/setup.md'.").size.should eq(1)
  end

  it "resolves image embeds from the bundle and static/, sized, and withholds a draft bundle's image" do
    build_site(
      WIKI_CONFIG,
      content_files: {
        "trip/index.md"    => "---\ntitle: Trip\n---\n![[photo.png|300x200]] ![[photo.png|A view]] ![[logo.svg|64]] ![[secret.png]]\n",
        "trip/photo.png"   => "png",
        "draft/index.md"   => "---\ntitle: Draft\ndraft: true\n---\n",
        "draft/secret.png" => "png",
      },
      static_files: {"img/logo.svg" => "<svg/>"},
      template_files: WIKI_TEMPLATES,
    ) do |dir|
      html = wiki_main(dir, "trip")
      html.should contain(%(<img src="photo.png" alt="photo.png" width="300" height="200" />))
      html.should contain(%(<img src="photo.png" alt="A view" />))
      html.should contain(%(<img src="/img/logo.svg" alt="logo.svg" width="64" />))
      html.should contain(%(<span class="wikilink wikilink-missing">secret.png</span>))
    end
  end

  it "folds `-`/`+` callouts into <details> and leaves plain alerts unchanged" do
    build_site(
      WIKI_CONFIG,
      content_files: {"c.md" => "---\ntitle: C\n---\n> [!TIP]- Closed\n> body one\n\n> [!NOTE]+ Open\n> body two\n\n> [!WARNING]\n> plain\n"},
      template_files: WIKI_TEMPLATES,
    ) do |dir|
      html = wiki_main(dir, "c")
      html.should contain(%(<details class="admonition admonition-tip">\n<summary class="admonition-title">Closed</summary>\n<p>body one</p>\n</details>))
      html.should contain(%(<details class="admonition admonition-note" open>\n<summary class="admonition-title">Open</summary>))
      html.should contain(%(<div class="admonition admonition-warning">\n<p class="admonition-title">Warning</p>\n<p>plain</p>\n</div>))
    end
  end

  it "leaves the syntax alone with the flags off" do
    build_site(
      "title = \"Vault\"\nbase_url = \"http://localhost\"\n",
      content_files: {
        "a.md" => "---\ntitle: A\n---\n[[b]] ![[x.png|300]]\n\n> [!TIP]- Closed\n> body\n",
        "b.md" => "---\ntitle: B\n---\n",
      },
      template_files: {"page.html" => "{{ content }}|{{ page.backlinks is defined }}"},
    ) do |dir|
      html = wiki_main(dir, "a")
      html.should contain("[[b]] ![[x.png|300]]")
      html.should contain(%(<div class="admonition admonition-tip">))
      wiki_main(dir, "b").should contain("|false")
    end
  end
end

describe "wikilinks review regressions" do
  it "drops a just-drafted page from the index before a serve rebuild renders its linkers" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", WIKI_CONFIG)
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ content }}|{{ page.lower.title }}")
        FileUtils.mkdir_p("content")
        File.write("content/a.md", "---\ntitle: A\ndate: 2024-01-01\n---\nA\n")
        File.write("content/c.md", "---\ntitle: C\ndate: 2024-01-02\n---\nSee [[a]].\n")
        builder, options = wiki_build(serve: true)
        File.read("public/c/index.html").should contain(%(<a href="/a/">a</a>))

        File.write("content/a.md", "---\ntitle: A\ndate: 2024-01-01\ndraft: true\n---\nA\n")
        with_captured_log { builder.run_incremental(["content/a.md"], options).should be_true }
        html = File.read("public/c/index.html")
        html.should_not contain("@/a.md")
        html.should contain(%(<span class="wikilink wikilink-missing">a</span>))
      end
    end
  end

  it "skips a symlink loop and out-of-project links when indexing embed targets" do
    Dir.mktmpdir do |outside|
      File.write(File.join(outside, "leak.png"), "png")
      build_site(
        WIKI_CONFIG,
        content_files: {"p.md" => "---\ntitle: P\n---\n![[nothere.png]] ![[leak.png]] ![[ok.png]]\n"},
        static_files: {"ok.png" => "png"},
        template_files: WIKI_TEMPLATES,
      ) do |dir|
        File.symlink("loop", File.join(dir, "static", "loop"))
        File.symlink(File.join(outside, "leak.png"), File.join(dir, "static", "leak.png"))
        with_captured_log { wiki_build }
        html = wiki_main(dir, "p")
        html.should contain(%(<img src="/ok.png" alt="ok.png" />))
        html.should contain(%(<span class="wikilink wikilink-missing">leak.png</span>))
        html.should contain(%(<span class="wikilink wikilink-missing">nothere.png</span>))
      end
    end
  end

  it "re-renders an `@/a%20b.md` linker on a warm --cache build when the target moves (flags off)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", "title = \"x\"\nbase_url = \"http://localhost\"\n")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ content }}")
        FileUtils.mkdir_p("content")
        File.write("content/src.md", "---\ntitle: Src\n---\n[x](@/a%20b.md)\n")
        File.write("content/a b.md", "---\ntitle: AB\nslug: s1\n---\nab\n")
        wiki_build(cache: true)
        File.read("public/src/index.html").should contain(%(href="/s1/"))
        File.write("content/a b.md", "---\ntitle: AB\nslug: s2\n---\nab\n")
        wiki_build(cache: true)
        File.read("public/src/index.html").should contain(%(href="/s2/"))
      end
    end
  end

  it "re-renders an `<@/a b.md>` linker on a warm --cache build when the target moves (flags off)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", "title = \"x\"\nbase_url = \"http://localhost\"\n")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ content }}")
        FileUtils.mkdir_p("content")
        File.write("content/src.md", "---\ntitle: Src\n---\n[y](<@/a b.md>)\n")
        File.write("content/a b.md", "---\ntitle: AB\nslug: s1\n---\nab\n")
        wiki_build(cache: true)
        File.read("public/src/index.html").should contain(%(href="/s1/"))
        File.write("content/a b.md", "---\ntitle: AB\nslug: s2\n---\nab\n")
        wiki_build(cache: true)
        File.read("public/src/index.html").should contain(%(href="/s2/"))
      end
    end
  end

  it "keeps a link between two fenced braces as a backlink" do
    build_site(
      WIKI_CONFIG,
      content_files: {
        "a.md"   => "---\ntitle: A\n---\n{{ badge(text=\"new\") }}\n\n```rust\nprintln!(\"{{\");\n```\n\nSee [[foo]]\n\n```rust\nprintln!(\"}}\");\n```\n",
        "foo.md" => "---\ntitle: Foo\n---\nfoo\n",
      },
      template_files: WIKI_TEMPLATES.merge({"shortcodes/badge.html" => "<b>{{ text }}</b>"}),
    ) do |dir|
      wiki_main(dir, "a").should contain(%(<a href="/foo/">foo</a>))
      wiki_main(dir, "foo").should contain("|BL:A;")
    end
  end

  it "does not count a link in a block shortcode written on its opener line" do
    build_site(
      WIKI_CONFIG,
      content_files: {
        "a.md"   => "---\ntitle: A\n---\nA {% note() %}See [[foo]] inline{% end %} B\n",
        "c.md"   => "---\ntitle: C\n---\n{% note() %}See [[foo]]\nmore\n{% end %}\n",
        "foo.md" => "---\ntitle: Foo\n---\nfoo\n",
      },
      template_files: WIKI_TEMPLATES.merge({"shortcodes/note.html" => "<div class=\"note\">{{ body }}</div>"}),
    ) do |dir|
      wiki_main(dir, "a").should contain("See [[foo]] inline")
      wiki_main(dir, "foo").should contain("|BL:")
      wiki_main(dir, "foo").should_not contain("A;")
      wiki_main(dir, "foo").should_not contain("C;")
    end
  end

  it "warns about an ambiguous wikilink once per serve session" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_backlink_site
        FileUtils.mkdir_p("content/x")
        FileUtils.mkdir_p("content/y")
        File.write("content/x/foo.md", "---\ntitle: XF\n---\n")
        File.write("content/y/foo.md", "---\ntitle: YF\n---\n")
        File.write("content/src.md", "---\ntitle: Src\n---\n[[foo]]\n")
        built = nil
        with_captured_log { built = wiki_build(serve: true) }
        builder, options = built.not_nil!
        File.write("content/pad0.md", "---\ntitle: Pad edited\ndate: 2024-01-03\n---\npad\n")
        log = with_captured_log { builder.run_incremental(["content/pad0.md"], options).should be_true }
        log.should_not contain("Ambiguous wikilink")
      end
    end
  end

  it "does not count links inside a shortcode body as backlinks" do
    build_site(
      WIKI_CONFIG,
      content_files: {
        "a.md" => "---\ntitle: A\n---\n{% note() %}\nsee [[b]]\n{% end %}\n",
        "b.md" => "---\ntitle: B\n---\nB\n",
      },
      template_files: WIKI_TEMPLATES.merge({"shortcodes/note.html" => "<aside>{{ body }}</aside>"}),
    ) do |dir|
      wiki_main(dir, "b").should contain("|BL:")
      wiki_main(dir, "b").should_not contain("A;")
    end
  end
end

describe "page.backlinks" do
  it "lists same-language published linkers, newest first, without self-links, duplicates or drafts" do
    build_site(
      "default_language = \"en\"\n" + WIKI_CONFIG + "\n[languages.ko]\nname = \"Korean\"\n",
      content_files: {
        "target.md"    => "---\ntitle: Target\n---\n[[target]] self\n",
        "old.md"       => "---\ntitle: Old\ndate: 2023-01-01\n---\n[[target]] [[Target]] [t](@/target.md)\n",
        "new.md"       => "---\ntitle: New\ndate: 2024-01-01\n---\n[t](/target/)\n",
        "undated.md"   => "---\ntitle: Undated\n---\n<a href=\"../target/\">t</a>\n",
        "draft.md"     => "---\ntitle: Draft\ndraft: true\n---\n[[target]]\n",
        "code.md"      => "---\ntitle: Code\n---\n`[[target]]`\n",
        "target.ko.md" => "---\ntitle: KoTarget\n---\n",
        "ko.md"        => "---\ntitle: Ko\n---\n[[target]] ko only\n",
        "ko.ko.md"     => "---\ntitle: KoLinker\n---\n[[target]]\n",
      },
      template_files: WIKI_TEMPLATES,
    ) do |dir|
      wiki_main(dir, "target").should contain("|BL:New;Old;Ko;Undated;")
      wiki_main(dir, "ko/target").should contain("|BL:KoLinker;")
    end
  end

  it "re-renders the linked page on a warm --cache build when a link is removed" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_backlink_site
        wiki_build(cache: true)
        File.read("public/b/index.html").should contain("|BL:A;")
        wiki_build(cache: true)

        File.write("content/a.md", "---\ntitle: A\ndate: 2024-01-01\n---\nNo link now.\n")
        wiki_build(cache: true)
        File.read("public/b/index.html").should contain("|BL:")
        File.read("public/b/index.html").should_not contain("A;")

        File.write("content/a.md", "---\ntitle: A2\ndate: 2024-01-01\n---\n[back](@/b.md)\n")
        wiki_build(cache: true)
        File.read("public/b/index.html").should contain("|BL:A2;")
      end
    end
  end

  it "re-renders the linked page on a serve incremental rebuild" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_backlink_site
        builder, options = wiki_build(serve: true)
        File.read("public/b/index.html").should contain("|BL:A;")

        File.write("content/a.md", "---\ntitle: A\ndate: 2024-01-01\n---\nNo link now.\n")
        builder.run_incremental(["content/a.md"], options).should be_true
        File.read("public/b/index.html").should_not contain("A;")

        File.write("content/a.md", "---\ntitle: Renamed\ndate: 2024-01-01\n---\n[[b]]\n")
        builder.run_incremental(["content/a.md"], options).should be_true
        File.read("public/b/index.html").should contain("|BL:Renamed;")
      end
    end
  end
end
