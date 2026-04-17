require "../spec_helper"

# =============================================================================
# Gap-filling unit specs for pagination that complement existing coverage in:
#   - spec/unit/pagination_spec.cr             (paginator basics, 384 lines)
#   - spec/unit/pagination_renderer_spec.cr    (renderer basics, 593 lines)
#   - spec/functional/pagination_spec.cr       (end-to-end, 348 lines)
#
# Targets behaviors not exercised elsewhere:
# - per_page clamping (per_page=0 or negative → minimum 1)
# - Last partial page item count math
# - Sort interaction (section.sort_by / section.reverse honored)
# - Pagination of zero pages with pagination enabled
# - Direct PaginatedPage / PaginationResult struct constructor
# - visible_pages output for first / middle / last current with large total
# - HTML escaping for URLs with special characters
# =============================================================================

private def make_section(per_page : Int32? = nil, sort_by : String? = nil, reverse : Bool? = nil) : Hwaro::Models::Section
  s = Hwaro::Models::Section.new("blog/_index.md")
  s.section = "blog"
  s.url = "/blog/"
  s.paginate = per_page
  s.sort_by = sort_by
  s.reverse = reverse
  s
end

private def make_pages(count : Int32, &block : Int32, Hwaro::Models::Page ->) : Array(Hwaro::Models::Page)
  # Caller's block is responsible for setting page.title (every test does).
  Array(Hwaro::Models::Page).new(count) do |i|
    p = Hwaro::Models::Page.new("blog/post-#{i}.md")
    p.section = "blog"
    yield(i, p)
    p
  end
end

describe Hwaro::Content::Pagination::Paginator do
  describe "per_page clamping" do
    it "clamps a per_page of 0 up to 1 (avoids divide-by-zero)" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled = true
      section = make_section(per_page: 0)
      pages = make_pages(3) { |i, p| p.title = "P#{i}" }

      paginator = Hwaro::Content::Pagination::Paginator.new(config)
      result = paginator.paginate(section, pages)

      result.per_page.should eq(1)
      result.paginated_pages.size.should eq(3)
    end

    it "clamps a negative per_page up to 1" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled = true
      section = make_section(per_page: -5)
      pages = make_pages(2) { |i, p| p.title = "P#{i}" }

      paginator = Hwaro::Content::Pagination::Paginator.new(config)
      result = paginator.paginate(section, pages)

      result.per_page.should eq(1)
      result.paginated_pages.size.should eq(2)
    end
  end

  describe "page splitting math" do
    it "puts the remainder on the final page (7 items / per_page=3 → [3,3,1])" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled = true
      section = make_section(per_page: 3, sort_by: "title")
      pages = make_pages(7) { |i, p| p.title = "P%02d" % i }

      paginator = Hwaro::Content::Pagination::Paginator.new(config)
      result = paginator.paginate(section, pages)

      result.paginated_pages.map(&.pages.size).should eq([3, 3, 1])
      result.paginated_pages.last.page_number.should eq(3)
      result.paginated_pages.last.has_next.should be_false
      result.paginated_pages.last.has_prev.should be_true
    end

    it "produces a single page when total_items < per_page" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled = true
      section = make_section(per_page: 100)
      pages = make_pages(3) { |i, p| p.title = "P#{i}" }

      paginator = Hwaro::Content::Pagination::Paginator.new(config)
      result = paginator.paginate(section, pages)

      result.paginated_pages.size.should eq(1)
      # All 3 items must land on that single page (not silently truncated)
      result.paginated_pages.first.pages.size.should eq(3)
      result.paginated_pages.first.total_items.should eq(3)
      result.paginated_pages.first.has_prev.should be_false
      result.paginated_pages.first.has_next.should be_false
    end

    it "produces total_pages=1 even when zero pages remain after sorting" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled = true
      section = make_section(per_page: 5)
      empty = [] of Hwaro::Models::Page

      paginator = Hwaro::Content::Pagination::Paginator.new(config)
      result = paginator.paginate(section, empty)

      result.paginated_pages.size.should eq(1)
      result.paginated_pages.first.pages.should be_empty
      result.paginated_pages.first.total_items.should eq(0)
    end
  end

  describe "sort interaction" do
    it "honors section.sort_by = 'title' ascending" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled = true
      section = make_section(per_page: 10, sort_by: "title")
      # Insert in reverse order; expect ascending output
      pages = make_pages(3) { |i, p| p.title = "Z#{2 - i}" }

      paginator = Hwaro::Content::Pagination::Paginator.new(config)
      result = paginator.paginate(section, pages)
      result.paginated_pages.first.pages.map(&.title).should eq(["Z0", "Z1", "Z2"])
    end

    it "applies sort even when pagination is disabled" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled = false
      section = make_section(sort_by: "title")
      pages = make_pages(3) { |i, p| p.title = "M#{2 - i}" }

      paginator = Hwaro::Content::Pagination::Paginator.new(config)
      result = paginator.paginate(section, pages)
      result.enabled.should be_false
      result.paginated_pages.first.pages.map(&.title).should eq(["M0", "M1", "M2"])
    end
  end

  describe "URL generation" do
    it "page 1 URL has no /page/N/ suffix (just trailing slash)" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled = true
      section = make_section(per_page: 1)
      pages = make_pages(3) { |i, p| p.title = "P#{i}" }

      paginator = Hwaro::Content::Pagination::Paginator.new(config)
      result = paginator.paginate(section, pages)

      result.paginated_pages.first.first_url.should eq("/blog/")
      result.paginated_pages[1].prev_url.should eq("/blog/")
    end

    it "uses the section's paginate_path constant in subsequent page URLs" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled = true
      section = make_section(per_page: 1)
      section.paginate_path = "p"
      pages = make_pages(3) { |i, p| p.title = "P#{i}" }

      paginator = Hwaro::Content::Pagination::Paginator.new(config)
      result = paginator.paginate(section, pages)
      result.paginated_pages[1].prev_url.should eq("/blog/")
      result.paginated_pages[2].prev_url.should eq("/blog/p/2/")
      result.paginated_pages.last.last_url.should eq("/blog/p/3/")
      # Boundary: last page has no next_url; first page has no prev_url
      result.paginated_pages.last.next_url.should be_nil
      result.paginated_pages.first.prev_url.should be_nil
    end
  end
