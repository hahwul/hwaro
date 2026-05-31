require "../spec_helper"
require "../../src/services/scaffolds/docs"

describe Hwaro::Services::Scaffolds::Docs do
  describe "#static_files" do
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
  end
end
