require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose private Render helpers for testing.
module Hwaro::Core::Build
  class Builder
    def test_get_output_path(page : Models::Page, output_dir : String)
      get_output_path(page, output_dir)
    end

    def test_determine_template(page : Models::Page, templates : Hash(String, String),
                                site : Models::Site = Models::Site.new(Models::Config.new))
      determine_template(page, templates, site)
    end

    def test_filter_changed_pages(pages, output_dir, cache,
                                  templates = {} of String => String,
                                  site = Models::Site.new(Models::Config.new))
      filter_changed_pages(pages, output_dir, cache, templates, site)
    end

    def test_build_pages_by_path(site : Models::Site)
      build_pages_by_path(site)
    end

    def test_render_error_signature(message : String)
      render_error_signature(message)
    end

    def test_report_render_failures(failures, verbose)
      report_render_failures(failures, verbose)
    end

    def test_build_global_vars(site : Models::Site)
      build_global_vars(site)
    end

    def test_split_priority_pages(pages : Array(Models::Page), count : Int32)
      split_priority_pages(pages, count)
    end

    def test_auto_render_workers(pages : Array(Models::Page), site : Models::Site,
                                 templates : Hash(String, String),
                                 features : Hash(String, TemplateVarFeatures))
      @template_var_features = features
      auto_render_workers(pages, site, templates)
    end

    def test_render_worker_count(pages : Array(Models::Page), site : Models::Site,
                                 templates : Hash(String, String),
                                 features : Hash(String, TemplateVarFeatures),
                                 item_count : Int32, jobs : Int32)
      @template_var_features = features
      @render_workers = jobs
      render_worker_count(pages, site, templates, item_count)
    end
  end
end

# Builds a site whose `page` template renders every page, with `page_count`
# pages spread over one section.
private def fanout_site(page_count : Int32) : {Hwaro::Models::Site, Array(Hwaro::Models::Page)}
  site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
  pages = Array.new(page_count) do |i|
    page = Hwaro::Models::Page.new("posts/post-#{i}.md")
    page.url = "/posts/post-#{i}/"
    page.section = "posts"
    page
  end
  site.pages = pages
  site.pages_by_section = {"posts" => pages}
  {site, pages}
end

private def features_for(site_loop : Bool, section_loop : Bool)
  {"page" => Hwaro::Core::Build::Builder::TemplateVarFeatures.new(
    needs_seo: false, needs_jsonld: false, needs_section_pages: section_loop,
    listing_fanout_site: site_loop, listing_fanout_section: section_loop)}
end

