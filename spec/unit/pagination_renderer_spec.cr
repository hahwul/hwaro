require "../spec_helper"

describe Hwaro::Content::Pagination::Renderer do
  describe "#render_section_list" do
    it "generates li/a elements for each page" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page1 = Hwaro::Models::Page.new("wiki/1.md")
      page1.title = "First Page"
      page1.url = "/wiki/first/"

      page2 = Hwaro::Models::Page.new("wiki/2.md")
      page2.title = "Second Page"
      page2.url = "/wiki/second/"

      paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
        pages: [page1, page2],
        page_number: 1,
        total_pages: 1,
        per_page: 10,
        total_items: 2,
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

      html.should contain("<li><a href=\"https://example.com/wiki/first/\">First Page</a></li>")
      html.should contain("<li><a href=\"https://example.com/wiki/second/\">Second Page</a></li>")
    end

    it "HTML-escapes title and url" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Title with <script> & \"quotes\""
      page.url = "/path?a=1&b=2"

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
        first_url: "/",
        last_url: "/",
        base_url: "/page/"
      )

      renderer = Hwaro::Content::Pagination::Renderer.new(config)
      html = renderer.render_section_list(paginated_page)

      html.should contain("&lt;script&gt;")
      html.should contain("&amp;")
      html.should_not contain("<script>")
    end

    it "returns empty string for empty pages array" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
        pages: [] of Hwaro::Models::Page,
        page_number: 1,
        total_pages: 1,
        per_page: 10,
        total_items: 0,
        has_prev: false,
        has_next: false,
        prev_url: nil,
        next_url: nil,
        first_url: "/",
        last_url: "/",
        base_url: "/page/"
      )

      renderer = Hwaro::Content::Pagination::Renderer.new(config)
      html = renderer.render_section_list(paginated_page)

      html.should eq("")
    end
  end

  describe "#render_pagination_nav" do
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

    it "on first page: prev is disabled, next is active with rel=next" do
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

      html.should contain("pagination-prev pagination-disabled")
      html.should contain("<span>Prev</span>")
      html.should contain("rel=\"next\"")
      html.should contain("pagination-next")
      html.should_not contain("pagination-next pagination-disabled")
    end

    it "on first page: page 1 uses first_url" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
        pages: [] of Hwaro::Models::Page,
        page_number: 1,
        total_pages: 2,
        per_page: 10,
        total_items: 15,
        has_prev: false,
        has_next: true,
        prev_url: nil,
        next_url: "/wiki/page/2/",
        first_url: "/wiki/",
        last_url: "/wiki/page/2/",
        base_url: "/wiki/page/"
      )

      renderer = Hwaro::Content::Pagination::Renderer.new(config)
      html = renderer.render_pagination_nav(paginated_page)

      html.should contain("https://example.com/wiki/")
    end

    it "on middle page: prev and next are both active" do
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

      # Both prev and next should be active links (not disabled spans)
      html.should contain("pagination-prev\"><a href=")
      html.should contain("rel=\"prev\"")
      html.should contain("pagination-next\"><a href=")
      html.should contain("rel=\"next\"")
      # No disabled class on prev or next
      lines = html.split("\n")
      prev_line = lines.find { |l| l.includes?("pagination-prev") }
      prev_line.should_not be_nil
      prev_line.not_nil!.should_not contain("pagination-disabled")

      next_line = lines.find { |l| l.includes?("pagination-next") }
      next_line.should_not be_nil
      next_line.not_nil!.should_not contain("pagination-disabled")
    end

    it "on middle page: current page is highlighted with span, others are links" do
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

      # Page 2 (current) should be a span
      html.should contain("pagination-current\"><span>2</span>")
      # Pages 1 and 3 should be links
      html.should contain("pagination-page\"><a href=")
    end

    it "on last page: next is disabled, prev is active" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
        pages: [] of Hwaro::Models::Page,
        page_number: 3,
        total_pages: 3,
        per_page: 10,
        total_items: 25,
        has_prev: true,
        has_next: false,
        prev_url: "/wiki/page/2/",
        next_url: nil,
        first_url: "/wiki/",
        last_url: "/wiki/page/3/",
        base_url: "/wiki/page/"
      )

      renderer = Hwaro::Content::Pagination::Renderer.new(config)
      html = renderer.render_pagination_nav(paginated_page)

      # Next should be disabled
      html.should contain("pagination-next pagination-disabled")
      html.should contain("<span>Next</span>")
      # Prev should be active
      html.should contain("pagination-prev\"><a href=")
      html.should contain("rel=\"prev\"")
    end

    it "generates page number links using base_url for page 2+" do
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

      # Page 2 and 3 should use base_url pattern
      html.should contain("https://example.com/wiki/page/2/")
      html.should contain("https://example.com/wiki/page/3/")
    end
  end

  describe "#render_paginated_section" do
    it "combines section list and pagination nav" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("wiki/1.md")
      page.title = "Test"
      page.url = "/wiki/1/"

      paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
        pages: [page],
        page_number: 1,
        total_pages: 2,
        per_page: 1,
        total_items: 2,
        has_prev: false,
        has_next: true,
        prev_url: nil,
        next_url: "/wiki/page/2/",
        first_url: "/wiki/",
        last_url: "/wiki/page/2/",
        base_url: "/wiki/page/"
      )

      renderer = Hwaro::Content::Pagination::Renderer.new(config)
      html = renderer.render_paginated_section(paginated_page)

      # Should have both section list and nav
      html.should contain("<li>")
      html.should contain("<nav class=\"pagination\"")
    end

    it "only shows section list for single page (no nav)" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("wiki/1.md")
      page.title = "Test"
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
      html = renderer.render_paginated_section(paginated_page)

      html.should contain("<li>")
      html.should_not contain("<nav")
    end
  end
end
