require "./support/build_helper"

# =============================================================================
# Regression test for the parallel write-phase directory race.
#
# `ensure_dir` used to record a directory in `@created_dirs` BEFORE `mkdir_p`
# actually created it. Under `-Dpreview_mt`, when two pages resolved to the
# same output directory (a slug collision), the second worker saw the dir as
# "already created", skipped its own mkdir, and raced ahead to `File.write`
# on a directory that did not exist yet — a flaky
# `Error opening file with mode 'w': ... No such file or directory` that
# failed the whole build with HWARO_E_TEMPLATE.
#
# The fix records the dir only after mkdir_p returns. This test drives many
# colliding pages through a parallel build; with the bug present it crashes
# (probabilistically, but reliably across this many collisions), and with the
# fix it always completes and overwrites deterministically-per-run.
# =============================================================================

describe "Parallel write race: colliding output directories" do
  it "builds many slug-colliding pages in parallel without a missing-directory crash" do
    # Each pair of pages collides on one shared output directory. Many pairs
    # maximize the number of concurrent same-dir writes so the pre-fix race
    # is hit reliably.
    content = {} of String => String
    50.times do |i|
      content["a#{i}.md"] = "---\ntitle: Alpha #{i}\nslug: shared-#{i}\n---\nAlpha body #{i}"
      content["b#{i}.md"] = "---\ntitle: Beta #{i}\nslug: shared-#{i}\n---\nBeta body #{i}"
    end

    build_site(
      BASIC_CONFIG,
      content_files: content,
      template_files: {"page.html" => "TITLE={{ page_title }}|{{ content }}"},
      parallel: true,
    ) do
      # Every collided directory must have been created and hold exactly one
      # rendered page (one of the two colliding sources won the overwrite).
      50.times do |i|
        path = "public/shared-#{i}/index.html"
        File.exists?(path).should be_true
        html = File.read(path)
        (html.includes?("Alpha #{i}") || html.includes?("Beta #{i}")).should be_true
      end
    end
  end
end

# =============================================================================
# Regression test for the non-atomic serve-watcher static copy.
#
# `copy_changed_static` / `copy_changed_content_files` ran `FileUtils.cp`
# straight onto the live destination, and Crystal's copy opens the destination
# with O_TRUNC and then streams — so `hwaro serve`, which runs these on the
# watcher while HTTP fibers stream the same paths, answered GETs mid-copy with
# zero-length or truncated bodies (a 21 MB stylesheet observed at 0.5 MB, with
# header and body agreeing on the short length, so nothing retried).
#
# The race window itself is not deterministic in a spec, so the invariant is
# asserted through the property that produces it: a reader holding the file
# open across the copy must keep seeing one complete revision. That holds for a
# temp-file-plus-rename replacement and fails for a truncate-and-stream copy.
# =============================================================================

describe "Serve watcher file copies" do
  it "replaces a static file atomically instead of truncating it in place" do
    Dir.mktmpdir do |dir|
      static_dir = File.join(dir, "static")
      output_dir = File.join(dir, "public")
      FileUtils.mkdir_p(static_dir)
      FileUtils.mkdir_p(output_dir)

      src = File.join(static_dir, "big.css")
      dest = File.join(output_dir, "big.css")
      # Same length on both revisions so the assertion can only be satisfied by
      # atomicity, never by a size difference.
      old_bytes = "a{color:red }" * 40_000
      new_bytes = "a{color:blue}" * 40_000
      File.write(src, old_bytes)

      Dir.cd(dir) do
        builder = Hwaro::Core::Build::Builder.new
        builder.copy_changed_static(["static/big.css"], output_dir, false)

        # Stands in for an in-flight HTTP response streaming the file.
        reader = File.open(dest)
        begin
          File.write(src, new_bytes)
          builder.copy_changed_static(["static/big.css"], output_dir, false)

          reader.gets_to_end.should eq(old_bytes)
        ensure
          reader.close
        end

        File.read(dest).should eq(new_bytes)
        # The temp file must never survive the copy.
        Dir.glob(File.join(output_dir, "*.tmp")).should be_empty
      end
    end
  end
end
