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

  it "regenerates the pages when a partial an inline template spec includes changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_generate_site
        config = File.read("config.toml").sub(%(body_template = "gen/product.md"),
          %(body = "{% include 'partials/spec.html' %} body"\ndescription = "{% include 'partials/other.html' %}"))
        File.write("config.toml", config)
        File.write("templates/page.html", "<html><body>{{ page.description }} {{ content }}</body></html>")
        server = Hwaro::Services::Server.new
        options = watch_parity_options
        server.watch_parity_builder.run(options).should be_true
        File.read("public/products/w1/index.html").should contain("other <p>spec-v1 body</p>")

        File.write("templates/partials/spec.html", "spec-v2")
        File.write("templates/partials/other.html", "other-v2")
        changeset = watch_parity_changeset(templates: ["templates/partials/spec.html", "templates/partials/other.html"])
        server.watch_parity_effective_strategy(changeset, "public").should eq(:full)
        server.watch_parity_apply_changeset(changeset, options)

        File.read("public/products/w1/index.html").should contain("other-v2 <p>spec-v2 body</p>")
      end
    end
  end

  # A non-literal include leaves the template graph `dynamic?`: it cannot
  # say which partial the spec reaches, so any template edit must count.
  it "regenerates the pages when a spec's include is dynamic" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_generate_site
        config = File.read("config.toml").sub(%(body_template = "gen/product.md"),
          %(description = "{% include 'partials/' ~ 'spec.html' %}"))
        File.write("config.toml", config)
        File.write("templates/page.html", "<html><body>{{ page.description }}</body></html>")
        server = Hwaro::Services::Server.new
        options = watch_parity_options
        server.watch_parity_builder.run(options).should be_true
        File.read("public/products/w1/index.html").should contain("spec-v1")

        File.write("templates/partials/spec.html", "spec-v2")
        changeset = watch_parity_changeset(templates: ["templates/partials/spec.html"])
        server.watch_parity_effective_strategy(changeset, "public").should eq(:full)
        server.watch_parity_apply_changeset(changeset, options)

        File.read("public/products/w1/index.html").should contain("spec-v2")
      end
    end
  end

  it "regenerates the pages when the body template's include is dynamic" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_generate_site
        File.write("templates/gen/product.md", "Body {% include 'partials/' ~ 'spec.html' %}")
        server = Hwaro::Services::Server.new
        options = watch_parity_options
        server.watch_parity_builder.run(options).should be_true
        File.read("public/products/w1/index.html").should contain("spec-v1")

        File.write("templates/partials/spec.html", "spec-v2")
        changeset = watch_parity_changeset(templates: ["templates/partials/spec.html"])
        server.watch_parity_effective_strategy(changeset, "public").should eq(:full)
        server.watch_parity_apply_changeset(changeset, options)

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

  # A computed include elsewhere (here only the homepage's) leaves the
  # graph `dynamic?`, but not the closure of a spec that includes nothing:
  # every template save used to regenerate the site.
  it "keeps the cheap strategy when only an unrelated template's include is dynamic" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_generate_site
        config = File.read("config.toml").sub(%(body_template = "gen/product.md"), "").sub(%(slug = "sku"), %(slug = "{{ item.sku | slugify }}"))
        File.write("config.toml", config)
        File.write("templates/index.html", "<html><body>{% include 'partials/' ~ 'other.html' %}</body></html>")
        server = Hwaro::Services::Server.new
        options = watch_parity_options
        server.watch_parity_builder.run(options).should be_true
        File.exists?("public/products/w1/index.html").should be_true

        changeset = watch_parity_changeset(templates: ["templates/page.html"])
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

  # The lane used to copy the file before escalating, so the full rebuild's
  # own static copy found the destination up to date, recorded nothing, and
  # the OG generator counted its manifest hit on the user's bytes.
  it "regenerates an auto OG image a static save lands on" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_shadow_site
        File.write("config.toml", File.read("config.toml") + %(\n[og.auto_image]\nenabled = true\nformat = "svg"\n))
        FileUtils.mkdir_p("static/og-images")
        File.write("static/og-images/about.svg", "USER BYTES v1")
        File.write("content/about.md", %(+++\ntitle = "About"\n+++\nabout))
        server = Hwaro::Services::Server.new
        options = watch_parity_options
        server.watch_parity_builder.run(options).should be_true
        File.read("public/og-images/about.svg").should start_with("<?xml")

        File.write("static/og-images/about.svg", "USER BYTES v2")
        server.watch_parity_apply_changeset(watch_parity_changeset(static: ["static/og-images/about.svg"]), options)
        File.read("public/og-images/about.svg").should start_with("<?xml")
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

