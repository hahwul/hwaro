require "../spec_helper"
require "../../src/services/server/server"

# Regression coverage for #760: the two routes to the #755 hook-rewrite
# rebuild loop that survived the data//i18n digest fix (#757).
#
# The loop's engine is always the same — a FULL rebuild is the only strategy
# that re-runs `build.hooks.pre`, so any hook whose own output is reported
# back as a change that forces a full rebuild retriggers itself forever:
#
#   1. A pre hook that byte-identically rewrites one `templates/` file AND
#      one `static/` file. Both buckets have a cheap hook-free strategy on
#      their own, but the mixed changeset matched none of the `*_only?`
#      predicates and fell through to `:full`.
#   2. A pre hook that byte-identically rewrites `config.toml`. Config stamps
#      carry no digest, and the config branch ran before the digest check, so
#      every poll reported `config_changed` and forced a full rebuild.
#
# `touch config.toml` is the documented force-a-full-rebuild escape hatch for
# hook authors (docs/content/features/build-hooks.md) — the fix must break the
# hook's loop without breaking a developer's touch.

# Reopened for the private seams; names are prefixed so they can't collide
# with the shims other spec files install.
module Hwaro
  module Services
    class Server
      def hook_loop_builder : Hwaro::Core::Build::Builder
        @builder
      end

      def hook_loop_capture_baseline
        capture_watch_baseline
      end

      def hook_loop_initial_watch_mtimes : Hash(String, FileStamp)
        initial_watch_mtimes
      end

      def hook_loop_scan(prev : Hash(String, FileStamp)? = nil) : Hash(String, FileStamp)
        scan_mtimes(prev)
      end

      def hook_loop_detect_changes(old_mtimes : Hash(String, FileStamp), new_mtimes : Hash(String, FileStamp)) : ChangeSet
        detect_changes(old_mtimes, new_mtimes)
      end

      def hook_loop_run_full_build(options : Hwaro::Config::Options::BuildOptions) : Bool
        run_full_build(options)
      end
    end
  end
end

private def hook_loop_options : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
  options.serve_mode = true
  options
end

private TEMPLATE_BYTES = "<html><body>{{ content }}</body></html>"
private STATIC_BYTES   = "body{margin:0}"

# A site whose pre hook re-emits byte-identical copies of a template and a
# static file on every build — the deterministic-bundler pattern (`tsc`,
# `tailwindcss`, `esbuild` writing the same output twice).
private def write_mixed_rewrite_site
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates")
  FileUtils.mkdir_p("static")
  File.write("content/foo.md", "---\ntitle: Foo\n---\nBody")
  File.write("templates/page.html", TEMPLATE_BYTES)
  File.write("static/site.css", STATIC_BYTES)
  File.write("seed_page.html", TEMPLATE_BYTES)
  File.write("seed_site.css", STATIC_BYTES)
  File.write("config.toml", <<-TOML
    title = "Hook Loop"
    base_url = "https://example.com"

    [build.hooks]
    pre = ["cp seed_page.html templates/page.html", "cp seed_site.css static/site.css"]
    TOML
  )
end

# A site whose pre hook rewrites config.toml itself. `config_seed.toml` holds
# the very bytes of config.toml, so every run is a byte-identical rewrite.
private def write_config_rewrite_site(seed_differs = false)
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates")
  File.write("content/foo.md", "---\ntitle: Foo\n---\nBody")
  File.write("templates/page.html", TEMPLATE_BYTES)
  config = <<-TOML
    title = "Config Loop"
    base_url = "https://example.com"

    [build.hooks]
    pre = ["cp config_seed.toml config.toml"]
    TOML
  File.write("config.toml", config)
  File.write("config_seed.toml", seed_differs ? config.sub("Config Loop", "Rewritten By Hook") : config)
end

