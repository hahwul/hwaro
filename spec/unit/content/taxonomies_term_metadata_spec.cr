require "../../spec_helper"
require "../../support/build_helper"

# gh#891: `content/<taxonomy>/<slug>/_index.md` supplies the generated term
# page's title, description, extra, image and body instead of publishing a
# page that collides with (and is replaced by) the term page.

private CONFIG = <<-TOML
  title = "S"
  base_url = "https://ex.com"

  [[taxonomies]]
  name = "tags"
  feed = true

  [sitemap]
  enabled = true

  [search]
  enabled = true

  [llms]
  enabled = true
  TOML

private MULTILINGUAL_CONFIG = <<-TOML
  title = "S"
  base_url = "https://ex.com"
  default_language = "en"

  [languages.en]
  language_name = "English"

  [languages.ko]
  language_name = "Korean"
  taxonomies = ["tags"]

  [[taxonomies]]
  name = "tags"
  TOML

private TEMPLATES = {
  "page.html"          => %({{ page.title }}|{% for t in get_taxonomy(kind="tags").items %}{{ t.name }}={{ t.title }}/{{ t.description }};{% endfor %}),
  "taxonomy.html"      => "{{ content }}",
  "section.html"       => "SECTION={{ page.title }}|{{ content }}",
  "taxonomy_term.html" => "T={{ page.title }}|D={{ page.description }}|X={{ page.extra.icon }}|B={{ term_content }}|{{ og_tags }}|L={{ content }}",
}

private def post(title : String, tags : Array(String)) : String
  "+++\ntitle = \"#{title}\"\ndate = 2024-01-01\ntags = #{tags.to_json}\n+++\nbody\n"
end

private RUST_META = "+++\ntitle = \"Rust, the language\"\ndescription = \"All about Rust\"\n[extra]\nicon = \"crab\"\n+++\nIntro **bold** [p1](@/posts/p1.md)\n"