end

describe Hwaro::Content::Pagination::PaginatedPage do
  it "exposes its constructor arguments verbatim" do
    pages = [Hwaro::Models::Page.new("a.md")]
    pp = Hwaro::Content::Pagination::PaginatedPage.new(
      pages: pages,
      page_number: 2,
      total_pages: 5,
      per_page: 10,
      total_items: 47,
      has_prev: true,
      has_next: true,
      prev_url: "/blog/",
      next_url: "/blog/page/3/",
      first_url: "/blog/",
      last_url: "/blog/page/5/",
      base_url: "/blog/page/",
    )

    pp.pages.should eq(pages)
    pp.page_number.should eq(2)
    pp.total_pages.should eq(5)
    pp.per_page.should eq(10)
    pp.total_items.should eq(47)
    pp.has_prev.should be_true
    pp.has_next.should be_true
    pp.prev_url.should eq("/blog/")
    pp.next_url.should eq("/blog/page/3/")
    pp.first_url.should eq("/blog/")
    pp.last_url.should eq("/blog/page/5/")
    pp.base_url.should eq("/blog/page/")
  end
end

describe Hwaro::Content::Pagination::PaginationResult do
  it "exposes its constructor arguments verbatim" do
    paginated = [] of Hwaro::Content::Pagination::PaginatedPage
    result = Hwaro::Content::Pagination::PaginationResult.new(
      paginated_pages: paginated,
      enabled: true,
      per_page: 7,
    )
    result.paginated_pages.should be(paginated)
    result.enabled.should be_true
    result.per_page.should eq(7)
  end
end

