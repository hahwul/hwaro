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

  it "warns about, and does not publish, a file no term page matches" do
    log = with_captured_log do
      build_site(CONFIG,
        content_files: {"posts/p1.md" => post("P1", ["go"]), "tags/ghost/_index.md" => "+++\ntitle = \"Ghost\"\n+++\n"},
        template_files: TEMPLATES) do |dir|
        File.exists?(File.join(dir, "public/tags/ghost/index.html")).should be_false
        File.read(File.join(dir, "public/sitemap.xml")).should_not contain("ghost")
      end
    end
    log.should contain("content/tags/ghost/_index.md describes a taxonomy term page")
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
