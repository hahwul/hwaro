require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose private Transform helpers for testing.
module Hwaro::Core::Build
  class Builder
    def test_build_subsections(ctx : Lifecycle::BuildContext)
      build_subsections(ctx)
    end

    def test_link_page_navigation(ctx : Lifecycle::BuildContext)
      link_page_navigation(ctx)
    end

    def test_collect_assets(ctx : Lifecycle::BuildContext)
      collect_assets(ctx)
    end

    def test_populate_taxonomies(ctx : Lifecycle::BuildContext)
      populate_taxonomies(ctx)
    end

    def test_rebuild_taxonomies(site : Models::Site, pages : Array(Models::Page))
      rebuild_taxonomies(site, pages)
    end

    def test_update_taxonomies_incremental(site, changed_pages, snapshot)
      update_taxonomies_incremental(site, changed_pages, snapshot)
    end

    def test_compute_series(site : Models::Site)
      compute_series(site)
    end

    def test_aggregate_site_authors(site : Models::Site)
      aggregate_site_authors(site)
    end

    def test_recompute_series_for_pages(site, changed, old_names = {} of String => String?)
      recompute_series_for_pages(site, changed, old_names)
    end

    def test_relink_navigation_for_sections(site, affected = Set(String).new)
      relink_navigation_for_sections(site, affected)
    end

    def test_recompute_related_posts_for_pages(site, changed, removed = Set(String).new)
      recompute_related_posts_for_pages(site, changed, removed)
    end

    def test_run_transform(ctx : Lifecycle::BuildContext, profiler : Profiler)
      execute_transform_phase(ctx, profiler)
    end

    def test_set_transform_site(site : Models::Site)
      @site = site
    end
  end
end

private def make_section(path : String, name : String) : Hwaro::Models::Section
  s = Hwaro::Models::Section.new(path)
  s.section = name
  s
end

private def make_page(path : String, section : String = "") : Hwaro::Models::Page
  p = Hwaro::Models::Page.new(path)
  p.section = section
  p
end

