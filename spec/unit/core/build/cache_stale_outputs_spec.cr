require "../../../spec_helper"
require "../../../../src/core/build/builder"
require "../../../../src/content/hooks"

# End-to-end cover for what a warm `--cache` build leaves behind.
#
# A cold build starts from an empty output directory; `--cache` keeps it, and
# the render phase only ever walks pages that still exist. So a page that was
# deleted, renamed or turned into a draft kept its HTML in `public/` — still
# served, still deployed — and a page turned `render = false` additionally
# stayed in every SEO surface, because it renders nothing and the "nothing
# rendered, set unchanged" skip then held.
private def with_cached_site(&)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      File.write("config.toml", <<-TOML)
        title = "T"
        base_url = "http://localhost"

        [sitemap]
        enabled = true
        TOML
      FileUtils.mkdir_p("content/posts")
      File.write("content/posts/keep.md", "+++\ntitle = \"Keep\"\n+++\nkeep body")
      File.write("content/posts/gone.md", "+++\ntitle = \"Gone\"\n+++\ngone body")
      FileUtils.mkdir_p("templates")
      File.write("templates/page.html", "<p>{{ content }}</p>")
      yield dir
    end
  end
end

private def cached_build
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public", parallel: false, cache: true, highlight: false,
  )).should be_true
  builder
end

describe "warm --cache builds" do
  it "removes the output of a deleted page" do
    with_cached_site do
      cached_build
      File.exists?("public/posts/gone/index.html").should be_true

      File.delete("content/posts/gone.md")
      cached_build

      File.exists?("public/posts/gone/index.html").should be_false
      File.exists?("public/posts/keep/index.html").should be_true
    end
  end

  it "removes the output of a renamed page" do
    with_cached_site do
      cached_build
      File.rename("content/posts/gone.md", "content/posts/moved.md")
      cached_build

      File.exists?("public/posts/gone/index.html").should be_false
      File.exists?("public/posts/moved/index.html").should be_true
    end
  end

  it "removes the output of a page turned draft" do
    with_cached_site do
      cached_build
      File.write("content/posts/gone.md", "+++\ntitle = \"Gone\"\ndraft = true\n+++\ngone body")
      cached_build

      File.exists?("public/posts/gone/index.html").should be_false
    end
  end

  it "drops a page turned render = false from the sitemap" do
    with_cached_site do
      cached_build
      File.read("public/sitemap.xml").should contain("/posts/gone/")

      File.write("content/posts/gone.md", "+++\ntitle = \"Gone\"\nrender = false\n+++\ngone body")
      cached_build

      File.exists?("public/posts/gone/index.html").should be_false
      File.read("public/sitemap.xml").should_not contain("/posts/gone/")
    end
  end

  it "leaves an untouched page's output alone" do
    with_cached_site do
      cached_build
      before = File.read("public/posts/keep/index.html")
      cached_build

      File.exists?("public/posts/keep/index.html").should be_true
      File.read("public/posts/keep/index.html").should eq(before)
      File.exists?("public/posts/gone/index.html").should be_true
    end
  end
end
