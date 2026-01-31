require "../spec_helper"

describe Hwaro::Models::Site do
  describe "#pages_for_section" do
    it "returns direct pages for a non-transparent section" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      post1 = Hwaro::Models::Page.new("blog/post1.md")
      post1.section = "blog"
      post1.title = "Post 1"

      archive = Hwaro::Models::Section.new("blog/archive/_index.md")
      archive.section = "blog/archive"
      archive.title = "Archive"

      site.sections << blog
      site.sections << archive
      site.pages << post1

      # When listing pages for "blog", we want post1 and archive
      pages = site.pages_for_section("blog", nil)
      pages.size.should eq(2)
      pages.should contain(post1)
      pages.should contain(archive)
    end

    it "bubbles up pages from a transparent section" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      archive = Hwaro::Models::Section.new("blog/archive/_index.md")
      archive.section = "blog/archive"
      archive.transparent = true

      post2 = Hwaro::Models::Page.new("blog/archive/post2.md")
      post2.section = "blog/archive"
      post2.title = "Post 2"

      site.sections << blog
      site.sections << archive
      site.pages << post2

      # When listing pages for "blog", archive is transparent, so post2 should bubble up
      pages = site.pages_for_section("blog", nil)
      pages.size.should eq(1)
      pages.should contain(post2)
      pages.should_not contain(archive)
    end

    it "bubbles up recursively" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      archive = Hwaro::Models::Section.new("blog/archive/_index.md")
      archive.section = "blog/archive"
      archive.transparent = true

      year2024 = Hwaro::Models::Section.new("blog/archive/2024/_index.md")
      year2024.section = "blog/archive/2024"
      year2024.transparent = true

      post3 = Hwaro::Models::Page.new("blog/archive/2024/post3.md")
      post3.section = "blog/archive/2024"
      post3.title = "Post 3"

      site.sections << blog
      site.sections << archive
      site.sections << year2024
      site.pages << post3

      # "blog" -> "blog/archive" (transparent) -> "blog/archive/2024" (transparent) -> post3
      pages = site.pages_for_section("blog", nil)
      pages.size.should eq(1)
      pages.should contain(post3)
      pages.should_not contain(archive)
      pages.should_not contain(year2024)
    end

    it "handles root section correctly" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      root = Hwaro::Models::Section.new("_index.md")
      root.section = ""

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"
      blog.transparent = true

      post1 = Hwaro::Models::Page.new("blog/post1.md")
      post1.section = "blog"
      post1.title = "Post 1"

      about = Hwaro::Models::Page.new("about.md")
      about.section = ""
      about.title = "About"

      site.sections << root
      site.sections << blog
      site.pages << post1
      site.pages << about

      # Root should contain "about.md" and bubbled up "post1.md"
      pages = site.pages_for_section("", nil)
      pages.size.should eq(2)
      pages.should contain(about)
      pages.should contain(post1)
      pages.should_not contain(blog)
    end

    it "filters by language" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog_en = Hwaro::Models::Section.new("blog/_index.md")
      blog_en.section = "blog"
      blog_en.language = "en"

      post_en = Hwaro::Models::Page.new("blog/post.md")
      post_en.section = "blog"
      post_en.language = "en"

      post_ko = Hwaro::Models::Page.new("blog/post.ko.md")
      post_ko.section = "blog"
      post_ko.language = "ko"

      site.sections << blog_en
      site.pages << post_en
      site.pages << post_ko

      pages_en = site.pages_for_section("blog", "en")
      pages_en.size.should eq(1)
      pages_en.should contain(post_en)

      pages_ko = site.pages_for_section("blog", "ko")
      pages_ko.size.should eq(1)
      pages_ko.should contain(post_ko)
    end
  end
end
