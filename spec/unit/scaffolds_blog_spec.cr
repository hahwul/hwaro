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
      files["index.md"].should contain("A blog powered by [Hwaro](https://github.com/hahwul/hwaro), a fast and lightweight static site generator.")
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
    # by date and could even link non-series posts. The scope stops at the
    # post-nav block ("Older/newer neighbours"), which legitimately walks the
    # date-ordered chain.
    it "builds series nav from series_pages/series_index, not page.lower/higher" do
      tpl = Hwaro::Services::Scaffolds::Blog.new.template_files["post.html"].not_nil!
      series_nav = tpl.partition("series-nav")[2].partition("Older/newer neighbours")[0]
      series_nav.should contain("page.series_pages[page.series_index")
      series_nav.should contain("page.series_index > 1")
      series_nav.should_not contain("page.lower")
      series_nav.should_not contain("page.higher")
    end

    # The post header carries a reading-time estimate next to the date,
    # guarded so pages without the computed field render no dangling dot.
    it "renders reading time in the post meta" do
      tpl = Hwaro::Services::Scaffolds::Blog.new.template_files["post.html"].not_nil!
      tpl.should contain("page.reading_time")
      tpl.should contain("min read")
      tpl.should contain(%(datetime="{{ page.date }}"))
    end

    # Older/newer nav walks page.lower/page.higher but never leaves the
    # post's own section (the chain is site-wide) and never links _index.
    it "guards the older/newer nav to the post's section" do
      tpl = Hwaro::Services::Scaffolds::Blog.new.template_files["post.html"].not_nil!
      tpl.should contain(%(class="post-nav"))
      tpl.should contain("page.lower.section == page.section")
      tpl.should contain("page.higher.section == page.section")
      tpl.should contain("not page.lower.is_index")
      tpl.should contain(%(rel="prev"))
      tpl.should contain(%(rel="next"))
      tpl.should contain("{{ base_url }}{{ page.lower.url }}")
    end

    # Tag pills link to /tags/<term>/ pages, so they are omitted entirely
    # for --skip-taxonomies sites where those pages don't exist.
    it "ships tag pills only when taxonomies are enabled" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      with_tags = scaffold.template_files(skip_taxonomies: false)["post.html"].not_nil!
      with_tags.should contain("post-tags")
      with_tags.should contain("get_taxonomy_url(kind='tags', term=t)")
      without_tags = scaffold.template_files(skip_taxonomies: true)["post.html"].not_nil!
      without_tags.should_not contain("post-tags")
      without_tags.should_not contain("get_taxonomy_url")
    end

    # The reading-progress thread is pure CSS scroll-driven animation:
    # gated behind @supports and prefers-reduced-motion, no JS.
    it "ships a guarded CSS reading-progress bar on post pages" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      tpl = scaffold.template_files["post.html"].not_nil!
      tpl.should contain(%(class="reading-progress"))
      css = scaffold.static_files["css/style.css"]
      css.should contain("@supports (animation-timeline: scroll())")
      css.should contain("animation-timeline: scroll(root)")
      supports_block = css.partition("@supports (animation-timeline: scroll())")[2]
      supports_block.should contain("@media (prefers-reduced-motion: no-preference)")
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

  describe "css" do
    # The blog stylesheet is built on the shared ember token system:
    # every color is a light-dark() pair resolved by color-scheme, and
    # the fixed header paints with the --glass token instead of a
    # hardcoded rgba() surface.
    it "uses the shared design tokens (adaptive scheme + glass header)" do
      css = Hwaro::Services::Scaffolds::Blog.new.static_files["css/style.css"]
      css.should contain("color-scheme: light dark")
      css.should contain("var(--glass)")
    end

    # Regression: the archives page markup (.archive-list/.archive-entry)
    # shipped with NO styles at all, rendering as a bare unstyled list.
    # Both ledgers (home feed + archives) share the date-rail grid rhythm.
    it "styles the archives ledger and the home feed with the date rail" do
      css = Hwaro::Services::Scaffolds::Blog.new.static_files["css/style.css"]
      css.should contain(".archive-entry {")
      css.should contain(".post-date {")
      css.scan(/grid-template-columns: 6\.5rem 1fr;/).size.should be >= 2
    end

    it "marks the active nav item" do
      css = Hwaro::Services::Scaffolds::Blog.new.static_files["css/style.css"]
      css.should contain(%(.blog-header nav a[aria-current="page"]))
    end

    # Feed and archive rows take the ember tint on hover (pointer devices
    # only), pulled full-bleed so the tint reads as a row, not a text strip.
    it "tints ledger rows on hover behind a hover-capable media query" do
      css = Hwaro::Services::Scaffolds::Blog.new.static_files["css/style.css"]
      css.should contain("@media (hover: hover) { .post-item:hover { background: var(--primary-tint); } }")
      css.should contain("@media (hover: hover) { .archive-entry:hover { background: var(--primary-tint); } }")
    end

    # The search palette is a glass surface with a @starting-style entry
    # reveal; both degrade gracefully (solid fallback, reduced-motion).
    it "renders the search modal as glass with a guarded entry reveal" do
      css = Hwaro::Services::Scaffolds::Blog.new.static_files["css/style.css"]
      css.should contain("backdrop-filter: saturate(180%) blur(24px)")
      css.should contain("@starting-style")
      reveal_block = css.partition("@starting-style")[0]
      reveal_block.should contain("@media (prefers-reduced-motion: no-preference)")
    end
  end

  describe "home template" do
    it "renders the post feed as date-rail entries inside the hero'd landing" do
      tpl = Hwaro::Services::Scaffolds::Blog.new.template_files["index.html"].not_nil!
      tpl.should contain(%(<time class="post-date"))
      tpl.should contain(%(class="post-item-body"))
      # The intro copy lives inside the hero, not stranded below it.
      tpl.index!("home-intro").should be < tpl.index!("</header>")
    end
  end
end
