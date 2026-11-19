require "../../../spec_helper"
require "../../../../src/core/build/builder"
require "../../../../src/content/hooks"

# A `--cache` build trusts .hwaro_cache.json to describe what sits in the
# output directory. Anything that rewrites that directory without leaving the
# cache in step with it must make the next `--cache` build start from scratch:
# a plain (cache-less) build, and a `--cache` build that failed part-way.
private def foreign_build(cache : Bool, drafts : Bool = false, minify : Bool = false, output_dir : String = "public") : Bool
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: output_dir, parallel: false, cache: cache, drafts: drafts, minify: minify, highlight: false,
  ))
rescue Hwaro::HwaroError
  false
end

private def with_foreign_site(&)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      File.write("config.toml", "title = \"T\"\nbase_url = \"http://localhost\"\n")
      FileUtils.mkdir_p("content/posts")
      FileUtils.mkdir_p("templates/partials")
      File.write("content/posts/pub.md", "+++\ntitle = \"pub\"\n+++\nbody")
      File.write("content/posts/secret.md", "+++\ntitle = \"secret\"\ndraft = true\n+++\nbody")
      File.write("templates/page.html", "{% include \"partials/p.html\" %}|{{ content }}")
      File.write("templates/partials/p.html", "V1")
      yield
    end
  end
end

describe "--cache after a build that rewrote the output behind its back" do
  it "drops a draft published by an intervening cache-less build" do
    with_foreign_site do
      foreign_build(cache: true).should be_true
      File.exists?("public/posts/secret/index.html").should be_false

      foreign_build(cache: false, drafts: true).should be_true
      File.exists?("public/posts/secret/index.html").should be_true

      foreign_build(cache: true).should be_true
      File.exists?("public/posts/secret/index.html").should be_false
    end
  end

  it "re-renders minified output left by an intervening cache-less build" do
    with_foreign_site do
      File.write("templates/partials/p.html", "<p>\n\n  V1\n\n</p>")
      foreign_build(cache: true).should be_true
      cold = File.read("public/posts/pub/index.html")

      foreign_build(cache: false, minify: true).should be_true
      File.read("public/posts/pub/index.html").should_not eq(cold)

      foreign_build(cache: true).should be_true
      File.read("public/posts/pub/index.html").should eq(cold)
    end
  end

  it "leaves the cache alone when the cache-less build targets another directory" do
    with_foreign_site do
      foreign_build(cache: true).should be_true
      before = File.read(".hwaro_cache.json")

      foreign_build(cache: false, output_dir: "elsewhere").should be_true

      File.read(".hwaro_cache.json").should eq(before)
    end
  end

  it "does not trust output a failed --cache build left half rewritten" do
    with_foreign_site do
      %w[a b c].each { |name| File.write("content/posts/#{name}.md", "+++\ntitle = \"#{name}\"\n+++\nbody") }
      foreign_build(cache: true).should be_true
      File.read("public/posts/a/index.html").should contain("V1")

      File.write("templates/partials/p.html", "{% if page.title == \"c\" %}{{ nope_fn() }}{% endif %}V2")
      foreign_build(cache: true).should be_false
      File.read("public/posts/a/index.html").should contain("V2")

      File.write("templates/partials/p.html", "V1")
      foreign_build(cache: true).should be_true
      %w[a b c].each { |name| File.read("public/posts/#{name}/index.html").should contain("V1") }
    end
  end
end

# `hwaro serve --cache` keeps its own cache file beside its own tree, and every
# rebuild of the session rewrites that tree. A rebuild that fails after it
# wrote pages saves nothing, so the file must stop vouching for them too:
# undoing the failing edit made every hash match again, and the recovering
# rebuild (or the next `serve --cache`) kept serving the undone edit.
private def serve_cache_options(watch : Bool = true) : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: ".hwaro/serve", parallel: false, cache: true, highlight: false,
  )
  options.serve_mode = true
  options.preserve_output = watch
  options
end

private def serve_cache_builder : Hwaro::Core::Build::Builder
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder
end

private def with_strict_serve_site(&)
  with_foreign_site do
    File.write("config.toml", "title = \"T\"\nbase_url = \"http://localhost\"\n[links]\nbroken_internal = \"error\"\n")
    File.write("templates/partials/p.html", "{% for p in site.pages %}[{{ p.title }}]{% endfor %}")
    yield
  end
end

