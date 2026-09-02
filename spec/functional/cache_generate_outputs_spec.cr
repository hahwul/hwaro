require "./support/build_helper"

# =============================================================================
# The Generate phase's outputs (search index, feeds) must be byte-identical
# between a clean build and a `--cache` build, whatever the cache hit ratio.
#
# Two defects made them diverge:
#   * SeoHooks (registered by every CLI build) held a second copy of the
#     generate calls with no `skip_if_unchanged`, so a warm all-hit build
#     regenerated search.json / rss.xml from pages the render phase never
#     populated;
#   * cache-hit pages reach Generate with an empty `content`, and the
#     generators' markdown-only fallback expands no shortcodes, resolves no
#     `@/` links and prefixes no base_path — so raw `{% shortcode %}` markup
#     landed in the index and the feed for every cached page.
# =============================================================================

private CACHE_CONFIG = <<-TOML
  title = "Cache Site"
  base_url = "http://localhost/sub"

  [feeds]
  enabled = true

  [search]
  enabled = true
  fields = ["title", "content"]
  TOML

private def run_builder(cache : Bool, parallel : Bool)
  builder = Hwaro::Core::Build::Builder.new
  # The hooks are what every real CLI build registers; the bug lived in the
  # hook path, so the spec must go through it.
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public", parallel: parallel, cache: cache))
end

private def clean_build(parallel : Bool = false)
  FileUtils.rm_rf("public")
  FileUtils.rm_rf(".hwaro_cache.json")
  run_builder(false, parallel)
end

private def shortcode_project
  File.write("config.toml", CACHE_CONFIG)
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates/shortcodes")
  File.write("templates/page.html", "{{ content }}")
  File.write("templates/index.html", "{{ content }}")
  File.write("templates/shortcodes/gal.html", "<div class=\"gal\">{{ body }}</div>")
  File.write("content/index.md", "---\ntitle: Home\n---\nHome")
  File.write("content/shorty.md",
    "---\ntitle: S\n---\nIntro.\n\n{% gal() %}\nINNER\n{% end %}\n\n[home](@/index.md) and [root](/other/)\n\nOutro.\n")
  File.write("content/other.md", "---\ntitle: Other\n---\nOther body.\n")
end

private def generated_outputs : Hash(String, String)
  {
    "search.json" => File.read("public/search.json"),
    "rss.xml"     => File.read("public/rss.xml"),
  }
end

