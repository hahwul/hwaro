require "../spec_helper"
require "../../src/services/scaffolds/registry"

# =============================================================================
# Unit specs for the Book scaffold and the abstract Base class.
#
# Existing scaffolds_spec.cr covers Simple, Docs, and Registry.
# scaffolds_blog_spec.cr / scaffolds_bare_spec.cr / scaffolds_docs_spec.cr
# cover the remaining named scaffolds.
# =============================================================================

describe Hwaro::Services::Scaffolds::Book do
  describe "#type" do
    it "returns Book scaffold type" do
      Hwaro::Services::Scaffolds::Book.new.type
        .should eq(Hwaro::Config::Options::ScaffoldType::Book)
    end
  end

  describe "#description" do
    it "is a non-empty string mentioning Book-style structure" do
      desc = Hwaro::Services::Scaffolds::Book.new.description
      desc.should_not be_empty
      desc.should contain("Book-style")
    end
  end

  describe "#content_files" do
    it "includes the root index" do
      files = Hwaro::Services::Scaffolds::Book.new.content_files
      files.has_key?("index.md").should be_true
    end

    it "includes 3 chapter sections with their pages" do
      files = Hwaro::Services::Scaffolds::Book.new.content_files
      files.has_key?("chapter-1/_index.md").should be_true
      files.has_key?("chapter-1/getting-started.md").should be_true
      files.has_key?("chapter-1/installation.md").should be_true
      files.has_key?("chapter-2/_index.md").should be_true
      files.has_key?("chapter-2/basic-usage.md").should be_true
      files.has_key?("chapter-2/configuration.md").should be_true
      files.has_key?("chapter-3/_index.md").should be_true
      files.has_key?("chapter-3/advanced-topics.md").should be_true
    end

    it "produces non-empty content for every file" do
      files = Hwaro::Services::Scaffolds::Book.new.content_files
      files.each do |path, content|
        # Custom failure message names the offending file so a regression
        # is immediately localized.
        fail "content for #{path} was empty" if content.empty?
      end
    end
  end

  describe "#template_files" do
    it "includes the standard 5 templates" do
      files = Hwaro::Services::Scaffolds::Book.new.template_files
      files.has_key?("header.html").should be_true
      files.has_key?("footer.html").should be_true
      files.has_key?("page.html").should be_true
      files.has_key?("section.html").should be_true
      files.has_key?("404.html").should be_true
    end

    # Book scaffolds intentionally omit taxonomy templates: chapter-
    # ordered books don't use tags by default and the matching
    # `[[taxonomies]]` block is also dropped from the config emit.
    # Users who want taxonomies can copy from the simple/blog scaffolds.
    it "omits taxonomy templates by default (book uses chapter ordering)" do
      files = Hwaro::Services::Scaffolds::Book.new.template_files
      files.has_key?("taxonomy.html").should be_false
      files.has_key?("taxonomy_term.html").should be_false
    end

    it "ships nav, search, sidebar, and page-arrows partials" do
      files = Hwaro::Services::Scaffolds::Book.new.template_files
      files.has_key?("partials/nav.html").should be_true
      files.has_key?("partials/search.html").should be_true
      files.has_key?("partials/sidebar.html").should be_true
      files.has_key?("partials/page-arrows.html").should be_true
    end

    # The page template renders `{{ toc }}`, and the archetype enables it,
    # so a chapter's in-page table of contents actually appears (previously
    # `toc` was exposed by the engine but no scaffold template used it).
    it "renders an in-page table of contents driven by the archetype" do
      scaffold = Hwaro::Services::Scaffolds::Book.new
      page = scaffold.template_files["page.html"]
      page.should contain("{% if toc %}")
      page.should contain("{{ toc }}")
      page.should contain("book-toc")
      scaffold.archetype_files["default.md"].should contain("toc = true")
    end

    # Regression for gh#523: the book TOC sidebar used to bake the
    # original three chapters with hand-numbered "1.", "1.1" links
    # into the template. Adding a chapter via `hwaro new` left the
    # sidebar stale. Now the sidebar partial iterates `site.sections`.
    it "renders the chapter sidebar dynamically via site.sections (gh#523)" do
      files = Hwaro::Services::Scaffolds::Book.new.template_files
      sidebar = files["partials/sidebar.html"]
      sidebar.should contain("{% for sec in site.sections")
      sidebar.should contain("{% for p in sec.pages")
      sidebar.should_not contain("/chapter-1/installation/")
      sidebar.should_not contain("/chapter-2/configuration/")
      sidebar.should_not contain("/chapter-3/advanced-topics/")
    end

    # The chapter numbering captures `loop.index` from the outer
    # `{% for sec in site.sections %}` to render `1.`, `1.1`, etc.
    # If empty-name (root) sections were filtered with an inner
    # `{% if sec.name != "" %}`, Jinja's `loop.index` would still
    # increment for the skipped iteration and chapters would be
    # numbered `2., 3., 4.` once a user added a root `_index.md` or
    # turned on a taxonomy-as-section. Filter the sequence first so
    # the index lines up with the rendered chapters.
    it "pre-filters empty-name sections so chapter numbering is stable" do
      files = Hwaro::Services::Scaffolds::Book.new.template_files
      sidebar = files["partials/sidebar.html"]
      sidebar.should contain(%q(rejectattr("name", "equalto", "")))
      sidebar.should_not match(/{%\s*if\s+sec\.name\s*!=\s*""\s*%}/)
    end

    # The sidebar's top-level chapter order must match the prev/next
    # reading chain, which transform.cr orders by weight with a path
    # tiebreak. Crinja sort is stable, so `sort(attribute="path")` then
    # `sort(attribute="weight")` yields weight-asc, path-tiebroken order.
    # A path-only sort (the old behavior) diverged from the reading chain
    # whenever chapter weights didn't follow alphabetical paths.
    it "orders top-level chapters by weight with a path tiebreak (matches reading chain)" do
      files = Hwaro::Services::Scaffolds::Book.new.template_files
      sidebar = files["partials/sidebar.html"]
      sidebar.should contain(%q(| sort(attribute="path") | sort(attribute="weight")))
    end

    # Nested sections (name like "parent/child") also appear flat in
    # `site.sections`, so the outer loop skips them and renders them one
    # level deeper from the parent's `subsections` — mirroring the
    # depth-first nesting of the prev/next reading chain. Without the
    # skip they rendered as bogus top-level chapter groups.
    it "renders nested subsections beneath their parent, not as flat chapters" do
      files = Hwaro::Services::Scaffolds::Book.new.template_files
      sidebar = files["partials/sidebar.html"]
      # The top-level loop filters to top_level sections (so loop.index chapter
      # numbering stays contiguous even when a nested section sorts earlier).
      sidebar.should contain(%q(selectattr("top_level")))
      # Render each parent's subsections nested beneath it.
      sidebar.should contain("{% for sub in sec.subsections")
      sidebar.should contain("{% for sp in sub.pages")
    end
  end

  describe "#section_template" do
    # An empty chapter (a section with no non-index child pages) used to
    # render an orphan "In This Chapter" heading over an empty <ul>. The
    # heading + list are now guarded so they only appear when the section
    # has at least one listable child page.
    it "guards the chapter listing so empty chapters don't show an orphan heading" do
      files = Hwaro::Services::Scaffolds::Book.new.template_files
      section = files["section.html"]
      section.should contain(%q({% if section.pages | rejectattr("is_index") | length %}))
      # The heading and list live inside the guard.
      section.should match(/{%\s*if\s+section\.pages.*%}.*In This Chapter.*{%\s*endif\s*%}/m)
    end
  end

  describe "#static_files" do
    it "ships the book CSS and JS assets" do
      files = Hwaro::Services::Scaffolds::Book.new.static_files
      files.has_key?("css/style.css").should be_true
      files.has_key?("js/book.js").should be_true
    end

    it "ships real CSS and JS payloads (not just placeholders)" do
      files = Hwaro::Services::Scaffolds::Book.new.static_files
      # Structural fingerprints catch a wider class of regression than an
      # arbitrary byte-count threshold (e.g., truncation to a stub).
      files["css/style.css"].should contain(":root")
      files["js/book.js"].should contain("function")
    end

    # The sheet is token-driven: the shared ember :root prelude (both
    # schemes) plus book's own layout tokens injected through the layout
    # hook — including --bg-sidebar, the family's one scheme-pair outside
    # design_tokens.cr — and the shared ember rule mark.
    it "builds the CSS from the shared design tokens plus book layout tokens" do
      css = Hwaro::Services::Scaffolds::Book.new.static_files["css/style.css"]
      css.should contain("color-scheme: light dark;")
      css.should contain("--sidebar-w: 280px;")
      css.should contain("--bg-sidebar: light-dark(#f4f0e8, #181513);")
      css.should contain("linear-gradient(90deg, var(--rule-from), var(--rule-to))")
    end

    # The reading-progress thread is pure CSS scroll-driven animation:
    # gated behind @supports and prefers-reduced-motion, no JS.
    it "ships a guarded CSS reading-progress bar" do
      scaffold = Hwaro::Services::Scaffolds::Book.new
      nav = scaffold.template_files["partials/nav.html"].not_nil!
      nav.should contain(%(class="reading-progress"))
      css = scaffold.static_files["css/style.css"]
      css.should contain("@supports (animation-timeline: scroll())")
      css.should contain("animation-timeline: scroll(root)")
      supports_block = css.partition("@supports (animation-timeline: scroll())")[2]
      supports_block.should contain("@media (prefers-reduced-motion: no-preference)")
    end

    # The reading column caps prose at the shared measure while the wider
    # container stays for code, tables, and images.
    it "caps book prose at the shared measure" do
      css = Hwaro::Services::Scaffolds::Book.new.static_files["css/style.css"]
      css.should contain(".book-content p, .book-content li { max-width: var(--measure); }")
    end

    # Side arrows breathe on hover and press down on click; the base
    # translateY(-50%) centering must survive both states.
    it "gives the page arrows hover and press physics" do
      css = Hwaro::Services::Scaffolds::Book.new.static_files["css/style.css"]
      hover = css.partition(".book-nav-arrow:hover {")[2].partition("}")[0]
      hover.should contain("transform: translateY(-50%) scale(1.06);")
      active = css.partition(".book-nav-arrow:active {")[2].partition("}")[0]
      active.should contain("transform: translateY(-50%) scale(0.94);")
    end

    # The sidebar active state is applied by book.js; aria-current keeps
    # it accessible and the stylesheet matches both hooks.
    it "marks the active chapter link with aria-current" do
      scaffold = Hwaro::Services::Scaffolds::Book.new
      scaffold.static_files["js/book.js"].should contain(%(setAttribute('aria-current', 'page')))
      scaffold.static_files["css/style.css"].should contain(%(.chapter-links a[aria-current="page"]))
    end

    # The search palette is a glass surface with a @starting-style entry
    # reveal; both degrade gracefully (solid fallback, reduced-motion).
    it "renders the search modal as glass with a guarded entry reveal" do
      css = Hwaro::Services::Scaffolds::Book.new.static_files["css/style.css"]
      css.should contain("backdrop-filter: saturate(180%) blur(24px)")
      css.should contain("@starting-style")
      css.partition("@starting-style")[0].should contain("@media (prefers-reduced-motion: no-preference)")
    end
  end

  describe "#config_content" do
    it "returns non-empty TOML config" do
      config = Hwaro::Services::Scaffolds::Book.new.config_content
      config.should_not be_empty
    end

    it "uses the Book scaffold's title and description" do
      config = Hwaro::Services::Scaffolds::Book.new.config_content
      config.should contain(%(title = "My Book"))
      config.should contain("A book powered by Hwaro.")
    end

    it "uses the github highlight.js theme" do
      config = Hwaro::Services::Scaffolds::Book.new.config_content
      config.should contain(%(theme = "github"))
    end

    # Book intentionally drops `[[taxonomies]]` from the default
    # config — chapter-ordered books don't use tags. Users who want
    # them can copy from the simple/blog scaffolds.
    it "omits taxonomies block by default" do
      config = Hwaro::Services::Scaffolds::Book.new.config_content
      config.should_not contain("[[taxonomies]]")
    end
  end
