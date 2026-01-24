require "../spec_helper"

describe Hwaro::Models::Page do
  describe "#initialize" do
    it "creates a page with default values" do
      page = Hwaro::Models::Page.new("test.md")
      page.path.should eq("test.md")
      page.title.should eq("Untitled")
      page.draft.should be_false
      page.render.should be_true
      page.tags.should eq([] of String)
      page.aliases.should eq([] of String)
      page.taxonomies.should eq({} of String => Array(String))
      page.front_matter_keys.should eq([] of String)
      page.weight.should eq(0)
      page.content.should eq("")
      page.raw_content.should eq("")
      page.section.should eq("")
      page.url.should eq("")
      page.is_index.should be_false
      page.in_sitemap.should be_true
      page.toc.should be_false
      page.generated.should be_false
      page.language.should be_nil
      page.description.should be_nil
      page.date.should be_nil
      page.updated.should be_nil
      page.template.should be_nil
      page.slug.should be_nil
      page.custom_path.should be_nil
      page.taxonomy_name.should be_nil
      page.taxonomy_term.should be_nil
      page.image.should be_nil
    end
  end

  describe "property setters" do
    it "can set title" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "My Title"
      page.title.should eq("My Title")
    end

    it "can set description" do
      page = Hwaro::Models::Page.new("test.md")
      page.description = "A description"
      page.description.should eq("A description")
    end

    it "can set date" do
      page = Hwaro::Models::Page.new("test.md")
      date = Time.utc(2024, 6, 15)
      page.date = date
      page.date.should eq(date)
    end

    it "can set updated" do
      page = Hwaro::Models::Page.new("test.md")
      updated = Time.utc(2024, 7, 20)
      page.updated = updated
      page.updated.should eq(updated)
    end

    it "can set draft" do
      page = Hwaro::Models::Page.new("test.md")
      page.draft = true
      page.draft.should be_true
    end

    it "can set render" do
      page = Hwaro::Models::Page.new("test.md")
      page.render = false
      page.render.should be_false
    end

    it "can set tags" do
      page = Hwaro::Models::Page.new("test.md")
      page.tags = ["crystal", "programming"]
      page.tags.should eq(["crystal", "programming"])
    end

    it "can set taxonomies" do
      page = Hwaro::Models::Page.new("test.md")
      page.taxonomies = {"categories" => ["tech", "news"]}
      page.taxonomies["categories"].should eq(["tech", "news"])
    end

    it "can set front_matter_keys" do
      page = Hwaro::Models::Page.new("test.md")
      page.front_matter_keys = ["title", "tags", "custom_field"]
      page.front_matter_keys.should contain("custom_field")
    end

    it "can set weight" do
      page = Hwaro::Models::Page.new("test.md")
      page.weight = 10
      page.weight.should eq(10)
    end

    it "can set content" do
      page = Hwaro::Models::Page.new("test.md")
      page.content = "<p>Hello World</p>"
      page.content.should eq("<p>Hello World</p>")
    end

    it "can set raw_content" do
      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "# Hello World"
      page.raw_content.should eq("# Hello World")
    end

    it "can set section" do
      page = Hwaro::Models::Page.new("blog/post.md")
      page.section = "blog"
      page.section.should eq("blog")
    end

    it "can set url" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/blog/my-post/"
      page.url.should eq("/blog/my-post/")
    end

    it "can set is_index" do
      page = Hwaro::Models::Page.new("blog/index.md")
      page.is_index = true
      page.is_index.should be_true
    end

    it "can set in_sitemap" do
      page = Hwaro::Models::Page.new("test.md")
      page.in_sitemap = false
      page.in_sitemap.should be_false
    end

    it "can set toc" do
      page = Hwaro::Models::Page.new("test.md")
      page.toc = true
      page.toc.should be_true
    end

    it "can set generated" do
      page = Hwaro::Models::Page.new("test.md")
      page.generated = true
      page.generated.should be_true
    end

    it "can set language" do
      page = Hwaro::Models::Page.new("test.ko.md")
      page.language = "ko"
      page.language.should eq("ko")
    end

    it "can set image" do
      page = Hwaro::Models::Page.new("test.md")
      page.image = "/images/cover.png"
      page.image.should eq("/images/cover.png")
    end

    it "can set template" do
      page = Hwaro::Models::Page.new("test.md")
      page.template = "custom"
      page.template.should eq("custom")
    end

    it "can set slug" do
      page = Hwaro::Models::Page.new("test.md")
      page.slug = "custom-slug"
      page.slug.should eq("custom-slug")
    end

    it "can set custom_path" do
      page = Hwaro::Models::Page.new("test.md")
      page.custom_path = "/custom/path/"
      page.custom_path.should eq("/custom/path/")
    end

    it "can set aliases" do
      page = Hwaro::Models::Page.new("test.md")
      page.aliases = ["/old-url/", "/another-old-url/"]
      page.aliases.should eq(["/old-url/", "/another-old-url/"])
    end

    it "can set taxonomy_name" do
      page = Hwaro::Models::Page.new("test.md")
      page.taxonomy_name = "tags"
      page.taxonomy_name.should eq("tags")
    end

    it "can set taxonomy_term" do
      page = Hwaro::Models::Page.new("test.md")
      page.taxonomy_term = "crystal"
      page.taxonomy_term.should eq("crystal")
    end
  end
