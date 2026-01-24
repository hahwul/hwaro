require "../spec_helper"

describe Hwaro::Content::Taxonomies do
  describe ".generate" do
    it "does nothing when taxonomies are empty" do
      config = Hwaro::Models::Config.new
      config.taxonomies = [] of Hwaro::Models::TaxonomyConfig
      site = Hwaro::Models::Site.new(config)

      Dir.mktmpdir do |output_dir|
        templates = {} of String => String
        # Should not raise and should not create any files
        Hwaro::Content::Taxonomies.generate(site, output_dir, templates)
        Dir.children(output_dir).should eq([] of String)
      end
    end

    it "builds taxonomy index from pages" do
      config = Hwaro::Models::Config.new
      taxonomy_config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.taxonomies = [taxonomy_config]

      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("post1.md")
      page1.title = "Post 1"
      page1.url = "/blog/post1/"
      page1.tags = ["crystal", "programming"]
      page1.draft = false
      page1.generated = false

      page2 = Hwaro::Models::Page.new("post2.md")
      page2.title = "Post 2"
      page2.url = "/blog/post2/"
      page2.tags = ["crystal", "web"]
      page2.draft = false
      page2.generated = false

      site.pages = [page1, page2]

      Dir.mktmpdir do |output_dir|
        templates = {
          "taxonomy"      => "<html>{{ content }}</html>",
          "taxonomy_term" => "<html>{{ content }}</html>",
        }

        Hwaro::Content::Taxonomies.generate(site, output_dir, templates)

        # Check that taxonomy index was created
        File.exists?(File.join(output_dir, "tags", "index.html")).should be_true

        # Check that term pages were created
        File.exists?(File.join(output_dir, "tags", "crystal", "index.html")).should be_true
        File.exists?(File.join(output_dir, "tags", "programming", "index.html")).should be_true
        File.exists?(File.join(output_dir, "tags", "web", "index.html")).should be_true
      end
    end

    it "excludes draft pages from taxonomy" do
      config = Hwaro::Models::Config.new
      taxonomy_config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.taxonomies = [taxonomy_config]

      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("published.md")
      page1.title = "Published"
      page1.url = "/published/"
      page1.tags = ["test"]
      page1.draft = false
      page1.generated = false

      page2 = Hwaro::Models::Page.new("draft.md")
      page2.title = "Draft"
      page2.url = "/draft/"
      page2.tags = ["draft-only-tag"]
      page2.draft = true
      page2.generated = false

      site.pages = [page1, page2]

      Dir.mktmpdir do |output_dir|
        templates = {
          "taxonomy"      => "<html>{{ content }}</html>",
          "taxonomy_term" => "<html>{{ content }}</html>",
        }

        Hwaro::Content::Taxonomies.generate(site, output_dir, templates)

        # Published tag should exist
        File.exists?(File.join(output_dir, "tags", "test", "index.html")).should be_true
        # Draft-only tag should not exist
        File.exists?(File.join(output_dir, "tags", "draft-only-tag", "index.html")).should be_false
      end
    end

    it "excludes generated pages from taxonomy" do
      config = Hwaro::Models::Config.new
      taxonomy_config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.taxonomies = [taxonomy_config]

      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("normal.md")
      page1.title = "Normal"
      page1.url = "/normal/"
      page1.tags = ["normal-tag"]
      page1.draft = false
      page1.generated = false

      page2 = Hwaro::Models::Page.new("generated.md")
      page2.title = "Generated"
      page2.url = "/generated/"
      page2.tags = ["generated-tag"]
      page2.draft = false
      page2.generated = true

      site.pages = [page1, page2]

      Dir.mktmpdir do |output_dir|
        templates = {
          "taxonomy"      => "<html>{{ content }}</html>",
          "taxonomy_term" => "<html>{{ content }}</html>",
        }

        Hwaro::Content::Taxonomies.generate(site, output_dir, templates)

        # Normal tag should exist
        File.exists?(File.join(output_dir, "tags", "normal-tag", "index.html")).should be_true
        # Generated-only tag should not exist
        File.exists?(File.join(output_dir, "tags", "generated-tag", "index.html")).should be_false
      end
    end

    it "handles multiple taxonomies" do
      config = Hwaro::Models::Config.new
      tags_config = Hwaro::Models::TaxonomyConfig.new("tags")
      categories_config = Hwaro::Models::TaxonomyConfig.new("categories")
      config.taxonomies = [tags_config, categories_config]

      site = Hwaro::Models::Site.new(config)

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.tags = ["tag1"]
      page.taxonomies = {"categories" => ["cat1"]}
      page.draft = false
      page.generated = false

      site.pages = [page]

      Dir.mktmpdir do |output_dir|
        templates = {
          "taxonomy"      => "<html>{{ content }}</html>",
          "taxonomy_term" => "<html>{{ content }}</html>",
        }

        Hwaro::Content::Taxonomies.generate(site, output_dir, templates)

        # Both taxonomy indexes should exist
        File.exists?(File.join(output_dir, "tags", "index.html")).should be_true
        File.exists?(File.join(output_dir, "categories", "index.html")).should be_true

        # Both term pages should exist
        File.exists?(File.join(output_dir, "tags", "tag1", "index.html")).should be_true
        File.exists?(File.join(output_dir, "categories", "cat1", "index.html")).should be_true
      end
    end

    it "skips taxonomies with empty names" do
      config = Hwaro::Models::Config.new
      empty_taxonomy = Hwaro::Models::TaxonomyConfig.new("")
      valid_taxonomy = Hwaro::Models::TaxonomyConfig.new("tags")
      config.taxonomies = [empty_taxonomy, valid_taxonomy]

      site = Hwaro::Models::Site.new(config)

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.tags = ["tag1"]
      page.draft = false
      page.generated = false

      site.pages = [page]

      Dir.mktmpdir do |output_dir|
        templates = {
          "taxonomy"      => "<html>{{ content }}</html>",
          "taxonomy_term" => "<html>{{ content }}</html>",
        }

        # Should not raise
        Hwaro::Content::Taxonomies.generate(site, output_dir, templates)

        # Valid taxonomy should exist
        File.exists?(File.join(output_dir, "tags", "index.html")).should be_true
      end
    end

    it "slugifies term names for URLs" do
      config = Hwaro::Models::Config.new
      taxonomy_config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.taxonomies = [taxonomy_config]

      site = Hwaro::Models::Site.new(config)

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.tags = ["Crystal Programming"]
      page.draft = false
      page.generated = false

      site.pages = [page]

      Dir.mktmpdir do |output_dir|
        templates = {
          "taxonomy"      => "<html>{{ content }}</html>",
          "taxonomy_term" => "<html>{{ content }}</html>",
        }

        Hwaro::Content::Taxonomies.generate(site, output_dir, templates)

        # Should be slugified (lowercase, hyphenated)
        File.exists?(File.join(output_dir, "tags", "crystal-programming", "index.html")).should be_true
      end
    end
  end
end

describe Hwaro::Models::TaxonomyConfig do
  describe "#initialize" do
    it "creates taxonomy config with name" do
      config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.name.should eq("tags")
    end
  end

  describe "properties" do
    it "has sitemap property" do
      config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.sitemap.should be_true # Default value
    end

    it "has feed property" do
      config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.feed.should be_false # Default value
    end

    it "has paginate_by property" do
      config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.paginate_by.should be_nil # Default value
    end

    it "can set properties" do
      config = Hwaro::Models::TaxonomyConfig.new("categories")
      config.sitemap = false
      config.feed = true
      config.paginate_by = 10

      config.sitemap.should be_false
      config.feed.should be_true
      config.paginate_by.should eq(10)
    end
  end
end