describe "serve --cache after a rebuild that failed part-way" do
  pub = ".hwaro/serve/posts/pub/index.html"

  it "re-renders a page a failed incremental rebuild wrote, once the edit is undone" do
    with_strict_serve_site do
      builder = serve_cache_builder
      builder.run(serve_cache_options(watch: false)).should be_true

      # The strict link check raises after the fan-out wrote the page.
      File.write("content/posts/pub.md", "+++\ntitle = \"pub\"\n+++\nedited [x](@/missing.md)")
      expect_raises(Hwaro::HwaroError) { builder.run_incremental(["content/posts/pub.md"], serve_cache_options) }
      File.read(pub).should contain("edited")

      # The watcher escalates the rebuild after a failure to a full one.
      File.write("content/posts/pub.md", "+++\ntitle = \"pub\"\n+++\nbody")
      builder.run(serve_cache_options).should be_true
      File.read(pub).should_not contain("edited")
    end
  end

  it "does not trust that page on the next serve --cache start either" do
    with_strict_serve_site do
      builder = serve_cache_builder
      builder.run(serve_cache_options(watch: false)).should be_true

      File.write("content/posts/pub.md", "+++\ntitle = \"pub\"\n+++\nedited [x](@/missing.md)")
      expect_raises(Hwaro::HwaroError) { builder.run_incremental(["content/posts/pub.md"], serve_cache_options) }

      File.write("content/posts/pub.md", "+++\ntitle = \"pub\"\n+++\nbody")
      serve_cache_builder.run(serve_cache_options(watch: false)).should be_true
      File.read(pub).should_not contain("edited")
    end
  end

  it "re-renders the listings a failed full rebuild wrote" do
    with_strict_serve_site do
      builder = serve_cache_builder
      builder.run(serve_cache_options(watch: false)).should be_true

      # An added file takes the full-rebuild lane.
      File.write("content/posts/ghost.md", "+++\ntitle = \"ghost\"\n+++\n[x](@/missing.md)")
      expect_raises(Hwaro::HwaroError) { builder.run(serve_cache_options) }
      File.read(pub).should contain("[ghost]")

      File.delete("content/posts/ghost.md")
      builder.run(serve_cache_options).should be_true
      File.read(pub).should_not contain("[ghost]")
    end
  end

  it "re-renders the pages a failed template re-render wrote" do
    with_foreign_site do
      %w[a b c].each { |name| File.write("content/posts/#{name}.md", "+++\ntitle = \"#{name}\"\n+++\nbody") }
      builder = serve_cache_builder
      builder.run(serve_cache_options(watch: false)).should be_true

      File.write("templates/partials/p.html", "{% if page.title == \"c\" %}{{ nope_fn() }}{% endif %}V2")
      expect_raises(Hwaro::HwaroError) { builder.run_rerender(serve_cache_options) }
      File.read(".hwaro/serve/posts/a/index.html").should contain("V2")

      File.write("templates/partials/p.html", "V1")
      builder.run(serve_cache_options).should be_true
      %w[a b c].each { |name| File.read(".hwaro/serve/posts/#{name}/index.html").should contain("V1") }
    end
  end

  # The static copy runs before any render (see the same case for
  # `build --cache` in cache_stale_outputs_spec).
  it "re-renders a page the static copy overwrote in a full rebuild that failed" do
    with_foreign_site do
      FileUtils.mkdir_p("static/posts/pub")
      File.write("static/posts/pub/index.html", "<p>STATIC</p>")
      builder = serve_cache_builder
      builder.run(serve_cache_options(watch: false)).should be_true
      File.read(pub).should contain("body")

      File.write("content/posts/typo.md", "+++\ntitle = \"Typo\"\nfoo = [\n+++\nx")
      expect_raises(Hwaro::HwaroError, /Invalid TOML frontmatter/) { builder.run(serve_cache_options) }

      File.delete("content/posts/typo.md")
      builder.run(serve_cache_options).should be_true
      File.read(pub).should contain("body")
    end
  end

  # The recovering rebuild starts without a cache file, so its prune rests on
  # the builder's own record of the previous outputs.
  it "still prunes a page the recovering rebuild drafts" do
    with_strict_serve_site do
      File.write("content/posts/other.md", "+++\ntitle = \"other\"\n+++\nother")
      builder = serve_cache_builder
      builder.run(serve_cache_options(watch: false)).should be_true
      File.exists?(".hwaro/serve/posts/other/index.html").should be_true

      File.write("content/posts/pub.md", "+++\ntitle = \"pub\"\n+++\nedited [x](@/missing.md)")
      expect_raises(Hwaro::HwaroError) { builder.run_incremental(["content/posts/pub.md"], serve_cache_options) }

      File.write("content/posts/pub.md", "+++\ntitle = \"pub\"\n+++\nbody")
      File.write("content/posts/other.md", "+++\ntitle = \"other\"\ndraft = true\n+++\nother")
      builder.run(serve_cache_options).should be_true
      File.exists?(".hwaro/serve/posts/other/index.html").should be_false
      File.read(pub).should_not contain("[other]")
    end
  end

  it "keeps the cache file when a rebuild has nothing to write" do
    with_strict_serve_site do
      builder = serve_cache_builder
      builder.run(serve_cache_options(watch: false)).should be_true
      before = File.read(".hwaro/serve_cache.json")

      builder.run_incremental(["content/posts/not-a-page.md"], serve_cache_options).should be_true
      builder.run_rerender(serve_cache_options).should be_true

      File.read(".hwaro/serve_cache.json").should eq(before)
    end
  end
end
