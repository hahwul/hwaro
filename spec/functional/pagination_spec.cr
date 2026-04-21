require "./support/build_helper"

# =============================================================================
# Pagination functional tests
#
# Verifies paginator variables, navigation links, per-section pagination
# overrides, and edge cases.
# =============================================================================

PAGINATION_CONFIG = <<-TOML
  title = "Test"
  base_url = "http://localhost"

  [pagination]
  enabled = true
  per_page = 2
  TOML

describe "Pagination: Paginator variables" do
  it "exposes paginator.current_index on each page" do
    build_site(
      PAGINATION_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/p1.md"     => "---\ntitle: P1\n---\nP1",
        "blog/p2.md"     => "---\ntitle: P2\n---\nP2",
        "blog/p3.md"     => "---\ntitle: P3\n---\nP3",
        "blog/p4.md"     => "---\ntitle: P4\n---\nP4",
        "blog/p5.md"     => "---\ntitle: P5\n---\nP5",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "PAGE={{ paginator.current_index }}|{{ section_list }}{{ pagination }}",
      },
    ) do
      page1 = File.read("public/blog/index.html")
      page1.should contain("PAGE=1")

      page2 = File.read("public/blog/page/2/index.html")
      page2.should contain("PAGE=2")

      page3 = File.read("public/blog/page/3/index.html")
      page3.should contain("PAGE=3")
    end
  end
end

describe "Pagination: Navigation links" do
  it "generates pagination HTML with prev/next links" do
    build_site(
      PAGINATION_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/p1.md"     => "---\ntitle: P1\n---\nP1",
        "blog/p2.md"     => "---\ntitle: P2\n---\nP2",
        "blog/p3.md"     => "---\ntitle: P3\n---\nP3",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "PAGE={{ paginator.current_index }}|{{ section_list }}{{ pagination }}",
      },
    ) do
      # First page: prev is disabled, has next link
      page1 = File.read("public/blog/index.html")
      page1.should contain("PAGE=1")
      page1.should contain("pagination-prev pagination-disabled")
      page1.should contain("rel=\"next\"")

      # Last page: has prev link, next is disabled
      page2 = File.read("public/blog/page/2/index.html")
      page2.should contain("PAGE=2")
      page2.should contain("pagination-next pagination-disabled")
    end
  end
end

describe "Pagination: Page content distribution" do
  it "distributes correct number of items per page" do
    build_site(
      PAGINATION_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\nsort_by: title\n---\n",
        "blog/a.md"      => "---\ntitle: AAA\n---\nA",
        "blog/b.md"      => "---\ntitle: BBB\n---\nB",
        "blog/c.md"      => "---\ntitle: CCC\n---\nC",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "COUNT={{ paginator.pages | length }}|{{ section_list }}{{ pagination }}",
      },
    ) do
      # First page: 2 items
      page1 = File.read("public/blog/index.html")
      page1.should contain("COUNT=2")

      # Second page: 1 item
      page2 = File.read("public/blog/page/2/index.html")
      page2.should contain("COUNT=1")
    end
  end
end

describe "Pagination: Single page (no pagination needed)" do
  it "does not create extra pages when all items fit on one page" do
    build_site(
      PAGINATION_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/p1.md"     => "---\ntitle: P1\n---\nP1",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "TOTAL={{ paginator.total_pages }}|{{ section_list }}{{ pagination }}",
      },
    ) do
      page1 = File.read("public/blog/index.html")
      page1.should contain("TOTAL=1")
      File.exists?("public/blog/page/2/index.html").should be_false
    end
  end
end

describe "Pagination: Prev/Next URLs in pagination HTML" do
  it "includes correct page links in pagination navigation" do
    build_site(
      PAGINATION_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/p1.md"     => "---\ntitle: P1\n---\nP1",
        "blog/p2.md"     => "---\ntitle: P2\n---\nP2",
        "blog/p3.md"     => "---\ntitle: P3\n---\nP3",
        "blog/p4.md"     => "---\ntitle: P4\n---\nP4",
        "blog/p5.md"     => "---\ntitle: P5\n---\nP5",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ section_list }}{{ pagination }}",
      },
    ) do
      # Page 1 links to page 2
      page1 = File.read("public/blog/index.html")
      page1.should contain("href=\"http://localhost/blog/page/2/\"")

      # Page 2 links to page 3
      page2 = File.read("public/blog/page/2/index.html")
      page2.should contain("href=\"http://localhost/blog/page/3/\"")

      # All three pages should exist
      File.exists?("public/blog/index.html").should be_true
      File.exists?("public/blog/page/2/index.html").should be_true
      File.exists?("public/blog/page/3/index.html").should be_true
    end
  end
end

