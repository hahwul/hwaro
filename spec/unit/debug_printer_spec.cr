require "../spec_helper"
require "../../src/utils/debug_printer"
require "../../src/models/site"
require "../../src/models/page"
require "../../src/models/section"
require "../../src/models/config"

describe Hwaro::Utils::DebugPrinter do
  describe ".print" do
    it "prints an empty site structure" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      io = IO::Memory.new
      Hwaro::Utils::DebugPrinter.print(site, io)
      output = io.to_s

      output.should contain("Site Structure (Debug):")
    end

    it "prints a site with pages and sections" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      # Root page
      page1 = Hwaro::Models::Page.new("index.md")
      page1.title = "Home"
      page1.section = ""
      site.pages << page1

      # Section page
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.title = "Blog"
      # section.section is not used directly by DebugPrinter logic for sections,
      # it uses path dirname.
      site.sections << section

      # Page in section
      page2 = Hwaro::Models::Page.new("blog/post1.md")
      page2.title = "Post 1"
      page2.section = "blog"
      site.pages << page2

      io = IO::Memory.new
      Hwaro::Utils::DebugPrinter.print(site, io)
      output = io.to_s

      # Clean up color codes for easier checking
      plain_output = output.gsub(/\e\[\d+(?:;\d+)*m/, "")

      plain_output.should contain("Site Structure (Debug):")
      plain_output.should contain("- Home (index.md)")
      plain_output.should contain("blog (Section: Blog)")
      plain_output.should contain("- Post 1 (blog/post1.md)")
    end

    it "prints a site with nested sections" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      # Section: docs
      section1 = Hwaro::Models::Section.new("docs/_index.md")
      section1.title = "Docs"
      site.sections << section1

      # Subsection: docs/api
      section2 = Hwaro::Models::Section.new("docs/api/_index.md")
      section2.title = "API"
      site.sections << section2

      # Page in subsection
      page = Hwaro::Models::Page.new("docs/api/v1.md")
      page.title = "API V1"
      page.section = "docs/api"
      site.pages << page

      io = IO::Memory.new
      Hwaro::Utils::DebugPrinter.print(site, io)
      output = io.to_s
      plain_output = output.gsub(/\e\[\d+(?:;\d+)*m/, "")

      plain_output.should contain("docs (Section: Docs)")
      plain_output.should contain("api (Section: API)")
      plain_output.should contain("- API V1 (docs/api/v1.md)")
    end
  end
end
