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

        [[taxonomies]]
        name = "tags"
        TOML
      FileUtils.mkdir_p("content/posts")
      # A section index is what paginates, so the pagination specs need one.
      File.write("content/posts/_index.md", "+++\ntitle = \"Posts\"\n+++\n")
      File.write("content/posts/keep.md", "+++\ntitle = \"Keep\"\ntags = [\"keep-tag\"]\n+++\nkeep body")
      File.write("content/posts/gone.md", "+++\ntitle = \"Gone\"\ntags = [\"gone-tag\"]\naliases = [\"/legacy/\"]\n+++\ngone body")
      FileUtils.mkdir_p("templates")
      File.write("templates/page.html", "<p>{{ content }}</p>")
      # A section listing is what paginates; without its own template the
      # section renders as a plain page and never emits /page/N/.
      File.write("templates/section.html", "<h1>{{ page.title }}</h1>{{ pagination_nav }}")
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

  it "removes the taxonomy term page of a term nobody uses any more" do
    with_cached_site do
      cached_build
      File.exists?("public/tags/gone-tag/index.html").should be_true

      File.delete("content/posts/gone.md")
      cached_build

      File.exists?("public/tags/gone-tag/index.html").should be_false
      # The surviving post's term page must not be touched.
      File.exists?("public/tags/keep-tag/index.html").should be_true
    end
  end

  it "removes an alias redirect stub with the page that declared it" do
    with_cached_site do
      cached_build
      File.exists?("public/legacy/index.html").should be_true

      File.delete("content/posts/gone.md")
      cached_build

      File.exists?("public/legacy/index.html").should be_false
    end
  end

  it "removes an alias the page stopped declaring" do
    with_cached_site do
      cached_build
      File.exists?("public/legacy/index.html").should be_true

      File.write("content/posts/gone.md", "+++\ntitle = \"Gone\"\ntags = [\"gone-tag\"]\n+++\ngone body")
      cached_build

      File.exists?("public/legacy/index.html").should be_false
      File.exists?("public/posts/gone/index.html").should be_true
    end
  end

  it "removes the pagination page a section no longer fills" do
    with_cached_site do
      File.write("config.toml", File.read("config.toml") + "\n[pagination]\nenabled = true\nper_page = 1\n")
      cached_build
      File.exists?("public/posts/page/2/index.html").should be_true

      File.delete("content/posts/gone.md")
      cached_build

      File.exists?("public/posts/page/2/index.html").should be_false
      File.exists?("public/posts/index.html").should be_true
    end
  end

  it "removes the AMP mirror of a deleted page" do
    with_cached_site do
      File.write("config.toml", File.read("config.toml") + "\n[amp]\nenabled = true\n")
      cached_build
      File.exists?("public/amp/posts/gone/index.html").should be_true

      File.delete("content/posts/gone.md")
      cached_build

      File.exists?("public/amp/posts/gone/index.html").should be_false
      File.exists?("public/amp/posts/keep/index.html").should be_true
    end
  end

  # AMP claims nothing when it is off, so every mirror the last build wrote is
  # stale — the whole tree goes.
  it "removes every AMP mirror once AMP is switched off" do
    with_cached_site do
      base_config = File.read("config.toml")
      File.write("config.toml", base_config + "\n[amp]\nenabled = true\n")
      cached_build
      File.exists?("public/amp/posts/keep/index.html").should be_true

      File.write("config.toml", base_config + "\n[amp]\nenabled = false\n")
      cached_build

      File.exists?("public/amp/posts/keep/index.html").should be_false
      File.exists?("public/posts/keep/index.html").should be_true
    end
  end

  # A config edit invalidates every cache entry, which used to take the record
  # of what the last build wrote with it — so nothing could be pruned, and
  # (once a prune existed) nothing must be over-pruned either.
  it "keeps live output across a config change that invalidates the cache" do
    with_cached_site do
      File.write("config.toml", File.read("config.toml") + "\n[pagination]\nenabled = true\nper_page = 1\n")
      cached_build
      File.exists?("public/posts/page/2/index.html").should be_true

      File.write("config.toml", File.read("config.toml").sub("per_page = 1", "per_page = 5"))
      cached_build

      # Everything still published survives...
      File.exists?("public/posts/keep/index.html").should be_true
      File.exists?("public/posts/gone/index.html").should be_true
      File.exists?("public/posts/index.html").should be_true
      File.exists?("public/legacy/index.html").should be_true
      # ...and the page the section no longer paginates into does not.
      File.exists?("public/posts/page/2/index.html").should be_false
    end
  end

  # OG images prune themselves inside the generator, against the manifest it
  # already keeps in its own output directory.
  it "removes the auto-generated OG image of a deleted page" do
    with_cached_site do
      File.write("config.toml", File.read("config.toml") + "\n[og.auto_image]\nenabled = true\n")
      cached_build
      images = Dir.glob("public/og-images/posts-gone.*")
      images.should_not be_empty

      File.delete("content/posts/gone.md")
      cached_build

      Dir.glob("public/og-images/posts-gone.*").should be_empty
      Dir.glob("public/og-images/posts-keep.*").should_not be_empty
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