describe "serve hook rebuild-loop regression (#760)" do
  describe "mixed templates+static rewrites" do
    it "picks the hook-free :templates strategy instead of a full rebuild" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          write_mixed_rewrite_site

          server = Hwaro::Services::Server.new
          options = hook_loop_options
          server.hook_loop_capture_baseline
          server.hook_loop_run_full_build(options).should be_true

          baseline = server.hook_loop_initial_watch_mtimes
          current = server.hook_loop_scan(baseline)
          changes = server.hook_loop_detect_changes(baseline, current)

          # The hook's own output, reported back to the watcher.
          changes.modified_templates.should eq(["templates/page.html"])
          changes.modified_static.should eq(["static/site.css"])
          # Nothing structural changed, so nothing justifies re-running hooks.
          changes.needs_full_rebuild?.should be_false
          changes.rebuild_strategy.should eq(:templates)
        end
      end
    end

    it "settles: the rebuild that changeset asks for re-runs no hooks" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          write_mixed_rewrite_site

          server = Hwaro::Services::Server.new
          options = hook_loop_options
          server.hook_loop_capture_baseline
          server.hook_loop_run_full_build(options).should be_true

          baseline = server.hook_loop_initial_watch_mtimes
          current = server.hook_loop_scan(baseline)
          changes = server.hook_loop_detect_changes(baseline, current)
          changes.rebuild_strategy.should eq(:templates)

          # What the watcher runs for :templates. It touches no source file,
          # so the next poll sees a quiet tree — the loop is over.
          server.hook_loop_builder.run_rerender(options).should be_true

          settled = server.hook_loop_detect_changes(current, server.hook_loop_scan(current))
          settled.empty?.should be_true
        end
      end
    end

    it "still full-rebuilds when the mixed set carries a structural change" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          write_mixed_rewrite_site

          server = Hwaro::Services::Server.new
          options = hook_loop_options
          server.hook_loop_capture_baseline
          server.hook_loop_run_full_build(options).should be_true

          baseline = server.hook_loop_initial_watch_mtimes
          File.write("content/bar.md", "---\ntitle: Bar\n---\nBody")

          changes = server.hook_loop_detect_changes(baseline, server.hook_loop_scan(baseline))
          changes.added_files.should eq(["content/bar.md"])
          changes.rebuild_strategy.should eq(:full)
        end
      end
    end
  end

  describe "config.toml rewrites" do
    it "drops the byte-identical rewrite its own build's hooks produced" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          write_config_rewrite_site

          server = Hwaro::Services::Server.new
          options = hook_loop_options
          server.hook_loop_capture_baseline
          server.hook_loop_run_full_build(options).should be_true

          baseline = server.hook_loop_initial_watch_mtimes
          # The hook moved config.toml's stamp during the build.
          baseline["config.toml"].should_not eq(server.hook_loop_scan(baseline)["config.toml"])

          changes = server.hook_loop_detect_changes(baseline, server.hook_loop_scan(baseline))
          changes.config_changed.should be_false
          changes.empty?.should be_true
        end
      end
    end

    it "still honours a developer's `touch config.toml` after that build" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          write_config_rewrite_site

          server = Hwaro::Services::Server.new
          options = hook_loop_options
          server.hook_loop_capture_baseline
          server.hook_loop_run_full_build(options).should be_true

          settled = server.hook_loop_scan
          # The documented force-a-full-rebuild escape hatch: same bytes, new
          # mtime — but NOT the stamp the build left behind.
          File.touch("config.toml", Time.utc + 5.seconds)

          changes = server.hook_loop_detect_changes(settled, server.hook_loop_scan(settled))
          changes.config_changed.should be_true
          changes.needs_full_rebuild?.should be_true
        end
      end
    end

    it "still rebuilds when a hook changes config.toml's bytes" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          write_config_rewrite_site(seed_differs: true)

          server = Hwaro::Services::Server.new
          options = hook_loop_options
          server.hook_loop_capture_baseline
          server.hook_loop_run_full_build(options).should be_true

          baseline = server.hook_loop_initial_watch_mtimes
          changes = server.hook_loop_detect_changes(baseline, server.hook_loop_scan(baseline))
          changes.config_changed.should be_true
          changes.needs_full_rebuild?.should be_true
        end
      end
    end

    it "still rebuilds on a config edit made between builds" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          write_config_rewrite_site

          server = Hwaro::Services::Server.new
          options = hook_loop_options
          server.hook_loop_capture_baseline
          server.hook_loop_run_full_build(options).should be_true

          settled = server.hook_loop_scan
          File.write("config.toml", File.read("config.toml").sub("Config Loop", "Renamed"))

          changes = server.hook_loop_detect_changes(settled, server.hook_loop_scan(settled))
          changes.config_changed.should be_true
        end
      end
    end
  end
end
