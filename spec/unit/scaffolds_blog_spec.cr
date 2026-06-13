require "../spec_helper"
require "../../src/services/scaffolds/blog"

describe Hwaro::Services::Scaffolds::Blog do
  describe "#content_files" do
    it "generates content with taxonomies by default" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      files = scaffold.content_files(skip_taxonomies: false)

      # Check index.md
      files["index.md"].should contain("tags = [\"home\"]")
      files["index.md"].should contain("Browse posts by [Tags](/tags/), [Categories](/categories/), or [Authors](/authors/).")
      files["index.md"].should contain("[Tags](/tags/)")

      # Check about.md
      files["about.md"].should contain("tags = [\"about\"]")
      files["about.md"].should contain("categories = [\"pages\"]")

      # Check posts
      files["posts/hello-world.md"].should contain("tags = [\"introduction\", \"hello\"]")
      files["posts/hello-world.md"].should contain("categories = [\"general\"]")
      files["posts/hello-world.md"].should contain("authors = [\"admin\"]")
      files["posts/hello-world.md"].should match(/date = "\d{4}-\d{2}-\d{2}"/)
    end

    it "generates content without taxonomies when requested" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      files = scaffold.content_files(skip_taxonomies: true)

      # Check index.md
      files["index.md"].should_not contain("tags =")
      files["index.md"].should contain("A blog powered by [Hwaro](https://github.com/hahwul/hwaro) — a fast, lightweight static site generator.")
      files["index.md"].should_not contain("Browse posts by")
      files["index.md"].should_not contain("[Tags](/tags/)")

      # Check about.md
      files["about.md"].should_not contain("tags =")
      files["about.md"].should_not contain("categories =")

      # Check posts
      files["posts/hello-world.md"].should_not contain("tags =")
      files["posts/hello-world.md"].should_not contain("categories =")
      files["posts/hello-world.md"].should_not contain("authors =")

      # Date should still be present
      files["posts/hello-world.md"].should match(/date = "\d{4}-\d{2}-\d{2}"/)
    end
  end

  # Regression for gh#523: blog `archives.md` used to be a one-line
  # placeholder ("Browse all posts by date.") with no template logic
  # to actually list anything. The scaffold now ships a working
  # `templates/archives.html` and points the page at it.
  describe "archives" do
    it "ships an archives.html template that iterates site.pages (gh#523)" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      tpl = scaffold.template_files["archives.html"]?
      tpl.should_not be_nil
      tpl = tpl.not_nil!
      tpl.should contain(%(sort(attribute="date", reverse=true)))
      tpl.should contain("archive-list")
    end

    # The first version of the archives template hardcoded
    # `selectattr("section", "equalto", "posts")`, so renaming the
    # `posts/` section silently produced an empty archives page even
    # though `/archives/` was still in the header nav. The template
    # now filters by `date` truthiness so any dated leaf page shows
    # up regardless of its section name.
    it "filters by date rather than a hardcoded section name" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      tpl = scaffold.template_files["archives.html"].not_nil!
      tpl.should contain(%(selectattr("date")))
      tpl.should_not contain(%(selectattr("section", "equalto", "posts")))
      tpl.should contain(%(rejectattr("draft")))
      tpl.should contain(%(rejectattr("is_index")))
    end

    it "wires archives.md to the archives template (gh#523)" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      content = scaffold.content_files["archives.md"]
      content.should contain(%(template = "archives"))
    end
  end

  describe "posts" do
    # The blog scaffold ships a post.html with an <article> layout, a
    # post-meta block (publish date) and series navigation, but posts
    # inherit their template from the section's `page_template`. Without
    # this wiring every post fell back to the bare page.html — rendering
    # no date, no meta and no series nav, and edits to post.html had no
    # effect at all.
    it "wires the posts section to templates/post.html" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      scaffold.content_files["posts/_index.md"].should contain(%(page_template = "post"))
      scaffold.template_files["post.html"]?.should_not be_nil
    end

    it "ships a post.html that renders the publish date" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      tpl = scaffold.template_files["post.html"].not_nil!
      tpl.should contain("post-meta")
      tpl.should contain("page.date")
    end

    # Series nav must walk `series_pages` (ordered by series_weight) via the
    # 1-based `series_index`. It previously used page.lower/page.higher, which
    # are the section's flat date-ordered neighbours — so chapters were ordered
    # by date and could even link non-series posts.
    it "builds series nav from series_pages/series_index, not page.lower/higher" do
      tpl = Hwaro::Services::Scaffolds::Blog.new.template_files["post.html"].not_nil!
      series_nav = tpl.partition("series-nav")[2]
      series_nav.should contain("page.series_pages[page.series_index")
      series_nav.should contain("page.series_index > 1")
      series_nav.should_not contain("page.lower")
      series_nav.should_not contain("page.higher")
    end

    # The engine computes `page.related_posts` when [related] is enabled, but
    # no scaffold rendered it — so the advertised feature produced nothing.
    # post.html now renders a guarded related block.
    it "renders related posts (guarded by page.related_posts)" do
      tpl = Hwaro::Services::Scaffolds::Blog.new.template_files["post.html"].not_nil!
      tpl.should contain("{% if page.related_posts %}")
      tpl.should contain("{% for r in page.related_posts %}")
      tpl.should contain("class=\"related-posts\"")
    end
  end
end
