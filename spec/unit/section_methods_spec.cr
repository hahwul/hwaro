require "../spec_helper"

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

  describe "#effective_page_template" do
    it "returns nil when page_template is not set" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.effective_page_template.should be_nil
    end

    it "returns the page_template when set" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.page_template = "blog_post"
      section.effective_page_template.should eq("blog_post")
    end

    it "returns correct template for different values" do
      section = Hwaro::Models::Section.new("docs/_index.md")
      section.page_template = "documentation"
      section.effective_page_template.should eq("documentation")
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

  describe "#find_subsection" do
    it "finds subsection by section name" do
      parent = Hwaro::Models::Section.new("blog/_index.md")

      archive = Hwaro::Models::Section.new("blog/archive/_index.md")
      archive.section = "archive"
      archive.title = "Archive"

      recent = Hwaro::Models::Section.new("blog/recent/_index.md")
      recent.section = "recent"
      recent.title = "Recent"

      parent.add_subsection(archive)
      parent.add_subsection(recent)

      found = parent.find_subsection("archive")
      found.should_not be_nil
      found.not_nil!.title.should eq("Archive")
    end

    it "finds subsection by title (case-insensitive)" do
      parent = Hwaro::Models::Section.new("blog/_index.md")

      archive = Hwaro::Models::Section.new("blog/archive/_index.md")
      archive.section = "blog/archive"
      archive.title = "Archive Section"

      parent.add_subsection(archive)

      found = parent.find_subsection("archive section")
      found.should_not be_nil
      found.not_nil!.title.should eq("Archive Section")
    end

    it "returns nil when subsection is not found" do
      parent = Hwaro::Models::Section.new("blog/_index.md")

      archive = Hwaro::Models::Section.new("blog/archive/_index.md")
      archive.section = "archive"
      archive.title = "Archive"
      parent.add_subsection(archive)

      found = parent.find_subsection("nonexistent")
      found.should be_nil
    end

    it "returns nil when no subsections exist" do
      parent = Hwaro::Models::Section.new("blog/_index.md")
      found = parent.find_subsection("anything")
      found.should be_nil
    end
  end

  describe "#all_pages" do
    it "returns pages from the section" do
      section = Hwaro::Models::Section.new("blog/_index.md")

      page1 = Hwaro::Models::Page.new("blog/post1.md")
      page1.title = "Post 1"
      page1.draft = false

      page2 = Hwaro::Models::Page.new("blog/post2.md")
      page2.title = "Post 2"
      page2.draft = false

      section.pages << page1
      section.pages << page2

      result = section.all_pages
      result.size.should eq(2)
      result.map(&.title).should eq(["Post 1", "Post 2"])
    end

    it "excludes draft pages by default" do
      section = Hwaro::Models::Section.new("blog/_index.md")

      published = Hwaro::Models::Page.new("blog/published.md")
      published.title = "Published"
      published.draft = false

      draft = Hwaro::Models::Page.new("blog/draft.md")
      draft.title = "Draft"
      draft.draft = true

      section.pages << published
      section.pages << draft

      result = section.all_pages
      result.size.should eq(1)
      result.first.title.should eq("Published")
    end

    it "includes draft pages when include_drafts is true" do
      section = Hwaro::Models::Section.new("blog/_index.md")

      published = Hwaro::Models::Page.new("blog/published.md")
      published.title = "Published"
      published.draft = false

      draft = Hwaro::Models::Page.new("blog/draft.md")
      draft.title = "Draft"
      draft.draft = true

      section.pages << published
      section.pages << draft

      result = section.all_pages(include_drafts: true)
      result.size.should eq(2)
    end

    it "includes pages from subsections" do
      parent = Hwaro::Models::Section.new("blog/_index.md")

      parent_page = Hwaro::Models::Page.new("blog/post1.md")
      parent_page.title = "Parent Post"
      parent_page.draft = false
      parent.pages << parent_page

      child = Hwaro::Models::Section.new("blog/archive/_index.md")
      child_page = Hwaro::Models::Page.new("blog/archive/old.md")
      child_page.title = "Old Post"
      child_page.draft = false
      child.pages << child_page

      parent.add_subsection(child)

      result = parent.all_pages
      result.size.should eq(2)
      result.map(&.title).should contain("Parent Post")
      result.map(&.title).should contain("Old Post")
    end

    it "recursively collects pages from nested subsections" do
      root = Hwaro::Models::Section.new("docs/_index.md")

      root_page = Hwaro::Models::Page.new("docs/intro.md")
      root_page.title = "Intro"
      root_page.draft = false
      root.pages << root_page

      level1 = Hwaro::Models::Section.new("docs/guide/_index.md")
      l1_page = Hwaro::Models::Page.new("docs/guide/basics.md")
      l1_page.title = "Basics"
      l1_page.draft = false
      level1.pages << l1_page

      level2 = Hwaro::Models::Section.new("docs/guide/advanced/_index.md")
      l2_page = Hwaro::Models::Page.new("docs/guide/advanced/deep.md")
      l2_page.title = "Deep Dive"
      l2_page.draft = false
      level2.pages << l2_page

      level1.add_subsection(level2)
      root.add_subsection(level1)

      result = root.all_pages
      result.size.should eq(3)
      result.map(&.title).should contain("Intro")
      result.map(&.title).should contain("Basics")
      result.map(&.title).should contain("Deep Dive")
    end

    it "excludes drafts from subsections too" do
      parent = Hwaro::Models::Section.new("blog/_index.md")

      child = Hwaro::Models::Section.new("blog/sub/_index.md")
      draft_page = Hwaro::Models::Page.new("blog/sub/draft.md")
      draft_page.title = "Sub Draft"
      draft_page.draft = true
      child.pages << draft_page

      published_page = Hwaro::Models::Page.new("blog/sub/published.md")
      published_page.title = "Sub Published"
      published_page.draft = false
      child.pages << published_page

      parent.add_subsection(child)

      result = parent.all_pages(include_drafts: false)
      result.size.should eq(1)
      result.first.title.should eq("Sub Published")

      result_with_drafts = parent.all_pages(include_drafts: true)
      result_with_drafts.size.should eq(2)
    end

    it "returns empty array when no pages exist" do
      section = Hwaro::Models::Section.new("empty/_index.md")
      result = section.all_pages
      result.should be_empty
    end
  end

  describe "#pagination_url" do
    it "returns base url with trailing slash for page 1" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.url = "/blog/"

      url = section.pagination_url(1)
      url.should eq("/blog/")
    end

    it "returns url with page number for subsequent pages" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.url = "/blog/"

      url = section.pagination_url(2)
      url.should eq("/blog/page/2/")
    end

    it "uses custom paginate_path" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.url = "/blog/"
      section.paginate_path = "p"

      url = section.pagination_url(3)
      url.should eq("/blog/p/3/")
    end

    it "handles url with trailing slash correctly for page 1" do
      section = Hwaro::Models::Section.new("wiki/_index.md")
      section.url = "/wiki/"

      url = section.pagination_url(1)
      url.should eq("/wiki/")
    end

    it "handles url without trailing slash" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.url = "/blog"

      url = section.pagination_url(1)
      url.should eq("/blog/")

      url2 = section.pagination_url(2)
      url2.should eq("/blog/page/2/")
    end

    it "handles root url" do
      section = Hwaro::Models::Section.new("_index.md")
      section.url = "/"

      url = section.pagination_url(1)
      url.should eq("/")

      url2 = section.pagination_url(2)
      url2.should eq("/page/2/")
    end

    it "uses default paginate_path 'page'" do
      section = Hwaro::Models::Section.new("blog/_index.md")
      section.paginate_path.should eq("page")
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