describe Hwaro::Core::Build::Phases::Transform do
  describe "#build_subsections" do
    it "links subsections to their parent" do
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      parent = make_section("docs/_index.md", "docs")
      child = make_section("docs/guide/_index.md", "docs/guide")
      ctx.sections = [parent, child]

      builder = Hwaro::Core::Build::Builder.new
      builder.test_build_subsections(ctx)

      parent.subsections.size.should eq(1)
      parent.subsections.first.section.should eq("docs/guide")
      child.ancestors.size.should eq(1)
      child.ancestors.first.section.should eq("docs")
    end

    it "links page ancestors based on section path" do
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      docs = make_section("docs/_index.md", "docs")
      guide = make_section("docs/guide/_index.md", "docs/guide")
      page = make_page("docs/guide/topic.md", "docs/guide")
      ctx.sections = [docs, guide]
      ctx.pages = [page]

      builder = Hwaro::Core::Build::Builder.new
      builder.test_build_subsections(ctx)

      page.ancestors.map(&.section).should eq(["docs", "docs/guide"])
    end

    it "resolves per-language ancestors for multilingual section indexes" do
      # posts/_index.md (default) and posts/_index.ko.md both have section
      # "posts"; a language-blind lookup made the last one win, so every page's
      # breadcrumb pointed at one language's section. Each page must get its OWN
      # language's section.
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
      site = Hwaro::Models::Site.new(config)
      ctx.site = site

      en_index = make_section("posts/_index.md", "posts")
      en_index.url = "/posts/"
      ko_index = make_section("posts/_index.ko.md", "posts")
      ko_index.language = "ko"
      ko_index.url = "/ko/posts/"
      ctx.sections = [en_index, ko_index]

      en_page = make_page("posts/a.md", "posts")
      ko_page = make_page("posts/a.ko.md", "posts")
      ko_page.language = "ko"
      ctx.pages = [en_page, ko_page]

      builder = Hwaro::Core::Build::Builder.new
      builder.test_build_subsections(ctx)

      en_page.ancestors.map(&.url).should eq(["/posts/"])
      ko_page.ancestors.map(&.url).should eq(["/ko/posts/"])
    end
  end

  describe "#link_page_navigation" do
    it "links pages with lower/higher in flat reading order" do
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      section = make_section("blog/_index.md", "blog")
      section.is_index = true
      section.weight = 1
      # Sorted by weight ascending within the section
      page_a = make_page("blog/a.md", "blog")
      page_a.title = "A"
      page_a.weight = 1
      page_b = make_page("blog/b.md", "blog")
      page_b.title = "B"
      page_b.weight = 2

      ctx.sections = [section]
      ctx.pages = [page_a, page_b]

      builder = Hwaro::Core::Build::Builder.new
      builder.test_link_page_navigation(ctx)

      # Flat order: section index → page_a (weight 1) → page_b (weight 2)
      section.lower.should be_nil
      section.higher.should eq(page_a)

      page_a.lower.should eq(section)
      page_a.higher.should eq(page_b)

      page_b.lower.should eq(page_a)
      page_b.higher.should be_nil
    end

    it "links page bundles alongside single-file pages (issue #539)" do
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      section = make_section("posts/_index.md", "posts")
      section.is_index = true
      section.weight = 1
      section.sort_by = "weight"

      # Single-file page
      foo = make_page("posts/foo.md", "posts")
      foo.title = "Foo"
      foo.weight = 1
      # Page bundle (index.md) — also has is_index = true for URL generation,
      # but should still receive lower/higher links.
      bar = make_page("posts/bar/index.md", "posts")
      bar.title = "Bar"
      bar.weight = 2
      bar.is_index = true

      ctx.sections = [section]
      ctx.pages = [foo, bar]

      builder = Hwaro::Core::Build::Builder.new
      builder.test_link_page_navigation(ctx)

      # Flat order: section index → foo (weight 1) → bar (weight 2)
      foo.lower.should eq(section)
      foo.higher.should eq(bar)

      bar.lower.should eq(foo)
      bar.higher.should be_nil
    end

    it "leads the reading order with the site root index, not trailing it (book prev/next)" do
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      # Site root index (content/index.md): is_index with an empty section.
      # Previously it was appended as a generic orphan and landed LAST, making
      # the book scaffold's prev/next chain wrap (home got a prev, chapter-1
      # lost its prev). It must lead the reading order instead.
      home = make_page("index.md", "")
      home.title = "Introduction"
      home.is_index = true
      home.weight = 0

      chapter = make_section("chapter-1/_index.md", "chapter-1")
      chapter.is_index = true
      chapter.weight = 1
      lesson = make_page("chapter-1/intro.md", "chapter-1")
      lesson.title = "Intro"
      lesson.weight = 1

      ctx.sections = [chapter]
      ctx.pages = [home, lesson]

      builder = Hwaro::Core::Build::Builder.new
      builder.test_link_page_navigation(ctx)

      # Flat order: home → chapter-1 index → lesson
      home.lower.should be_nil
      home.higher.should eq(chapter)
      chapter.lower.should eq(home)
      lesson.higher.should be_nil
    end
  end

  describe "#populate_taxonomies / #rebuild_taxonomies" do
    it "groups pages by taxonomy term" do
      site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
      page1 = make_page("p1.md")
      page1.taxonomies = {"tags" => ["crystal", "ssg"]}
      page2 = make_page("p2.md")
      page2.taxonomies = {"tags" => ["crystal"]}

      builder = Hwaro::Core::Build::Builder.new
      builder.test_rebuild_taxonomies(site, [page1, page2])

      site.taxonomies["tags"]["crystal"].size.should eq(2)
      site.taxonomies["tags"]["ssg"].size.should eq(1)
    end

    it "clears existing taxonomies before rebuilding" do
      site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
      site.taxonomies["stale"] = {"old" => [] of Hwaro::Models::Page}

      builder = Hwaro::Core::Build::Builder.new
      builder.test_rebuild_taxonomies(site, [] of Hwaro::Models::Page)

      site.taxonomies.has_key?("stale").should be_false
    end

    it "includes a configured 'authors' taxonomy sourced from page.authors" do
      # "authors" lives on @authors, not page.taxonomies, so the render-phase
      # map omitted it — making get_taxonomy("authors") empty even though the
      # generator writes /authors/ pages. It must be present here.
      config = Hwaro::Models::Config.new
      config.taxonomies = [Hwaro::Models::TaxonomyConfig.new("authors")]
      site = Hwaro::Models::Site.new(config)
      page1 = make_page("p1.md")
      page1.authors = ["Jane Doe"]
      page2 = make_page("p2.md")
      page2.authors = ["Jane Doe"]

      builder = Hwaro::Core::Build::Builder.new
      builder.test_rebuild_taxonomies(site, [page1, page2])

      site.taxonomies.has_key?("authors").should be_true
      site.taxonomies["authors"]["Jane Doe"].size.should eq(2)
    end

    it "does not double-count a configured 'tags' taxonomy already in page.taxonomies" do
      config = Hwaro::Models::Config.new
      config.taxonomies = [Hwaro::Models::TaxonomyConfig.new("tags")]
      site = Hwaro::Models::Site.new(config)
      page = make_page("p.md")
      page.taxonomies = {"tags" => ["crystal"]} # merged at parse like the real flow
      page.tags = ["crystal"]

      builder = Hwaro::Core::Build::Builder.new
      builder.test_rebuild_taxonomies(site, [page])

      # The authors-union pass must skip "tags" (already in page.taxonomies).
      site.taxonomies["tags"]["crystal"].size.should eq(1)
    end

    it "populates taxonomies via the context-aware variant" do
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
      ctx.site = site

      page = make_page("p.md")
      page.taxonomies = {"categories" => ["news"]}
      ctx.pages = [page]

      builder = Hwaro::Core::Build::Builder.new
      builder.test_populate_taxonomies(ctx)

      site.taxonomies["categories"]["news"].size.should eq(1)
    end
  end

  describe "#relink_navigation_for_sections" do
    it "reports the set of pages whose prev/next changed (block reorder)" do
      site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
      section = make_section("blog/_index.md", "blog")
      section.sort_by = "weight"
      p1 = make_page("blog/p1.md", "blog")
      p1.weight = 1
      p2 = make_page("blog/p2.md", "blog")
      p2.weight = 2
      p3 = make_page("blog/p3.md", "blog")
      p3.weight = 3
      site.sections = [section]
      site.pages = [p1, p2, p3]

      builder = Hwaro::Core::Build::Builder.new
      # First relink establishes pointers; a second no-op relink reports nothing.
      builder.test_relink_navigation_for_sections(site)
      builder.test_relink_navigation_for_sections(site).empty?.should be_true

      # Reorder the block: p3 moves to the front. Pages whose neighbors flipped
      # must be reported — including p1, which is neither p3 nor a changed page.
      p3.weight = 0
      changed = builder.test_relink_navigation_for_sections(site)
      changed.empty?.should be_false
      changed.map(&.path).should contain("blog/p1.md")
    end
  end

  describe "#recompute_related_posts_for_pages" do
    it "drops a removed page from referrers' related_posts via removed_paths" do
      config = Hwaro::Models::Config.new
      config.related.enabled = true
      config.related.taxonomies = ["tags"]
      config.related.limit = 5
      site = Hwaro::Models::Site.new(config)

      a = make_page("a.md")
      a.tags = ["crystal"]
      b = make_page("b.md")
      b.tags = ["crystal"]
      site.pages = [a, b]

      builder = Hwaro::Core::Build::Builder.new
      builder.test_recompute_related_posts_for_pages(site, [a, b])
      b.related_posts.map(&.path).should contain("a.md") # a and b are related

      # `a` turns draft/future -> removed from site.pages. Without seeding the
      # removed path, b would keep a stale related link to a (a now-deleted page).
      site.pages = [b]
      updated = builder.test_recompute_related_posts_for_pages(site, [] of Hwaro::Models::Page, Set{"a.md"})
      updated.should contain("b.md")
      b.related_posts.map(&.path).should_not contain("a.md")
    end
  end

  describe "#aggregate_site_authors" do
    it "excludes draft pages so site.authors matches the /authors/ generator" do
      site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
      published = make_page("pub.md")
      published.authors = ["Alice"]
      published.draft = false
      drafted = make_page("draft.md")
      drafted.authors = ["Alice"]
      drafted.draft = true
      site.pages = [published, drafted]

      builder = Hwaro::Core::Build::Builder.new
      builder.test_aggregate_site_authors(site)

      site.authors.has_key?("alice").should be_true
      pages_raw = site.authors["alice"].raw.as(Hash(Crinja::Value, Crinja::Value))["pages"].raw.as(Array(Crinja::Value))
      pages_raw.size.should eq(1) # only the published page, not the draft
    end
  end

  describe "#update_taxonomies_incremental" do
    it "removes old assignments and adds new ones for changed pages" do
      site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
      page = make_page("p.md")
      page.taxonomies = {"tags" => ["new"]}
      site.taxonomies["tags"] = {"old" => [page], "shared" => [page]}

      snapshot = {"p.md" => {"tags" => ["old", "shared"]}}

      builder = Hwaro::Core::Build::Builder.new
      affected = builder.test_update_taxonomies_incremental(site, [page], snapshot)

      affected.includes?({"tags", "old"}).should be_true
      affected.includes?({"tags", "new"}).should be_true
      site.taxonomies["tags"].has_key?("old").should be_false
      site.taxonomies["tags"]["new"].size.should eq(1)
    end
  end

  describe "#compute_series" do
    it "assigns series_index and series_pages within a series" do
      config = Hwaro::Models::Config.new
      config.series.enabled = true
      site = Hwaro::Models::Site.new(config)

      p1 = make_page("a.md")
      p1.title = "A"
      p1.series = "tutorial"
      p1.series_weight = 2
      p2 = make_page("b.md")
      p2.title = "B"
      p2.series = "tutorial"
      p2.series_weight = 1

      site.pages = [p1, p2]
      builder = Hwaro::Core::Build::Builder.new
      builder.test_compute_series(site)

      # Lower series_weight comes first
      p2.series_index.should eq(1)
      p1.series_index.should eq(2)
      p1.series_pages.size.should eq(2)
    end

    it "skips drafts and non-renderable pages" do
      config = Hwaro::Models::Config.new
      config.series.enabled = true
      site = Hwaro::Models::Site.new(config)

      published = make_page("p.md")
      published.title = "P"
      published.series = "guide"
      draft = make_page("d.md")
      draft.title = "D"
      draft.series = "guide"
      draft.draft = true

      site.pages = [published, draft]
      builder = Hwaro::Core::Build::Builder.new
      builder.test_compute_series(site)

      published.series_index.should eq(1)
      # Draft is excluded, leaving a single-member series, which renders no
      # prev/next nav, so series_pages is left empty.
      published.series_pages.size.should eq(0)
    end

    it "leaves series_pages empty for a single-post series" do
      config = Hwaro::Models::Config.new
      config.series.enabled = true
      site = Hwaro::Models::Site.new(config)

      lonely = make_page("lonely.md")
      lonely.title = "Lonely"
      lonely.series = "Lonely"

      site.pages = [lonely]
      builder = Hwaro::Core::Build::Builder.new
      builder.test_compute_series(site)

      lonely.series_index.should eq(1)
      lonely.series_pages.size.should eq(0)
    end
  end

  describe "#recompute_series_for_pages" do
    it "recomputes only the affected series" do
      config = Hwaro::Models::Config.new
      config.series.enabled = true
      site = Hwaro::Models::Site.new(config)

      p1 = make_page("p1.md"); p1.title = "P1"; p1.series = "tutorial"
      p2 = make_page("p2.md"); p2.title = "P2"; p2.series = "tutorial"
      other = make_page("o.md"); other.title = "O"; other.series = "other"
      site.pages = [p1, p2, other]

      builder = Hwaro::Core::Build::Builder.new
      affected = builder.test_recompute_series_for_pages(site, [p1])
      affected.includes?("tutorial").should be_true
      affected.includes?("other").should be_false
    end

    it "leaves series_pages empty for a single-post series" do
      config = Hwaro::Models::Config.new
      config.series.enabled = true
      site = Hwaro::Models::Site.new(config)

      lonely = make_page("lonely.md"); lonely.title = "Lonely"; lonely.series = "Lonely"
      site.pages = [lonely]

      builder = Hwaro::Core::Build::Builder.new
      builder.test_recompute_series_for_pages(site, [lonely])

      lonely.series_index.should eq(1)
      lonely.series_pages.size.should eq(0)
    end
  end

  describe "#collect_assets" do
    it "collects co-located assets for pages and sections" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/blog/post")
          File.write("content/blog/post/index.md", "---\ntitle: P\n---\nbody")
          File.write("content/blog/post/cover.png", "binary")

          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
          page = make_page("blog/post/index.md", "blog")
          page.is_index = true
          ctx.pages = [page]

          builder = Hwaro::Core::Build::Builder.new
          builder.test_collect_assets(ctx)

          page.assets.any?(&.ends_with?("cover.png")).should be_true
        end
      end
    end
  end

  describe "#execute_transform_phase" do
    it "populates the site model with pages and sections" do
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      ctx.config = Hwaro::Models::Config.new

      site = Hwaro::Models::Site.new(ctx.config.not_nil!)

      page = make_page("p.md")
      page.title = "P"
      ctx.pages = [page]

      builder = Hwaro::Core::Build::Builder.new
      builder.test_set_transform_site(site)

      profiler = Hwaro::Profiler.new(enabled: false)
      result = builder.test_run_transform(ctx, profiler)

      result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      site.pages.size.should eq(1)
    end
  end
end
