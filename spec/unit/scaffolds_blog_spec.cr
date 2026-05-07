require "../spec_helper"
require "../../src/services/scaffolds/blog"

describe Hwaro::Services::Scaffolds::Blog do
  describe "#content_files" do
    it "generates content with taxonomies by default" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      files = scaffold.content_files(skip_taxonomies: false)

      # Check index.md
      files["index.md"].should contain("tags = [\"home\"]")
      files["index.md"].should contain("Check out the latest posts in the [Posts](/posts/) section, or browse by:")
      files["index.md"].should contain("- [Tags](/tags/)")

      # Check about.md
      files["about.md"].should contain("tags = [\"about\"]")
      files["about.md"].should contain("categories = [\"pages\"]")

      # Check posts
      files["posts/hello-world.md"].should contain("tags = [\"introduction\", \"hello\"]")
      files["posts/hello-world.md"].should contain("categories = [\"general\"]")
      files["posts/hello-world.md"].should contain("authors = [\"admin\"]")
      files["posts/hello-world.md"].should match(/date = "\d{4}-\d{2}-\d{2}"/)
    end

    it "generates content without taxonomies when requested" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      files = scaffold.content_files(skip_taxonomies: true)

      # Check index.md
      files["index.md"].should_not contain("tags =")
      files["index.md"].should contain("Check out the latest posts in the [Posts](/posts/) section.")
      files["index.md"].should_not contain("or browse by:")
      files["index.md"].should_not contain("- [Tags](/tags/)")

      # Check about.md
      files["about.md"].should_not contain("tags =")
      files["about.md"].should_not contain("categories =")

      # Check posts
      files["posts/hello-world.md"].should_not contain("tags =")
      files["posts/hello-world.md"].should_not contain("categories =")
      files["posts/hello-world.md"].should_not contain("authors =")

      # Date should still be present
      files["posts/hello-world.md"].should match(/date = "\d{4}-\d{2}-\d{2}"/)
    end
  end

  # Regression for gh#523: blog `archives.md` used to be a one-line
  # placeholder ("Browse all posts by date.") with no template logic
  # to actually list anything. The scaffold now ships a working
  # `templates/archives.html` and points the page at it.
  describe "archives" do
    it "ships an archives.html template that iterates site.pages (gh#523)" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      tpl = scaffold.template_files["archives.html"]?
      tpl.should_not be_nil
      tpl = tpl.not_nil!
      tpl.should contain(%[sort(attribute="date", reverse=true)])
      tpl.should contain("archive-list")
    end

    # The first version of the archives template hardcoded
    # `selectattr("section", "equalto", "posts")`, so renaming the
    # `posts/` section silently produced an empty archives page even
    # though `/archives/` was still in the header nav. The template
    # now filters by `date` truthiness so any dated leaf page shows
    # up regardless of its section name.
    it "filters by date rather than a hardcoded section name" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      tpl = scaffold.template_files["archives.html"].not_nil!
      tpl.should contain(%[selectattr("date")])
      tpl.should_not contain(%[selectattr("section", "equalto", "posts")])
      tpl.should contain(%[rejectattr("draft")])
      tpl.should contain(%[rejectattr("is_index")])
    end

    it "wires archives.md to the archives template (gh#523)" do
      scaffold = Hwaro::Services::Scaffolds::Blog.new
      content = scaffold.content_files["archives.md"]
      content.should contain(%[template = "archives"])
    end
  end
end
