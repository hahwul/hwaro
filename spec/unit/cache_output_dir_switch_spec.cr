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
  describe ".output_dir_key" do
    it "is identical for the same relative output dir under different roots" do
      keys = [] of String
      2.times do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) { keys << Hwaro::Core::Build::Cache.output_dir_key("public") }
        end
      end
      # CI restoring .hwaro_cache.json under a different checkout path, Docker
      # vs native, a renamed project directory: all must keep the cache warm.
      keys[0].should eq(keys[1])
      keys[0].should eq("public")
    end

    it "distinguishes genuinely different output dirs" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          Hwaro::Core::Build::Cache.output_dir_key("dist")
            .should_not eq(Hwaro::Core::Build::Cache.output_dir_key("preview"))
        end
      end
    end

    it "normalizes equivalent spellings of one directory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          Hwaro::Core::Build::Cache.output_dir_key("./public")
            .should eq(Hwaro::Core::Build::Cache.output_dir_key("public"))
          Hwaro::Core::Build::Cache.output_dir_key("public/")
            .should eq(Hwaro::Core::Build::Cache.output_dir_key("public"))
        end
      end
    end
  end

  describe "#set_global_checksums output-directory tracking" do
    it "invalidates every entry when the output directory changes" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("page.md", "body")
          cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: "c.json")
          cache.set_global_checksums("t", "c", output_dir: "dist")
          cache.update("page.md", File.expand_path("dist/index.html"))
          cache.stats[:total].should eq(1)

          cache.set_global_checksums("t", "c", output_dir: "preview")
          cache.stats[:total].should eq(0)
        end
      end
    end

    it "keeps entries when the output directory is unchanged" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("page.md", "body")
          cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: "c.json")
          cache.set_global_checksums("t", "c", output_dir: "dist")
          cache.update("page.md", File.expand_path("dist/index.html"))

          cache.set_global_checksums("t", "c", output_dir: "./dist")
          cache.stats[:total].should eq(1)
        end
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
