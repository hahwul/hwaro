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
    it "page template includes search overlay" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      page = scaffold.template_files["page.html"]
      page.should contain("searchOverlay")
      page.should contain("searchInput")
    end

    it "page template includes search trigger button" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      page = scaffold.template_files["page.html"]
      page.should contain("search-trigger")
      page.should contain("openSearch()")
    end

    it "section template includes search overlay" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      section = scaffold.template_files["section.html"]
      section.should contain("searchOverlay")
    end

    it "footer template includes search.js script" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      footer = scaffold.template_files["footer.html"]
      footer.should contain("js/search.js")
    end

    it "page template includes header-right with search" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      page = scaffold.template_files["page.html"]
      page.should contain("header-right")
    end

    # Regression for gh#523: the docs sidebar used to be a hand-written
    # `<aside>` with the original three sections × three to four
    # pages baked in, so any page added via `hwaro new` never appeared
    # in the sidebar. Now the sidebar iterates `site.sections`
    # dynamically, so the per-section URLs must NOT be present in the
    # template source.
    it "renders the sidebar dynamically via site.sections (gh#523)" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      page = scaffold.template_files["page.html"]
      section = scaffold.template_files["section.html"]

      [page, section].each do |tmpl|
        tmpl.should contain("{% for sec in site.sections")
        tmpl.should contain("{% for p in sec.pages")
        # No hardcoded URLs.
        tmpl.should_not contain("/getting-started/installation/")
        tmpl.should_not contain("/guide/templates/")
        tmpl.should_not contain("/reference/cli/")
      end
    end

    it "page template includes Documentation span in logo" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      page = scaffold.template_files["page.html"]
      page.should contain("<span>Documentation</span>")
    end
  end
end
