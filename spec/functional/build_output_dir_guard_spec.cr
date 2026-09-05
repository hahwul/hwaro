require "../support/build_helper"

# =============================================================================
# Output-directory handling for `hwaro build`
#
#  * `-o public/` (a trailing slash — what shell directory completion types)
#    made OutputGuard reject every page. The build reported success, wrote
#    only static assets, and the site root index.html ended up holding
#    whichever page rendered last (get_output_path's root fallback).
#
#  * `-o content` wiped the project's own sources: the cold-build `rm_rf` was
#    only guarded against `/`, `$HOME` and ancestors of the project.
# =============================================================================

private GUARD_CONFIG = <<-TOML
  title = "Guard Site"
  base_url = "http://localhost"
  TOML

private def guard_project(dir)
  File.write("config.toml", GUARD_CONFIG)
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  FileUtils.mkdir_p("static")
  File.write("content/index.md", "---\ntitle: Home\n---\nHomepage body")
  File.write("content/about.md", "---\ntitle: About\n---\nAbout body")
  File.write("content/posts/first.md", "---\ntitle: First\n---\nFirst body")
  File.write("static/asset.txt", "asset")
  File.write("templates/index.html", "HOME:{{ content }}")
  File.write("templates/page.html", "PAGE:{{ content }}")
  File.write("templates/section.html", "SECTION:{{ content }}")
end

private def run_build(output_dir : String)
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: output_dir, parallel: false, highlight: false))
end

# `--cache` takes the incremental branch: it never deletes the output
# directory, but it still writes every rendered page into it.
private def run_build_cached(output_dir : String)
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: output_dir, parallel: false, highlight: false, cache: true))
end

describe "build: output directory with a trailing separator" do
  it "writes every page, exactly as it does without the slash" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)

        run_build("with_slash/").should be_true
        run_build("no_slash").should be_true

        with_slash = Dir.glob("with_slash/**/*.html").map(&.sub("with_slash/", "")).sort!
        no_slash = Dir.glob("no_slash/**/*.html").map(&.sub("no_slash/", "")).sort!

        with_slash.should eq(no_slash)
        with_slash.should contain("about/index.html")
        with_slash.should contain("posts/first/index.html")
      end
    end
  end

  it "keeps the homepage at the output root instead of the last page rendered" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        run_build("out/").should be_true

        root = File.read("out/index.html")
        root.should contain("HOME:")
        root.should contain("Homepage body")
        root.should_not contain("First body")
        root.should_not contain("About body")
      end
    end
  end

  it "produces byte-identical page output with and without the slash" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        run_build("with_slash/")
        run_build("no_slash")

        File.read("with_slash/about/index.html").should eq(File.read("no_slash/about/index.html"))
        File.read("with_slash/index.html").should eq(File.read("no_slash/index.html"))
      end
    end
  end
end

describe "build: refusing to delete project input directories" do
  it "refuses to use content/ as the output directory" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)

        err = expect_raises(Hwaro::HwaroError) { run_build("content") }
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        (err.message || "").should contain("content")
        (err.hint || "").should contain("public")

        # Sources survive.
        File.exists?("content/index.md").should be_true
        File.exists?("content/posts/first.md").should be_true
      end
    end
  end

  it "refuses templates/ and static/ too" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)

        expect_raises(Hwaro::HwaroError) { run_build("templates") }
        expect_raises(Hwaro::HwaroError) { run_build("static") }

        File.exists?("templates/page.html").should be_true
        File.exists?("static/asset.txt").should be_true
      end
    end
  end

  it "refuses a directory nested inside a project input directory" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        FileUtils.mkdir_p("content/generated")

        expect_raises(Hwaro::HwaroError) { run_build("content/generated") }
        File.exists?("content/index.md").should be_true
      end
    end
  end

  it "recognizes content/ written with a trailing separator" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)

        expect_raises(Hwaro::HwaroError) { run_build("content/") }
        File.exists?("content/index.md").should be_true
      end
    end
  end

  it "still allows an output directory that merely shares a prefix" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        # Pre-create them so the destructive-clean guard is actually reached.
        FileUtils.mkdir_p("contents")
        FileUtils.mkdir_p("static-site")

        run_build("contents").should be_true
        run_build("static-site").should be_true

        File.exists?("contents/about/index.html").should be_true
        File.exists?("static-site/about/index.html").should be_true
      end
    end
  end

  it "still allows the conventional public/ output directory" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        run_build("public").should be_true
        run_build("public").should be_true
        File.exists?("public/about/index.html").should be_true
      end
    end
  end
