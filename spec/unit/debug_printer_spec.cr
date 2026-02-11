require "../spec_helper"
require "../../src/utils/debug_printer"
require "../../src/models/site"
require "../../src/models/page"
require "../../src/models/section"

describe Hwaro::Utils::DebugPrinter do
  describe ".print" do
    it "prints the site structure correctly" do
      # Setup site
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      # Create sections
      blog_section = Hwaro::Models::Section.new("blog/_index.md")
      blog_section.title = "Blog"
      site.sections << blog_section

      # Create pages
      page1 = Hwaro::Models::Page.new("index.md")
      page1.title = "Home"
      page1.section = ""
      site.pages << page1

      page2 = Hwaro::Models::Page.new("blog/post-1.md")
      page2.title = "Post 1"
      page2.section = "blog"
      site.pages << page2

      # Create IO to capture output
      io = IO::Memory.new

      # Call print
      Hwaro::Utils::DebugPrinter.print(site, io)

      # Verify output
      output = io.to_s
      output.should contain("Site Structure (Debug):")
      output.should contain("Home")
      output.should contain("index.md")
      output.should contain("blog")
      output.should contain("Blog")
      output.should contain("Post 1")
      output.should contain("blog/post-1.md")
    end

    it "handles nested sections" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      # Create nested section
      tech_section = Hwaro::Models::Section.new("blog/tech/_index.md")
      tech_section.title = "Tech"
      site.sections << tech_section

      page = Hwaro::Models::Page.new("blog/tech/post.md")
      page.title = "Tech Post"
      page.section = "blog/tech"
      site.pages << page

      io = IO::Memory.new
      Hwaro::Utils::DebugPrinter.print(site, io)

      output = io.to_s
      output.should contain("blog")
      output.should contain("tech")
      output.should contain("Tech")
      output.should contain("Tech Post")
    end

    it "handles empty site" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      io = IO::Memory.new
      Hwaro::Utils::DebugPrinter.print(site, io)

      output = io.to_s
      output.should contain("Site Structure (Debug):")
      # Should not contain any page indicators if there are no pages
      output.should_not contain("- ")
    end
  end
end
