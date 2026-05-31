require "./support/build_helper"

# =============================================================================
# Series navigation functional test.
#
# Verifies the scaffold's series-nav pattern — deriving prev/next from
# `page.series_pages` (ordered by series_weight) via the 1-based
# `page.series_index` — produces correct in-series ordering against the real
# build engine (and is NOT ordered by the section's flat date neighbours).
# =============================================================================

SERIES_CONFIG = <<-TOML
  title = "Test"
  base_url = "http://localhost"

  [series]
  enabled = true
  TOML

# Minimal post template using the same series-nav logic the blog scaffold ships.
SERIES_POST_TEMPLATE = <<-HTML
  <article>
  {% if page.series %}
  <nav class="series-nav">
    {% if page.series_index > 1 %}
    <a class="series-prev" href="{{ page.series_pages[page.series_index - 2].url }}">{{ page.series_pages[page.series_index - 2].title }}</a>
    {% endif %}
    {% if page.series_index < (page.series_pages | length) %}
    <a class="series-next" href="{{ page.series_pages[page.series_index].url }}">{{ page.series_pages[page.series_index].title }}</a>
    {% endif %}
  </nav>
  {% endif %}
  {{ content }}
  </article>
  HTML

describe "Series navigation" do
  it "orders prev/next by series_weight and omits prev on the first / next on the last" do
    build_site(
      SERIES_CONFIG,
      content_files: {
        "posts/_index.md" => "+++\ntitle = \"Posts\"\npage_template = \"post\"\n+++\n",
        # Deliberately give later chapters EARLIER dates so date-ordering would
        # disagree with series_weight — the nav must follow series_weight.
        "posts/c1.md"    => "+++\ntitle = \"Chapter 1\"\ndate = \"2026-01-03\"\nseries = \"Guide\"\nseries_weight = 1\n+++\nC1",
        "posts/c2.md"    => "+++\ntitle = \"Chapter 2\"\ndate = \"2026-01-02\"\nseries = \"Guide\"\nseries_weight = 2\n+++\nC2",
        "posts/c3.md"    => "+++\ntitle = \"Chapter 3\"\ndate = \"2026-01-01\"\nseries = \"Guide\"\nseries_weight = 3\n+++\nC3",
        "posts/loner.md" => "+++\ntitle = \"Loner\"\ndate = \"2026-01-09\"\n+++\nNot in a series",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ content }}",
        "post.html"    => SERIES_POST_TEMPLATE,
      },
    ) do
      c1 = File.read("public/posts/c1/index.html")
      c2 = File.read("public/posts/c2/index.html")
      c3 = File.read("public/posts/c3/index.html")

      # Chapter 1: no prev, next -> Chapter 2
      c1.should_not contain("series-prev")
      c1.should contain(%(series-next" href="/posts/c2/">Chapter 2))

      # Chapter 2: prev -> Chapter 1, next -> Chapter 3
      c2.should contain(%(series-prev" href="/posts/c1/">Chapter 1))
      c2.should contain(%(series-next" href="/posts/c3/">Chapter 3))

      # Chapter 3: prev -> Chapter 2, no next
      c3.should contain(%(series-prev" href="/posts/c2/">Chapter 2))
      c3.should_not contain("series-next")

      # A non-series post never renders series nav (and must build fine despite
      # an empty series_pages — no out-of-bounds indexing).
      File.read("public/posts/loner/index.html").should_not contain("series-nav")
    end
  end
end