describe Hwaro::Core::Build::Phases::Render do
  describe "#get_output_path" do
    it "appends index.html to a section URL" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          page = Hwaro::Models::Page.new("blog/post.md")
          page.url = "/blog/post/"
          builder.test_get_output_path(page, "public").not_nil!
            .should end_with("public/blog/post/index.html")
        end
      end
    end

    it "produces public/index.html for the root URL" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          page = Hwaro::Models::Page.new("index.md")
          page.url = "/"
          builder.test_get_output_path(page, "public").not_nil!
            .should end_with("public/index.html")
        end
      end
    end

    it "produces a path inside the output directory for nested pages" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          page = Hwaro::Models::Page.new("nested/page.md")
          page.url = "/nested/page/"
          result = builder.test_get_output_path(page, "public")
          result.not_nil!.should contain("public/nested/page/index.html")
        end
      end
    end

    # Regression: an output directory written with a trailing separator must
    # resolve exactly like one without it. It used to fail containment, and
    # the rejected page then fell back to `<output_dir>/index.html` — every
    # page in the site overwriting the homepage in turn.
    it "resolves the same path when output_dir has a trailing separator" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          page = Hwaro::Models::Page.new("blog/post.md")
          page.url = "/blog/post/"
          builder.test_get_output_path(page, "public/")
            .should eq(builder.test_get_output_path(page, "public"))
        end
      end
    end
  end

  # Regression: the auto worker count used to be `cpu_count * 2` regardless of
  # workload. On a 5000-page site whose `page` template iterates `site.pages`
  # that cost 2.4x (18.4s at 1 worker vs 44.4s at the old default), while on a
  # site with no per-page listing it cost 2.2x to run too FEW workers. The two
  # curves invert, so the count has to follow the site's listing fan-out.
  describe "#auto_render_workers" do
    templates = {"page" => "{{ content }}"}

    it "serializes when every page materializes the whole site" do
      site, pages = fanout_site(5000)
      builder = Hwaro::Core::Build::Builder.new
      builder.test_auto_render_workers(pages, site, templates, features_for(true, false))
        .should eq(1)
    end

    it "serializes when every page materializes a large section" do
      site, pages = fanout_site(600)
      builder = Hwaro::Core::Build::Builder.new
      builder.test_auto_render_workers(pages, site, templates, features_for(false, true))
        .should eq(1)
    end

    it "limits workers for a mid-sized per-page listing" do
      site, pages = fanout_site(200)
      builder = Hwaro::Core::Build::Builder.new
      builder.test_auto_render_workers(pages, site, templates, features_for(true, false))
        .should eq(2)
    end

    it "uses the full auto cap when no page template lists anything" do
      site, pages = fanout_site(5000)
      builder = Hwaro::Core::Build::Builder.new
      expected = Math.min(System.cpu_count.to_i, 4)
      builder.test_auto_render_workers(pages, site, templates, features_for(false, false))
        .should eq(expected)
    end

    # A homepage that lists every page is one expensive render among thousands
    # of cheap ones. Taking the max fan-out instead of the mean would drop the
    # entire site to a single worker for that one page.
    it "is not dragged down by a single site-wide listing page" do
      site, pages = fanout_site(5000)
      index = Hwaro::Models::Page.new("index.md")
      index.url = "/"
      index.is_index = true
      site.pages = pages + [index]
      all = pages + [index]
      features = features_for(false, false).merge({
        "index" => Hwaro::Core::Build::Builder::TemplateVarFeatures.new(
          needs_seo: false, needs_jsonld: false, needs_section_pages: false,
          listing_fanout_site: true, listing_fanout_section: false),
      })
      builder = Hwaro::Core::Build::Builder.new
      builder.test_auto_render_workers(all, site, {"page" => "x", "index" => "y"}, features)
        .should eq(Math.min(System.cpu_count.to_i, 4))
    end

    it "hedges when no template closure could be analyzed" do
      site, pages = fanout_site(100)
      builder = Hwaro::Core::Build::Builder.new
      builder.test_auto_render_workers(pages, site, templates,
        {} of String => Hwaro::Core::Build::Builder::TemplateVarFeatures)
        .should eq(2)
    end

    it "hedges when most pages use an unanalyzable template" do
      site, pages = fanout_site(100)
      # Only "other" is analyzed; every page resolves to "page".
      features = {"other" => Hwaro::Core::Build::Builder::TemplateVarFeatures.new(
        needs_seo: false, needs_jsonld: false, needs_section_pages: false,
        listing_fanout_site: false, listing_fanout_section: false)}
      builder = Hwaro::Core::Build::Builder.new
      builder.test_auto_render_workers(pages, site, templates, features).should eq(2)
    end
  end

  describe "#render_worker_count" do
    templates = {"page" => "{{ content }}"}

    it "lets an explicit --jobs override the fan-out heuristic" do
      site, pages = fanout_site(5000)
      builder = Hwaro::Core::Build::Builder.new
      # The heuristic would pick 1 here; --jobs 8 must win.
      builder.test_render_worker_count(pages, site, templates, features_for(true, false), 5000, 8)
        .should eq(8)
    end

    it "never exceeds the item count" do
      site, pages = fanout_site(3)
      builder = Hwaro::Core::Build::Builder.new
      builder.test_render_worker_count(pages, site, templates, features_for(false, false), 3, 0)
        .should be <= 3
    end

    it "returns 1 for a single item" do
      site, pages = fanout_site(1)
      builder = Hwaro::Core::Build::Builder.new
      builder.test_render_worker_count(pages, site, templates, features_for(false, false), 1, 0)
        .should eq(1)
    end
  end

  describe "#determine_template" do
    it "returns 'page' as the default for regular pages" do
      builder = Hwaro::Core::Build::Builder.new
      page = Hwaro::Models::Page.new("about.md")
      templates = {"page" => "x"}
      builder.test_determine_template(page, templates).should eq("page")
    end

    it "returns 'section' for Section instances when available" do
      builder = Hwaro::Core::Build::Builder.new
      section = Hwaro::Models::Section.new("blog/_index.md")
      templates = {"page" => "p", "section" => "s"}
      builder.test_determine_template(section, templates).should eq("section")
    end

    it "returns 'index' for the root index page when an index template exists" do
      builder = Hwaro::Core::Build::Builder.new
      page = Hwaro::Models::Page.new("_index.md")
      page.is_index = true
      page.section = ""
      templates = {"page" => "p", "index" => "i"}
      builder.test_determine_template(page, templates).should eq("index")
    end

    it "does not treat a one-level page bundle as the homepage" do
      builder = Hwaro::Core::Build::Builder.new
      # content/about/index.md — an index page whose section also resolves to
      # "", so only the path distinguishes it from the root index page.
      page = Hwaro::Models::Page.new("about/index.md")
      page.is_index = true
      page.section = ""
      templates = {"page" => "p", "index" => "i"}
      builder.test_determine_template(page, templates).should eq("page")
    end

    it "honors a page-level custom template when present" do
      builder = Hwaro::Core::Build::Builder.new
      page = Hwaro::Models::Page.new("about.md")
      page.template = "landing"
      templates = {"page" => "p", "landing" => "l"}
      builder.test_determine_template(page, templates).should eq("landing")
    end

    it "warns and falls back when the custom template is missing" do
      builder = Hwaro::Core::Build::Builder.new
      page = Hwaro::Models::Page.new("about.md")
      page.template = "missing"
      templates = {"page" => "p"}
      builder.test_determine_template(page, templates).should eq("page")
      page.build_warnings.any?(&.includes?("missing")).should be_true
    end

    it "inherits the parent section's page_template for child pages" do
      builder = Hwaro::Core::Build::Builder.new
      site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
      section = Hwaro::Models::Section.new("guide/_index.md")
      section.section = "guide"
      section.page_template = "doc-page"
      site.sections << section
      site.build_lookup_index

      page = Hwaro::Models::Page.new("guide/intro.md")
      page.section = "guide"
      templates = {"page" => "p", "doc-page" => "d"}
      builder.test_determine_template(page, templates, site).should eq("doc-page")
    end

    it "lets a page-level template override the section page_template" do
      builder = Hwaro::Core::Build::Builder.new
      site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
      section = Hwaro::Models::Section.new("guide/_index.md")
      section.section = "guide"
      section.page_template = "doc-page"
      site.sections << section
      site.build_lookup_index

      page = Hwaro::Models::Page.new("guide/intro.md")
      page.section = "guide"
      page.template = "landing"
      templates = {"page" => "p", "doc-page" => "d", "landing" => "l"}
      builder.test_determine_template(page, templates, site).should eq("landing")
    end

    it "falls back to 'page' when the section page_template is not a real template" do
      builder = Hwaro::Core::Build::Builder.new
      site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
      section = Hwaro::Models::Section.new("guide/_index.md")
      section.section = "guide"
      section.page_template = "doc-page"
      site.sections << section
      site.build_lookup_index

      page = Hwaro::Models::Page.new("guide/intro.md")
      page.section = "guide"
      templates = {"page" => "p"}
      builder.test_determine_template(page, templates, site).should eq("page")
    end
  end

  describe "#filter_changed_pages" do
    it "returns all pages when none are cached" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          File.write("content/p.md", "x")

          builder = Hwaro::Core::Build::Builder.new
          page = Hwaro::Models::Page.new("p.md")
          page.url = "/p/"

          cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: ".cache.json")
          result = builder.test_filter_changed_pages([page], "public", cache)
          result.size.should eq(1)
        end
      end
    end

    it "skips pages that are unchanged in the cache" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          File.write("content/p.md", "x")
          FileUtils.mkdir_p("public/p")
          File.write("public/p/index.html", "<html/>")

          builder = Hwaro::Core::Build::Builder.new
          page = Hwaro::Models::Page.new("p.md")
          page.url = "/p/"

          cache = Hwaro::Core::Build::Cache.new(enabled: true, cache_path: ".cache.json")
          # Mark page as cached
          cache.update("content/p.md", "public/p/index.html")

          result = builder.test_filter_changed_pages([page], "public", cache)
          result.size.should eq(0)
        end
      end
    end
  end

  describe "#build_pages_by_path" do
    it "indexes both pages and sections by path" do
      builder = Hwaro::Core::Build::Builder.new
      site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
      page = Hwaro::Models::Page.new("blog/post.md")
      section = Hwaro::Models::Section.new("blog/_index.md")
      site.pages = [page]
      site.sections = [section]

      result = builder.test_build_pages_by_path(site)
      result["blog/post.md"].should eq(page)
      result["blog/_index.md"].should eq(section)
    end
  end

  describe "#render_error_signature" do
    it "strips the page-specific 'Template error for <path>' prefix" do
      builder = Hwaro::Core::Build::Builder.new
      msg = "Template error for posts/hello-world.md: Unterminated tag\ntemplate: <string>:1:20 .. 1:20"
      builder.test_render_error_signature(msg).should eq("Unterminated tag")
    end

    it "normalizes the same underlying error across different pages" do
      builder = Hwaro::Core::Build::Builder.new
      a = "Template error for about.md: Unterminated tag\nmore context"
      b = "Template error for posts/hello-world.md: Unterminated tag\nother context"
      builder.test_render_error_signature(a).should eq(builder.test_render_error_signature(b))
    end

    it "falls back to the first line when there is no 'Template error for' prefix" do
      builder = Hwaro::Core::Build::Builder.new
      builder.test_render_error_signature("Missing filter 'foo'\n  at line 3").should eq("Missing filter 'foo'")
    end
  end

  describe "#report_render_failures" do
    it "groups identical failures into a single summary line" do
      buffer = IO::Memory.new
      previous_io = Hwaro::Logger.io
      Hwaro::Logger.io = buffer
      begin
        builder = Hwaro::Core::Build::Builder.new
        failures = [
          {page_path: "index.md", message: "Template error for index.md: Unterminated tag"},
          {page_path: "about.md", message: "Template error for about.md: Unterminated tag"},
          {page_path: "posts/hello.md", message: "Template error for posts/hello.md: Unterminated tag"},
        ]
        builder.test_report_render_failures(failures, verbose: false)
      ensure
        Hwaro::Logger.io = previous_io
      end
      output = buffer.to_s
      output.should contain("Render failed for 3 pages: Unterminated tag")
      output.should contain("  - index.md")
      output.should contain("  - about.md")
      output.should contain("  - posts/hello.md")
      output.should contain("--verbose")
      output.scan("Unterminated tag").size.should eq(1)
    end

    it "shows per-page detail under --verbose" do
      buffer = IO::Memory.new
      previous_io = Hwaro::Logger.io
      Hwaro::Logger.io = buffer
      begin
        builder = Hwaro::Core::Build::Builder.new
        failures = [
          {page_path: "index.md", message: "Template error for index.md: Unterminated tag"},
          {page_path: "about.md", message: "Template error for about.md: Unterminated tag"},
        ]
        builder.test_report_render_failures(failures, verbose: true)
      ensure
        Hwaro::Logger.io = previous_io
      end
      output = buffer.to_s
      output.scan("Parallel render failed for").size.should eq(2)
      output.should contain("index.md")
      output.should contain("about.md")
    end

    it "uses the single-page format when only one page fails with a given error" do
      buffer = IO::Memory.new
      previous_io = Hwaro::Logger.io
      Hwaro::Logger.io = buffer
      begin
        builder = Hwaro::Core::Build::Builder.new
        failures = [
          {page_path: "index.md", message: "Template error for index.md: something unique"},
        ]
        builder.test_report_render_failures(failures, verbose: false)
      ensure
        Hwaro::Logger.io = previous_io
      end
      output = buffer.to_s
      output.should contain("Render failed for index.md:")
      output.should_not contain("Run with --verbose")
    end

    it "truncates large affected-page lists with an '… and N more' tail" do
      buffer = IO::Memory.new
      previous_io = Hwaro::Logger.io
      Hwaro::Logger.io = buffer
      begin
        builder = Hwaro::Core::Build::Builder.new
        failures = (1..8).map do |i|
          {page_path: "posts/p#{i}.md", message: "Template error for posts/p#{i}.md: Unterminated tag"}
        end.to_a
        builder.test_report_render_failures(failures, verbose: false)
      ensure
        Hwaro::Logger.io = previous_io
      end
      output = buffer.to_s
      output.should contain("Render failed for 8 pages: Unterminated tag")
      output.should contain("… and 3 more")
    end
  end

  # Regression for https://github.com/hahwul/hwaro/issues/481
  # `get_section()` reads its data from the `__sections_by_key__` map that
  # `build_global_vars` builds. The section value used to be populated from
  # `Section#pages` (an unfilled array on the model) and dropped subsections
  # entirely, so every `get_section(...).pages_count` came back as 0.
  describe "#build_global_vars / get_section data" do
    it "fills section.pages from the live page list (not the empty Section#pages property)" do
      config = Hwaro::Models::Config.new
      config.base_url = "http://example.com"
      site = Hwaro::Models::Site.new(config)

      posts = Hwaro::Models::Section.new("posts/_index.md")
      posts.title = "Posts"
      posts.section = "posts"
      posts.url = "/posts/"
      posts.language = "en"

      hello = Hwaro::Models::Page.new("posts/hello.md")
      hello.title = "Hello"
      hello.section = "posts"
      hello.url = "/posts/hello/"
      hello.language = "en"

      second = Hwaro::Models::Page.new("posts/second.md")
      second.title = "Second"
      second.section = "posts"
      second.url = "/posts/second/"
      second.language = "en"

      # `_index.md` files become `Section` objects in `site.sections`;
      # only regular pages go into `site.pages`. `pages_for_section`
      # bucketing reads from `site.pages`, so adding the Section to
      # both lists would double-count.
      site.sections << posts
      site.pages << hello << second
      site.build_lookup_index

      builder = Hwaro::Core::Build::Builder.new
      vars = builder.test_build_global_vars(site)
      sections_by_key = vars["__sections_by_key__"].raw.as(Hash)
      posts_val = sections_by_key["posts"].raw.as(Hash)

      posts_val["pages_count"].raw.should eq(2)
      posts_val["pages"].raw.as(Array).size.should eq(2)
    end

    # Regression: the fallback for a section without `sort_by` must be "date"
    # (newest first) — the same default the paginator (paginator.cr), the
    # prev/next navigation (transform.cr), and the docs promise. It used to
    # be "title", so `get_section(...).pages` and `section.pages` on member
    # pages disagreed with the section template's own listing order.
    it "defaults section page order to date (newest first) when sort_by is unset" do
      config = Hwaro::Models::Config.new
      config.base_url = "http://example.com"
      site = Hwaro::Models::Site.new(config)

      posts = Hwaro::Models::Section.new("posts/_index.md")
      posts.title = "Posts"
      posts.section = "posts"
      posts.url = "/posts/"
      posts.language = "en"
      # No sort_by / reverse set — exercise the default.

      # Title order (Alpha, Zulu) is the REVERSE of date order (Zulu is
      # newer) so the title fallback and the date default can't coincide.
      older = Hwaro::Models::Page.new("posts/older.md")
      older.title = "Alpha"
      older.section = "posts"
      older.url = "/posts/older/"
      older.language = "en"
      older.date = Time.utc(2024, 1, 1)

      newer = Hwaro::Models::Page.new("posts/newer.md")
      newer.title = "Zulu"
      newer.section = "posts"
      newer.url = "/posts/newer/"
      newer.language = "en"
      newer.date = Time.utc(2024, 12, 1)

      site.sections << posts
      site.pages << older << newer
      site.build_lookup_index

      builder = Hwaro::Core::Build::Builder.new
      vars = builder.test_build_global_vars(site)
      sections_by_key = vars["__sections_by_key__"].raw.as(Hash)
      posts_val = sections_by_key["posts"].raw.as(Hash)

      titles = posts_val["pages"].raw.as(Array).map do |v|
        v.raw.as(Hash)["title"].to_s
      end
      titles.should eq(["Zulu", "Alpha"])
    end

    it "exposes subsections so {{ section.subsections }} works inside get_section()" do
      config = Hwaro::Models::Config.new
      config.base_url = "http://example.com"
      site = Hwaro::Models::Site.new(config)

      posts = Hwaro::Models::Section.new("posts/_index.md")
      posts.title = "Posts"
      posts.section = "posts"
      posts.url = "/posts/"
      posts.language = "en"

      cli_series = Hwaro::Models::Section.new("posts/cli-series/_index.md")
      cli_series.title = "CLI Series"
      cli_series.section = "posts/cli-series"
      cli_series.url = "/posts/cli-series/"
      cli_series.language = "en"

      posts.subsections << cli_series

      hello = Hwaro::Models::Page.new("posts/hello.md")
      hello.title = "Hello"
      hello.section = "posts"
      hello.url = "/posts/hello/"
      hello.language = "en"

      part1 = Hwaro::Models::Page.new("posts/cli-series/part1.md")
      part1.title = "Part 1"
      part1.section = "posts/cli-series"
      part1.url = "/posts/cli-series/part1/"
      part1.language = "en"

      site.sections << posts << cli_series
      site.pages << hello << part1
      site.build_lookup_index

      builder = Hwaro::Core::Build::Builder.new
      vars = builder.test_build_global_vars(site)
      sections_by_key = vars["__sections_by_key__"].raw.as(Hash)
      posts_val = sections_by_key["posts"].raw.as(Hash)

      subsections = posts_val["subsections"].raw.as(Array)
      subsections.size.should eq(1)
      first_sub = subsections.first.raw.as(Hash)
      first_sub["name"].raw.should eq("posts/cli-series")
      first_sub["pages_count"].raw.should eq(1)
    end
  end

  # `split_priority_pages` underpins `--fast-start` — it picks the page
  # subset that gets rendered before the dev server binds the port and
  # defers the rest to a background fiber. Wrong partitioning either
  # makes ready-time regress (too many pages priority) or makes obvious
  # URLs 404 until the background finishes (homepage in deferred).
  describe "#split_priority_pages" do
    it "returns everything as priority when total page count is <= count" do
      builder = Hwaro::Core::Build::Builder.new
      pages = [
        Hwaro::Models::Page.new("a.md"),
        Hwaro::Models::Page.new("b.md"),
      ]
      priority, deferred = builder.test_split_priority_pages(pages, 5)
      priority.should eq(pages)
      deferred.empty?.should be_true
    end

    it "always puts shallow section index pages in priority regardless of date" do
      builder = Hwaro::Core::Build::Builder.new
      home = Hwaro::Models::Section.new("_index.md")
      home.is_index = true
      home.section = ""
      home.date = nil

      section_idx = Hwaro::Models::Section.new("posts/_index.md")
      section_idx.is_index = true
      section_idx.section = "posts"
      section_idx.date = Time.utc(2000, 1, 1)

      recent = Hwaro::Models::Page.new("posts/new.md")
      recent.date = Time.utc(2026, 5, 1)

      old = Hwaro::Models::Page.new("posts/old.md")
      old.date = Time.utc(2024, 1, 1)

      undated = Hwaro::Models::Page.new("about.md")
      undated.date = nil

      pages = [home.as(Hwaro::Models::Page), section_idx.as(Hwaro::Models::Page), recent, old, undated]
      priority, deferred = builder.test_split_priority_pages(pages, 1)

      priority.includes?(home.as(Hwaro::Models::Page)).should be_true
      priority.includes?(section_idx.as(Hwaro::Models::Page)).should be_true
      # With count=1 only the most recent regular post is included
      priority.includes?(recent).should be_true
      priority.includes?(old).should be_false
      priority.includes?(undated).should be_false
      # Deferred must contain exactly the leftovers
      deferred.sort_by(&.path).should eq([old.as(Hwaro::Models::Page), undated.as(Hwaro::Models::Page)].sort_by(&.path))
    end

    it "defers deeply nested section indexes — only depth ≤ 1 are auto-priority" do
      builder = Hwaro::Core::Build::Builder.new
      home = Hwaro::Models::Section.new("_index.md")
      home.is_index = true
      home.section = ""

      top = Hwaro::Models::Section.new("archive/_index.md")
      top.is_index = true
      top.section = "archive"

      deep = Hwaro::Models::Section.new("archive/dev/crystal/_index.md")
      deep.is_index = true
      deep.section = "archive/dev/crystal"

      # Many regulars so depth-deep section can't sneak in via the recent-N fill.
      regulars = (1..30).map do |i|
        p = Hwaro::Models::Page.new("posts/p#{i}.md")
        p.date = Time.utc(2026, 5, i)
        p
      end

      pages = [home.as(Hwaro::Models::Page), top.as(Hwaro::Models::Page), deep.as(Hwaro::Models::Page)] + regulars.map(&.as(Hwaro::Models::Page))
      priority, deferred = builder.test_split_priority_pages(pages, 5)

      priority.includes?(home.as(Hwaro::Models::Page)).should be_true
      priority.includes?(top.as(Hwaro::Models::Page)).should be_true
      priority.includes?(deep.as(Hwaro::Models::Page)).should be_false
      deferred.includes?(deep.as(Hwaro::Models::Page)).should be_true
    end

    it "treats `index.md` page bundles as regulars, not auto-priority" do
      builder = Hwaro::Core::Build::Builder.new
      home = Hwaro::Models::Section.new("_index.md")
      home.is_index = true
      home.section = ""

      # A regular post that happens to use Hugo-style page-bundle layout —
      # `is_index` is true on the underlying Page but it's still just a
      # post, not a section listing. Must compete for the recent-N slot.
      old_bundle = Hwaro::Models::Page.new("posts/2020/old/index.md")
      old_bundle.is_index = true
      old_bundle.date = Time.utc(2020, 1, 1)

      new_post = Hwaro::Models::Page.new("posts/new.md")
      new_post.date = Time.utc(2026, 5, 1)

      pages = [home.as(Hwaro::Models::Page), old_bundle.as(Hwaro::Models::Page), new_post.as(Hwaro::Models::Page)]
      priority, deferred = builder.test_split_priority_pages(pages, 1)

      priority.includes?(home.as(Hwaro::Models::Page)).should be_true
      priority.includes?(new_post).should be_true
      priority.includes?(old_bundle.as(Hwaro::Models::Page)).should be_false
      deferred.includes?(old_bundle.as(Hwaro::Models::Page)).should be_true
    end

    it "sorts regular pages by date descending, nil-dated pages last" do
      builder = Hwaro::Core::Build::Builder.new
      a = Hwaro::Models::Page.new("a.md")
      a.date = Time.utc(2026, 5, 1)
      b = Hwaro::Models::Page.new("b.md")
      b.date = Time.utc(2024, 1, 1)
      c = Hwaro::Models::Page.new("c.md")
      c.date = nil
      d = Hwaro::Models::Page.new("d.md")
      d.date = Time.utc(2025, 6, 1)

      pages = [b, c, a, d] # input order intentionally scrambled
      priority, deferred = builder.test_split_priority_pages(pages, 2)
      # Top 2 by date desc: a (2026), d (2025)
      priority.includes?(a).should be_true
      priority.includes?(d).should be_true
      priority.size.should eq(2)
      # nil-dated falls into deferred ahead of dated b? No — both deferred
      deferred.includes?(b).should be_true
      deferred.includes?(c).should be_true
    end

    it "preserves the original input order in the priority list" do
      builder = Hwaro::Core::Build::Builder.new
      a = Hwaro::Models::Page.new("a.md")
      a.date = Time.utc(2026, 5, 1)
      b = Hwaro::Models::Section.new("b/_index.md")
      b.is_index = true
      b.section = "b"
      c = Hwaro::Models::Page.new("c.md")
      c.date = Time.utc(2024, 1, 1)

      pages = [a, b.as(Hwaro::Models::Page), c] # b is section index, a is most recent
      priority, _deferred = builder.test_split_priority_pages(pages, 1)
      # Priority should contain a and b, ordered as they appeared in input
      priority.should eq([a, b.as(Hwaro::Models::Page)])
    end

    it "handles an empty input gracefully" do
      builder = Hwaro::Core::Build::Builder.new
      priority, deferred = builder.test_split_priority_pages([] of Hwaro::Models::Page, 5)
      priority.empty?.should be_true
      deferred.empty?.should be_true
    end
  end
