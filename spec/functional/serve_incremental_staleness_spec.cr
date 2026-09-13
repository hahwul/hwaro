require "../spec_helper"
require "../../src/services/server/server"

# Regression coverage for the serve lane's "the watcher ran but the browser
# still shows the old bytes" defects:
#
# - L1: a `.markdown` page landed in the content-ASSET bucket, whose
#   republish path drops page extensions — so editing one rebuilt nothing.
# - L2: pages that render a GLOBAL listing (the homepage's "latest posts",
#   an archive, a nav built from `site.menus`) were never selected by the
#   incremental strategies, so a retitled post left them stale.
# - L3: an `[assets] source_dir` outside `static/` was not watched at all,
#   so bundle edits produced no event and the fingerprinted bundle kept
#   serving its pre-edit bytes.
#
# Reopened for the private seams; names are prefixed so they can't collide
# with the shims other spec files install.
module Hwaro
  module Services
    class Server
      def staleness_builder : Hwaro::Core::Build::Builder
        @builder
      end

      def staleness_apply_changeset(changeset : ChangeSet, options : Config::Options::BuildOptions)
        apply_changeset(changeset, options)
      end

      def staleness_detect_changes(old_mtimes : Hash(String, FileStamp), new_mtimes : Hash(String, FileStamp)) : ChangeSet
        detect_changes(old_mtimes, new_mtimes)
      end

      def staleness_scan_mtimes : Hash(String, FileStamp)
        scan_mtimes
      end

      def staleness_resolve_extra_roots(env : String? = nil, output_dir : String = "public") : Array(String)
        @extra_watch_roots = resolve_extra_watch_roots(load_config_or_nil(env), output_dir)
      end
    end
  end
end

private def staleness_options : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
  options.serve_mode = true
  options
end

# A site with a listing page that owns none of the content it prints —
# `content/misc/archive.md` is neither the edited page, its section, nor one
# of its ancestors (the edits below all land under `content/posts/`), so no
# incremental selection reaches it. That is the shape the KNOWN LIMITATION
# used to leave stale.
private def write_listing_site
  File.write("config.toml", <<-TOML
    title = "Listing Site"
    base_url = "https://example.com"
    TOML
  )
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", "<html><body>{{ page.title }}|{{ content }}</body></html>")
  File.write("templates/archive.html", <<-HTML
    <html><body>{% for p in site.pages %}<a href="{{ p.url }}">{{ p.title }}</a>{% endfor %}</body></html>
    HTML
  )
  FileUtils.mkdir_p("content/misc")
  File.write("content/index.md", "---\ntitle: Home\nweight: 1\n---\nhome")
  File.write("content/misc/archive.md", "---\ntitle: Archive\nweight: 2\ntemplate: archive.html\n---\nlist")
  # Neighbours for the edited post, so the reading-order rule (which pulls a
  # page's prev/next into the render set) cannot be what selects the listing
  # page — the fan-out under test has to be.
  5.times do |i|
    File.write("content/posts/pad#{i}.md", "---\ntitle: Pad #{i}\nweight: #{10 + i}\n---\npadding")
  end
end