end

# =============================================================================
# Output directories reached through a symlink
#
# The guard above compared `File.expand_path(output_dir)`, which is purely
# lexical, so ONE symlinked component hid the real destination:
#
#   * `ln -s content pub` + `-o pub/archive` passed every rule and the cold
#     build's `rm_rf` deleted `content/archive` — exit 0, no warning.
#   * `ln -s templates public` + `--cache` never deletes, but it writes: the
#     project's own templates were overwritten with rendered HTML.
#
# And a symlinked output directory did not survive a cold build at all:
# `rm_rf` unlinks the LINK rather than clearing the tree behind it, so
# `public` became a real directory and later builds published where nobody
# deploys.
# =============================================================================
describe "build: output directory reached through a symlink" do
  it "refuses an output path whose symlinked ancestor lands in content/" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        FileUtils.mkdir_p("content/archive")
        File.write("content/archive/old.md", "---\ntitle: Old\n---\nPRECIOUS body")
        File.symlink("content", "pub")

        err = expect_raises(Hwaro::HwaroError) { run_build("pub/archive") }
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)

        File.read("content/archive/old.md").should contain("PRECIOUS body")
      end
    end
  end

  it "refuses a symlink to templates/ on the incremental (--cache) path" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        File.symlink("templates", "public")

        expect_raises(Hwaro::HwaroError) { run_build_cached("public") }

        # The templates must still be Crinja sources, not rendered pages.
        File.read("templates/index.html").should eq("HOME:{{ content }}")
        File.read("templates/page.html").should eq("PAGE:{{ content }}")
      end
    end
  end

  it "publishes through a symlinked output directory instead of replacing it" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        FileUtils.mkdir_p("webroot")
        File.write("webroot/stale.html", "stale")
        File.symlink("webroot", "public")

        run_build("public").should be_true

        # The link survives the cold build...
        File.symlink?("public").should be_true
        # ...the site lands behind it...
        File.exists?("webroot/about/index.html").should be_true
        # ...and the cold build still starts from a clean slate.
        File.exists?("webroot/stale.html").should be_false
      end
    end
  end
end

# =============================================================================
# Ordinary IO failures must not masquerade as internal faults
#
# A plain file squatting on the output name (`printf x > public`, `-o /dev/null`)
# aborted the Initialize phase with a raw File::Error. The lifecycle manager
# discarded the exception TYPE, so the CLI reported HWARO_E_INTERNAL / exit 70
# — the code documented as "unrecoverable bug or unexpected state" — and the
# only useful detail (which path, which errno) never reached the --json
# payload. CI that alerts on "hwaro hit an internal bug" fired on a typo.
# =============================================================================
describe "build: output path occupied by a regular file" do
  it "fails with a classified IO error naming the path, not an internal fault" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        File.write("public", "squatter")

        err = expect_raises(Hwaro::HwaroError) { run_build("public") }
        err.code.should eq(Hwaro::Errors::HWARO_E_IO)
        err.exit_code.should eq(6)
        (err.message || "").should contain("public")
        (err.hint || "").should_not be_empty

        # The build refused; it did not clobber whatever was there.
        File.read("public").should eq("squatter")
      end
    end
  end
end