end

describe Hwaro::Models::Section do
  describe "#initialize" do
    it "creates a section with default values" do
      section = Hwaro::Models::Section.new("blog/index.md")
      section.path.should eq("blog/index.md")
      section.transparent.should be_false
      section.generate_feeds.should be_false
      section.paginate.should be_nil
      section.pagination_enabled.should be_nil
      section.sort_by.should be_nil
      section.reverse.should be_nil
    end

    it "inherits from Page" do
      section = Hwaro::Models::Section.new("blog/index.md")
      section.is_a?(Hwaro::Models::Page).should be_true
    end
  end

  describe "section-specific properties" do
    it "has pagination properties" do
      section = Hwaro::Models::Section.new("wiki/index.md")
      section.paginate.should be_nil
      section.pagination_enabled.should be_nil
    end

    it "can set pagination properties" do
      section = Hwaro::Models::Section.new("wiki/index.md")
      section.paginate = 5
      section.pagination_enabled = true
      section.paginate.should eq(5)
      section.pagination_enabled.should eq(true)
    end

    it "can set transparent" do
      section = Hwaro::Models::Section.new("blog/index.md")
      section.transparent = true
      section.transparent.should be_true
    end

    it "can set generate_feeds" do
      section = Hwaro::Models::Section.new("blog/index.md")
      section.generate_feeds = true
      section.generate_feeds.should be_true
    end

    it "can set sort_by" do
      section = Hwaro::Models::Section.new("blog/index.md")
      section.sort_by = "weight"
      section.sort_by.should eq("weight")
    end

    it "can set reverse" do
      section = Hwaro::Models::Section.new("blog/index.md")
      section.reverse = true
      section.reverse.should be_true
    end
  end
end

