require "../spec_helper"

describe Hwaro::Models::Site do
  describe "#all_content" do
    it "returns combined pages and sections sorted by path" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("blog/post1.md")
      page2 = Hwaro::Models::Page.new("about.md")
      section = Hwaro::Models::Section.new("blog/_index.md")

      site.pages << page1
      site.pages << page2
      site.sections << section

      all = site.all_content
      all.size.should eq(3)
      # Should be sorted by path
      all.map(&.path).should eq(["about.md", "blog/_index.md", "blog/post1.md"])
    end

    it "returns empty array when no content exists" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      all = site.all_content
      all.should be_empty
    end

    it "returns only pages when no sections exist" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("a.md")
      page2 = Hwaro::Models::Page.new("b.md")
      site.pages << page1
      site.pages << page2

      all = site.all_content
      all.size.should eq(2)
      all.map(&.path).should eq(["a.md", "b.md"])
    end

    it "returns only sections when no pages exist" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      section = Hwaro::Models::Section.new("docs/_index.md")
      site.sections << section

      all = site.all_content
      all.size.should eq(1)
      all.first.path.should eq("docs/_index.md")
    end

    it "includes sections as Page types" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      section = Hwaro::Models::Section.new("blog/_index.md")
      site.sections << section

      all = site.all_content
      all.first.is_a?(Hwaro::Models::Page).should be_true
    end

    it "sorts mixed content correctly by path" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      site.pages << Hwaro::Models::Page.new("z_page.md")
      site.pages << Hwaro::Models::Page.new("a_page.md")
      site.sections << Hwaro::Models::Section.new("m_section/_index.md")
      site.pages << Hwaro::Models::Page.new("c_page.md")
      site.sections << Hwaro::Models::Section.new("b_section/_index.md")

      all = site.all_content
      all.size.should eq(5)
      paths = all.map(&.path)
      paths.should eq(paths.sort)
    end
  end

  describe "#build_lookup_index" do
    it "builds pages_by_section index" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("blog/post1.md")
      page1.section = "blog"

      page2 = Hwaro::Models::Page.new("blog/post2.md")
      page2.section = "blog"

      page3 = Hwaro::Models::Page.new("docs/guide.md")
      page3.section = "docs"

      site.pages << page1
      site.pages << page2
      site.pages << page3

      site.build_lookup_index

      site.pages_by_section["blog"].size.should eq(2)
      site.pages_by_section["docs"].size.should eq(1)
    end

    it "builds sections_by_parent index" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      archive = Hwaro::Models::Section.new("blog/archive/_index.md")
      archive.section = "blog/archive"

      docs = Hwaro::Models::Section.new("docs/_index.md")
      docs.section = "docs"

      site.sections << blog
      site.sections << archive
      site.sections << docs

      site.build_lookup_index

      # "blog" is a child of root ("")
      site.sections_by_parent[""].should contain(blog)
      site.sections_by_parent[""].should contain(docs)
      # "blog/archive" is a child of "blog"
      site.sections_by_parent["blog"].should contain(archive)
    end

    it "clears previous index data before rebuilding" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("blog/post1.md")
      page1.section = "blog"
      site.pages << page1

      site.build_lookup_index
      site.pages_by_section["blog"].size.should eq(1)

      # Remove the page and rebuild
      site.pages.clear
      page2 = Hwaro::Models::Page.new("docs/guide.md")
      page2.section = "docs"
      site.pages << page2

      site.build_lookup_index
      site.pages_by_section.has_key?("blog").should be_false
      site.pages_by_section["docs"].size.should eq(1)
    end

    it "clears pages_for_section cache on rebuild" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      page = Hwaro::Models::Page.new("blog/post.md")
      page.section = "blog"

      site.sections << blog
      site.pages << page

      site.build_lookup_index

      # Call pages_for_section to populate cache
      result1 = site.pages_for_section("blog", nil)
      result1.size.should eq(1)

      # Add another page and rebuild
      page2 = Hwaro::Models::Page.new("blog/post2.md")
      page2.section = "blog"
      site.pages << page2

      site.build_lookup_index

      result2 = site.pages_for_section("blog", nil)
      result2.size.should eq(2)
    end

    it "handles root section (empty string) correctly" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      root = Hwaro::Models::Section.new("_index.md")
      root.section = ""

      page = Hwaro::Models::Page.new("about.md")
      page.section = ""

      site.sections << root
      site.pages << page

      site.build_lookup_index

      site.pages_by_section[""].should contain(page)
      # Root section itself should not appear in sections_by_parent
      # because we skip empty sections in the parent indexing
      site.sections_by_parent.has_key?("").should be_false
    end

    it "handles sections with nested paths" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      docs = Hwaro::Models::Section.new("docs/_index.md")
      docs.section = "docs"

      guide = Hwaro::Models::Section.new("docs/guide/_index.md")
      guide.section = "docs/guide"

      advanced = Hwaro::Models::Section.new("docs/guide/advanced/_index.md")
      advanced.section = "docs/guide/advanced"

      site.sections << docs
      site.sections << guide
      site.sections << advanced

      site.build_lookup_index

      site.sections_by_parent[""].should contain(docs)
      site.sections_by_parent["docs"].should contain(guide)
      site.sections_by_parent["docs/guide"].should contain(advanced)
    end
  end

  describe "#pages_for_section (with lookup index)" do
    it "returns direct pages for a section" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      post1 = Hwaro::Models::Page.new("blog/post1.md")
      post1.section = "blog"
      post1.title = "Post 1"

      post2 = Hwaro::Models::Page.new("blog/post2.md")
      post2.section = "blog"
      post2.title = "Post 2"

      site.sections << blog
      site.pages << post1
      site.pages << post2

      site.build_lookup_index

      pages = site.pages_for_section("blog", nil)
      pages.size.should eq(2)
      pages.map(&.title).should contain("Post 1")
      pages.map(&.title).should contain("Post 2")
    end

    it "includes non-transparent subsections as items" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      archive = Hwaro::Models::Section.new("blog/archive/_index.md")
      archive.section = "blog/archive"
      archive.title = "Archive"
      archive.transparent = false

      post1 = Hwaro::Models::Page.new("blog/post1.md")
      post1.section = "blog"
      post1.title = "Post 1"

      site.sections << blog
      site.sections << archive
      site.pages << post1

      site.build_lookup_index

      pages = site.pages_for_section("blog", nil)
      pages.size.should eq(2)
      pages.should contain(post1)
      pages.should contain(archive)
    end

    it "bubbles up pages from transparent subsections" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      archive = Hwaro::Models::Section.new("blog/archive/_index.md")
      archive.section = "blog/archive"
      archive.transparent = true

      archived_post = Hwaro::Models::Page.new("blog/archive/old.md")
      archived_post.section = "blog/archive"
      archived_post.title = "Old Post"

      site.sections << blog
      site.sections << archive
      site.pages << archived_post

      site.build_lookup_index

      pages = site.pages_for_section("blog", nil)
      pages.size.should eq(1)
      pages.should contain(archived_post)
      pages.should_not contain(archive)
    end

    it "recursively bubbles up through nested transparent sections" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      archive = Hwaro::Models::Section.new("blog/archive/_index.md")
      archive.section = "blog/archive"
      archive.transparent = true

      year = Hwaro::Models::Section.new("blog/archive/2024/_index.md")
      year.section = "blog/archive/2024"
      year.transparent = true

      deep_post = Hwaro::Models::Page.new("blog/archive/2024/deep.md")
      deep_post.section = "blog/archive/2024"
      deep_post.title = "Deep Post"

      site.sections << blog
      site.sections << archive
      site.sections << year
      site.pages << deep_post

      site.build_lookup_index

      pages = site.pages_for_section("blog", nil)
      pages.size.should eq(1)
      pages.should contain(deep_post)
    end

    it "filters pages by language" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      en_post = Hwaro::Models::Page.new("blog/post.md")
      en_post.section = "blog"
      en_post.language = "en"
      en_post.title = "English Post"

      ko_post = Hwaro::Models::Page.new("blog/post.ko.md")
      ko_post.section = "blog"
      ko_post.language = "ko"
      ko_post.title = "Korean Post"

      site.sections << blog
      site.pages << en_post
      site.pages << ko_post

      site.build_lookup_index

      en_pages = site.pages_for_section("blog", "en")
      en_pages.size.should eq(1)
      en_pages.first.title.should eq("English Post")

      ko_pages = site.pages_for_section("blog", "ko")
      ko_pages.size.should eq(1)
      ko_pages.first.title.should eq("Korean Post")
    end

    it "caches pages_for_section results" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      post = Hwaro::Models::Page.new("blog/post.md")
      post.section = "blog"
      post.title = "Post"

      site.sections << blog
      site.pages << post

      site.build_lookup_index

      # First call populates cache
      result1 = site.pages_for_section("blog", nil)
      # Second call should return cached result
      result2 = site.pages_for_section("blog", nil)

      result1.should eq(result2)
      result1.size.should eq(1)
    end

    it "returns empty array for section with no pages" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"
      site.sections << blog

      site.build_lookup_index

      pages = site.pages_for_section("blog", nil)
      pages.should be_empty
    end

    it "returns empty array for non-existent section" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      site.build_lookup_index

      pages = site.pages_for_section("nonexistent", nil)
      pages.should be_empty
    end

    it "handles mixed transparent and non-transparent subsections" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      transparent_sub = Hwaro::Models::Section.new("blog/transparent/_index.md")
      transparent_sub.section = "blog/transparent"
      transparent_sub.transparent = true
      transparent_sub.title = "Transparent"

      opaque_sub = Hwaro::Models::Section.new("blog/opaque/_index.md")
      opaque_sub.section = "blog/opaque"
      opaque_sub.transparent = false
      opaque_sub.title = "Opaque"

      transparent_post = Hwaro::Models::Page.new("blog/transparent/post.md")
      transparent_post.section = "blog/transparent"
      transparent_post.title = "Transparent Post"

      opaque_post = Hwaro::Models::Page.new("blog/opaque/post.md")
      opaque_post.section = "blog/opaque"
      opaque_post.title = "Opaque Post"

      direct_post = Hwaro::Models::Page.new("blog/direct.md")
      direct_post.section = "blog"
      direct_post.title = "Direct Post"

      site.sections << blog
      site.sections << transparent_sub
      site.sections << opaque_sub
      site.pages << transparent_post
      site.pages << opaque_post
      site.pages << direct_post

      site.build_lookup_index

      pages = site.pages_for_section("blog", nil)
      # Should include: direct_post, opaque_sub (as section item), transparent_post (bubbled up)
      pages.map(&.title).should contain("Direct Post")
      pages.map(&.title).should contain("Opaque")
      pages.map(&.title).should contain("Transparent Post")
      # Transparent section itself should NOT be in the list
      pages.should_not contain(transparent_sub)
      # Opaque post should NOT bubble up to blog level
      pages.map(&.title).should_not contain("Opaque Post")
    end

    it "handles root section with transparent child" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      root = Hwaro::Models::Section.new("_index.md")
      root.section = ""

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"
      blog.transparent = true
      blog.title = "Blog"

      blog_post = Hwaro::Models::Page.new("blog/post.md")
      blog_post.section = "blog"
      blog_post.title = "Blog Post"

      root_page = Hwaro::Models::Page.new("about.md")
      root_page.section = ""
      root_page.title = "About"

      site.sections << root
      site.sections << blog
      site.pages << blog_post
      site.pages << root_page

      site.build_lookup_index

      pages = site.pages_for_section("", nil)
      pages.map(&.title).should contain("About")
      pages.map(&.title).should contain("Blog Post")
      pages.should_not contain(blog)
    end

    it "handles section name with leading/trailing slashes" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      post = Hwaro::Models::Page.new("blog/post.md")
      post.section = "blog"
      post.title = "Post"

      site.sections << blog
      site.pages << post

      site.build_lookup_index

      # Should normalize section names with slashes
      pages = site.pages_for_section("/blog/", nil)
      pages.size.should eq(1)
      pages.first.title.should eq("Post")
    end

    it "handles section name with extra whitespace" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      post = Hwaro::Models::Page.new("blog/post.md")
      post.section = "blog"
      post.title = "Post"

      site.sections << blog
      site.pages << post

      site.build_lookup_index

      pages = site.pages_for_section("  blog  ", nil)
      pages.size.should eq(1)
      pages.first.title.should eq("Post")
    end

    it "separates pages by different section names" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      docs = Hwaro::Models::Section.new("docs/_index.md")
      docs.section = "docs"

      blog_post = Hwaro::Models::Page.new("blog/post.md")
      blog_post.section = "blog"
      blog_post.title = "Blog Post"

      doc_page = Hwaro::Models::Page.new("docs/guide.md")
      doc_page.section = "docs"
      doc_page.title = "Guide"

      site.sections << blog
      site.sections << docs
      site.pages << blog_post
      site.pages << doc_page

      site.build_lookup_index

      blog_pages = site.pages_for_section("blog", nil)
      blog_pages.size.should eq(1)
      blog_pages.first.title.should eq("Blog Post")

      docs_pages = site.pages_for_section("docs", nil)
      docs_pages.size.should eq(1)
      docs_pages.first.title.should eq("Guide")
    end

    it "filters transparent subsection pages by language" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      archive = Hwaro::Models::Section.new("blog/archive/_index.md")
      archive.section = "blog/archive"
      archive.transparent = true
      archive.language = "en"

      en_post = Hwaro::Models::Page.new("blog/archive/post.md")
      en_post.section = "blog/archive"
      en_post.language = "en"
      en_post.title = "English Archived"

      ko_archive = Hwaro::Models::Section.new("blog/archive/_index.ko.md")
      ko_archive.section = "blog/archive"
      ko_archive.transparent = true
      ko_archive.language = "ko"

      ko_post = Hwaro::Models::Page.new("blog/archive/post.ko.md")
      ko_post.section = "blog/archive"
      ko_post.language = "ko"
      ko_post.title = "Korean Archived"

      site.sections << blog
      site.sections << archive
      site.sections << ko_archive
      site.pages << en_post
      site.pages << ko_post

      site.build_lookup_index

      en_pages = site.pages_for_section("blog", "en")
      en_pages.size.should eq(1)
      en_pages.first.title.should eq("English Archived")

      ko_pages = site.pages_for_section("blog", "ko")
      ko_pages.size.should eq(1)
      ko_pages.first.title.should eq("Korean Archived")
    end
  end

  describe "#pages_for_section (without lookup index)" do
    it "returns direct pages using unoptimized path" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      post = Hwaro::Models::Page.new("blog/post.md")
      post.section = "blog"
      post.title = "Post"

      site.sections << blog
      site.pages << post

      # Do NOT call build_lookup_index - uses unoptimized path
      pages = site.pages_for_section("blog", nil)
      pages.size.should eq(1)
      pages.first.title.should eq("Post")
    end

    it "bubbles up transparent section pages without index" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      archive = Hwaro::Models::Section.new("blog/archive/_index.md")
      archive.section = "blog/archive"
      archive.transparent = true

      archived_post = Hwaro::Models::Page.new("blog/archive/old.md")
      archived_post.section = "blog/archive"
      archived_post.title = "Old Post"

      site.sections << blog
      site.sections << archive
      site.pages << archived_post

      pages = site.pages_for_section("blog", nil)
      pages.size.should eq(1)
      pages.should contain(archived_post)
    end

    it "produces same results as optimized path" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      blog = Hwaro::Models::Section.new("blog/_index.md")
      blog.section = "blog"

      archive = Hwaro::Models::Section.new("blog/archive/_index.md")
      archive.section = "blog/archive"
      archive.transparent = true

      post1 = Hwaro::Models::Page.new("blog/direct.md")
      post1.section = "blog"
      post1.title = "Direct"

      post2 = Hwaro::Models::Page.new("blog/archive/old.md")
      post2.section = "blog/archive"
      post2.title = "Old"

      site.sections << blog
      site.sections << archive
      site.pages << post1
      site.pages << post2

      # Unoptimized
      result1 = site.pages_for_section("blog", nil)

      # Optimized
      site.build_lookup_index
      result2 = site.pages_for_section("blog", nil)

      result1.size.should eq(result2.size)
      result1.map(&.title).sort.should eq(result2.map(&.title).sort)
    end
  end

  describe "#taxonomy_terms" do
    it "returns sorted terms for a taxonomy" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      page = Hwaro::Models::Page.new("test.md")
      site.taxonomies["tags"] = {
        "crystal"     => [page],
        "programming" => [page],
        "web"         => [page],
      }

      terms = site.taxonomy_terms("tags")
      terms.should eq(["crystal", "programming", "web"])
    end

    it "returns empty array for unknown taxonomy" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      site.taxonomy_terms("nonexistent").should eq([] of String)
    end
  end

  describe "#taxonomy_pages" do
    it "returns pages for a given taxonomy term" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("post1.md")
      page1.title = "Post 1"
      page2 = Hwaro::Models::Page.new("post2.md")
      page2.title = "Post 2"

      site.taxonomies["tags"] = {
        "crystal" => [page1, page2],
      }

      pages = site.taxonomy_pages("tags", "crystal")
      pages.size.should eq(2)
    end

    it "returns empty array for unknown term" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      page = Hwaro::Models::Page.new("test.md")
      site.taxonomies["tags"] = {"other" => [page]}

      site.taxonomy_pages("tags", "nonexistent").should eq([] of Hwaro::Models::Page)
    end

    it "returns empty array for unknown taxonomy" do
      config = Hwaro::Models::Config.new
      site = Hwaro::Models::Site.new(config)

      site.taxonomy_pages("nonexistent", "term").should eq([] of Hwaro::Models::Page)
    end
  end
end