private def write_auto_includes_site
  File.write("config.toml", <<-TOML
    title = "Bust"
    base_url = "https://example.com"

    [auto_includes]
    enabled = true
    dirs = ["inc/css"]
    TOML
  )
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates")
  FileUtils.mkdir_p("static/inc/css")
  File.write("templates/page.html", "<html><head>{{ auto_includes }}</head><body>{{ page.title }}</body></html>")
  File.write("content/about.md", "+++\ntitle = \"About\"\n+++\nabout")
  File.write("static/inc/css/01.css", "body { color: red; }")
  File.write("static/other.css", "p { color: blue; }")
end

private def cache_bust_of(html : String) : String
  html[/01\.css\?v=([0-9a-f]+)/, 1]
end

describe "serve watch parity: cache-busted assets" do
  # The `?v=` digest of an auto-included (or self-hosted highlight) asset is
  # printed into every page that references it; the static lane only copied
  # the edited file, so every page kept the pre-edit hash.
  it "re-renders the pages when an auto-included asset changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_auto_includes_site
        server = Hwaro::Services::Server.new
        options = watch_parity_options
        server.watch_parity_builder.run(options).should be_true
        before = cache_bust_of(File.read("public/about/index.html"))

        File.write("static/inc/css/01.css", "body { color: green; }")
        server.watch_parity_apply_changeset(watch_parity_changeset(static: ["static/inc/css/01.css"]), options)

        after = cache_bust_of(File.read("public/about/index.html"))
        after.should_not eq(before)
        after.should eq(Digest::MD5.hexdigest("body { color: green; }")[0, 8])
      end
    end
  end

  it "only copies a static file the digest does not read" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_auto_includes_site
        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true

        builder.cache_bust_input_changed?(["static/other.css"]).should be_false
        builder.cache_bust_input_changed?(["static/inc/css/01.css"]).should be_true
      end
    end
  end
end

describe "serve watch parity: failed incremental passes" do
  # The re-parse moves the page model to its new URL in place; a date-token
  # permalink error then raised before the pass pruned the old file, and the
  # recovering full build computes "what the previous site owned" from the
  # moved model — so the old output was published for the rest of the
  # session, through every later full rebuild.
  it "prunes the old output of a page whose permalink failed mid-edit" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", <<-TOML
          title = "Dated"
          base_url = "https://example.com"

          [permalinks]
          posts = "/:year/:month/:title/"
          TOML
        )
        FileUtils.mkdir_p("content/posts")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "<html><body>{{ page.title }}</body></html>")
        File.write("templates/section.html", "<html><body>{{ section.title }}</body></html>")
        File.write("content/posts/_index.md", "+++\ntitle = \"Posts\"\n+++\n")
        post = "content/posts/hello.md"
        File.write(post, "+++\ntitle = \"Hello\"\ndate = \"2024-01-01\"\n+++\nbody")

        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true
        File.exists?("public/2024/01/hello/index.html").should be_true

        File.write(post, "+++\ntitle = \"Hello\"\ndate = \"2025-05-05\"\n+++\nbody")
        builder.run_incremental([post], options).should be_true
        File.exists?("public/2025/05/hello/index.html").should be_true
        File.exists?("public/2024/01/hello/index.html").should be_false

        # No date: the :year/:month tokens cannot resolve — the pass fails.
        File.write(post, "+++\ntitle = \"Hello\"\n+++\nbody")
        expect_raises(Hwaro::HwaroError) { builder.run_incremental([post], options) }

        # The watcher recovers with a full rebuild.
        File.write(post, "+++\ntitle = \"Hello\"\ndate = \"2024-01-01\"\n+++\nbody")
        builder.run(options).should be_true

        File.exists?("public/2024/01/hello/index.html").should be_true
        File.exists?("public/2025/05/hello/index.html").should be_false
      end
    end
  end
