require "../spec_helper"

describe Hwaro::Content::Pagination::Paginator do
  it "creates a paginator with config" do
    config = Hwaro::Models::Config.new
    paginator = Hwaro::Content::Pagination::Paginator.new(config)
    paginator.should_not be_nil
  end

  it "paginates pages when enabled" do
    config = Hwaro::Models::Config.new
    config.pagination.enabled = true
    config.pagination.per_page = 2

    section = Hwaro::Models::Section.new("wiki/index.md")
    section.section = "wiki"

    pages = [
      Hwaro::Models::Page.new("wiki/1.md"),
      Hwaro::Models::Page.new("wiki/2.md"),
      Hwaro::Models::Page.new("wiki/3.md"),
    ]
    pages.each { |p| p.section = "wiki"; p.title = p.path }

    paginator = Hwaro::Content::Pagination::Paginator.new(config)
    result = paginator.paginate(section, pages)

    result.enabled.should be_true
    result.per_page.should eq(2)
    result.paginated_pages.size.should eq(2)
    result.paginated_pages[0].page_number.should eq(1)
    result.paginated_pages[0].pages.size.should eq(2)
    result.paginated_pages[1].page_number.should eq(2)
    result.paginated_pages[1].pages.size.should eq(1)
  end

  it "returns single page when pagination is disabled" do
    config = Hwaro::Models::Config.new
    config.pagination.enabled = false

    section = Hwaro::Models::Section.new("wiki/index.md")
    section.section = "wiki"

    pages = [
      Hwaro::Models::Page.new("wiki/1.md"),
      Hwaro::Models::Page.new("wiki/2.md"),
    ]
    pages.each { |p| p.section = "wiki"; p.title = p.path }

    paginator = Hwaro::Content::Pagination::Paginator.new(config)
    result = paginator.paginate(section, pages)

    result.enabled.should be_false
    result.paginated_pages.size.should eq(1)
    result.paginated_pages[0].pages.size.should eq(2)
  end

  it "respects section-level pagination override" do
    config = Hwaro::Models::Config.new
    config.pagination.enabled = false # Globally disabled
    config.pagination.per_page = 10

    section = Hwaro::Models::Section.new("wiki/index.md")
    section.section = "wiki"
    section.pagination_enabled = true # Section-level override
    section.paginate = 1              # Section-level per_page

    pages = [
      Hwaro::Models::Page.new("wiki/1.md"),
      Hwaro::Models::Page.new("wiki/2.md"),
    ]
    pages.each { |p| p.section = "wiki"; p.title = p.path }

    paginator = Hwaro::Content::Pagination::Paginator.new(config)
    result = paginator.paginate(section, pages)

    result.enabled.should be_true
    result.per_page.should eq(1)
    result.paginated_pages.size.should eq(2)
  end

  it "generates correct page URLs" do
    config = Hwaro::Models::Config.new
    config.pagination.enabled = true
    config.pagination.per_page = 1

    section = Hwaro::Models::Section.new("blog/index.md")
    section.section = "blog"
    section.url = "/blog/"

    pages = [
      Hwaro::Models::Page.new("blog/1.md"),
      Hwaro::Models::Page.new("blog/2.md"),
      Hwaro::Models::Page.new("blog/3.md"),
    ]
    pages.each { |p| p.section = "blog"; p.title = p.path }

    paginator = Hwaro::Content::Pagination::Paginator.new(config)
    result = paginator.paginate(section, pages)

    # First page URL should be base URL (no /page/1/)
    result.paginated_pages[0].first_url.should eq("/blog/")
    # Second page should have /page/2/
    result.paginated_pages[1].prev_url.should eq("/blog/")
    result.paginated_pages[1].next_url.should eq("/blog/page/3/")
    # Last page
    result.paginated_pages[2].has_next.should be_false
    result.paginated_pages[2].next_url.should be_nil
  end

  it "uses custom paginate_path from section" do
    config = Hwaro::Models::Config.new
    config.pagination.enabled = true
    config.pagination.per_page = 1

    section = Hwaro::Models::Section.new("blog/index.md")
    section.section = "blog"
    section.url = "/blog/"
    section.paginate_path = "p"

    pages = [
      Hwaro::Models::Page.new("blog/1.md"),
      Hwaro::Models::Page.new("blog/2.md"),
    ]
    pages.each { |p| p.section = "blog"; p.title = p.path }

    paginator = Hwaro::Content::Pagination::Paginator.new(config)
    result = paginator.paginate(section, pages)

    result.paginated_pages[1].prev_url.should eq("/blog/")
    result.paginated_pages[0].last_url.should eq("/blog/p/2/")
    result.paginated_pages[0].base_url.should contain("/p/")
  end

  it "handles empty page list" do
    config = Hwaro::Models::Config.new
    config.pagination.enabled = true
    config.pagination.per_page = 10

    section = Hwaro::Models::Section.new("empty/index.md")
    section.section = "empty"
    section.url = "/empty/"

    paginator = Hwaro::Content::Pagination::Paginator.new(config)
    result = paginator.paginate(section, [] of Hwaro::Models::Page)

    result.enabled.should be_true
    result.paginated_pages.size.should eq(1) # At least 1 page even if empty
    result.paginated_pages[0].pages.should be_empty
    result.paginated_pages[0].total_items.should eq(0)
  end

  it "sets correct has_prev/has_next on boundary pages" do
    config = Hwaro::Models::Config.new
    config.pagination.enabled = true
    config.pagination.per_page = 2

    section = Hwaro::Models::Section.new("blog/index.md")
    section.section = "blog"
    section.url = "/blog/"

    pages = (1..5).map do |i|
      p = Hwaro::Models::Page.new("blog/#{i}.md")
      p.section = "blog"
      p.title = "Page #{i}"
      p
    end

    paginator = Hwaro::Content::Pagination::Paginator.new(config)
    result = paginator.paginate(section, pages)

    # First page
    result.paginated_pages[0].has_prev.should be_false
    result.paginated_pages[0].has_next.should be_true
    result.paginated_pages[0].prev_url.should be_nil

    # Middle page
    result.paginated_pages[1].has_prev.should be_true
    result.paginated_pages[1].has_next.should be_true

    # Last page
    result.paginated_pages[2].has_prev.should be_true
    result.paginated_pages[2].has_next.should be_false
    result.paginated_pages[2].next_url.should be_nil
    result.paginated_pages[2].pages.size.should eq(1) # 5 items, 2 per page = last page has 1
  end

  it "enables pagination when section has paginate set even if global disabled" do
    config = Hwaro::Models::Config.new
    config.pagination.enabled = false

    section = Hwaro::Models::Section.new("wiki/index.md")
    section.section = "wiki"
    section.paginate = 5 # Implicitly enables pagination

    pages = (1..6).map do |i|
      p = Hwaro::Models::Page.new("wiki/#{i}.md")
      p.section = "wiki"
      p.title = "Page #{i}"
      p
    end

    paginator = Hwaro::Content::Pagination::Paginator.new(config)
    result = paginator.paginate(section, pages)

    result.enabled.should be_true
    result.per_page.should eq(5)
    result.paginated_pages.size.should eq(2)
  end
