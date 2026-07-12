require "../spec_helper"
require "../../src/services/scaffolds/docs"

describe Hwaro::Services::Scaffolds::Docs do
  describe "#static_files" do
    it "consumes the shared token system (auto light+dark)" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      css = scaffold.static_files["css/style.css"]
      css.should contain("color-scheme: light dark")
      css.should contain("var(--glass)")
      css.should contain("var(--primary-tint)")
      css.should contain("--bg-sidebar: light-dark(")
    end

    it "includes css/style.css" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.static_files
      files.has_key?("css/style.css").should be_true
      files["css/style.css"].should_not be_empty
    end

    it "includes js/search.js" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.static_files
      files.has_key?("js/search.js").should be_true
      files["js/search.js"].should_not be_empty
    end
  end

  describe "#styles" do
    it "returns a link tag" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      header = scaffold.template_files["header.html"]
      header.should contain("<link rel=\"stylesheet\" href=\"{{ base_url }}/css/style.css\">")
    end
  end

  describe "#template_files" do
    it "ships nav, search, and sidebar partials" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      files.has_key?("partials/nav.html").should be_true
      files.has_key?("partials/search.html").should be_true
      files.has_key?("partials/sidebar.html").should be_true
    end

    it "search partial defines the overlay" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      search = scaffold.template_files["partials/search.html"]
      search.should contain("searchOverlay")
      search.should contain("searchInput")
    end

    it "nav partial defines the search trigger button" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      nav = scaffold.template_files["partials/nav.html"]
      nav.should contain("search-trigger")
      nav.should contain("openSearch()")
      nav.should contain("header-right")
    end

    # Each chrome-bearing template pulls the partials in via include
    # so editing the nav (or 404 layout) is a one-file change. The
    # 404/taxonomy templates that previously closed unmatched
    # `</main></div>` get the same treatment.
    it "page/section/404/taxonomy templates pull in nav, search, and sidebar partials" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      ["page.html", "section.html", "404.html", "taxonomy.html"].each do |name|
        body = files[name]
        body.should contain(%({% include "partials/nav.html" %}))
        body.should contain(%({% include "partials/search.html" %}))
        body.should contain(%({% include "partials/sidebar.html" %}))
        body.should contain("docs-container")
      end
    end

    it "footer template includes search.js script" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      footer = scaffold.template_files["footer.html"]
      footer.should contain("js/search.js")
    end

    # The docs archetype sets `toc = true`, but the page template never
    # rendered `{{ toc }}` — so the table of contents was silently dropped.
    it "renders an in-page table of contents in the page template" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      page = scaffold.template_files["page.html"]
      page.should contain("{% if toc %}")
      page.should contain("{{ toc }}")
      page.should contain("docs-toc")
      # And the docs archetypes that drive it still enable toc.
      scaffold.archetype_files["guide.md"].should contain("toc = true")
    end

    # Regression for gh#523: the docs sidebar used to be a hand-written
    # `<aside>` with the original three sections × three to four
    # pages baked in, so any page added via `hwaro new` never appeared
    # in the sidebar. Now the sidebar iterates `site.sections`
    # dynamically, so the per-section URLs must NOT be present in the
    # sidebar partial source.
    it "renders the sidebar dynamically via site.sections (gh#523)" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      sidebar = scaffold.template_files["partials/sidebar.html"]

      sidebar.should contain("{% for sec in site.sections")
      sidebar.should contain("{% for p in sec.pages")
      sidebar.should_not contain("/getting-started/installation/")
      sidebar.should_not contain("/guide/templates/")
      sidebar.should_not contain("/reference/cli/")
    end

    # On a multilingual site the sidebar must only list sections for the
    # current page's language; without a `sec.language == page_language`
    # guard a /ko/ page listed every language's sections (3 × 3 = 9
    # entries) with hrefs jumping across languages.
    it "filters sidebar sections by the current page language" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      sidebar = scaffold.template_files["partials/sidebar.html"]

      sidebar.should contain("sec.language == page_language")
    end

    it "nav partial includes Documentation span in logo" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      nav = scaffold.template_files["partials/nav.html"]
      nav.should contain("<span>Documentation</span>")
    end

    # Without `lang_prefix` the docs nav was hardcoded to English URLs,
    # so a Korean reader on a translated page was one click from being
    # bounced back to `/getting-started/`.
    it "nav partial routes through lang_prefix for multilingual sites" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      nav = scaffold.template_files["partials/nav.html"]
      nav.should contain("{{ base_url }}{{ lang_prefix }}/getting-started/")
    end

    # Sidebar pages sort by weight (path as stable tiebreak) so each
    # section reads in learning order — Installation before Configuration
    # — instead of alphabetically.
    it "orders sidebar pages by weight with a stable path tiebreak" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      sidebar = scaffold.template_files["partials/sidebar.html"]
      sidebar.should contain(%(sort(attribute="path") | sort(attribute="weight")))

      files = scaffold.content_files
      files["getting-started/installation.md"].should contain("weight = 1")
      files["getting-started/quick-start.md"].should contain("weight = 2")
      files["getting-started/configuration.md"].should contain("weight = 3")
    end
  end

  describe "landing composition" do
    it "ships section link-cards and a typographic feature grid" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      index = scaffold.content_files["index.md"]
      index.should contain(%(class="link-cards"))
      index.should contain(%(class="feature-grid"))

      css = scaffold.static_files["css/style.css"]
      css.should contain("a.link-card {")
      css.should contain(".feature-grid {")
      css.should contain("var(--bg-raised)")
    end

    # The raw-HTML card links must localize like Markdown links do —
    # otherwise the cards reintroduce gh#524 through the HTML side door.
    it "rewrites card hrefs in localized stubs (gh#524)" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      multi = scaffold.multilingual_content_files(["en", "ko"])

      ko_index = multi["index.ko.md"]
      ko_index.should contain(%(href="/ko/getting-started/"))
      ko_index.should_not contain(%(href="/getting-started/"))
    end
  end
end