describe "serve incremental staleness" do
  # L1: `.markdown` is a first-class page extension (ReadContent::PAGE_EXTENSIONS),
  # but the watcher's own `.md`-only test sent it to the content-asset bucket.
  # The asset republish then skipped it (a page extension is never in
  # `[content.files] allow_extensions`), so the rebuild was a silent no-op.
  it "classifies a .markdown page as content, not a content asset (L1)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_listing_site
        File.write("content/posts/note.markdown", "---\ntitle: Note\n---\nORIGINAL")

        server = Hwaro::Services::Server.new
        before = server.staleness_scan_mtimes
        File.write("content/posts/note.markdown", "---\ntitle: Note\n---\nCHANGED")
        # Force a stamp move on filesystems with coarse mtimes.
        File.touch("content/posts/note.markdown", Time.local + 2.seconds)

        changeset = server.staleness_detect_changes(before, server.staleness_scan_mtimes)
        changeset.modified_content.should eq(["content/posts/note.markdown"])
        changeset.modified_content_files.should be_empty
        changeset.rebuild_strategy.should eq(:incremental)
      end
    end
  end

  it "re-renders an edited .markdown page through the incremental strategy (L1)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_listing_site
        File.write("content/posts/note.markdown", "---\ntitle: Note\n---\nORIGINAL")

        server = Hwaro::Services::Server.new
        options = staleness_options
        server.staleness_builder.run(options).should be_true
        File.read("public/posts/note/index.html").should contain("ORIGINAL")

        # Driven through detect_changes, not a hand-built changeset: the bug
        # was in classification, so the spec has to let the watcher classify.
        before = server.staleness_scan_mtimes
        File.write("content/posts/note.markdown", "---\ntitle: Note\n---\nCHANGED")
        File.touch("content/posts/note.markdown", Time.local + 2.seconds)
        server.staleness_apply_changeset(
          server.staleness_detect_changes(before, server.staleness_scan_mtimes),
          options,
        )

        File.read("public/posts/note/index.html").should contain("CHANGED")
      end
    end
  end

  # L2: the homepage lists `site.pages`. It owns no changed file, so none of
  # the incremental selections reach it — it kept printing the pre-edit title
  # until something unrelated re-rendered it.
  it "re-renders a global listing page when an edit moves the page set (L2)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_listing_site
        File.write("content/posts/one.md", "---\ntitle: First Title\nweight: 12\n---\nbody")

        server = Hwaro::Services::Server.new
        options = staleness_options
        server.staleness_builder.run(options).should be_true
        File.read("public/misc/archive/index.html").should contain("First Title")

        File.write("content/posts/one.md", "---\ntitle: Second Title\nweight: 12\n---\nbody")
        server.staleness_builder.run_incremental(["content/posts/one.md"], options).should be_true

        listing = File.read("public/misc/archive/index.html")
        listing.should contain("Second Title")
        listing.should_not contain("First Title")
      end
    end
  end

  # The fingerprint gate is what keeps the fan-out cheap: an edit that moves
  # nothing a listing prints must not drag the listings into the render set.
  it "leaves listing pages alone when the edit moves nothing they print (L2)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_listing_site
        File.write("content/posts/one.md", "---\ntitle: Only Title\nweight: 12\n---\nfirst body")

        server = Hwaro::Services::Server.new
        options = staleness_options
        server.staleness_builder.run(options).should be_true
        listing_mtime = File.info("public/misc/archive/index.html").modification_time

        File.write("content/posts/one.md", "---\ntitle: Only Title\nweight: 12\n---\nsecond body")
        server.staleness_builder.run_incremental(["content/posts/one.md"], options).should be_true

        File.read("public/posts/one/index.html").should contain("second body")
        File.info("public/misc/archive/index.html").modification_time.should eq(listing_mtime)
      end
    end
  end

  # Same gap on the content+template strategy, whose selective re-render
  # only covers template-affected pages.
  it "re-renders a global listing page on the content+template strategy (L2)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_listing_site
        File.write("content/posts/one.md", "---\ntitle: First Title\nweight: 12\n---\nbody")

        server = Hwaro::Services::Server.new
        options = staleness_options
        server.staleness_builder.run(options).should be_true
        File.read("public/misc/archive/index.html").should contain("First Title")

        File.write("content/posts/one.md", "---\ntitle: Second Title\nweight: 12\n---\nbody")
        File.write("templates/page.html", "<html><body>v2 {{ page.title }}|{{ content }}</body></html>")
        server.staleness_builder.run_incremental_then_rerender(["content/posts/one.md"], options).should be_true

        File.read("public/misc/archive/index.html").should contain("Second Title")
      end
    end
  end

  # L3: the watcher scanned five fixed roots. A project that keeps bundle
  # sources outside static/ got no event for them at all.
  it "watches a configured [assets] source_dir outside static/ (L3)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_listing_site
        FileUtils.mkdir_p("assets/js")
        File.write("assets/js/app.js", "console.log(1)")
        File.write("config.toml", <<-TOML
          title = "Listing Site"
          base_url = "https://example.com"

          [assets]
          enabled = true
          source_dir = "assets"

          [[assets.bundles]]
          name = "app.js"
          files = ["js/app.js"]
          TOML
        )

        server = Hwaro::Services::Server.new
        server.staleness_resolve_extra_roots.should eq(["assets"])

        before = server.staleness_scan_mtimes
        before.has_key?("assets/js/app.js").should be_true

        File.write("assets/js/app.js", "console.log(2)")
        File.touch("assets/js/app.js", Time.local + 2.seconds)
        changeset = server.staleness_detect_changes(before, server.staleness_scan_mtimes)
        changeset.modified_static.should eq(["assets/js/app.js"])
        changeset.rebuild_strategy.should eq(:static)
      end
    end
  end

  it "adds no extra root when the asset sources already live under static/ (L3)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_listing_site
        File.write("config.toml", <<-TOML
          title = "Listing Site"
          base_url = "https://example.com"

          [assets]
          enabled = true

          [[assets.bundles]]
          name = "app.js"
          files = ["js/app.js"]
          TOML
        )

        server = Hwaro::Services::Server.new
        server.staleness_resolve_extra_roots.should be_empty
      end
    end
  end

  # Every rejection here leaves the directory simply unwatched, which is
  # never worse than before the fix. Scanning the project root would sweep
  # the build output and `.git` every 500ms, and an absolute root — `"/"`, or
  # any typo that normalizes to one — would put a full-filesystem glob on the
  # poll loop.
  it "refuses a project-root, absolute or escaping [assets] source_dir (L3)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_listing_site
        {".", "", "../elsewhere", "/", "/srv/assets"}.each do |source_dir|
          File.write("config.toml", <<-TOML
            title = "Listing Site"
            base_url = "https://example.com"

            [assets]
            enabled = true
            source_dir = "#{source_dir}"
            TOML
          )
          Hwaro::Services::Server.new.staleness_resolve_extra_roots.should be_empty
        end
      end
    end
  end

  # Watching the build output would re-stat the whole generated tree every
  # poll and read the build's own writes back as source changes.
  it "refuses an [assets] source_dir that overlaps the output directory (L3)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_listing_site
        {"public", "public/js", "."}.each do |source_dir|
          File.write("config.toml", <<-TOML
            title = "Listing Site"
            base_url = "https://example.com"

            [assets]
            enabled = true
            source_dir = "#{source_dir}"
            TOML
          )
          Hwaro::Services::Server.new.staleness_resolve_extra_roots(output_dir: "public").should be_empty
        end
      end
    end
  end

  # A disabled pipeline reads nothing from source_dir, so watching it would
  # only cost stat calls on every poll.
  it "adds no extra root while the asset pipeline is disabled (L3)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_listing_site
        File.write("config.toml", <<-TOML
          title = "Listing Site"
          base_url = "https://example.com"

          [assets]
          enabled = false
          source_dir = "assets"
          TOML
        )

        Hwaro::Services::Server.new.staleness_resolve_extra_roots.should be_empty
      end
    end
  end
