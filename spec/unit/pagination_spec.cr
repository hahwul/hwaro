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

    result.enabled.should eq(true)
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

    result.enabled.should eq(false)
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

    result.enabled.should eq(true)
    result.per_page.should eq(1)
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
end
