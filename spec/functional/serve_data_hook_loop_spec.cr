require "../spec_helper"
require "../../src/services/server/server"

# Regression coverage for #755: a `build.hooks.pre` command that rewrites an
# unchanged payload into data/ (the workflow #752 documents — `curl -o
# data/x.json`) used to retrigger a full rebuild forever. Any data/i18n
# change forces a full rebuild, a full rebuild re-runs the pre hooks, and the
# watcher compared mtime+size only — so the hook's byte-identical rewrite
# registered as a modification, once per debounce interval, for the lifetime
# of the serve session.
#
# The watcher now carries a content digest in the FileStamp for the
# full-rebuild buckets (data/**, i18n/**) and drops stamp changes whose
# bytes are unchanged. Genuinely changed payloads must still force the full
# rebuild they always did, and content/ / templates/ / static/ must stay
# mtime-based (their rebuild paths never re-run hooks, so they cannot loop).

# Reopened for the private seams; names are prefixed so they can't collide
# with the shims other spec files install.
module Hwaro
  module Services
    class Server
      def data_loop_builder : Hwaro::Core::Build::Builder
        @builder
      end

      def data_loop_capture_baseline
        capture_watch_baseline
      end

      def data_loop_initial_watch_mtimes : Hash(String, FileStamp)
        initial_watch_mtimes
      end

      def data_loop_scan(prev : Hash(String, FileStamp)? = nil) : Hash(String, FileStamp)
        scan_mtimes(prev)
      end

      def data_loop_detect_changes(old_mtimes : Hash(String, FileStamp), new_mtimes : Hash(String, FileStamp)) : ChangeSet
        detect_changes(old_mtimes, new_mtimes)
      end
    end
  end
end

private def data_loop_options : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
  options.serve_mode = true
  options
end

private def write_data_loop_site
  File.write("config.toml", <<-TOML
    title = "Data Hook Loop"
    base_url = "https://example.com"
    TOML
  )
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates")
  FileUtils.mkdir_p("data")
  File.write("templates/page.html", "<html><body>{{ content }}</body></html>")
  File.write("content/foo.md", "---\ntitle: Foo\n---\nBody")
end

# A rewrite whose bytes are `content` but whose stamp is guaranteed to move:
# the explicit future mtime makes the FileStamp differ even under coarse
# mtime granularity, exactly like a hook's `curl -o` landing between polls.
private def rewrite_with_fresh_mtime(path : String, content : String)
  File.write(path, content)
  File.touch(path, Time.utc + 5.seconds)
end