end

private def write_load_data_site
  File.write("config.toml", <<-TOML
    title = "Loader"
    base_url = "https://example.com"

    [content.files]
    allow_extensions = ["json"]
    TOML
  )
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates")
  FileUtils.mkdir_p("static")
  File.write("templates/page.html", <<-HTML
    <html><body>{% set s = load_data(path="static/prices.json") %}{% set c = load_data('content/stock.json') %}[{{ s.v }}|{{ c.v }}]</body></html>
    HTML
  )
  File.write("content/about.md", "+++\ntitle = \"About\"\n+++\nabout")
  File.write("static/prices.json", %({"v": "s1"}))
  File.write("static/plain.json", %({"v": "p1"}))
  File.write("content/stock.json", %({"v": "c1"}))
end

describe "serve watch parity: load_data() sources outside data/" do
  # Only data/ edits took the full-rebuild lane; a file a template reads via
  # load_data() from static/ or content/ was just copied, so every page
  # printing it kept the pre-edit values for the rest of the session.
  it "re-renders the pages when a static file read by load_data changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_load_data_site
        server = Hwaro::Services::Server.new
        options = watch_parity_options
        server.watch_parity_builder.run(options).should be_true
        File.read("public/about/index.html").should contain("[s1|c1]")

        File.write("static/prices.json", %({"v": "s2"}))
        File.touch("static/prices.json", Time.local + 2.seconds)
        server.watch_parity_apply_changeset(watch_parity_changeset(static: ["static/prices.json"]), options)
        File.read("public/about/index.html").should contain("[s2|c1]")
      end
    end
  end

  it "re-renders the pages when a content file read by load_data changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_load_data_site
        server = Hwaro::Services::Server.new
        options = watch_parity_options
        server.watch_parity_builder.run(options).should be_true

        File.write("content/stock.json", %({"v": "c2"}))
        File.touch("content/stock.json", Time.local + 2.seconds)
        server.watch_parity_apply_changeset(watch_parity_changeset(content_files: ["content/stock.json"]), options)
        File.read("public/about/index.html").should contain("[s1|c2]")
      end
    end
  end

  it "does not treat a file no template loads as a load_data source" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_load_data_site
        builder = Hwaro::Services::Server.new.watch_parity_builder
        builder.run(watch_parity_options).should be_true

        builder.load_data_source_changed?(["static/plain.json"]).should be_false
        builder.load_data_source_changed?(["static/prices.json"]).should be_true
      end
    end
  end
end

# Raw bytes of a w×h PNG.
private def watch_parity_png(w : Int32, h : Int32) : String
  Dir.mktmpdir do |dir|
    path = File.join(dir, "x.png")
    px = Bytes.new(w * h * 3, 90_u8)
    LibStb.stbi_write_png(path, w, h, 3, px.to_unsafe.as(Void*), w * 3)
    File.read(path)
  end
end