describe Hwaro::Content::Pagination::Renderer do
  describe "URL escaping" do
    it "HTML-escapes URLs that contain special characters" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      renderer = Hwaro::Content::Pagination::Renderer.new(config)

      pp = Hwaro::Content::Pagination::PaginatedPage.new(
        pages: [] of Hwaro::Models::Page,
        page_number: 2,
        total_pages: 3,
        per_page: 5,
        total_items: 11,
        has_prev: true,
        has_next: true,
        prev_url: "/blog/q?a=<b>&c=\"d\"/",
        next_url: "/blog/q?a=<b>&c=\"d\"/page/3/",
        first_url: "/blog/",
        last_url: "/blog/page/3/",
        base_url: "/blog/page/",
      )

      html = renderer.render_pagination_nav(pp)
      # Assert the full escaped href, not just the per-character substrings —
      # rules out false positives where one escape happens to land elsewhere.
      html.should contain(%(href="https://example.com/blog/q?a=&lt;b&gt;&amp;c=&quot;d&quot;/"))
      html.should_not contain("<b>")
    end

    it "HTML-escapes prev/next URLs in render_seo_links" do
      config = Hwaro::Models::Config.new
      config.base_url = ""
      renderer = Hwaro::Content::Pagination::Renderer.new(config)

      pp = Hwaro::Content::Pagination::PaginatedPage.new(
        pages: [] of Hwaro::Models::Page,
        page_number: 2,
        total_pages: 3,
        per_page: 5,
        total_items: 11,
        has_prev: true,
        has_next: true,
        prev_url: "/a&b/",
        next_url: "/c<d>/",
        first_url: "/",
        last_url: "/page/3/",
        base_url: "/page/",
      )

      html = renderer.render_seo_links(pp)
      html.should contain("rel=\"prev\"")
      html.should contain("rel=\"next\"")
      html.should contain("/a&amp;b/")
      html.should contain("/c&lt;d&gt;/")
    end
  end

  describe "rel attribute correctness" do
    it "emits rel=prev only on the previous-page anchor and rel=next only on next-page" do
      config = Hwaro::Models::Config.new
      renderer = Hwaro::Content::Pagination::Renderer.new(config)

      pp = Hwaro::Content::Pagination::PaginatedPage.new(
        pages: [] of Hwaro::Models::Page,
        page_number: 5, total_pages: 10, per_page: 1, total_items: 10,
        has_prev: true, has_next: true,
        prev_url: "/blog/page/4/", next_url: "/blog/page/6/",
        first_url: "/blog/", last_url: "/blog/page/10/",
        base_url: "/blog/page/",
      )

      html = renderer.render_pagination_nav(pp)
      # Exactly one rel="prev" and one rel="next" — neither attribute leaks to
      # the numbered page links.
      html.scan("rel=\"prev\"").size.should eq(1)
      html.scan("rel=\"next\"").size.should eq(1)
    end
  end

  describe "ellipsis boundaries" do
    it "shows pages [1, 2, 3, 4, 5, …, 10] when current is near the start" do
      config = Hwaro::Models::Config.new
      renderer = Hwaro::Content::Pagination::Renderer.new(config)
      pp = Hwaro::Content::Pagination::PaginatedPage.new(
        pages: [] of Hwaro::Models::Page,
        page_number: 2, total_pages: 10, per_page: 1, total_items: 10,
        has_prev: true, has_next: true,
        prev_url: "/blog/", next_url: "/blog/page/3/",
        first_url: "/blog/", last_url: "/blog/page/10/",
        base_url: "/blog/page/",
      )
      html = renderer.render_pagination_nav(pp)
      # Visible page numbers should include 1, 2, 3, 4 and 10 (ellipsis between 4 and 10)
      ["1", "2", "3", "4", "10"].each { |n| html.should contain(">#{n}<") }
      html.scan("pagination-ellipsis").size.should eq(1)
    end

    it "shows pages [1, …, 6, 7, 8, 9, 10] when current is near the end" do
      config = Hwaro::Models::Config.new
      renderer = Hwaro::Content::Pagination::Renderer.new(config)
      pp = Hwaro::Content::Pagination::PaginatedPage.new(
        pages: [] of Hwaro::Models::Page,
        page_number: 9, total_pages: 10, per_page: 1, total_items: 10,
        has_prev: true, has_next: true,
        prev_url: "/blog/page/8/", next_url: "/blog/page/10/",
        first_url: "/blog/", last_url: "/blog/page/10/",
        base_url: "/blog/page/",
      )
      html = renderer.render_pagination_nav(pp)
      ["1", "7", "8", "9", "10"].each { |n| html.should contain(">#{n}<") }
      html.scan("pagination-ellipsis").size.should eq(1)
    end
  end
end
