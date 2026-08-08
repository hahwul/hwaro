require "../spec_helper"
require "../../src/services/server/server"

# Regression coverage for the serve watch-lane fixes:
# - S1: apply_changeset owns the @rebuild_failed reset (success only)
# - S2: post-rebuild stale pruning must not delete outputs the rebuilt
#   site re-created from a different source
# - S3: the watcher baseline is captured BEFORE the initial build
# - A2: plain (non-Sass) bundle-source saves refresh fingerprinted
#   bundles AND the pages that reference them
# - A13: a draft flip on the content+template path refreshes the SEO
#   surfaces even when the template edit was a bare touch

# Reopened for the private seams; names are prefixed so they can't collide
# with the shims other spec files install.
module Hwaro
  module Services
    class Server
      def watch_fixes_builder : Hwaro::Core::Build::Builder
        @builder
      end

      def watch_fixes_apply_changeset(changeset : ChangeSet, options : Config::Options::BuildOptions)
        apply_changeset(changeset, options)
      end

      def watch_fixes_rebuild_failed? : Bool
        @rebuild_failed
      end

      def watch_fixes_set_rebuild_failed(value : Bool)
        @rebuild_failed = value
      end

      def watch_fixes_capture_baseline
        capture_watch_baseline
      end

      def watch_fixes_initial_watch_mtimes : Hash(String, FileStamp)
        initial_watch_mtimes
      end

      def watch_fixes_scan_mtimes : Hash(String, FileStamp)
        scan_mtimes
      end

      def watch_fixes_detect_changes(old_mtimes : Hash(String, FileStamp), new_mtimes : Hash(String, FileStamp)) : ChangeSet
        detect_changes(old_mtimes, new_mtimes)
      end
    end
  end
end

private def watch_changeset(
  modified_content = [] of String,
  modified_static = [] of String,
  added = [] of String,
  removed = [] of String,
) : Hwaro::Services::ChangeSet
  Hwaro::Services::ChangeSet.new(
    modified_content: modified_content,
    modified_templates: [] of String,
    modified_static: modified_static,
    added_files: added,
    removed_files: removed,
    config_changed: false,
  )
end

private def watch_options : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
  options.serve_mode = true
  options
end

private def write_minimal_site
  File.write("config.toml", <<-TOML
    title = "Watch Fixes"
    base_url = "https://example.com"

    [sitemap]
    enabled = true
    TOML
  )
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", "<html><body>{{ content }}</body></html>")
end

