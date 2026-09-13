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

      def staleness_resolve_extra_roots(env : String? = nil) : Array(String)
        @extra_watch_roots = resolve_extra_watch_roots(load_config_or_nil(env))
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

  # Scanning the project root would sweep the build output, `.git` and every
  # dependency directory on every poll; an escaping path is refused outright.
  it "refuses a project-root or escaping [assets] source_dir (L3)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_listing_site
        {".", "", "../elsewhere"}.each do |source_dir|
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
