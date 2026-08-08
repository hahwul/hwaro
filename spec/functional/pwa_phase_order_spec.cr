require "../spec_helper"

# Regression coverage for the PWA generation-phase fixes:
#
# - A3: sw.js used to be generated at BeforeGenerate, BEFORE the phases that
#   write 404.html (Write) and search_index/search.json (AfterGenerate) — so a
#   CLEAN build dropped those URLs from the precache list ("no matching output
#   file"), while a warm build hashed the PREVIOUS build's bytes. Generation
#   now runs at AfterWrite, over the final output tree.
# - A10: serve's incremental rebuild paths (run_incremental / run_rerender)
#   never regenerated sw.js, so registered service workers kept serving stale
#   bytes through live reloads. regenerate_seo_surfaces now rewrites it.

private PWA_CONFIG = <<-TOML
  title = "PWA Site"
  base_url = "https://example.com"

  [pwa]
  enabled = true
  precache_urls = ["/404.html", "/search.json"]

  [search]
  enabled = true
  TOML

private def write_pwa_site
  File.write("config.toml", PWA_CONFIG)
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", "<html><body>{{ content }}</body></html>")
  File.write("templates/404.html", "<html><body>not found</body></html>")
  File.write("content/index.md", "---\ntitle: Home\n---\nhome body v1")
  File.write("content/about.md", "---\ntitle: About\n---\nabout body")
end

private def pwa_builder : Hwaro::Core::Build::Builder
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder
end

private def pwa_options(preserve : Bool = false) : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
  options.preserve_output = preserve
  options
end

private def precache_urls(sw_source : String) : Array(String)
  block = sw_source[/PRECACHE_URLS = \[(.*?)\];/m, 1]? || ""
  block.scan(/"([^"]*)"/).map(&.[1])
end

private def cache_name(sw_source : String) : String
  sw_source[/CACHE_NAME = '([^']+)'/, 1]
end

describe "PWA generation phase order (A3/A10)" do
  it "includes 404.html and the search index in the precache on a CLEAN build (A3)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_pwa_site
        pwa_builder.run(pwa_options).should be_true

        File.exists?("public/404.html").should be_true
        File.exists?("public/search.json").should be_true
        sw = File.read("public/sw.js")

        urls = precache_urls(sw)
        urls.should contain("/404.html")
        urls.should contain("/search.json")
      end
    end
  end

  it "emits byte-identical sw.js for a clean build and an immediately following warm build (A3)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_pwa_site
        builder = pwa_builder
        builder.run(pwa_options).should be_true
        first = File.read("public/sw.js")

        # Warm rebuild over the same output tree (serve's watch options).
        builder.run(pwa_options(preserve: true)).should be_true
        File.read("public/sw.js").should eq(first)
      end
    end
  end

  it "regenerates sw.js (new CACHE_NAME) on an incremental content rebuild (A10)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_pwa_site
        builder = pwa_builder
        options = pwa_options
        builder.run(options).should be_true
        before = cache_name(File.read("public/sw.js"))

        # The homepage backs the precached start_url "/", so its bytes feed
        # the content-derived cache version.
        File.write("content/index.md", "---\ntitle: Home\n---\nhome body v2 — changed")
        watch = pwa_options(preserve: true)
        builder.run_incremental(["content/index.md"], watch).should be_true

        File.read("public/index.html").should contain("v2")
        cache_name(File.read("public/sw.js")).should_not eq(before)
      end
    end
  end

  it "regenerates sw.js on a template-only re-render (A10)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_pwa_site
        builder = pwa_builder
        options = pwa_options
        builder.run(options).should be_true
        before = cache_name(File.read("public/sw.js"))

        File.write("templates/page.html", "<html><body class=\"v2\">{{ content }}</body></html>")
        builder.run_rerender(pwa_options(preserve: true)).should be_true

        File.read("public/index.html").should contain("v2")
        cache_name(File.read("public/sw.js")).should_not eq(before)
      end
    end
  end
end
