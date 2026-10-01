require "../../../../../spec_helper"
require "../../../../../../src/core/build/builder"
require "../../../../../../src/content/hooks"

# Per-page invalidation on warm `--cache` builds: a page that renders a piece
# of ANOTHER page must re-render when that page changes, even though its own
# source, template closure and the global listing markers say nothing moved.
#
# - prev/next neighbours, series, related posts, translations
#   (CacheEntry#relations_hash)
# - a literal `get_page(path=...)` and the `@/` links in the content
# - a listing shortcode the content calls (its template was never scanned for
#   page-set markers — only the page's entry template was)
#
# Every page here uses templates WITHOUT any global listing marker, so the
# page-set fingerprint cannot be what re-renders them.
private def write_relations_site
  File.write("config.toml", <<-TOML)
    title = "T"
    base_url = "http://localhost"
    default_language = "en"

    [languages.en]
    language_name = "English"

    [languages.ko]
    language_name = "Korean"

    [series]
    enabled = true

    [related]
    enabled = true

    [[taxonomies]]
    name = "tags"
    TOML
  FileUtils.mkdir_p("templates/shortcodes")
  File.write("templates/page.html", <<-HTML)
    <h1>{{ page.title }}</h1>
    NEXT={% if page.higher %}{{ page.higher.title }}{% endif %}
    SERIES={% for p in page.series_pages %}{{ p.title }};{% endfor %}
    RELATED={% for p in page.related_posts %}{{ p.title }};{% endfor %}
    TR={% for t in page.translations %}{{ t.code }}:{{ t.title }};{% endfor %}
    {{ content }}
    HTML
  File.write("templates/plain.html", "<h1>{{ page.title }}</h1>{{ content }}")
  File.write("templates/about.html", %(<h1>{{ page.title }}</h1>GP={{ get_page(path="posts/a.md").title }}))
  File.write("templates/shortcodes/recent.html", "{% for p in site.pages %}[{{ p.title }}]{% endfor %}")
  FileUtils.mkdir_p("content/posts")
  File.write("content/posts/_index.md", "+++\ntitle = \"Posts\"\nsort_by = \"date\"\n+++\n")
  %w[a b c].each_with_index do |x, i|
    File.write("content/posts/#{x}.md", "+++\ntitle = \"Post #{x}\"\ndate = 2024-01-0#{i + 1}\nseries = \"s1\"\ntags = [\"t1\"]\n+++\nBody #{x}")
  end
  File.write("content/posts/b.ko.md", "+++\ntitle = \"Post b ko\"\ndate = 2024-01-02\n+++\nKO b")
  File.write("content/about.md", "+++\ntitle = \"About\"\ntemplate = \"about\"\n+++\nabout")
  File.write("content/sc.md", "+++\ntitle = \"SC\"\ntemplate = \"plain\"\n+++\n{{ recent() }}")
  File.write("content/linker.md", "+++\ntitle = \"Linker\"\ntemplate = \"plain\"\n+++\n[A](@/posts/a.md)")
  File.write("content/plain.md", "+++\ntitle = \"Plain\"\ntemplate = \"plain\"\n+++\nplain")
end

private def relations_cached_build
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public", parallel: false, cache: true, highlight: false,
  )).should be_true
end

private def with_relations_site(&)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      write_relations_site
      relations_cached_build
      yield
    end
  end
end

private def retitle(path : String, from : String, to : String)
  File.write(path, File.read(path).sub("title = \"#{from}\"", "title = \"#{to}\""))
end

describe "warm --cache: pages rendering other pages" do
  it "re-renders a page whose next-page link names a retitled neighbour" do
    with_relations_site do
      File.read("public/posts/b/index.html").should contain("NEXT=Post a")
      retitle("content/posts/a.md", "Post a", "Post A2")
      relations_cached_build
      File.read("public/posts/b/index.html").should contain("NEXT=Post A2")
    end
  end

  it "drops a deleted page from the other members' series and related lists" do
    with_relations_site do
      File.read("public/posts/a/index.html").should contain("Post c;")
      File.delete("content/posts/c.md")
      relations_cached_build
      a = File.read("public/posts/a/index.html")
      a.should_not contain("SERIES=Post a;Post b;Post c;")
      a.should_not contain("RELATED=Post b;Post c;")
    end
  end

  it "updates the language switcher when a translation is added" do
    with_relations_site do
      File.read("public/posts/a/index.html").should_not contain("ko:")
      File.write("content/posts/a.ko.md", "+++\ntitle = \"Post a ko\"\ndate = 2024-01-01\n+++\nKO a")
      relations_cached_build
      File.read("public/posts/a/index.html").should contain("ko:Post a ko")
    end
  end

  it "re-renders a page reading a retitled page through get_page" do
    with_relations_site do
      File.read("public/about/index.html").should contain("GP=Post a")
      retitle("content/posts/a.md", "Post a", "Post A2")
      relations_cached_build
      File.read("public/about/index.html").should contain("GP=Post A2")
    end
  end

  it "treats a get_page call with a computed path as a page-set read" do
    with_relations_site do
      File.write("templates/dyn.html", %(DYN={{ get_page(path=page.extra.ref).title }}))
      File.write("content/dyn.md", "+++\ntitle = \"Dyn\"\ntemplate = \"dyn\"\n[extra]\nref = \"posts/b.md\"\n+++\n")
      relations_cached_build
      File.read("public/dyn/index.html").should contain("DYN=Post b")
      retitle("content/posts/b.md", "Post b", "Post B2")
      relations_cached_build
      File.read("public/dyn/index.html").should contain("DYN=Post B2")
    end
  end

  it "re-renders a page whose shortcode lists the page set" do
    with_relations_site do
      File.read("public/sc/index.html").should_not contain("[Post d]")
      File.write("content/posts/d.md", "+++\ntitle = \"Post d\"\ndate = 2024-01-09\n+++\nd")
      relations_cached_build
      File.read("public/sc/index.html").should contain("[Post d]")
    end
  end

  it "re-resolves an @/ link whose target page moved" do
    with_relations_site do
      File.read("public/linker/index.html").should contain(%(href="/posts/a/"))
      File.write("content/posts/a.md", File.read("content/posts/a.md").sub("series =", "slug = \"renamed-a\"\nseries ="))
      relations_cached_build
      File.read("public/linker/index.html").should contain(%(href="/posts/renamed-a/"))
    end
  end

  it "leaves a page alone when it renders nothing of the changed page" do
    with_relations_site do
      # A sentinel only survives if the file is not written again.
      File.write("public/plain/index.html", "SENTINEL")
      retitle("content/posts/c.md", "Post c", "Post C2")
      relations_cached_build
      File.read("public/plain/index.html").should eq("SENTINEL")
    end
  end

  it "re-renders nothing on an untouched warm build" do
    with_relations_site do
      relations_cached_build
      # Content pages only — taxonomy pages have no cache entry.
      pages = Dir.glob(["public/posts/*/index.html", "public/ko/posts/*/index.html",
                        "public/{about,sc,linker,plain}/index.html"])
      pages.size.should be > 5
      pages.each { |f| File.write(f, "SENTINEL") }
      relations_cached_build
      pages.each { |f| File.read(f).should eq("SENTINEL") }
    end
  end
end