end

# A minimal concrete subclass to exercise Base's default and protected helpers.
# Type returns Bare arbitrarily — this class is never registered with the
# scaffold registry; it exists only so the abstract Base methods can be
# instantiated and called.
private class TestBaseScaffold < Hwaro::Services::Scaffolds::Base
  def type : Hwaro::Config::Options::ScaffoldType
    Hwaro::Config::Options::ScaffoldType::Bare
  end

  def description : String
    "test scaffold"
  end

  def content_files(skip_taxonomies : Bool = false) : Hash(String, String)
    {} of String => String
  end

  def template_files(skip_taxonomies : Bool = false) : Hash(String, String)
    {} of String => String
  end

  def config_content(skip_taxonomies : Bool = false, multilingual_languages : Array(String) = [] of String) : String
    minimal_config_content(skip_taxonomies, multilingual_languages)
  end
end

describe Hwaro::Services::Scaffolds::Base do
  describe "#static_files (default)" do
    # The base scaffold ships a tiny SVG favicon so generated sites
    # don't show a blank tab icon out of the box. Subclasses that
    # override `static_files` are expected to merge `super` to
    # preserve it.
    it "ships the inherited favicon and nothing else" do
      files = TestBaseScaffold.new.static_files
      files.keys.should eq(["favicon.svg"])
      files["favicon.svg"].should contain("<svg")
    end
  end

  describe "#shortcode_files (default)" do
    it "ships the shared alert shortcode" do
      files = TestBaseScaffold.new.shortcode_files
      files.has_key?("shortcodes/alert.html").should be_true
      # Alert shortcode references body and type via Jinja. The body is
      # piped through `markdownify` so markdown inside the alert renders;
      # `{{ type` is truncated to match `{{ type | upper }}`.
      files["shortcodes/alert.html"].should contain("{{ body | markdownify }}")
      files["shortcodes/alert.html"].should contain("{{ type")
    end
  end

  describe "#minimal_config_content" do
    it "renders title, base_url, and processors plugin entries" do
      out = TestBaseScaffold.new.config_content
      out.should contain(%(title = "My Hwaro Site"))
      out.should contain("base_url")
      out.should contain("[plugins]")
      out.should contain(%(processors = ["markdown"]))
    end

    it "includes taxonomies block by default" do
      out = TestBaseScaffold.new.config_content(skip_taxonomies: false)
      out.should contain("[[taxonomies]]")
      out.should contain(%(name = "tags"))
    end

    it "omits taxonomies block when skip_taxonomies is true" do
      out = TestBaseScaffold.new.config_content(skip_taxonomies: true)
      out.should_not contain("[[taxonomies]]")
    end

    it "uses the github highlight theme" do
      out = TestBaseScaffold.new.config_content
      out.should contain(%(theme = "github"))
    end
  end
end