end

# The fan-out is only usable on a dev server if it stays proportional. A
# nav partial in the shared base layout puts `get_menu` in EVERY page's
# template closure, and tag pills put `get_taxonomy_url` in every post's —
# gating those on the broad page-set digest (what `--cache` does) selects the
# whole site for any metadata edit. Each marker class is paired with a digest
# of what it actually reads instead.
private def write_chrome_site
  File.write("config.toml", <<-TOML
    title = "Chrome Site"
    base_url = "https://example.com"

    [[taxonomies]]
    name = "tags"
    TOML
  )
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("templates/base.html", <<-HTML
    <html><body><nav>{% for item in get_menu(name="main") %}<a href="{{ item.href }}">{{ item.name }}</a>{% endfor %}</nav>{% block main %}{% endblock %}</body></html>
    HTML
  )
  File.write("templates/page.html", <<-HTML
    {% extends "base.html" %}{% block main %}<h1>{{ page.title }}</h1>{% for t in page.tags %}<a href="{{ get_taxonomy_url(kind='tags', term=t) }}">{{ t }}</a>{% endfor %}{{ content }}{% endblock %}
    HTML
  )
  File.write("templates/index.html", <<-HTML
    {% extends "base.html" %}{% block main %}{% for p in site.pages %}<a href="{{ p.url }}">{{ p.title }}</a>{% endfor %}{% endblock %}
    HTML
  )
  File.write("content/index.md", "---\ntitle: Home\ntemplate: index.html\nmenus: [main]\n---\nhome")
  8.times do |i|
    File.write("content/posts/p#{i}.md", "---\ntitle: Post #{i}\nweight: #{10 + i}\ntags: [t#{i % 3}]\n---\nbody #{i}")
  end