# =============================================================================
# Pre-existing output directories hwaro did not create
#
# The guard refuses the catastrophic targets, but any OTHER existing
# directory — `-o ~/Documents/site`, a `dist/` shared with a bundler — was
# emptied by the cold build's `rm_rf` silently, exit 0. hwaro now clears only
# what it can vouch for: the conventional `public/`, `hwaro serve` output,
# and directories it created or found empty on an earlier build.
# =============================================================================
describe "build: output directory that already holds unrelated files" do
  it "keeps the files, still publishes the site, and warns" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        FileUtils.mkdir_p("shared/sub")
        File.write("shared/notes.txt", "keep")
        File.write("shared/sub/deep.txt", "keep")

        log = with_captured_log { run_build("shared").should be_true }

        File.read("shared/notes.txt").should eq("keep")
        File.read("shared/sub/deep.txt").should eq("keep")
        File.exists?("shared/about/index.html").should be_true
        log.should contain("already holds 2 entries hwaro did not write")

        # Never handed over: the next cold build keeps them too.
        run_build("shared").should be_true
        File.exists?("shared/notes.txt").should be_true
      end
    end
  end

  it "clears a directory it created itself on the next cold build" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        run_build("dist").should be_true
        File.write("dist/stale.html", "stale")

        log = with_captured_log { run_build("dist").should be_true }

        File.exists?("dist/stale.html").should be_false
        log.should_not contain("did not write")
      end
    end
  end

  # Ownership was recorded only on non-incremental builds, so a `dist/` that
  # `build --cache` had just CREATED was never recorded: every later cold
  # build warned "entries hwaro did not write" about hwaro's own files and
  # kept the stale ones forever.
  it "records a directory it created on a --cache build so the next cold build clears it" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        run_build_cached("dist").should be_true
        File.write("dist/stale.html", "stale")

        log = with_captured_log { run_build("dist").should be_true }

        File.exists?("dist/stale.html").should be_false
        log.should_not contain("did not write")
      end
    end
  end

  it "still never hands over a pre-existing directory on a --cache build" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        FileUtils.mkdir_p("shared")
        File.write("shared/notes.txt", "keep")
        run_build_cached("shared").should be_true
        log = with_captured_log { run_build("shared").should be_true }
        File.read("shared/notes.txt").should eq("keep")
        log.should contain("did not write")
      end
    end
  end

  it "leaves no .hwaro/ workspace behind for the conventional public/ directory" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        run_build("public").should be_true
        Dir.exists?(".hwaro").should be_false
      end
    end
  end

  it "clears a directory it found empty on an earlier build" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        FileUtils.mkdir_p("dist")
        run_build("dist").should be_true
        File.write("dist/stale.html", "stale")
        run_build("dist").should be_true
        File.exists?("dist/stale.html").should be_false
      end
    end
  end

  it "still clears the conventional public/ directory" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        FileUtils.mkdir_p("public")
        File.write("public/stale.html", "stale")
        log = with_captured_log { run_build("public").should be_true }
        File.exists?("public/stale.html").should be_false
        log.should_not contain("did not write")
      end
    end
  end

  it "does not hand a foreign directory over through a --cache build" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        FileUtils.mkdir_p("shared")
        File.write("shared/notes.txt", "keep")
        run_build_cached("shared").should be_true
        run_build("shared").should be_true
        File.exists?("shared/notes.txt").should be_true
      end
    end
  end

  it "clears a directory that carries a real serve marker" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        FileUtils.mkdir_p("shared")
        File.write("shared/notes.txt", "keep")
        Hwaro::Utils::DevMarker.write("shared")
        run_build("shared").should be_true
        File.exists?("shared/notes.txt").should be_false
      end
    end
  end

  # `DevMarker.present?` fails closed (true) so deploy never ships output
  # it cannot rule out as serve output. Reusing that true here would invert
  # into "clearable" and wipe a foreign directory whose `.hwaro-dev` we
  # simply could not read.
  it "does not treat an unreadable .hwaro-dev as a serve marker" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        guard_project(dir)
        FileUtils.mkdir_p("shared")
        File.write("shared/notes.txt", "keep")
        marker = File.join("shared", Hwaro::Utils::DevMarker::FILENAME)
        File.write(marker, Hwaro::Utils::DevMarker::CONTENT)
        File.chmod(marker, 0o000)
        begin
          run_build("shared").should be_true
          File.exists?("shared/notes.txt").should be_true
        ensure
          File.chmod(marker, 0o644) if File.exists?(marker)
        end
      end
    end
  end
end