end

# `{{ pwa_tags }}` wires up the [pwa] outputs: manifest.json + sw.js are
# written by the PWA generator, but nothing referenced them — a page must
# link the manifest and register the service worker for the feature to do
# anything. The var resolves to "" while [pwa] is disabled so scaffold
# headers can include it unconditionally (same contract as math_tags).
describe "build_global_vars / pwa_tags" do
  it "is empty when [pwa] is disabled" do
    config = Hwaro::Models::Config.new
    site = Hwaro::Models::Site.new(config)
    site.build_lookup_index

    vars = Hwaro::Core::Build::Builder.new.test_build_global_vars(site)
    vars["pwa_tags"].raw.should eq("")
  end

  it "emits the manifest link, theme-color meta, and SW registration when enabled" do
    config = Hwaro::Models::Config.new
    config.pwa.enabled = true
    config.pwa.theme_color = "#123456"
    site = Hwaro::Models::Site.new(config)
    site.build_lookup_index

    tags = Hwaro::Core::Build::Builder.new.test_build_global_vars(site)["pwa_tags"].raw.as(String)
    tags.should contain(%(<link rel="manifest" href="/manifest.json">))
    tags.should contain(%(<meta name="theme-color" content="#123456">))
    tags.should contain(%(navigator.serviceWorker.register("/sw.js")))
  end

  it "prefixes manifest and sw.js with the base path on sub-path deploys" do
    config = Hwaro::Models::Config.new
    config.base_url = "https://user.github.io/repo"
    config.pwa.enabled = true
    site = Hwaro::Models::Site.new(config)
    site.build_lookup_index

    tags = Hwaro::Core::Build::Builder.new.test_build_global_vars(site)["pwa_tags"].raw.as(String)
    tags.should contain(%(href="/repo/manifest.json"))
    tags.should contain(%(register("/repo/sw.js")))
  end

  # `theme_color` is config-authored free text that lands inside an HTML
  # attribute. Unescaped, a quote in it closed the attribute early and the
  # rest of the value became markup in the `<head>` of every page — the
  # tag builders in `content/seo/tags.cr` all escape for this reason.
  it "escapes a theme-color that would otherwise break out of the attribute" do
    config = Hwaro::Models::Config.new
    config.pwa.enabled = true
    config.pwa.theme_color = %(#ff0000" onload="alert(1))
    site = Hwaro::Models::Site.new(config)
    site.build_lookup_index

    tags = Hwaro::Core::Build::Builder.new.test_build_global_vars(site)["pwa_tags"].raw.as(String)
    tags.should_not contain(%(onload="alert(1)"))
    tags.should contain(%(<meta name="theme-color" content="#ff0000&quot; onload=&quot;alert(1)">))
  end

  # The SW URL sits in a JS string inside an inline `<script>`, where HTML
  # entities are NOT decoded — escaping it as HTML would corrupt the URL,
  # so it is emitted as a JSON string literal instead.
  it "emits the service-worker URL as a JS string literal, not HTML-escaped" do
    config = Hwaro::Models::Config.new
    config.base_url = %(https://example.com/a"b)
    config.pwa.enabled = true
    site = Hwaro::Models::Site.new(config)
    site.build_lookup_index

    tags = Hwaro::Core::Build::Builder.new.test_build_global_vars(site)["pwa_tags"].raw.as(String)
    script = tags.lines.find!(&.includes?("serviceWorker"))
    script.should_not contain("&quot;")
    script.should contain(%(register("/a\\"b/sw.js")))
  end
end
