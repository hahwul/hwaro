require "../support/build_helper"

# =============================================================================
# Sharded search index under `--cache`.
#
# The shards are cut from the SAME entry list `search.json` is built from,
# so every guarantee the classic file has under a warm cache (hydrated
# shortcode content, resolved `@/` links, base_path-prefixed URLs — see
# cache_generate_outputs_spec) must hold for `search/index.json` and every
# `search/<id>.json` too, and a warm build that re-renders one page must
# refresh exactly that page's shard.
# =============================================================================

private SHARD_CONFIG = <<-TOML
  title = "Shard Site"
  base_url = "http://localhost/sub"

  [search]
  enabled = true
  fields = ["title", "content", "section"]
  shards = "section"
  TOML

private def run_shard_builder(cache : Bool)
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: cache))
end

private def shard_project
  File.write("config.toml", SHARD_CONFIG)
  FileUtils.mkdir_p("content/blog")
  FileUtils.mkdir_p("content/docs")
  FileUtils.mkdir_p("templates/shortcodes")
  File.write("templates/page.html", "{{ content }}")
  File.write("templates/index.html", "{{ content }}")
  File.write("templates/section.html", "{{ content }}")
  File.write("templates/shortcodes/gal.html", "<div class=\"gal\">{{ body }}</div>")
  File.write("content/index.md", "---\ntitle: Home\n---\nHome")
  File.write("content/blog/shorty.md",
    "---\ntitle: S\n---\nIntro.\n\n{% gal() %}\nINNER\n{% end %}\n\n[home](@/index.md)\n\nOutro.\n")
  File.write("content/docs/guide.md", "---\ntitle: Guide\n---\nGuide body.\n")
end

private def search_outputs : Hash(String, String)
  files = Dir.glob("public/search/**/*.json").sort
  files << "public/search.json"
  files.to_h { |f| {f, File.read(f)} }
end

describe "cache: sharded search index converges on the clean build" do
  it "keeps the manifest and every shard identical on cold, all-hit and partial-hit --cache builds" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        shard_project
        FileUtils.rm_rf("public")
        FileUtils.rm_rf(".hwaro_cache.json")
        run_shard_builder(false)
        expected = search_outputs
        expected.keys.should eq(["public/search/_root.json", "public/search/blog.json", "public/search/docs.json", "public/search/index.json", "public/search.json"])
        # Sanity: the shard really holds hydrated content and subpath URLs.
        expected["public/search/blog.json"].should contain("Intro. INNER")
        expected["public/search/blog.json"].should_not contain("{%")
        expected["public/search/blog.json"].should contain("\"/sub/blog/shorty/\"")
        expected["public/search/index.json"].should contain("\"/sub/search/blog.json\"")

        FileUtils.rm_rf("public")
        FileUtils.rm_rf(".hwaro_cache.json")
        run_shard_builder(true) # cold cache build
        search_outputs.should eq(expected)

        run_shard_builder(true) # warm, every page a cache hit
        search_outputs.should eq(expected)

        # Warm, one page re-rendered: only its shard changes, the shortcode
        # page (still a cache hit) keeps its hydrated content.
        File.write("content/docs/guide.md", "---\ntitle: Guide\n---\nGuide body edited.\n")
        run_shard_builder(true)
        got = search_outputs
        got["public/search/docs.json"].should contain("Guide body edited")
        got["public/search/docs.json"].should_not eq(expected["public/search/docs.json"])
        got["public/search/blog.json"].should eq(expected["public/search/blog.json"])
        got["public/search/_root.json"].should eq(expected["public/search/_root.json"])
        got["public/search/blog.json"].should contain("Intro. INNER")

        # ...and it must match what a clean build of the edited tree gives.
        FileUtils.rm_rf("public")
        FileUtils.rm_rf(".hwaro_cache.json")
        run_shard_builder(false)
        search_outputs.should eq(got)
      end
    end
  end

  it "drops a shard on a warm --cache build when its last page is removed" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        shard_project
        FileUtils.rm_rf("public")
        FileUtils.rm_rf(".hwaro_cache.json")
        run_shard_builder(true)
        File.exists?("public/search/docs.json").should be_true

        File.delete("content/docs/guide.md")
        run_shard_builder(true)
        File.exists?("public/search/docs.json").should be_false
        manifest = JSON.parse(File.read("public/search/index.json"))
        manifest["shards"].as_a.map(&.["id"].as_s).should eq(["_root", "blog"])
      end
    end
  end

  it "emits no search/ directory at the default shards = none" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        shard_project
        File.write("config.toml", SHARD_CONFIG.sub("shards = \"section\"", ""))
        FileUtils.rm_rf("public")
        run_shard_builder(false)
        File.exists?("public/search.json").should be_true
        Dir.exists?("public/search").should be_false
      end
    end
  end
end
