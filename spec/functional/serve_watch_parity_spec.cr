require "../spec_helper"
require "../../src/services/server/server"

# Serve watch passes whose `.hwaro/serve` tree differed from a cold build of
# the same final source (audit 2026-10). Each example drives the strategy the
# watcher picks for the save and compares against what a cold build writes.

module Hwaro
  module Services
    class Server
      def watch_parity_builder : Hwaro::Core::Build::Builder
        @builder
      end

      def watch_parity_apply_changeset(changeset : ChangeSet, options : Config::Options::BuildOptions)
        apply_changeset(changeset, options)
      end

      def watch_parity_effective_strategy(changeset : ChangeSet, output_dir : String) : Symbol
        effective_strategy(changeset, output_dir)
      end
    end
  end
end

private def watch_parity_options : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
  options.serve_mode = true
  options.preserve_output = true
  options
end

private def watch_parity_changeset(
  content : Array(String) = [] of String,
  templates : Array(String) = [] of String,
  static : Array(String) = [] of String,
  content_files : Array(String) = [] of String,
) : Hwaro::Services::ChangeSet
  Hwaro::Services::ChangeSet.new(
    modified_content: content,
    modified_templates: templates,
    modified_static: static,
    added_files: [] of String,
    removed_files: [] of String,
    config_changed: false,
    modified_content_files: content_files,
  )
end

# Three dated posts whose page template prints the reading-order neighbours,
# the series nav and the related box — every relationship a content edit can
# move on a page it never touched. `templates/unrelated.html` is rendered by
# no page: editing it in the same save takes the watcher down the
# content+template strategy without selecting any post on its own account.
private def write_relations_site
  File.write("config.toml", <<-TOML
    title = "Relations"
    base_url = "https://example.com"

    [[taxonomies]]
    name = "tags"

    [related]
    enabled = true
    taxonomies = ["tags"]

    [series]
    enabled = true
    TOML
  )
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", <<-HTML
    <html><body><h1>{{ page.title }}</h1>
    {% if page.lower %}<a class="newer" href="{{ page.lower.url }}">{{ page.lower.title }}</a>{% endif %}
    {% if page.higher %}<a class="older" href="{{ page.higher.url }}">{{ page.higher.title }}</a>{% endif %}
    {% for s in page.series_pages %}<a class="series" href="{{ s.url }}">{{ s.title }}</a>{% endfor %}
    {% for r in page.related_posts %}<a class="related" href="{{ r.url }}">{{ r.title }}</a>{% endfor %}
    </body></html>
    HTML
  )
  File.write("templates/section.html", "<html><body>{{ section.title }}</body></html>")
  File.write("templates/unrelated.html", "<p>unused</p>")
  File.write("content/posts/_index.md", "+++\ntitle = \"Posts\"\n+++\n")
  File.write("content/posts/a.md", "+++\ntitle = \"Alpha\"\ndate = \"2024-01-01\"\ntags = [\"x\"]\nseries = \"s\"\n+++\na")
  File.write("content/posts/b.md", "+++\ntitle = \"Bravo\"\ndate = \"2024-01-02\"\ntags = [\"y\"]\nseries = \"s\"\n+++\nb")
  File.write("content/posts/c.md", "+++\ntitle = \"Charlie\"\ndate = \"2024-01-03\"\ntags = [\"x\"]\n+++\nc")
end

