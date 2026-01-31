require "../spec_helper"

describe Hwaro::Models::Site do
  describe "#pages_for_section" do
    it "includes pages of transparent sub-sections in the parent section" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      root_section = Hwaro::Models::Section.new("_index.md")
      root_section.title = "Home"
      root_section.section = ""
      root_section.is_index = true

      blog_section = Hwaro::Models::Section.new("blog/_index.md")
      blog_section.title = "Blog"
      blog_section.section = "blog"
      blog_section.is_index = true
      blog_section.transparent = true

      post1 = Hwaro::Models::Page.new("blog/post1.md")
      post1.title = "Post 1"
      post1.section = "blog"

      about = Hwaro::Models::Page.new("about.md")
      about.title = "About"
      about.section = ""

      site.sections << root_section
      site.sections << blog_section
      site.pages << post1
      site.pages << about

      pages = site.pages_for_section("", nil)
      pages.should contain(about)
      pages.should contain(post1)
      pages.should_not contain(root_section)
      pages.should_not contain(blog_section)
    end

    it "correctly handles nested transparent sections" do
       config = Hwaro::Models::Config.new
       site = Hwaro::Models::Site.new(config)

       root = Hwaro::Models::Section.new("_index.md")
       root.section = ""
       root.is_index = true

       blog = Hwaro::Models::Section.new("blog/_index.md")
       blog.section = "blog"
       blog.is_index = true
       blog.transparent = true

       news = Hwaro::Models::Section.new("blog/news/_index.md")
       news.section = "blog/news"
       news.is_index = true
       news.transparent = true

       item = Hwaro::Models::Page.new("blog/news/item.md")
       item.section = "blog/news"

       site.sections << root << blog << news
       site.pages << item

       pages = site.pages_for_section("", nil)
       pages.should contain(item)
    end

    it "includes non-transparent sub-sections as items" do
       config = Hwaro::Models::Config.new
       site = Hwaro::Models::Site.new(config)

       blog = Hwaro::Models::Section.new("blog/_index.md")
       blog.section = "blog"
       blog.is_index = true

       news = Hwaro::Models::Section.new("blog/news/_index.md")
       news.section = "blog/news"
       news.is_index = true
       news.transparent = false

       site.sections << blog << news

       pages = site.pages_for_section("blog", nil)
       pages.should contain(news)
    end
  end
end