describe "taxonomy term _index.md metadata" do
  it "gives the term page the authored title, description, extra and body" do
    log = with_captured_log do
      build_site(CONFIG,
        content_files: {"posts/p1.md" => post("P1", ["Rust Lang", "go"]), "tags/rust-lang/_index.md" => RUST_META},
        template_files: TEMPLATES) do |dir|
        html = File.read(File.join(dir, "public/tags/rust-lang/index.html"))
        html.should contain("T=Rust, the language|D=All about Rust|X=crab|")
        html.should contain(%(B=<p>Intro <strong>bold</strong> <a href="/posts/p1/">p1</a></p>))
        html.should contain(%(<meta property="og:title" content="Rust, the language">))
        html.should contain(%(<meta property="og:description" content="All about Rust">))
        # The generated list keeps coming through `content`.
        html.should contain(%(L=<ul class="taxonomy-pages">\n  <li><a href="https://ex.com/posts/p1/">P1</a></li>))

        # A term without a file keeps the generated defaults.
        File.read(File.join(dir, "public/tags/go/index.html")).should start_with("T=Tags: go|D=|X=|B=|")

        # get_taxonomy() terms carry the authored title/description.
        File.read(File.join(dir, "public/posts/p1/index.html")).should eq("P1|go=/;Rust Lang=Rust, the language/All about Rust;")

        # One sitemap entry for the URL; not a search or llms.txt entry.
        sitemap = File.read(File.join(dir, "public/sitemap.xml"))
        sitemap.scan("https://ex.com/tags/rust-lang/</loc>").size.should eq(1)
        File.read(File.join(dir, "public/search.json")).should_not contain("Rust, the language")
        File.read(File.join(dir, "public/llms.txt")).should_not contain("Rust, the language")
        File.read(File.join(dir, "public/tags/rust-lang/rss.xml")).should contain("<title>S - Rust, the language</title>")
      end
    end
    log.should_not contain("replaces content page")
    log.should_not contain("rust-lang/_index.md")
  end

  it "matches the disambiguated slug, not the slugified directory name" do
    build_site(CONFIG,
      content_files: {
        "posts/p1.md"        => post("P1", ["C#", "C++"]),
        "tags/c-2/_index.md" => "+++\ntitle = \"C plus plus\"\n+++\n",
      },
      template_files: TEMPLATES) do |dir|
      File.read(File.join(dir, "public/tags/c/index.html")).should start_with("T=Tags: C#|")
      File.read(File.join(dir, "public/tags/c-2/index.html")).should start_with("T=C plus plus|")
    end
  end

  it "reads each language's file for that language's term page" do
    build_site(MULTILINGUAL_CONFIG,
      content_files: {
        "a.md"                   => post("A", ["rust"]),
        "a.ko.md"                => post("가", ["rust"]),
        "tags/rust/_index.md"    => "+++\ntitle = \"Rust EN\"\n[extra]\nicon = \"en\"\n+++\n",
        "tags/rust/_index.ko.md" => "+++\ntitle = \"러스트\"\n[extra]\nicon = \"ko\"\n+++\n본문\n",
      },
      template_files: TEMPLATES) do |dir|
      File.read(File.join(dir, "public/tags/rust/index.html")).should start_with("T=Rust EN|D=|X=en|B=|")
      File.read(File.join(dir, "public/ko/tags/rust/index.html")).should start_with("T=러스트|D=|X=ko|B=<p>본문</p>")
    end
  end

  # Only a file a generated term page takes is metadata; any other section
  # under content/<taxonomy>/ publishes exactly as before.
  it "keeps a section no term page takes publishing as an ordinary section" do
    log = with_captured_log do
      build_site(CONFIG,
        content_files: {
          "posts/p1.md"            => post("P1", ["go"]),
          "tags/nonterm/_index.md" => "+++\ntitle = \"Not a term section\"\n+++\nSection body\n",
          "tags/nonterm/child.md"  => post("Child", [] of String),
          "tags/moved/_index.md"   => "+++\ntitle = \"Moved\"\npath = \"/elsewhere/\"\n+++\n",
        },
        template_files: TEMPLATES) do |dir|
        File.read(File.join(dir, "public/tags/nonterm/index.html")).should eq("SECTION=Not a term section|<p>Section body</p>\n")
        File.exists?(File.join(dir, "public/tags/nonterm/child/index.html")).should be_true
        File.exists?(File.join(dir, "public/elsewhere/index.html")).should be_true
        File.read(File.join(dir, "public/sitemap.xml")).should contain("https://ex.com/tags/nonterm/</loc>")
        File.read(File.join(dir, "public/llms.txt")).should contain("Not a term section")
      end
    end
    log.should_not contain("tags/nonterm")
  end

  it "keeps a file publishing when its language does not generate the taxonomy" do
    config = MULTILINGUAL_CONFIG.sub(%(taxonomies = ["tags"]), %(taxonomies = []))
    build_site(config,
      content_files: {"a.md" => post("A", ["rust"]), "a.ko.md" => post("가", ["rust"]), "tags/rust/_index.ko.md" => "+++\ntitle = \"러스트\"\n+++\n"},
      template_files: TEMPLATES) do |dir|
      File.read(File.join(dir, "public/ko/tags/rust/index.html")).should start_with("SECTION=러스트|")
    end
  end

  it "keeps pages nested under a term directory publishing" do
    build_site(CONFIG,
      content_files: {
        "posts/p1.md"         => post("P1", ["rust"]),
        "tags/rust/_index.md" => "+++\ntitle = \"Rust\"\n+++\n",
        "tags/rust/notes.md"  => post("Notes", [] of String),
      },
      template_files: TEMPLATES) do |dir|
      File.read(File.join(dir, "public/tags/rust/index.html")).should start_with("T=Rust|")
      File.read(File.join(dir, "public/tags/rust/notes/index.html")).should start_with("Notes|")
    end
  end

  it "fails a strict build on a broken @/ link in a term body" do
    expect_raises(Hwaro::HwaroError, /tags\/rust\/_index\.md → @\/missing\.md/) do
      build_site(CONFIG + %(\n[links]\nbroken_internal = "error"\n),
        content_files: {"posts/p1.md" => post("P1", ["rust"]), "tags/rust/_index.md" => "+++\ntitle = \"Rust\"\n+++\n[x](@/missing.md)\n"},
        template_files: TEMPLATES) { }
    end
  end

  it "warns about broken @/ links and anchors in a term body" do
    log = with_captured_log do
      build_site(CONFIG + %(\n[links]\nbroken_anchors = "warn"\n),
        content_files: {
          "posts/p1.md"         => post("P1", ["rust"]),
          "tags/rust/_index.md" => "+++\ntitle = \"Rust\"\n+++\n[x](@/missing.md) [y](@/posts/p1.md#nope)\n",
        },
        template_files: TEMPLATES) { }
    end
    log.should contain("Internal link '@/missing.md' in 'tags/rust/_index.md' could not be resolved")
    log.should contain("Broken anchor: tags/rust/_index.md → @/posts/p1.md#nope")
  end

  it "highlights code in a term body like any page body" do
    body = "+++\ntitle = \"Rust\"\n+++\n```crystal\nputs 1\n```\n"
    build_site(CONFIG, content_files: {"posts/p1.md" => post("P1", ["rust"]), "tags/rust/_index.md" => body},
      template_files: TEMPLATES, highlight: true) do |dir|
      File.read(File.join(dir, "public/tags/rust/index.html")).should contain("<span")
    end
    build_site(CONFIG, content_files: {"posts/p1.md" => post("P1", ["rust"]), "tags/rust/_index.md" => body},
      template_files: TEMPLATES, highlight: false) do |dir|
      File.read(File.join(dir, "public/tags/rust/index.html")).should_not contain("<span")
    end
  end

  it "writes the file's aliases as redirects to the term page" do
    build_site(CONFIG,
      content_files: {"posts/p1.md" => post("P1", ["rust"]), "tags/rust/_index.md" => "+++\ntitle = \"Rust\"\naliases = [\"/old-rust/\"]\n+++\n"},
      template_files: TEMPLATES) do |dir, builder|
      stub = File.join(dir, "public/old-rust/index.html")
      File.read(stub).should contain("https://ex.com/tags/rust/")

      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false)
      options.serve_mode = true
      options.preserve_output = true
      File.write("content/tags/rust/_index.md", "+++\ntitle = \"Rust\"\n+++\n")
      builder.run_incremental(["content/tags/rust/_index.md"], options).should be_true
      File.exists?(stub).should be_false
    end
  end

  it "reports duplicate files for one term page and the ignored template key" do
    log = with_captured_log do
      build_site(CONFIG,
        content_files: {
          "posts/p1.md"               => post("P1", ["rust"]),
          "tags/rust/_index.md"       => "+++\ntitle = \"Rust\"\ntemplate = \"custom\"\n+++\n",
          "tags/rust/_index.markdown" => "+++\ntitle = \"Other\"\n+++\n",
        },
        template_files: TEMPLATES) do |dir|
        File.read(File.join(dir, "public/tags/rust/index.html")).should start_with("T=Rust|")
      end
    end
    log.should contain("content/tags/rust/_index.markdown is ignored: content/tags/rust/_index.md already describes the term page /tags/rust/")
    log.should contain("content/tags/rust/_index.md: `template` is ignored")
    log.should_not contain("replaces content page")
    log.should_not contain("Duplicate output path")
  end

  it "turns a section into term metadata, and back, as serve edits add and remove the term" do
    build_site(CONFIG,
      content_files: {"posts/p1.md" => post("P1", ["go"]), "tags/rust/_index.md" => "+++\ntitle = \"Rust\"\n+++\nprose\n"},
      template_files: TEMPLATES) do |dir, builder|
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false)
      options.serve_mode = true
      options.preserve_output = true
      dest = File.join(dir, "public/tags/rust/index.html")
      File.read(dest).should start_with("SECTION=Rust|")

      File.write("content/posts/p1.md", post("P1", ["go", "rust"]))
      builder.run_incremental(["content/posts/p1.md"], options).should be_true
      File.read(dest).should start_with("T=Rust|D=|X=|B=<p>prose</p>")

      File.write("content/posts/p1.md", post("P1", ["go"]))
      builder.run_incremental(["content/posts/p1.md"], options).should be_true
      File.read(dest).should start_with("SECTION=Rust|")
    end
  end

  it "turns a section back into an ordinary page on a --cache build once its term is gone" do
    build_site(CONFIG,
      content_files: {"posts/p1.md" => post("P1", ["rust"]), "tags/rust/_index.md" => "+++\ntitle = \"Rust\"\n+++\nprose\n"},
      template_files: TEMPLATES, cache: true) do |dir, builder|
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: true, highlight: false)
      dest = File.join(dir, "public/tags/rust/index.html")
      File.read(dest).should start_with("T=Rust|")

      File.write("content/posts/p1.md", post("P1", ["go"]))
      builder.run(options)
      File.read(dest).should eq("SECTION=Rust|<p>prose</p>\n")

      File.write("content/posts/p1.md", post("P1", ["rust"]))
      builder.run(options)
      File.read(dest).should start_with("T=Rust|")
    end
  end

  it "keeps the taxonomy index _index.md behaving as before" do
    log = with_captured_log do
      build_site(CONFIG,
        content_files: {"posts/p1.md" => post("P1", ["go"]), "tags/_index.md" => "+++\ntitle = \"All tags\"\n+++\n"},
        template_files: TEMPLATES) do |dir|
        File.read(File.join(dir, "public/tags/index.html")).should contain("taxonomy-terms")
      end
    end
    log.should contain("replaces content page 'tags/_index.md'")
  end

  it "re-renders on a --cache build after an edit and reverts once the file is gone" do
    build_site(CONFIG,
      content_files: {"posts/p1.md" => post("P1", ["rust"]), "tags/rust/_index.md" => "+++\ntitle = \"Old\"\n+++\n"},
      template_files: TEMPLATES, cache: true) do |dir, builder|
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: true, highlight: false)
      term = File.join(dir, "public/tags/rust/index.html")
      File.read(term).should start_with("T=Old|")

      File.write("content/tags/rust/_index.md", "+++\ntitle = \"New\"\n+++\n")
      builder.run(options)
      File.read(term).should start_with("T=New|")

      File.delete("content/tags/rust/_index.md")
      builder.run(options)
      File.read(term).should start_with("T=Tags: rust|")
    end
  end

  it "re-renders on a serve incremental rebuild after an edit" do
    build_site(CONFIG,
      content_files: {"posts/p1.md" => post("P1", ["rust"]), "tags/rust/_index.md" => "+++\ntitle = \"Old\"\n+++\n"},
      template_files: TEMPLATES) do |dir, builder|
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false)
      options.serve_mode = true
      options.preserve_output = true
      term = File.join(dir, "public/tags/rust/index.html")

      File.write("content/tags/rust/_index.md", "+++\ntitle = \"New\"\ndescription = \"d\"\n+++\nfresh\n")
      builder.run_incremental(["content/tags/rust/_index.md"], options).should be_true
      File.read(term).should start_with("T=New|D=d|X=|B=<p>fresh</p>")
      File.read(File.join(dir, "public/posts/p1/index.html")).should eq("P1|rust=New/d;")

      # A removed file is a full rebuild in serve (ChangeSet#removed_files).
      File.delete("content/tags/rust/_index.md")
      builder.run(options)
      File.read(term).should start_with("T=Tags: rust|D=|X=|B=|")
    end
  end
end
