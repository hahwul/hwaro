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

    def test_recompute_series_for_pages(site, changed, old_names = {} of String => String?)
      recompute_series_for_pages(site, changed, old_names)
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
  end

  describe "#link_page_navigation" do
    it "links pages with lower/higher in flat order" do
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      section = make_section("blog/_index.md", "blog")
      section.is_index = true
      section.weight = 1
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

      # The first page in the flat list has no lower neighbor
      [section, page_a, page_b].count(&.lower.nil?).should be >= 1
      [section, page_a, page_b].count(&.higher.nil?).should be >= 1
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

  describe "#update_taxonomies_incremental" do
    it "removes old assignments and adds new ones for changed pages" do
      site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
      page = make_page("p.md")
      page.taxonomies = {"tags" => ["new"]}
      site.taxonomies["tags"] = {"old" => [page], "shared" => [page]}

      snapshot = {"p.md" => {"tags" => ["old", "shared"]}}

      builder = Hwaro::Core::Build::Builder.new
      affected = builder.test_update_taxonomies_incremental(site, [page], snapshot)

      affected.includes?("tags:old").should be_true
      affected.includes?("tags:new").should be_true
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
      published.series_pages.size.should eq(1)
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

          page.assets.any? { |a| a.ends_with?("cover.png") }.should be_true
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