end

describe Hwaro::Content::Pagination::Renderer do
  it "renders section list" do
    config = Hwaro::Models::Config.new
    config.base_url = "https://example.com"

    page = Hwaro::Models::Page.new("wiki/1.md")
    page.title = "Test Page"
    page.url = "/wiki/1/"

    paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
      pages: [page],
      page_number: 1,
      total_pages: 1,
      per_page: 10,
      total_items: 1,
      has_prev: false,
      has_next: false,
      prev_url: nil,
      next_url: nil,
      first_url: "/wiki/",
      last_url: "/wiki/",
      base_url: "/wiki/page/"
    )

    renderer = Hwaro::Content::Pagination::Renderer.new(config)
    html = renderer.render_section_list(paginated_page)

    html.should contain("<li>")
    html.should contain("<a href=\"https://example.com/wiki/1/\">Test Page</a>")
  end

  it "renders pagination nav when multiple pages" do
    config = Hwaro::Models::Config.new
    config.base_url = "https://example.com"

    paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
      pages: [] of Hwaro::Models::Page,
      page_number: 1,
      total_pages: 3,
      per_page: 10,
      total_items: 25,
      has_prev: false,
      has_next: true,
      prev_url: nil,
      next_url: "/wiki/page/2/",
      first_url: "/wiki/",
      last_url: "/wiki/page/3/",
      base_url: "/wiki/page/"
    )

    renderer = Hwaro::Content::Pagination::Renderer.new(config)
    html = renderer.render_pagination_nav(paginated_page)

    html.should contain("<nav class=\"pagination\"")
    html.should contain("Next")
    html.should contain("pagination-disabled") # Previous is disabled on page 1
  end

  it "returns empty string for single page" do
    config = Hwaro::Models::Config.new

    paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
      pages: [] of Hwaro::Models::Page,
      page_number: 1,
      total_pages: 1,
      per_page: 10,
      total_items: 5,
      has_prev: false,
      has_next: false,
      prev_url: nil,
      next_url: nil,
      first_url: "/wiki/",
      last_url: "/wiki/",
      base_url: "/wiki/page/"
    )

    renderer = Hwaro::Content::Pagination::Renderer.new(config)
    html = renderer.render_pagination_nav(paginated_page)

    html.should eq("")
  end

  it "renders middle page nav with both prev and next active" do
    config = Hwaro::Models::Config.new
    config.base_url = "https://example.com"

    paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
      pages: [] of Hwaro::Models::Page,
      page_number: 2,
      total_pages: 3,
      per_page: 10,
      total_items: 25,
      has_prev: true,
      has_next: true,
      prev_url: "/wiki/",
      next_url: "/wiki/page/3/",
      first_url: "/wiki/",
      last_url: "/wiki/page/3/",
      base_url: "/wiki/page/"
    )

    renderer = Hwaro::Content::Pagination::Renderer.new(config)
    html = renderer.render_pagination_nav(paginated_page)

    # Both prev and next should be links, not disabled
    html.should contain("rel=\"prev\"")
    html.should contain("rel=\"next\"")
    # No pagination-disabled on prev or next lines
    html.split("\n").each do |line|
      if line.includes?("pagination-prev")
        line.should_not contain("pagination-disabled")
      end
      if line.includes?("pagination-next")
        line.should_not contain("pagination-disabled")
      end
    end
  end

  it "uses first_url for page 1 and /page/N/ for page 2+" do
    config = Hwaro::Models::Config.new
    config.base_url = "https://example.com"

    paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
      pages: [] of Hwaro::Models::Page,
      page_number: 2,
      total_pages: 3,
      per_page: 10,
      total_items: 25,
      has_prev: true,
      has_next: true,
      prev_url: "/wiki/",
      next_url: "/wiki/page/3/",
      first_url: "/wiki/",
      last_url: "/wiki/page/3/",
      base_url: "/wiki/page/"
    )

    renderer = Hwaro::Content::Pagination::Renderer.new(config)
    html = renderer.render_pagination_nav(paginated_page)

    # Page 1 link should use first_url
    html.should contain("https://example.com/wiki/\">1</a>")
    # Page 2 and 3 use base_url pattern
    html.should contain("https://example.com/wiki/page/3/")
  end

  it "has exactly one pagination-current element" do
    config = Hwaro::Models::Config.new
    config.base_url = "https://example.com"

    paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
      pages: [] of Hwaro::Models::Page,
      page_number: 2,
      total_pages: 4,
      per_page: 10,
      total_items: 35,
      has_prev: true,
      has_next: true,
      prev_url: "/wiki/",
      next_url: "/wiki/page/3/",
      first_url: "/wiki/",
      last_url: "/wiki/page/4/",
      base_url: "/wiki/page/"
    )

    renderer = Hwaro::Content::Pagination::Renderer.new(config)
    html = renderer.render_pagination_nav(paginated_page)

    # Count occurrences of pagination-current
    count = html.scan(/pagination-current/).size
    count.should eq(1)
  end
end