describe Hwaro::Models::Site do
  describe "#initialize" do
    it "creates a site with config" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)
      site.config.should eq(config)
      site.pages.should eq([] of Hwaro::Models::Page)
      site.sections.should eq([] of Hwaro::Models::Section)
      site.taxonomies.should eq({} of String => Hash(String, Array(Hwaro::Models::Page)))
    end
  end

  describe "#taxonomy_terms" do
    it "returns empty array for non-existent taxonomy" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)
      site.taxonomy_terms("tags").should eq([] of String)
    end

    it "returns sorted terms for existing taxonomy" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("post1.md")
      page2 = Hwaro::Models::Page.new("post2.md")

      site.taxonomies["tags"] = {
        "zebra"  => [page1],
        "apple"  => [page2],
        "banana" => [page1, page2],
      }

      terms = site.taxonomy_terms("tags")
      terms.should eq(["apple", "banana", "zebra"])
    end
  end

  describe "#taxonomy_pages" do
    it "returns empty array for non-existent taxonomy" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)
      site.taxonomy_pages("tags", "crystal").should eq([] of Hwaro::Models::Page)
    end

    it "returns empty array for non-existent term" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)
      page = Hwaro::Models::Page.new("test.md")
      site.taxonomies["tags"] = {"other" => [page]}
      # Term "crystal" doesn't exist in tags taxonomy
      site.taxonomy_pages("tags", "crystal").should eq([] of Hwaro::Models::Page)
    end

    it "returns pages for existing term" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("post1.md")
      page2 = Hwaro::Models::Page.new("post2.md")

      site.taxonomies["tags"] = {
        "crystal" => [page1, page2],
      }

      pages = site.taxonomy_pages("tags", "crystal")
      pages.size.should eq(2)
      pages.should contain(page1)
      pages.should contain(page2)
    end
  end

  describe "collections" do
    it "can add pages" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      page = Hwaro::Models::Page.new("test.md")
      site.pages << page

      site.pages.size.should eq(1)
      site.pages.first.should eq(page)
    end

    it "can add sections" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      section = Hwaro::Models::Section.new("blog/index.md")
      site.sections << section

      site.sections.size.should eq(1)
      site.sections.first.should eq(section)
    end

    it "can add taxonomies" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      page = Hwaro::Models::Page.new("test.md")
      site.taxonomies["categories"] = {"tech" => [page]}

      site.taxonomies.has_key?("categories").should be_true
      site.taxonomies["categories"]["tech"].should eq([page])
    end
  end
end

describe Hwaro::Models::TocHeader do
  describe "#initialize" do
    it "creates a TOC header with required properties" do
      header = Hwaro::Models::TocHeader.new(
        level: 2,
        id: "introduction",
        title: "Introduction",
        permalink: "#introduction"
      )

      header.level.should eq(2)
      header.id.should eq("introduction")
      header.title.should eq("Introduction")
      header.permalink.should eq("#introduction")
      header.children.should eq([] of Hwaro::Models::TocHeader)
    end
  end

  describe "hierarchy" do
    it "can add children" do
      parent = Hwaro::Models::TocHeader.new(
        level: 2,
        id: "chapter-1",
        title: "Chapter 1",
        permalink: "#chapter-1"
      )

      child1 = Hwaro::Models::TocHeader.new(
        level: 3,
        id: "section-1-1",
        title: "Section 1.1",
        permalink: "#section-1-1"
      )

      child2 = Hwaro::Models::TocHeader.new(
        level: 3,
        id: "section-1-2",
        title: "Section 1.2",
        permalink: "#section-1-2"
      )

      parent.children << child1
      parent.children << child2

      parent.children.size.should eq(2)
      parent.children[0].title.should eq("Section 1.1")
      parent.children[1].title.should eq("Section 1.2")
    end

    it "can have nested children" do
      h2 = Hwaro::Models::TocHeader.new(level: 2, id: "h2", title: "H2", permalink: "#h2")
      h3 = Hwaro::Models::TocHeader.new(level: 3, id: "h3", title: "H3", permalink: "#h3")
      h4 = Hwaro::Models::TocHeader.new(level: 4, id: "h4", title: "H4", permalink: "#h4")

      h3.children << h4
      h2.children << h3

      h2.children.size.should eq(1)
      h2.children[0].children.size.should eq(1)
      h2.children[0].children[0].level.should eq(4)
    end
  end

  describe "property setters" do
    it "can update level" do
      header = Hwaro::Models::TocHeader.new(level: 2, id: "test", title: "Test", permalink: "#test")
      header.level = 3
      header.level.should eq(3)
    end

    it "can update id" do
      header = Hwaro::Models::TocHeader.new(level: 2, id: "old-id", title: "Test", permalink: "#old-id")
      header.id = "new-id"
      header.id.should eq("new-id")
    end

    it "can update title" do
      header = Hwaro::Models::TocHeader.new(level: 2, id: "test", title: "Old Title", permalink: "#test")
      header.title = "New Title"
      header.title.should eq("New Title")
    end

    it "can update permalink" do
      header = Hwaro::Models::TocHeader.new(level: 2, id: "test", title: "Test", permalink: "#old")
      header.permalink = "#new"
      header.permalink.should eq("#new")
    end
  end
end
