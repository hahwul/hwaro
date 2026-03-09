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

    it "page template includes Documentation span in logo" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      page = scaffold.template_files["page.html"]
      page.should contain("<span>Documentation</span>")
    end
  end
end