describe "serve watch parity: image sizes read while rendering" do
  # `[image_processing] dimensions` prints the image's intrinsic size into the
  # page. A static image swap took the copy-only lane, so every page kept the
  # old width/height (and the browser laid the new image out distorted).
  it "re-renders the pages when a static image they size changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        # The watched-source set is process-wide and cwd-relative.
        Hwaro::Content::Hooks::ImageHooks.clear_intrinsic_sizes
        File.write("config.toml", %(title = "t"\nbase_url = "https://example.com"\n[image_processing]\ndimensions = true\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        FileUtils.mkdir_p("static/img")
        File.write("templates/page.html", "<html><body>{{ content }}</body></html>")
        File.write("content/about.md", "+++\ntitle = \"About\"\n+++\n![a](/img/a.png)\n")
        File.write("static/img/a.png", watch_parity_png(20, 3))
        File.write("static/img/b.png", watch_parity_png(5, 5))
        server = Hwaro::Services::Server.new
        options = watch_parity_options
        server.watch_parity_builder.run(options).should be_true
        File.read("public/about/index.html").should contain(%(width="20" height="3"))
        # Only an image a page actually printed escalates.
        Hwaro::Content::Hooks::ImageHooks.render_image_source_changed?(["static/img/b.png"]).should be_false
        Hwaro::Content::Hooks::ImageHooks.render_image_source_changed?(["static/img/a.png"]).should be_true

        File.write("static/img/a.png", watch_parity_png(7, 6))
        File.touch("static/img/a.png", Time.local + 2.seconds)
        server.watch_parity_apply_changeset(watch_parity_changeset(static: ["static/img/a.png"]), options)
        File.read("public/about/index.html").should contain(%(width="7" height="6"))
      end
    end
  end
end

# A listing page (not a section index, so no section relationship reaches
# it) printing each entry's language switcher. A counterpart turning into a
# `redirect_to` stub drops out of its translations' switchers, which the
# listing prints too.
private def write_translation_listing_site
  File.write("config.toml", <<-TOML
    title = "Langs"
    base_url = "https://example.com"
    default_language = "en"

    [languages.en]
    weight = 1

    [languages.ko]
    weight = 2
    TOML
  )
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", "<html><body>{{ page.title }}</body></html>")
  File.write("templates/section.html", "<html><body>{{ section.title }}</body></html>")
  File.write("templates/list.html",
    "<html><body>{% for p in site.pages %}<a href=\"{{ p.url }}\">{{ p.title }}</a>{% for t in p.translations %}[{{ t.code }}]{% endfor %}{% endfor %}</body></html>")
  File.write("content/list.ko.md", "+++\ntitle = \"목록\"\ntemplate = \"list\"\n+++\n")
  File.write("content/posts/a.md", "+++\ntitle = \"A\"\n+++\na")
  File.write("content/posts/a.ko.md", "+++\ntitle = \"가\"\n+++\na")
end

describe "serve watch parity: translation switchers in listings" do
  it "re-renders a listing when a counterpart becomes a redirect stub" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_translation_listing_site
        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true
        File.read("public/ko/list/index.html").should contain(%(가</a>[en][ko]))

        File.write("content/posts/a.md", "+++\ntitle = \"A\"\nredirect_to = \"https://other.example/\"\n+++\na")
        builder.run_incremental(["content/posts/a.md"], options).should be_true

        html = File.read("public/ko/list/index.html")
        html.should_not contain(%(가</a>[en][ko]))
        html.should contain(%(가</a><a))
      end
    end
  end
end

describe "serve watch parity: a language's homepage going headless" do
  # The JSON-LD breadcrumb's Home crumb is the page language's homepage
  # only while one is written; `render = false` on `_index.ko.md` moves it
  # to the site root on every Korean page, none of which the edit touched.
  it "re-renders the language's pages so their Home crumb leaves the unwritten homepage" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_translation_listing_site
        File.write("templates/page.html", "<html><body>{{ jsonld_breadcrumb | safe }}</body></html>")
        File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
        File.write("content/_index.ko.md", "+++\ntitle = \"홈\"\n+++\n")
        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true
        File.read("public/ko/posts/a/index.html").should contain(%("item":"https://example.com/ko/"))

        File.write("content/_index.ko.md", "+++\ntitle = \"홈\"\nrender = false\n+++\n")
        builder.run_incremental(["content/_index.ko.md"], options).should be_true

        html = File.read("public/ko/posts/a/index.html")
        html.should_not contain(%("item":"https://example.com/ko/"))
        html.should contain(%("item":"https://example.com/"}))
      end
    end
  end
end

describe "serve watch parity: summaries printing a page's translations" do
  # A shortcode in the `<!-- more -->` summary reads `page.translations`;
  # retitling the Korean counterpart re-rendered the English page's body
  # but kept its summary, which the feed prints.
  it "recomputes a counterpart's summary when its translation is retitled" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_translation_listing_site
        File.write("config.toml", File.read("config.toml") + "\n[feeds]\nenabled = true\n")
        FileUtils.mkdir_p("templates/shortcodes")
        File.write("templates/shortcodes/sw.html", "{% for t in page.translations %}{{ t.title }};{% endfor %}")
        File.write("content/posts/a.md", "+++\ntitle = \"A\"\ndate = \"2024-01-01\"\n+++\nlead {{ sw() }}\n\n<!-- more -->\n\nrest")
        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true
        File.read("public/rss.xml").should contain("<description>lead A;가;</description>")

        File.write("content/posts/a.ko.md", "+++\ntitle = \"가나\"\n+++\na")
        builder.run_incremental(["content/posts/a.ko.md"], options).should be_true

        File.read("public/rss.xml").should contain("<description>lead A;가나;</description>")
      end
    end
  end
end

describe "serve watch parity: summaries printing a page's neighbours" do
  # Same as the translations case above, through `page.lower`: the
  # neighbour re-rendered, its summary did not.
  it "recomputes a neighbour's summary when the page next to it is retitled" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_translation_listing_site
        File.write("config.toml", File.read("config.toml") + "\n[feeds]\nenabled = true\n")
        FileUtils.mkdir_p("templates/shortcodes")
        File.write("templates/shortcodes/nb.html", "{% if page.lower %}{{ page.lower.title }}{% endif %}|{% if page.higher %}{{ page.higher.title }}{% endif %}")
        File.write("content/posts/a.md", "+++\ntitle = \"A\"\ndate = \"2024-01-01\"\n+++\nlead {{ nb() }}\n\n<!-- more -->\n\nrest")
        File.write("content/posts/b.md", "+++\ntitle = \"B\"\ndate = \"2024-01-02\"\n+++\nb")
        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true
        File.read("public/rss.xml").should contain("<description>lead B|</description>")

        File.write("content/posts/b.md", "+++\ntitle = \"Bee\"\ndate = \"2024-01-02\"\n+++\nb")
        builder.run_incremental(["content/posts/b.md"], options).should be_true

        File.read("public/rss.xml").should contain("<description>lead Bee|</description>")
      end
    end
  end
end

describe "serve watch parity: an edited page's own relationship summary" do
  # The edited page's summary was rendered before its translations and
  # neighbours were relinked, so a shortcode printing them kept the pre-edit
  # titles: its own title in the switcher, the neighbour a date move brought.
  {
    {"retitled", %(title = "Ay"\ndate = "2024-01-01"\n), "lead Ay;가;|B|"},
    {"moved past its neighbour", %(title = "A"\ndate = "2024-01-05"\n), "lead A;가;||"},
  }.each do |label, front, expected|
    {"content", "content+template"}.each do |strategy|
      it "recomputes the summary of a page #{label} (#{strategy})" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            write_translation_listing_site
            File.write("config.toml", File.read("config.toml") + "\n[feeds]\nenabled = true\n")
            FileUtils.mkdir_p("templates/shortcodes")
            File.write("templates/shortcodes/rel.html",
              "{% for t in page.translations %}{{ t.title }};{% endfor %}|{% if page.lower %}{{ page.lower.title }}{% endif %}|")
            File.write("content/posts/b.md", "+++\ntitle = \"B\"\ndate = \"2024-01-02\"\n+++\nb")
            File.write("content/posts/c.md", "+++\ntitle = \"C\"\ndate = \"2024-01-03\"\n+++\nc")
            File.write("content/posts/a.md", "+++\ntitle = \"A\"\ndate = \"2024-01-01\"\n+++\nlead {{ rel() }}\n\n<!-- more -->\n\nrest")
            builder = Hwaro::Services::Server.new.watch_parity_builder
            options = watch_parity_options
            builder.run(options).should be_true
            File.read("public/rss.xml").should contain("<description>lead A;가;|B|</description>")

            File.write("content/posts/a.md", "+++\n#{front}+++\nlead {{ rel() }}\n\n<!-- more -->\n\nrest")
            if strategy == "content"
              builder.run_incremental(["content/posts/a.md"], options).should be_true
            else
              File.write("templates/unrelated.html", "<p>unused</p>")
              builder.run_incremental_then_rerender(["content/posts/a.md"], options).should be_true
            end

            File.read("public/rss.xml").should contain("<description>#{expected}</description>")
          end
        end
      end
    end
  end
end

# The post pages a cold build of the current source writes, by path.
private def watch_parity_cold_posts : Hash(String, String)
  options = watch_parity_options
  options.output_dir = "cold"
  Hwaro::Services::Server.new.watch_parity_builder.run(options).should be_true
  Dir.glob("cold/posts/**/*.html").sort!.to_h { |path| {path.lchop("cold/"), File.read(path)} }
ensure
  FileUtils.rm_rf("cold")
end

describe "serve watch parity: a page losing its URL to another" do
  # Bravo (`b.md`) loses its URL and writes nothing: it takes slug "a" and
  # `a.md`, which sorts first, keeps /posts/a/ — or a page that sorts before
  # it takes slug "b" from it: its series sibling `a.md`, or `a0.md`, which
  # shares nothing with it. Bravo must drop out of the neighbours and the
  # series, and come back once the slug goes, exactly as a cold build has it.
  zero = %(title = "Zero"\ndate = "2023-12-31"\ntags = ["z"]\n)
  {
    {"b", %(title = "Bravo"\ndate = "2024-01-02"\ntags = ["y"]\nseries = "s"\n), %(slug = "a"\n)},
    {"a", %(title = "Alpha"\ndate = "2024-01-01"\ntags = ["x"]\nseries = "s"\n), %(slug = "b"\n)},
    {"a0", zero, %(slug = "b"\n)},
  }.each do |name, front, slug_line|
    {"content", "content+template"}.each do |strategy|
      it "relinks neighbours and series around the loser (#{name}.md edit, #{strategy})" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            write_relations_site
            File.write("content/posts/a0.md", "+++\n#{zero}+++\nz")
            builder = Hwaro::Services::Server.new.watch_parity_builder
            options = watch_parity_options
            builder.run(options).should be_true

            [slug_line, ""].each_with_index do |slug, round|
              File.write("content/posts/#{name}.md", "+++\n#{slug}#{front}+++\n#{name}")
              if strategy == "content"
                builder.run_incremental(["content/posts/#{name}.md"], options).should be_true
              else
                File.write("templates/unrelated.html", "<p>unused v#{round}</p>")
                builder.run_incremental_then_rerender(["content/posts/#{name}.md"], options).should be_true
              end

              cold = watch_parity_cold_posts
              cold.values.any?(&.includes?("Bravo")).should eq(round == 1)
              cold.each { |path, html| {path, File.read(File.join("public", path))}.should eq({path, html}) }
            end
          end
        end
      end
    end
  end
end

describe "serve watch parity: --cache keys across sessions" do
  # A `serve --cache` session's watch passes saved the pages they wrote but
  # not the page-set fingerprint, so after an edit reverted between two
  # sessions the next start matched the first session's fingerprint and
  # kept the listings this session had re-rendered with the edit.
  {"content", "content+template"}.each do |strategy|
    it "re-renders the listings when an edit made in serve is reverted offline (#{strategy})" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = "https://example.com"\n))
          FileUtils.mkdir_p("content/posts")
          FileUtils.mkdir_p("templates")
          File.write("templates/index.html", "{% for p in site.pages %}[{{ p.title }}]{% endfor %}")
          File.write("templates/page.html", "{{ page.title }}")
          File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
          File.write("content/posts/a.md", "+++\ntitle = \"A\"\n+++\na")
          File.write("content/posts/b.md", "+++\ntitle = \"B\"\n+++\nb")
          options = watch_parity_options
          options.cache = true

          builder = Hwaro::Services::Server.new.watch_parity_builder
          builder.run(options).should be_true
          File.write("content/posts/a.md", "+++\ntitle = \"A2\"\n+++\na")
          if strategy == "content"
            builder.run_incremental(["content/posts/a.md"], options).should be_true
          else
            File.write("templates/unrelated.html", "<p>unused</p>")
            builder.run_incremental_then_rerender(["content/posts/a.md"], options).should be_true
          end
          File.read("public/index.html").should contain("[A2]")

          File.write("content/posts/a.md", "+++\ntitle = \"A\"\n+++\na")
          Hwaro::Services::Server.new.watch_parity_builder.run(options).should be_true
          File.read("public/index.html").should contain("[A]")
        end
      end
    end
  end

  # Same for what templates read outside the tracked files: a page the
  # session re-rendered against a moved `env()` value kept it once the value
  # went back, because the stored digest still described the old one.
  it "re-renders the pages when a render input that moved in serve is back" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "https://example.com"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", %({{ page.content }}{{ env("HWARO_SPEC_SERVE_INPUT", default="unset") }}))
        File.write("content/a.md", "+++\ntitle = \"A\"\n+++\na")
        options = watch_parity_options
        options.cache = true

        ENV["HWARO_SPEC_SERVE_INPUT"] = "one"
        builder = Hwaro::Services::Server.new.watch_parity_builder
        builder.run(options).should be_true
        ENV["HWARO_SPEC_SERVE_INPUT"] = "two"
        File.write("content/a.md", "+++\ntitle = \"A\"\n+++\na2")
        builder.run_incremental(["content/a.md"], options).should be_true
        File.read("public/a/index.html").should contain("two")

        ENV["HWARO_SPEC_SERVE_INPUT"] = "one"
        Hwaro::Services::Server.new.watch_parity_builder.run(options).should be_true
        File.read("public/a/index.html").should contain("one")
      ensure
        ENV.delete("HWARO_SPEC_SERVE_INPUT")
      end
    end
  end

  # Every build renders the 404 page, the taxonomy pages and feed templates
  # again, and the cold build does not record what they read. A watch pass
  # did, so their reads looked new and the next start rendered every page.
  {"content", "content+template"}.each do |strategy|
    it "keeps the cache when only 404, taxonomy and feed templates read an input (#{strategy})" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = "https://example.com"\n[[taxonomies]]\nname = "tags"\n[feeds]\nenabled = true\n))
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("templates")
          File.write("templates/page.html", "{{ page.title }}")
          File.write("templates/taxonomy_term.html", %({{ page.title }}{{ env(name="HWARO_SPEC_TERM", default="u") }}))
          File.write("templates/404.html", %({{ env(name="HWARO_SPEC_404", default="u") }}))
          File.write("templates/rss.xml", %(<rss>{{ env(name="HWARO_SPEC_FEED", default="u") }}</rss>))
          File.write("content/a.md", "+++\ntitle = \"A\"\ntags = [\"x\"]\n+++\na")
          File.write("content/b.md", "+++\ntitle = \"B\"\ntags = [\"y\"]\n+++\nb")
          options = watch_parity_options
          options.cache = true

          builder = Hwaro::Services::Server.new.watch_parity_builder
          builder.run(options).should be_true
          File.write("content/a.md", "+++\ntitle = \"A\"\ntags = [\"x\"]\n+++\na2")
          if strategy == "content"
            builder.run_incremental(["content/a.md"], options).should be_true
          else
            File.write("templates/unrelated.html", "<p>unused</p>")
            builder.run_incremental_then_rerender(["content/a.md"], options).should be_true
          end
          # The next pass takes what the last one rendered after recording.
          File.write("content/b.md", "+++\ntitle = \"B\"\ntags = [\"y\"]\n+++\nb2")
          builder.run_incremental(["content/b.md"], options).should be_true

          log = with_captured_log { Hwaro::Services::Server.new.watch_parity_builder.run(options).should be_true }
          log.should_not contain("invalidating all entries")
        end
      end
    end
  end

  # The next start prunes the generated outputs the last build recorded and
  # no longer writes; a watch pass did not record the term pages it added.
  {"content", "content+template"}.each do |strategy|
    it "prunes a term a session added once an offline edit removed it (#{strategy})" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = "https://example.com"\n[[taxonomies]]\nname = "tags"\n))
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("templates")
          File.write("templates/page.html", "{{ page.title }}")
          File.write("templates/taxonomy_term.html", "{{ page.title }}")
          File.write("content/a.md", "+++\ntitle = \"A\"\ntags = [\"x\"]\n+++\na")
          options = watch_parity_options
          options.cache = true

          builder = Hwaro::Services::Server.new.watch_parity_builder
          builder.run(options).should be_true
          File.write("content/a.md", "+++\ntitle = \"A\"\ntags = [\"x\", \"zz\"]\n+++\na")
          if strategy == "content"
            builder.run_incremental(["content/a.md"], options).should be_true
          else
            File.write("templates/unrelated.html", "<p>unused</p>")
            builder.run_incremental_then_rerender(["content/a.md"], options).should be_true
          end
          File.exists?("public/tags/zz/index.html").should be_true

          File.write("content/a.md", "+++\ntitle = \"A\"\ntags = [\"x\"]\n+++\na")
          Hwaro::Services::Server.new.watch_parity_builder.run(options).should be_true
          File.exists?("public/tags/zz/index.html").should be_false
          File.exists?("public/tags/x/index.html").should be_true
        end
      end
    end
  end

  # The cold build fingerprints the page set before the hooks assign auto
  # OG images; a watch pass fingerprinted it after, so the next start
  # re-rendered every listing and neighbour the session had re-rendered.
  it "keeps the listings cached across a session under auto OG images" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "https://example.com"\n[og.auto_image]\nenabled = true\nformat = "svg"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("templates/index.html", "{% for p in site.pages %}[{{ p.title }}={{ p.image }}]{% endfor %}")
        File.write("templates/page.html", "{{ page.content }}{% if page.lower %}{{ page.lower.image }}{% endif %}")
        File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
        File.write("content/a.md", "+++\ntitle = \"A\"\nweight = 1\n+++\na")
        File.write("content/b.md", "+++\ntitle = \"B\"\nweight = 2\n+++\nb")
        options = watch_parity_options
        options.cache = true

        builder = Hwaro::Services::Server.new.watch_parity_builder
        builder.run(options).should be_true
        File.write("content/a.md", "+++\ntitle = \"A2\"\nweight = 1\n+++\na")
        builder.run_incremental(["content/a.md"], options).should be_true
        File.read("public/index.html").should contain("[A2=/og-images/a.svg]")

        log = with_captured_log { Hwaro::Services::Server.new.watch_parity_builder.run(options).should be_true }
        log.should contain("render: 0 pages")
        File.read("public/index.html").should contain("[A2=/og-images/a.svg]")
      end
    end
  end
end

describe "serve watch parity: a page turning headless under auto OG images" do
  # The re-parse keeps an auto-assigned OG `image` the front matter cannot
  # restore — also for a page just set `render = false`, which a full build
  # never gives one, so listings printing `p.image` kept a URL no file
  # answers.
  it "drops the auto OG image of a page set to render = false" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "https://example.com"\n[og.auto_image]\nenabled = true\nformat = "svg"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("templates/index.html", "{% for p in site.pages %}[{{ p.title }}={{ p.image }}]{% endfor %}")
        File.write("templates/page.html", "{{ page.title }}")
        File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
        File.write("content/a.md", "+++\ntitle = \"A\"\n+++\na")
        File.write("content/b.md", "+++\ntitle = \"B\"\n+++\nb")
        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true
        File.read("public/index.html").should contain("[B=/og-images/b.svg]")

        File.write("content/b.md", "+++\ntitle = \"B\"\nrender = false\n+++\nb")
        builder.run_incremental(["content/b.md"], options).should be_true

        File.read("public/index.html").should contain("[B=]")
      end
    end
  end
end
