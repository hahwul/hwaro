require "../spec_helper"

# =============================================================================
# Cache invalidation keys that do not live in any input file
#
#  * Cache#changed? must treat an output-directory switch as a miss. Building
#    `--cache -o A`, editing, building `--cache -o B`, then `--cache -o A`
#    again left A permanently stale: A's file exists and the source hash
#    already matches the entry written for B, so the page was skipped forever.
#
#  * Cache.compute_options_hash must move for CLI flags that change what a
#    page renders to (`--minify`, `--skip-highlighting`, …) and stay put for
#    flags that only affect which pages are built or how fast the build runs.
# =============================================================================

private def build_options(**overrides)
  Hwaro::Config::Options::BuildOptions.new(**overrides)
end

describe Hwaro::Core::Build::Cache do
  describe "#changed? across output directories" do
    it "reports changed when the entry was recorded for another output dir" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "page.md")
        File.write(source, "body")
        out_a = File.join(dir, "A", "index.html")
        out_b = File.join(dir, "B", "index.html")
        [out_a, out_b].each do |path|
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, "rendered")
        end

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: File.join(dir, "c.json"))
        cache.update(source, out_a)

        cache.changed?(source, out_a).should be_false
        cache.changed?(source, out_b).should be_true
      end
    end

    it "does not invalidate entries recorded without an output path" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "asset.txt")
        File.write(source, "body")

        cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: File.join(dir, "c.json"))
        cache.update(source)

        cache.changed?(source).should be_false
      end
    end

    it "does not invalidate when the same output dir is spelled differently" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("page.md", "body")
          FileUtils.mkdir_p("public")
          File.write("public/index.html", "rendered")

          absolute = File.expand_path("public/index.html")
          cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: "c.json")
          cache.update("page.md", absolute)

          # `-o public` and `-o ./public` both resolve here.
          cache.changed?("page.md", File.expand_path("./public/index.html")).should be_false
        end
      end
    end
  end

  describe ".compute_options_hash" do
    it "changes when --minify is toggled" do
      a = Hwaro::Core::Build::Cache.compute_options_hash(build_options(minify: false))
      b = Hwaro::Core::Build::Cache.compute_options_hash(build_options(minify: true))
      a.should_not eq(b)
    end

    it "changes when --skip-highlighting is toggled" do
      a = Hwaro::Core::Build::Cache.compute_options_hash(build_options(highlight: true))
      b = Hwaro::Core::Build::Cache.compute_options_hash(build_options(highlight: false))
      a.should_not eq(b)
    end

    it "changes when cache busting, OG images or image processing are skipped" do
      base = Hwaro::Core::Build::Cache.compute_options_hash(build_options)
      Hwaro::Core::Build::Cache.compute_options_hash(build_options(cache_busting: false)).should_not eq(base)
      Hwaro::Core::Build::Cache.compute_options_hash(build_options(skip_og_image: true)).should_not eq(base)
      Hwaro::Core::Build::Cache.compute_options_hash(build_options(skip_image_processing: true)).should_not eq(base)
    end

    it "is stable for flags that never change a rendered page's bytes" do
      base = Hwaro::Core::Build::Cache.compute_options_hash(build_options)
      Hwaro::Core::Build::Cache.compute_options_hash(build_options(drafts: true)).should eq(base)
      Hwaro::Core::Build::Cache.compute_options_hash(build_options(include_future: true)).should eq(base)
      Hwaro::Core::Build::Cache.compute_options_hash(build_options(workers: 8)).should eq(base)
      Hwaro::Core::Build::Cache.compute_options_hash(build_options(parallel: false)).should eq(base)
      Hwaro::Core::Build::Cache.compute_options_hash(build_options(stream: true)).should eq(base)
      Hwaro::Core::Build::Cache.compute_options_hash(build_options(verbose: true)).should eq(base)
    end

    it "is deterministic across calls" do
      opts = build_options(minify: true, highlight: false)
      Hwaro::Core::Build::Cache.compute_options_hash(opts)
        .should eq(Hwaro::Core::Build::Cache.compute_options_hash(opts))
    end
  end
end