end

# Count the output files a rebuild rewrote, by mtime.
private def rewritten_since(marker : Time) : Int32
  Dir.glob("public/**/*.html").count { |f| File.info(f).modification_time > marker }
end

describe "serve listing fan-out proportionality" do
  it "does not re-render the whole site when only the shared nav carries a marker" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_chrome_site

        server = Hwaro::Services::Server.new
        options = staleness_options
        server.staleness_builder.run(options).should be_true
        total = Dir.glob("public/**/*.html").size
        total.should be > 5

        marker = Time.local
        sleep 1.1.seconds
        File.write("content/posts/p3.md", "---\ntitle: Post 3 RETITLED\nweight: 13\ntags: [t0]\n---\nbody 3")
        server.staleness_builder.run_incremental(["content/posts/p3.md"], options).should be_true

        # The edited post, its reading-order neighbours and the one page that
        # really prints `site.pages` — not the nav on all nine.
        rewritten_since(marker).should be < total
        File.read("public/index.html").should contain("Post 3 RETITLED")
      end
    end
  end

  # The menu projection is not merely ignored: an edit that DOES move a menu
  # entry has to reach every page that renders the nav.
  it "re-renders every page when a menu entry's title changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_chrome_site

        server = Hwaro::Services::Server.new
        options = staleness_options
        server.staleness_builder.run(options).should be_true

        File.write("content/index.md", "---\ntitle: Renamed Home\ntemplate: index.html\nmenus: [main]\n---\nhome")
        server.staleness_builder.run_incremental(["content/index.md"], options).should be_true

        File.read("public/posts/p5/index.html").should contain("Renamed Home")
      end
    end
  end

  # Same for the taxonomy-slug projection behind `get_taxonomy_url`.
  it "re-renders tag-pill pages when the term set changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_chrome_site

        server = Hwaro::Services::Server.new
        options = staleness_options
        server.staleness_builder.run(options).should be_true

        File.write("content/posts/p2.md", "---\ntitle: Post 2\nweight: 12\ntags: [t2, brandnew]\n---\nbody 2")
        server.staleness_builder.run_incremental(["content/posts/p2.md"], options).should be_true

        File.read("public/posts/p2/index.html").should contain("tags/brandnew")
      end
    end
  end
end

describe "serve watch reporting" do
  # The watch timeline used to print "config.toml" for every config event,
  # pointing the developer at a file they had not touched.
  it "names the env overlay a config change actually came from" do
    changeset = Hwaro::Services::ChangeSet.new(
      modified_content: [] of String,
      modified_templates: [] of String,
      modified_static: [] of String,
      added_files: [] of String,
      removed_files: [] of String,
      config_changed: true,
      config_files: ["config.staging.toml"],
    )
    changeset.display.should eq("config.staging.toml")
  end

  it "falls back to config.toml when no file was recorded" do
    changeset = Hwaro::Services::ChangeSet.new(
      modified_content: [] of String,
      modified_templates: [] of String,
      modified_static: [] of String,
      added_files: [] of String,
      removed_files: [] of String,
      config_changed: true,
    )
    changeset.display.should eq("config.toml")
  end
end
