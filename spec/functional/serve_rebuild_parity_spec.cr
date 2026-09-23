require "../spec_helper"
require "../../src/services/server/server"

# Serve rebuilds whose output differed from a cold build of the same final
# source: the incremental strategies skipped a file the cold build rewrites.

private def parity_options : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
  options.serve_mode = true
  options.preserve_output = true
  options
end

private def write_sidebar_site
  File.write("config.toml", <<-TOML
    title = "Sidebar"
    base_url = "https://example.com"
    TOML
  )
  FileUtils.mkdir_p("content/guide")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", "<html><body>{{ page.title }}</body></html>")
  # The 404 page prints the site's pages, like a docs sidebar or a nav.
  File.write("templates/404.html", "<html><body>{% for p in site.pages %}[{{ p.title }}]{% endfor %}</body></html>")
  File.write("content/guide/intro.md", "---\ntitle: Old Intro\n---\nbody")
end

describe "serve rebuild parity" do
  # The 404 page renders site-wide listings but was never in any incremental
  # render set, so it kept printing pre-edit titles until a full rebuild.
  it "regenerates 404.html on an incremental content rebuild" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_sidebar_site
        builder = Hwaro::Services::Server.new.@builder
        options = parity_options
        builder.run(options).should be_true
        File.read("public/404.html").should contain("[Old Intro]")

        File.write("content/guide/intro.md", "---\ntitle: New Intro\n---\nbody")
        builder.run_incremental(["content/guide/intro.md"], options).should be_true

        File.read("public/404.html").should contain("[New Intro]")
      end
    end
  end

  it "regenerates 404.html when content and an unrelated template change together" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_sidebar_site
        builder = Hwaro::Services::Server.new.@builder
        options = parity_options
        builder.run(options).should be_true

        File.write("content/guide/intro.md", "---\ntitle: New Intro\n---\nbody")
        File.write("templates/page.html", "<html><body><h1>{{ page.title }}</h1></body></html>")
        builder.run_incremental_then_rerender(["content/guide/intro.md"], options).should be_true

        File.read("public/404.html").should contain("[New Intro]")
      end
    end
  end

  # `[amp]` mirrors were only written by the full build's AfterRender hook.
  # An incremental re-render rewrote the canonical page without its
  # `<link rel="amphtml">` and left the mirror on the pre-edit content; a
  # deleted page kept its mirror.
  it "keeps AMP mirrors in step with incremental rebuilds" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_amp_site
        builder = Hwaro::Services::Server.new.@builder
        options = parity_options
        builder.run(options).should be_true
        File.read("public/amp/posts/one/index.html").should contain("Old One")

        File.write("content/posts/one.md", "---\ntitle: New One\n---\nbody")
        builder.run_incremental(["content/posts/one.md"], options).should be_true

        File.read("public/amp/posts/one/index.html").should contain("New One")
        File.read("public/posts/one/index.html").should contain(%(rel="amphtml"))
      end
    end
  end

  it "maps a deleted page to its AMP mirror" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_amp_site
        File.write("content/posts/two.md", "---\ntitle: Two\n---\nbody")
        builder = Hwaro::Services::Server.new.@builder
        options = parity_options
        builder.run(options).should be_true
        File.exists?("public/amp/posts/one/index.html").should be_true
        File.exists?("public/amp/posts/two/index.html").should be_true

        stale = builder.stale_outputs_for_removed(["content/posts/one.md"], "public")
        stale.should contain(File.join("public", "amp", "posts", "one", "index.html"))
      end
    end
  end

  it "removes the AMP mirror of a page an incremental edit drafted" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_amp_site
        File.write("content/posts/two.md", "---\ntitle: Two\n---\nbody")
        builder = Hwaro::Services::Server.new.@builder
        options = parity_options
        builder.run(options).should be_true
        File.exists?("public/amp/posts/two/index.html").should be_true

        File.write("content/posts/two.md", "---\ntitle: Two\ndraft: true\n---\nbody")
        builder.run_incremental(["content/posts/two.md"], options).should be_true
        File.exists?("public/amp/posts/two/index.html").should be_false
      end
    end
  end

  # Pruning the old output of a moved page deletes the directory it leaves
  # empty, but the builder's mkdir memo still listed it — so moving the page
  # back failed the rebuild with ENOENT on the temp file.
  it "renders a page back into a directory an earlier rebuild pruned" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_sidebar_site
        builder = Hwaro::Services::Server.new.@builder
        options = parity_options
        builder.run(options).should be_true
        File.exists?("public/guide/intro/index.html").should be_true

        File.write("content/guide/intro.md", "---\ntitle: Old Intro\nslug: away\n---\nbody")
        builder.run_incremental(["content/guide/intro.md"], options).should be_true
        Dir.exists?("public/guide/intro").should be_false

        File.write("content/guide/intro.md", "---\ntitle: Old Intro\n---\nbody")
        builder.run_incremental(["content/guide/intro.md"], options).should be_true
        File.exists?("public/guide/intro/index.html").should be_true
      end
    end
  end

  # A serve re-parse works on the live page object, and the `<!-- more -->`
  # chunk was never cleared — deleting the marker left the old marker
  # summary in every listing instead of the automatic excerpt.
  it "drops the marker summary once the marker is deleted" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_sidebar_site
        File.write("templates/section.html", "<html><body>{% for p in section.pages %}[{{ p.summary }}]{% endfor %}</body></html>")
        File.write("content/guide/_index.md", "---\ntitle: Guide\n---\n")
        File.write("content/guide/intro.md", "---\ntitle: Intro\n---\nMarker summary\n\n<!-- more -->\n\nrest")
        builder = Hwaro::Services::Server.new.@builder
        options = parity_options
        builder.run(options).should be_true
        File.read("public/guide/index.html").should contain("Marker summary")

        File.write("content/guide/intro.md", "---\ntitle: Intro\n---\nPlain body now")
        builder.run_incremental(["content/guide/intro.md"], options).should be_true

        listing = File.read("public/guide/index.html")
        listing.should contain("Plain body now")
        listing.should_not contain("Marker summary")
      end
    end
  end

  # A page's version switcher is derived from its counterparts in the other
  # versions, but `Versions.link!` only ran in the full parse: re-slugging,
  # drafting or un-rendering the latest counterpart left the old version's
  # page linking (and canonicalizing) to a URL that no longer existed.
  it "refreshes other versions' switchers when a counterpart stops rendering" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", <<-TOML
          title = "V"
          base_url = "https://example.com"

          [[versions.list]]
          name = "v2"
          path = "docs/v2"
          latest = true

          [[versions.list]]
          name = "v1"
          path = "docs/v1"
          TOML
        )
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "<html><head>{{ canonical_tag }}</head><body>{% for v in page.version_links %}[{{ v.name }} {{ v.url }} {{ v.exists }}]{% endfor %}</body></html>")
        {"v1", "v2"}.each do |v|
          FileUtils.mkdir_p("content/docs/#{v}")
          File.write("content/docs/#{v}/_index.md", "---\ntitle: Docs #{v}\n---\n")
          File.write("content/docs/#{v}/legacy.md", "---\ntitle: Legacy #{v}\n---\nbody")
        end
        builder = Hwaro::Services::Server.new.@builder
        options = parity_options
        builder.run(options).should be_true
        File.read("public/docs/v1/legacy/index.html").should contain("[v2 /docs/legacy/ true]")

        File.write("content/docs/v2/legacy.md", "---\ntitle: Legacy v2\nrender: false\n---\nbody")
        builder.run_incremental(["content/docs/v2/legacy.md"], options).should be_true

        old_version = File.read("public/docs/v1/legacy/index.html")
        old_version.should contain("[v2 /docs/ false]")
        old_version.should contain(%(href="https://example.com/docs/v1/legacy/"))
      end
    end
  end
end

private def write_amp_site
  File.write("config.toml", <<-TOML
    title = "Amp"
    base_url = "https://example.com"

    [amp]
    enabled = true
    sections = ["posts"]
    TOML
  )
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", "<html><head><title>{{ page.title }}</title></head><body>{{ page.title }}</body></html>")
  File.write("templates/section.html", "<html><head><title>{{ section.title }}</title></head><body>list</body></html>")
  File.write("content/posts/_index.md", "---\ntitle: Posts\n---\n")
  File.write("content/posts/one.md", "---\ntitle: Old One\n---\nbody")
end