describe "cache: generated outputs converge on the clean build" do
  {false, true}.each do |parallel|
    it "keeps search.json and rss.xml identical on cold, all-hit and partial-hit --cache builds (parallel=#{parallel})" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          shortcode_project
          clean_build(parallel)
          expected = generated_outputs
          # Sanity: the clean build really expanded the shortcode and resolved
          # links, so an identical warm output proves something.
          expected["search.json"].should contain("Intro. INNER")
          expected["search.json"].should_not contain("{%")
          expected["rss.xml"].should contain("<div class=\"gal\">")
          expected["rss.xml"].should_not contain("{%")

          FileUtils.rm_rf("public")
          FileUtils.rm_rf(".hwaro_cache.json")
          run_builder(true, parallel) # cold cache build
          generated_outputs.should eq(expected)

          run_builder(true, parallel) # warm, every page a cache hit
          generated_outputs.should eq(expected)

          # Warm, one page re-rendered, the shortcode page still a cache hit:
          # its content has to be hydrated, not left on the raw fallback.
          File.write("content/other.md", "---\ntitle: Other\n---\nOther body edited.\n")
          run_builder(true, parallel)
          got = generated_outputs
          got["search.json"].should contain("Other body edited")
          got["search.json"].should contain("Intro. INNER")
          got["search.json"].should_not contain("{%")
          got["rss.xml"].should contain("<div class=\"gal\">")
          got["rss.xml"].should_not contain("{%")

          # ...and it must match what a clean build of the edited tree gives.
          clean_build(parallel)
          generated_outputs.should eq(got)
        end
      end
    end
  end

  # The Generate phase's skip is not the only reader of a cache-hit page's
  # content: the taxonomy hook regenerates every per-term feed on every
  # build (skip or no skip), so an all-hit warm build with `taxonomy.feed`
  # shipped the raw-markdown fallback into tags/<term>/rss.xml.
  it "keeps taxonomy term feeds identical on a warm all-hit --cache build" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        shortcode_project
        File.write("config.toml", CACHE_CONFIG + "\n[[taxonomies]]\nname = \"tags\"\nfeed = true\n")
        File.write("templates/taxonomy.html", "{{ content }}")
        File.write("templates/taxonomy_term.html", "{{ content }}")
        File.write("content/shorty.md",
          "---\ntitle: S\ntags: [t]\n---\nIntro.\n\n{% gal() %}\nINNER\n{% end %}\n\n[home](@/index.md) and [root](/other/)\n\nOutro.\n")
        clean_build
        expected = File.read("public/tags/t/rss.xml")
        expected.should contain("<div class=\"gal\">")
        expected.should_not contain("{%")

        FileUtils.rm_rf("public")
        FileUtils.rm_rf(".hwaro_cache.json")
        run_builder(true, false) # cold
        File.read("public/tags/t/rss.xml").should eq(expected)
        run_builder(true, false) # warm, every page a cache hit
        File.read("public/tags/t/rss.xml").should eq(expected)
      end
    end
  end

  # Feeds never join the Generate skip while a user feed template exists, so
  # an all-hit warm build regenerates rss.xml from `page.content` — which
  # nothing hydrated: the feed carried raw shortcode markup again.
  it "hydrates cache hits on a warm all-hit build when a user feed template forces feed regeneration" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        shortcode_project
        File.write("templates/rss.xml.jinja", "<feed>{% for p in pages %}<item>{{ p.content }}</item>{% endfor %}</feed>")
        clean_build
        expected = File.read("public/rss.xml")
        expected.should contain("<div class=\"gal\">")
        expected.should contain("http://localhost/sub/")
        expected.should_not contain("{%")

        FileUtils.rm_rf("public")
        FileUtils.rm_rf(".hwaro_cache.json")
        run_builder(true, false) # cold
        File.read("public/rss.xml").should eq(expected)
        run_builder(true, false) # warm, every page a cache hit
        File.read("public/rss.xml").should eq(expected)
      end
    end
  end

  # `serve` keeps the Builder alive and regenerates search/feeds from the
  # in-memory page set after every edit. A `serve --cache` whose start was
  # an all-hit build had every page's content empty, so the first
  # incremental rebuild served the raw fallback for every untouched page.
  it "hydrates cache-hit pages on an all-hit start in serve mode so incremental rebuilds stay clean" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        shortcode_project
        # The shortcode page lives in its own section: the incremental
        # rebuild re-links and re-renders the edited page's section
        # neighbours, and a re-rendered page hides the bug.
        FileUtils.rm("content/shorty.md")
        FileUtils.mkdir_p("content/blog")
        File.write("templates/section.html", "{{ content }}")
        File.write("content/blog/_index.md", "---\ntitle: Blog\n---\nBlog")
        File.write("content/blog/shorty.md",
          "---\ntitle: S\ndate: 2024-01-01\n---\nIntro.\n\n{% gal() %}\nINNER\n{% end %}\n\n[home](@/index.md) and [root](/other/)\n\nOutro.\n")
        File.write("content/mid.md", "---\ntitle: Mid\ndate: 2024-01-02\n---\nMid body.\n")
        File.write("content/other.md", "---\ntitle: Other\ndate: 2024-01-04\n---\nOther body.\n")
        clean_build
        expected = generated_outputs

        FileUtils.rm_rf("public")
        FileUtils.rm_rf(".hwaro_cache.json")
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: true)
        options.serve_mode = true
        warm = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| warm.register(h) }
        warm.run(options) # cold: primes the cache
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        builder.run(options) # all-hit start, like a second `serve --cache`
        generated_outputs.should eq(expected)

        File.write("content/other.md", "---\ntitle: Other\ndate: 2024-01-04\n---\nOther body edited.\n")
        # The watcher hands the builder cwd-relative paths.
        builder.run_incremental(["content/other.md"], options).should be_true
        got = generated_outputs
        got["search.json"].should contain("Other body edited")
        got["search.json"].should contain("Intro. INNER")
        got["search.json"].should_not contain("{%")
        got["rss.xml"].should contain("<div class=\"gal\">")
        got["rss.xml"].should_not contain("{%")
      end
    end
  end

  it "leaves the previous outputs untouched on a warm all-hit build" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        shortcode_project
        FileUtils.rm_rf(".hwaro_cache.json")
        run_builder(true, false)
        before = File.info("public/search.json").modification_time
        # Any rewrite of an unchanged index is wasted work; make sure the
        # skip really engages through the hook path.
        sleep 0.05.seconds
        run_builder(true, false)
        File.info("public/search.json").modification_time.should eq(before)
      end
    end
  end
end
