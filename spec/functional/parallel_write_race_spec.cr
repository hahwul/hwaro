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