describe "serve watch parity: content+template saves" do
  # The content+template strategy recomputed the neighbours, series and
  # related posts but threw the affected pages away — only the edited page
  # reached the forced render set — so every other post kept linking the
  # old title (and, after a slug edit, a URL whose file was just deleted).
  it "re-renders the reading-order neighbours of a re-slugged page" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_relations_site
        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true
        File.read("public/posts/a/index.html").should contain(%(href="/posts/b/">Bravo<))

        File.write("content/posts/b.md", "+++\ntitle = \"Beta\"\nslug = \"beta\"\ndate = \"2024-01-02\"\ntags = [\"y\"]\nseries = \"s\"\n+++\nb")
        File.write("templates/unrelated.html", "<p>unused v2</p>")
        builder.run_incremental_then_rerender(["content/posts/b.md"], options).should be_true

        File.exists?("public/posts/b/index.html").should be_false
        {"a", "c"}.each do |slug|
          html = File.read("public/posts/#{slug}/index.html")
          html.should_not contain("/posts/b/")
          html.should contain(%(href="/posts/beta/">Beta<))
        end
      end
    end
  end

  it "re-renders the related box of a page the edit made related" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_relations_site
        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true
        File.read("public/posts/a/index.html").should_not contain(%(class="related" href="/posts/b/"))

        File.write("content/posts/b.md", "+++\ntitle = \"Bravo\"\ndate = \"2024-01-02\"\ntags = [\"x\"]\nseries = \"s\"\n+++\nb")
        File.write("templates/unrelated.html", "<p>unused v2</p>")
        builder.run_incremental_then_rerender(["content/posts/b.md"], options).should be_true

        File.read("public/posts/a/index.html").should contain(%(class="related" href="/posts/b/">Bravo<))
        File.read("public/posts/c/index.html").should contain(%(class="related" href="/posts/b/">Bravo<))
      end
    end
  end

  it "re-renders the other members of a series the edit renamed a page in" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        # Drop the neighbour links so only the series nav can carry the title.
        write_relations_site
        File.write("templates/page.html", <<-HTML
          <html><body>{% for s in page.series_pages %}<a class="series" href="{{ s.url }}">{{ s.title }}</a>{% endfor %}</body></html>
          HTML
        )
        File.write("content/posts/c.md", "+++\ntitle = \"Charlie\"\ndate = \"2024-01-03\"\ntags = [\"x\"]\nseries = \"s\"\n+++\nc")
        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true
        File.read("public/posts/a/index.html").should contain(%(class="series" href="/posts/c/">Charlie<))

        File.write("content/posts/c.md", "+++\ntitle = \"Charles\"\ndate = \"2024-01-03\"\ntags = [\"x\"]\nseries = \"s\"\n+++\nc")
        File.write("templates/unrelated.html", "<p>unused v2</p>")
        builder.run_incremental_then_rerender(["content/posts/c.md"], options).should be_true

        File.read("public/posts/a/index.html").should contain(%(class="series" href="/posts/c/">Charles<))
      end
    end
  end
end

private def write_generate_site
  File.write("config.toml", <<-TOML
    title = "Gen"
    base_url = "https://example.com"

    [[content.generate]]
    source = "products"
    section = "products"
    slug = "sku"
    title = "name"
    body_template = "gen/product.md"
    TOML
  )
  FileUtils.mkdir_p("data")
  FileUtils.mkdir_p("templates/gen")
  FileUtils.mkdir_p("templates/partials")
  FileUtils.mkdir_p("content/products")
  File.write("data/products.json", %([{"sku": "w1", "name": "Widget"}]))
  File.write("templates/page.html", "<html><body>{{ content }}</body></html>")
  File.write("templates/section.html", "<html><body>{{ section.title }}</body></html>")
  File.write("templates/gen/product.md", "Body of {{ item.name }} v1. {% include \"partials/spec.html\" %}")
  File.write("templates/partials/spec.html", "spec-v1")
  File.write("templates/partials/other.html", "other")
  File.write("content/products/_index.md", "+++\ntitle = \"Products\"\n+++\n")
end

