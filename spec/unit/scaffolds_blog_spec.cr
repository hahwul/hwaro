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
      files["posts/hello-world.md"].should contain("date = \"2024-01-15\"")
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
      files["posts/hello-world.md"].should contain("date = \"2024-01-15\"")
    end
  end
end
