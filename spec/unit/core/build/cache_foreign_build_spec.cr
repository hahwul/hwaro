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