describe "serve watch parity: [[content.generate]] body templates" do
  # Bodies render while the pages are generated, which only a full build
  # does; the re-render strategy re-rendered from the bodies it already held
  # (and the `.md` body file isn't in the template snapshot at all, so the
  # edit read as "contents are identical").
  it "regenerates the pages when the body template changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_generate_site
        server = Hwaro::Services::Server.new
        options = watch_parity_options
        server.watch_parity_builder.run(options).should be_true
        File.read("public/products/w1/index.html").should contain("Body of Widget v1.")

        File.write("templates/gen/product.md", "Body of {{ item.name }} v2. {% include \"partials/spec.html\" %}")
        server.watch_parity_apply_changeset(watch_parity_changeset(templates: ["templates/gen/product.md"]), options)

        File.read("public/products/w1/index.html").should contain("Body of Widget v2.")
      end
    end
  end

  it "regenerates the pages when a partial the body template includes changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_generate_site
        server = Hwaro::Services::Server.new
        options = watch_parity_options
        server.watch_parity_builder.run(options).should be_true
        File.read("public/products/w1/index.html").should contain("spec-v1")

        File.write("templates/partials/spec.html", "spec-v2")
        server.watch_parity_apply_changeset(watch_parity_changeset(templates: ["templates/partials/spec.html"]), options)

        File.read("public/products/w1/index.html").should contain("spec-v2")
      end
    end
  end

  it "keeps the cheap strategy for a template the body never reads" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_generate_site
        server = Hwaro::Services::Server.new
        options = watch_parity_options
        server.watch_parity_builder.run(options).should be_true

        changeset = watch_parity_changeset(templates: ["templates/partials/other.html"])
        server.watch_parity_effective_strategy(changeset, "public").should eq(:templates)
      end
    end
  end
end

# Static files sitting where the build writes something that is not a page's
# own output: a generator file, a taxonomy page, an alias stub, a pagination
# page, the PWA files. A cold build writes them all after copying static/,
# but the static-only lane copied the edit and re-rendered nothing.
private def write_shadow_site
  File.write("config.toml", <<-TOML
    title = "Shadow"
    base_url = "https://example.com"

    [[taxonomies]]
    name = "tags"

    [pwa]
    enabled = true
    TOML
  )
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", "<html><body>{{ page.title }}</body></html>")
  File.write("templates/section.html", "<html><body>{{ section.title }}</body></html>")
  File.write("templates/taxonomy_term.html", "<html><body>TERM {{ page.title }}</body></html>")
  File.write("templates/404.html", "<html><body>NOT FOUND</body></html>")
  File.write("content/posts/_index.md", "+++\ntitle = \"Posts\"\npaginate = 1\n+++\n")
  File.write("content/posts/a.md", "+++\ntitle = \"A\"\ndate = \"2024-01-01\"\ntags = [\"hello\"]\naliases = [\"/old-a/\"]\n+++\na")
  File.write("content/posts/b.md", "+++\ntitle = \"B\"\ndate = \"2024-01-02\"\n+++\nb")
  {
    "robots.txt", "404.html", "sw.js", "manifest.json", "tags/hello/index.html",
    "old-a/index.html", "posts/page/2/index.html", "plain.txt",
  }.each do |relative|
    FileUtils.mkdir_p(File.dirname(File.join("static", relative)))
    File.write(File.join("static", relative), "USER BYTES v1")
  end
end

describe "serve watch parity: static edits over generated outputs" do
  it "lets the generated file win again when a shadowing static file is edited" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_shadow_site
        server = Hwaro::Services::Server.new
        options = watch_parity_options
        server.watch_parity_builder.run(options).should be_true
        generated = {
          "robots.txt", "404.html", "sw.js", "manifest.json", "tags/hello/index.html",
          "old-a/index.html", "posts/page/2/index.html",
        }
        generated.each do |relative|
          fail "cold build served the static #{relative}" if File.read(File.join("public", relative)).includes?("USER BYTES")
        end

        generated.each do |relative|
          File.write(File.join("static", relative), "USER BYTES v2")
          server.watch_parity_apply_changeset(watch_parity_changeset(static: ["static/#{relative}"]), options)
          if File.read(File.join("public", relative)).includes?("USER BYTES")
            fail "a static edit of #{relative} replaced the generated file"
          end
        end
      end
    end
  end

  it "still copies an ordinary static file without a rebuild" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_shadow_site
        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true

        File.write("static/plain.txt", "USER BYTES v2")
        builder.copy_changed_static(["static/plain.txt"], "public").should be_false
        File.read("public/plain.txt").should eq("USER BYTES v2")
      end
    end
  end
end