describe "serve data/i18n hook-loop regression (#755)" do
  it "drops a byte-identical data/ rewrite with a fresh mtime" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_data_loop_site
        File.write("data/site.json", %({"answer": 42}))

        server = Hwaro::Services::Server.new
        old = server.data_loop_scan
        rewrite_with_fresh_mtime("data/site.json", %({"answer": 42}))

        changes = server.data_loop_detect_changes(old, server.data_loop_scan)
        changes.empty?.should be_true
      end
    end
  end

  it "still full-rebuilds on a same-size data/ change" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_data_loop_site
        File.write("data/site.json", %({"answer": 42}))

        server = Hwaro::Services::Server.new
        old = server.data_loop_scan
        rewrite_with_fresh_mtime("data/site.json", %({"answer": 43}))

        changes = server.data_loop_detect_changes(old, server.data_loop_scan)
        changes.modified_data.should eq(["data/site.json"])
        changes.needs_full_rebuild?.should be_true
      end
    end
  end

  it "still full-rebuilds on a size-changing data/ change" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_data_loop_site
        File.write("data/site.json", %({"answer": 42}))

        server = Hwaro::Services::Server.new
        old = server.data_loop_scan
        rewrite_with_fresh_mtime("data/site.json", %({"answer": 42, "more": true}))

        changes = server.data_loop_detect_changes(old, server.data_loop_scan)
        changes.modified_data.should eq(["data/site.json"])
        changes.needs_full_rebuild?.should be_true
      end
    end
  end

  it "drops a byte-identical i18n/ rewrite with a fresh mtime" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_data_loop_site
        FileUtils.mkdir_p("i18n")
        File.write("i18n/en.toml", %(hello = "Hello"))

        server = Hwaro::Services::Server.new
        old = server.data_loop_scan
        rewrite_with_fresh_mtime("i18n/en.toml", %(hello = "Hello"))

        changes = server.data_loop_detect_changes(old, server.data_loop_scan)
        changes.empty?.should be_true
      end
    end
  end

  it "still full-rebuilds on a changed i18n/ file" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_data_loop_site
        FileUtils.mkdir_p("i18n")
        File.write("i18n/en.toml", %(hello = "Hello"))

        server = Hwaro::Services::Server.new
        old = server.data_loop_scan
        rewrite_with_fresh_mtime("i18n/en.toml", %(hello = "Howdy"))

        changes = server.data_loop_detect_changes(old, server.data_loop_scan)
        changes.modified_data.should eq(["i18n/en.toml"])
        changes.needs_full_rebuild?.should be_true
      end
    end
  end

  # Structural events must be untouched by the digest comparison: a new data
  # file is genuinely new content, and a deleted one genuinely gone — both
  # keep forcing the full rebuild they always did.
  it "keeps added and removed data/ files as full-rebuild events" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_data_loop_site

        server = Hwaro::Services::Server.new
        old = server.data_loop_scan
        File.write("data/new.json", %({"fresh": true}))

        added = server.data_loop_detect_changes(old, server.data_loop_scan)
        added.added_files.should eq(["data/new.json"])
        added.needs_full_rebuild?.should be_true

        with_file = server.data_loop_scan
        File.delete("data/new.json")
        removed = server.data_loop_detect_changes(with_file, server.data_loop_scan)
        removed.removed_files.should eq(["data/new.json"])
        removed.needs_full_rebuild?.should be_true
      end
    end
  end

  # content/, templates/ and static/ stay mtime-based on purpose: their
  # rebuild paths are incremental (or a plain copy) and never re-run
  # build.hooks.pre, so they cannot produce the #755 loop — and hashing
  # them would tax every save of every page.
  it "keeps content/ and static/ touches mtime-based (no content comparison)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_data_loop_site
        FileUtils.mkdir_p("static")
        File.write("static/site.css", "body{}")

        server = Hwaro::Services::Server.new
        old = server.data_loop_scan
        rewrite_with_fresh_mtime("content/foo.md", "---\ntitle: Foo\n---\nBody")
        rewrite_with_fresh_mtime("static/site.css", "body{}")

        changes = server.data_loop_detect_changes(old, server.data_loop_scan)
        changes.modified_content.should eq(["content/foo.md"])
        changes.modified_static.should eq(["static/site.css"])
      end
    end
  end

  # The prefilter contract: scanning against a previous snapshot must not
  # re-read files whose mtime+size are unchanged, and a quiet tree must
  # produce a snapshot EQUAL to the previous one — the watch loop's
  # `current != last` quick check and the debounce settle test both compare
  # whole snapshots, digests included, so an unstable digest would spin them.
  it "carries digests forward for unchanged stamps and yields equal snapshots" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_data_loop_site
        File.write("data/site.json", %({"answer": 42}))

        server = Hwaro::Services::Server.new
        old = server.data_loop_scan
        server.data_loop_scan(old).should eq(old)

        # A same-size edit with the mtime forced back onto the old stamp is
        # invisible: the digest is carried, not recomputed. That is the
        # documented FileStamp tradeoff (bytes can't change without moving
        # mtime or size in any real editor/tool flow), and it is what keeps
        # steady-state polls read-free for large data files.
        mtime = File.info("data/site.json").modification_time
        File.write("data/site.json", %({"answer": 24}))
        File.touch("data/site.json", mtime)
        server.data_loop_scan(old)["data/site.json"].should eq(old["data/site.json"])
      end
    end
  end

  # The end-to-end #752 pattern: a pre hook that "fetches" an identical
  # payload into data/ on every build. The first build legitimately adds the
  # file (full rebuild); the full rebuild re-runs the hook, whose
  # byte-identical rewrite must now settle to an empty changeset instead of
  # scheduling the next full rebuild.
  it "breaks the pre-hook rewrite loop after the legitimate added-file rebuild" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_data_loop_site
        File.write("payload_seed.json", %({"answer": 42}))
        File.write("config.toml", <<-TOML
          title = "Data Hook Loop"
          base_url = "https://example.com"

          [build.hooks]
          pre = ["cp payload_seed.json data/payload.json"]
          TOML
        )

        server = Hwaro::Services::Server.new
        options = data_loop_options
        server.data_loop_capture_baseline
        server.data_loop_builder.run(options).should be_true

        # First poll after the initial build: the hook's file is new — a
        # legitimate full-rebuild trigger.
        baseline = server.data_loop_initial_watch_mtimes
        current = server.data_loop_scan
        first = server.data_loop_detect_changes(baseline, current)
        first.added_files.should contain("data/payload.json")
        first.needs_full_rebuild?.should be_true

        # The watcher runs that full rebuild; the pre hook re-runs and
        # rewrites the identical payload with a fresh mtime.
        server.data_loop_builder.run(options).should be_true

        second = server.data_loop_detect_changes(current, server.data_loop_scan(current))
        second.empty?.should be_true
      end
    end
  end
end