describe "Pagination: Large per_page value" do
  it "does not create extra pages when per_page exceeds items" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [pagination]
      enabled = true
      per_page = 100
      TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/p1.md"     => "---\ntitle: P1\n---\nP1",
        "blog/p2.md"     => "---\ntitle: P2\n---\nP2",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ section_list }}{{ pagination }}",
      },
    ) do
      html = File.read("public/blog/index.html")
      html.should contain("P1")
      html.should contain("P2")
      # No pagination-next link since all items fit on one page
      File.exists?("public/blog/page/2/index.html").should be_false
    end
  end
end

describe "Pagination: pagination_obj exposes individual variables" do
  it "exposes current_page, total_pages, has_previous, has_next on each page" do
    build_site(
      PAGINATION_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/p1.md"     => "---\ntitle: P1\n---\nP1",
        "blog/p2.md"     => "---\ntitle: P2\n---\nP2",
        "blog/p3.md"     => "---\ntitle: P3\n---\nP3",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "CP={{ pagination_obj.current_page }}|TP={{ pagination_obj.total_pages }}|HP={{ pagination_obj.has_previous }}|HN={{ pagination_obj.has_next }}",
      },
    ) do
      page1 = File.read("public/blog/index.html")
      page1.should contain("CP=1")
      page1.should contain("TP=2")
      page1.should contain("HP=false")
      page1.should contain("HN=true")

      page2 = File.read("public/blog/page/2/index.html")
      page2.should contain("CP=2")
      page2.should contain("TP=2")
      page2.should contain("HP=true")
      page2.should contain("HN=false")
    end
  end

  it "exposes previous_url and next_url" do
    build_site(
      PAGINATION_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/p1.md"     => "---\ntitle: P1\n---\nP1",
        "blog/p2.md"     => "---\ntitle: P2\n---\nP2",
        "blog/p3.md"     => "---\ntitle: P3\n---\nP3",
        "blog/p4.md"     => "---\ntitle: P4\n---\nP4",
        "blog/p5.md"     => "---\ntitle: P5\n---\nP5",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "PREV={{ pagination_obj.previous_url }}|NEXT={{ pagination_obj.next_url }}",
      },
    ) do
      # Page 1: no previous, next is page 2
      page1 = File.read("public/blog/index.html")
      page1.should contain("PREV=|NEXT=/blog/page/2/")

      # Page 2: previous is page 1, next is page 3
      page2 = File.read("public/blog/page/2/index.html")
      page2.should contain("PREV=/blog/|NEXT=/blog/page/3/")

      # Page 3: previous is page 2, no next
      page3 = File.read("public/blog/page/3/index.html")
      page3.should contain("PREV=/blog/page/2/|NEXT=")
    end
  end

  it "exposes per_page and total_items" do
    build_site(
      PAGINATION_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/p1.md"     => "---\ntitle: P1\n---\nP1",
        "blog/p2.md"     => "---\ntitle: P2\n---\nP2",
        "blog/p3.md"     => "---\ntitle: P3\n---\nP3",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "PP={{ pagination_obj.per_page }}|TI={{ pagination_obj.total_items }}",
      },
    ) do
      page1 = File.read("public/blog/index.html")
      page1.should contain("PP=2")
      page1.should contain("TI=3")
    end
  end

  it "renders empty when pagination is disabled" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [pagination]
      enabled = false
      per_page = 1
      TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/p1.md"     => "---\ntitle: P1\n---\nP1",
        "blog/p2.md"     => "---\ntitle: P2\n---\nP2",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "CP={{ pagination_obj.current_page }}|TP={{ pagination_obj.total_pages }}",
      },
    ) do
      # pagination_obj still available with single-page defaults when disabled
      html = File.read("public/blog/index.html")
      html.should contain("CP=1|TP=1")
    end
  end

  it "exposes pagination_obj.html with pre-rendered HTML" do
    build_site(
      PAGINATION_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/p1.md"     => "---\ntitle: P1\n---\nP1",
        "blog/p2.md"     => "---\ntitle: P2\n---\nP2",
        "blog/p3.md"     => "---\ntitle: P3\n---\nP3",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ pagination_obj.html }}",
      },
    ) do
      page1 = File.read("public/blog/index.html")
      page1.should contain("pagination")
      page1.should contain("pagination-prev")
    end
  end
end

describe "Pagination: Disabled pagination" do
  it "does not paginate when pagination is disabled" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [pagination]
      enabled = false
      per_page = 1
      TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/p1.md"     => "---\ntitle: P1\n---\nP1",
        "blog/p2.md"     => "---\ntitle: P2\n---\nP2",
        "blog/p3.md"     => "---\ntitle: P3\n---\nP3",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ section_list }}",
      },
    ) do
      # All items on one page
      html = File.read("public/blog/index.html")
      html.should contain("P1")
      html.should contain("P2")
      html.should contain("P3")
      File.exists?("public/blog/page/2/index.html").should be_false
    end
  end
end