describe "serve watch-lane regressions" do
  # S1: a Bool-failure build (pre-hook failure — Builder#run returns false
  # without raising) must leave @rebuild_failed set. The watch loop used to
  # clobber it back to false in the same iteration because apply_changeset
  # returned normally.
  it "keeps the failure flag set after a build that fails without raising (S1)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_minimal_site
        File.write("content/foo.md", "---\ntitle: Foo\n---\nBody")
        File.write("config.toml", <<-TOML
          title = "Watch Fixes"
          base_url = "https://example.com"

          [build.hooks]
          pre = ["false"]
          TOML
        )

        server = Hwaro::Services::Server.new
        server.watch_fixes_set_rebuild_failed(false)
        server.watch_fixes_apply_changeset(watch_changeset(modified_content: ["content/foo.md"]), watch_options)

        server.watch_fixes_rebuild_failed?.should be_true
      end
    end
  end

  # S1: the reset now lives inside apply_changeset, gated on success — the
  # recovery contract (next changeset escalates to :full, then clears).
  it "clears the failure flag only through a successful apply_changeset (S1)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_minimal_site
        File.write("content/foo.md", "---\ntitle: Foo\n---\nBody")

        server = Hwaro::Services::Server.new
        options = watch_options
        server.watch_fixes_builder.run(options).should be_true

        server.watch_fixes_set_rebuild_failed(true)
        server.watch_fixes_apply_changeset(watch_changeset(modified_content: ["content/foo.md"]), options)

        server.watch_fixes_rebuild_failed?.should be_false
      end
    end
  end

  # S2: one changeset deletes foo.md and re-creates the same URL from
  # foo/index.md. The stale list (mapped through the OLD site) contains
  # public/foo/index.html — which the rebuild just rewrote for the new
  # owner. It must survive the post-rebuild pruning.
  it "does not delete an output the rebuilt site re-created from a different source (S2)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_minimal_site
        File.write("content/foo.md", "---\ntitle: Foo\n---\nfirst body")

        server = Hwaro::Services::Server.new
        options = watch_options
        server.watch_fixes_builder.run(options).should be_true
        File.exists?("public/foo/index.html").should be_true

        File.delete("content/foo.md")
        FileUtils.mkdir_p("content/foo")
        File.write("content/foo/index.md", "---\ntitle: Foo\n---\nsecond body")

        server.watch_fixes_apply_changeset(
          watch_changeset(removed: ["content/foo.md"], added: ["content/foo/index.md"]),
          options,
        )

        File.exists?("public/foo/index.html").should be_true
        File.read("public/foo/index.html").should contain("second body")
      end
    end
  end

  # S2: pruning must still remove outputs the rebuilt site does NOT claim.
  it "still prunes outputs whose source is gone for good (S2)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_minimal_site
        File.write("content/foo.md", "---\ntitle: Foo\n---\nBody")
        File.write("content/keep.md", "---\ntitle: Keep\n---\nBody")

        server = Hwaro::Services::Server.new
        options = watch_options
        server.watch_fixes_builder.run(options).should be_true
        File.exists?("public/foo/index.html").should be_true

        File.delete("content/foo.md")
        server.watch_fixes_apply_changeset(watch_changeset(removed: ["content/foo.md"]), options)

        File.exists?("public/foo/index.html").should be_false
        File.exists?("public/keep/index.html").should be_true
      end
    end
  end

  # S3: the baseline snapshot is taken before the initial build, so an edit
  # saved while the build runs shows up in the watcher's first diff.
  it "seeds the watcher baseline from the pre-build snapshot (S3)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_minimal_site
        File.write("content/foo.md", "---\ntitle: Foo\n---\nbefore")

        server = Hwaro::Services::Server.new
        server.watch_fixes_capture_baseline

        # Simulates a save landing during the initial build (size change so
        # the FileStamp differs even under coarse mtime granularity).
        File.write("content/foo.md", "---\ntitle: Foo\n---\nafter — a longer body")

        initial = server.watch_fixes_initial_watch_mtimes
        changes = server.watch_fixes_detect_changes(initial, server.watch_fixes_scan_mtimes)
        changes.modified_content.should eq(["content/foo.md"])

        # The baseline is consumed exactly once; afterwards the loop falls
        # back to a fresh scan.
        second = server.watch_fixes_initial_watch_mtimes
        server.watch_fixes_detect_changes(second, server.watch_fixes_scan_mtimes).empty?.should be_true
      end
    end
  end

  # A2: a plain JS bundle-source save under the :static strategy must
  # re-run the bundle pipeline (new fingerprinted file) AND re-render pages
  # so their asset() references point at the new hash.
  it "refreshes fingerprinted bundles and page references on a plain bundle-source save (A2)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", <<-TOML
          title = "Watch Fixes"
          base_url = "https://example.com"

          [assets]
          enabled = true
          minify = false
          fingerprint = true

          [[assets.bundles]]
          name = "app.js"
          files = ["js/app.js"]
          TOML
        )
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        FileUtils.mkdir_p("static/js")
        File.write("templates/page.html", %(<script src="{{ asset(name='app.js') }}"></script>{{ content }}))
        File.write("content/page.md", "---\ntitle: Test\n---\nHello")
        File.write("static/js/app.js", "console.log('one');")

        server = Hwaro::Services::Server.new
        options = watch_options
        server.watch_fixes_builder.run(options).should be_true

        old_bundles = Dir.glob("public/assets/app.*.js")
        old_bundles.size.should eq(1)
        old_name = File.basename(old_bundles[0])
        File.read("public/page/index.html").should contain(old_name)

        File.write("static/js/app.js", "console.log('two, changed');")
        server.watch_fixes_apply_changeset(watch_changeset(modified_static: ["static/js/app.js"]), options)

        new_name = Dir.glob("public/assets/app.*.js").map { |p| File.basename(p) }.find { |n| n != old_name }
        new_name = new_name.should_not be_nil
        File.read(File.join("public/assets", new_name)).should contain("two, changed")
        File.read("public/page/index.html").should contain(new_name)
      end
    end
  end

  # A13: on the content+template path, a page flipped to draft alongside a
  # bare template touch (identical template bytes) must vanish from the
  # sitemap — the SEO refresh used to be gated on template semantics only,
  # and the identical-templates early return skipped everything.
  it "drops a page flipped to draft from the sitemap on the content+template path (A13)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_minimal_site
        File.write("content/post.md", "---\ntitle: Post\n---\nBody")
        # A second, live page: Sitemap.generate keeps the OLD file on disk
        # when the page set is empty, so the refresh is only observable with
        # a survivor in the set (the realistic shape anyway).
        File.write("content/keep.md", "---\ntitle: Keep\n---\nBody")

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
        options = watch_options
        builder.run(options).should be_true
        File.read("public/sitemap.xml").should contain("/post/")

        File.write("content/post.md", "---\ntitle: Post\ndraft: true\n---\nBody")
        FileUtils.touch("templates/page.html")

        builder.run_incremental_then_rerender(["content/post.md"], options).should be_true

        File.exists?("public/post/index.html").should be_false
        File.read("public/sitemap.xml").should_not contain("/post/")
      end
    end
  end
end
