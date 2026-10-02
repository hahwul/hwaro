require "../../spec_helper"

describe Hwaro::Models::Section do
  describe "#has_redirect?" do
    it "returns false when redirect_to is nil" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.has_redirect?.should be_false
    end

    it "returns false when redirect_to is empty string" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.redirect_to = ""
      section.has_redirect?.should be_false
    end

    it "returns true when redirect_to is set" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.redirect_to = "/new-blog/"
      section.has_redirect?.should be_true
    end

    it "returns true for external redirect URL" do
      section = Hwaro::Models::Section.new("legacy/_index.md")
      section.redirect_to = "https://example.com/new-location/"
      section.has_redirect?.should be_true
    end
  end

  describe "#add_subsection" do
    it "adds a subsection to the section" do
      parent = Hwaro::Models::Section.new("blog/_index.md")
      child = Hwaro::Models::Section.new("blog/archive/_index.md")
      child.section = "blog/archive"
      child.title = "Archive"

      parent.add_subsection(child)
      parent.subsections.size.should eq(1)
      parent.subsections.first.title.should eq("Archive")
    end

    it "adds multiple subsections" do
      parent = Hwaro::Models::Section.new("docs/_index.md")

      guide = Hwaro::Models::Section.new("docs/guide/_index.md")
      guide.section = "docs/guide"
      guide.title = "Guide"

      api = Hwaro::Models::Section.new("docs/api/_index.md")
      api.section = "docs/api"
      api.title = "API"

      faq = Hwaro::Models::Section.new("docs/faq/_index.md")
      faq.section = "docs/faq"
      faq.title = "FAQ"

      parent.add_subsection(guide)
      parent.add_subsection(api)
      parent.add_subsection(faq)

      parent.subsections.size.should eq(3)
      parent.subsections.map(&.title).should eq(["Guide", "API", "FAQ"])
    end
  end

  describe "property defaults" do
    it "initializes paginate_path as 'page'" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.paginate_path.should eq("page")
    end

    it "can set paginate_path" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.paginate_path = "p"
      section.paginate_path.should eq("p")
    end

    it "initializes redirect_to as nil" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.redirect_to.should be_nil
    end

    it "can set redirect_to" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.redirect_to = "/new-location/"
      section.redirect_to.should eq("/new-location/")
    end

    it "initializes page_template as nil" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.page_template.should be_nil
    end

    it "can set page_template" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.page_template = "custom_page"
      section.page_template.should eq("custom_page")
    end

    it "initializes subsections as empty array" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.subsections.should eq([] of Hwaro::Models::Section)
    end

    it "initializes pages as empty array" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.pages.should eq([] of Hwaro::Models::Page)
    end

    it "can add pages directly" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      page = Hwaro::Models::Page.new("blog/post.md")
      page.title = "Test Post"
      section.pages << page
      section.pages.size.should eq(1)
      section.pages.first.title.should eq("Test Post")
    end

    it "initializes transparent as false" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.transparent.should be_false
    end

    it "initializes generate_feeds as false" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.generate_feeds.should be_false
    end

    it "initializes sort_by as nil" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.sort_by.should be_nil
    end

    it "can set sort_by" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.sort_by = "title"
      section.sort_by.should eq("title")
    end

    it "initializes reverse as nil" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.reverse.should be_nil
    end

    it "can set reverse" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.reverse = true
      section.reverse.should be_true
    end
  end
end
