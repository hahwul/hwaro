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

    it "disambiguates distinct terms that slugify identically (no silent overwrite)" do
      config = Hwaro::Models::Config.new
      config.taxonomies = [Hwaro::Models::TaxonomyConfig.new("tags")]
      site = Hwaro::Models::Site.new(config)

      # "C++" and "C#" both slugify to "c"; without disambiguation one term
      # page overwrites the other and the index links both to the same URL.
      page1 = Hwaro::Models::Page.new("post1.md")
      page1.title = "Post 1"
      page1.url = "/blog/post1/"
      page1.tags = ["C++"]
      page1.draft = false
      page1.generated = false

      page2 = Hwaro::Models::Page.new("post2.md")
      page2.title = "Post 2"
      page2.url = "/blog/post2/"
      page2.tags = ["C#"]
      page2.draft = false
      page2.generated = false

      site.pages = [page1, page2]

      Dir.mktmpdir do |output_dir|
        templates = {
          "taxonomy"      => "<html>{{ content }}</html>",
          "taxonomy_term" => "<html>{{ content }}</html>",
        }
        Hwaro::Content::Taxonomies.generate(site, output_dir, templates)

        # Both distinct term pages must be written, not collapsed onto one.
        term_dirs = Dir.children(File.join(output_dir, "tags")).reject { |c| c == "index.html" }
        term_dirs.size.should eq(2)

        # The index lists both raw terms.
        index = File.read(File.join(output_dir, "tags", "index.html"))
        index.should contain("C++")
        index.should contain("C#")
      end
    end

    it "exposes get_taxonomy slugs (__taxonomy_slugs__) that match the written term-page paths" do
      # The slug map build_global_vars exposes to get_taxonomy / get_taxonomy_url
      # must point at the pages the generator actually wrote, even on a collision.
      config = Hwaro::Models::Config.new
      config.taxonomies = [Hwaro::Models::TaxonomyConfig.new("tags")]
      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("post1.md")
      page1.title = "Post 1"
      page1.url = "/blog/post1/"
      page1.tags = ["C++"]
      page2 = Hwaro::Models::Page.new("post2.md")
      page2.title = "Post 2"
      page2.url = "/blog/post2/"
      page2.tags = ["C#"]
      site.pages = [page1, page2]

      Dir.mktmpdir do |output_dir|
        templates = {
          "taxonomy"      => "<html>{{ content }}</html>",
          "taxonomy_term" => "<html>{{ content }}</html>",
        }
        # Writes the term pages and populates site.taxonomies.
        Hwaro::Content::Taxonomies.generate(site, output_dir, templates)

        vars = Hwaro::Core::Build::Builder.new.global_template_vars(site)
        slugs_raw = vars["__taxonomy_slugs__"].raw
        slugs_raw.should be_a(Hash(Crinja::Value, Crinja::Value))
        tags_raw = slugs_raw.as(Hash(Crinja::Value, Crinja::Value))["tags"].raw.as(Hash(Crinja::Value, Crinja::Value))
        cpp_slug = tags_raw["C++"].to_s
        cs_slug = tags_raw["C#"].to_s

        cpp_slug.should_not eq(cs_slug)
        # Each exposed slug resolves to a real written term page (no dead link).
        File.exists?(File.join(output_dir, "tags", cpp_slug, "index.html")).should be_true
        File.exists?(File.join(output_dir, "tags", cs_slug, "index.html")).should be_true
      end
    end

    it "keeps a published term's slug stable when a draft-only term collides (--drafts)" do
      # Under --drafts the render-phase taxonomy map includes draft pages, but
      # the generator skips drafts. The exposed slug for the PUBLISHED term must
      # match the page the generator actually writes — a draft-only colliding
      # term must not steal the base slug and shift the published term to a
      # never-written "-N" path.
      config = Hwaro::Models::Config.new
      config.taxonomies = [Hwaro::Models::TaxonomyConfig.new("tags")]
      site = Hwaro::Models::Site.new(config)

      published = Hwaro::Models::Page.new("pub.md")
      published.title = "Published"
      published.url = "/blog/pub/"
      published.tags = ["C++"]
      published.draft = false
      draft = Hwaro::Models::Page.new("draft.md")
      draft.title = "Draft"
      draft.url = "/blog/draft/"
      draft.tags = ["C#"]
      draft.draft = true
      site.pages = [published, draft]

      # Simulate the render-phase map under --drafts: the draft term IS present
      # (rebuild_taxonomies does not filter drafts) and sorts before "C++".
      site.taxonomies["tags"] = {
        "C#"  => [draft] of Hwaro::Models::Page,
        "C++" => [published] of Hwaro::Models::Page,
      }

      vars = Hwaro::Core::Build::Builder.new.global_template_vars(site)
      tags_raw = vars["__taxonomy_slugs__"].raw.as(Hash(Crinja::Value, Crinja::Value))["tags"].raw.as(Hash(Crinja::Value, Crinja::Value))
      cpp_slug = tags_raw["C++"].to_s
      # Published term keeps the base slug (draft excluded from disambiguation).
      cpp_slug.should eq("c")

      Dir.mktmpdir do |output_dir|
        templates = {
          "taxonomy"      => "<html>{{ content }}</html>",
          "taxonomy_term" => "<html>{{ content }}</html>",
        }
        # generate rebuilds site.taxonomies draft-free and writes /tags/c/.
        Hwaro::Content::Taxonomies.generate(site, output_dir, templates)
        File.exists?(File.join(output_dir, "tags", cpp_slug, "index.html")).should be_true
      end
    end

    it "does not expose a root slug for a term present only in a non-default language" do
      # On a multilingual site the root term page is written only for terms with
      # a default-language page. A non-default-only colliding term gets no root
      # page, so its disambiguated "-N" slug must NOT be exposed — get_taxonomy_url
      # falls back to safe_slugify (the existing base-slug page) instead of a 404.
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
      config.taxonomies = [Hwaro::Models::TaxonomyConfig.new("tags")]
      site = Hwaro::Models::Site.new(config)

      en = Hwaro::Models::Page.new("en.md")
      en.title = "En"
      en.url = "/blog/en/"
      en.tags = ["C"]
      en.language = "en"
      ko = Hwaro::Models::Page.new("ko.md")
      ko.title = "Ko"
      ko.url = "/ko/blog/ko/"
      ko.tags = ["C#"] # collides with "C" -> base slug "c"
      ko.language = "ko"
      site.pages = [en, ko]
      site.taxonomies["tags"] = {
        "C"  => [en] of Hwaro::Models::Page,
        "C#" => [ko] of Hwaro::Models::Page,
      }

      vars = Hwaro::Core::Build::Builder.new.global_template_vars(site)
      tags_raw = vars["__taxonomy_slugs__"].raw.as(Hash(Crinja::Value, Crinja::Value))["tags"].raw.as(Hash(Crinja::Value, Crinja::Value))

      # Default-language term is exposed with the base slug it was written at.
      tags_raw["C"].to_s.should eq("c")
      # Non-default-only term is omitted (falls back to safe_slugify downstream).
      tags_raw.has_key?(Crinja::Value.new("C#")).should be_false
    end

    it "still renders a configured taxonomy's index when it has zero terms (no 404)" do
      config = Hwaro::Models::Config.new
      config.taxonomies = [Hwaro::Models::TaxonomyConfig.new("tags")]
      site = Hwaro::Models::Site.new(config)

      # The taxonomy is configured but no page carries a tag, so it collects no
      # terms. The index must still be generated so site-internal links like the
      # scaffold homepage's `/tags/` don't 404 after a user removes the samples.
      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/blog/post/"
      page.draft = false
      page.generated = false
      site.pages = [page]

      Dir.mktmpdir do |output_dir|
        templates = {
          "taxonomy"      => "<html>{{ content }}</html>",
          "taxonomy_term" => "<html>{{ content }}</html>",
        }
        Hwaro::Content::Taxonomies.generate(site, output_dir, templates)

        File.exists?(File.join(output_dir, "tags", "index.html")).should be_true
        # No term pages, just the (empty) index.
        Dir.glob(File.join(output_dir, "tags", "*", "index.html")).should be_empty
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

    # Regression for https://github.com/hahwul/hwaro/issues/485
    # `authors` is stored on a dedicated `page.authors` property (so the
    # `site.authors` aggregation can use it) rather than in `page.taxonomies`.
    # The taxonomy generator used to special-case only `tags`, so configuring
    # `[[taxonomies]] name = "authors"` silently produced no listing pages.
    it "generates index and term pages for the `authors` taxonomy" do
      config = Hwaro::Models::Config.new
      config.taxonomies = [Hwaro::Models::TaxonomyConfig.new("authors")]

      site = Hwaro::Models::Site.new(config)

      page1 = Hwaro::Models::Page.new("post1.md")
      page1.title = "Post 1"
      page1.url = "/post1/"
      page1.authors = ["alice", "bob"]
      page1.draft = false
      page1.generated = false
      page1.front_matter_keys = ["title", "authors"]

      page2 = Hwaro::Models::Page.new("post2.md")
      page2.title = "Post 2"
      page2.url = "/post2/"
      page2.authors = ["alice"]
      page2.draft = false
      page2.generated = false
      page2.front_matter_keys = ["title", "authors"]

      site.pages = [page1, page2]

      Dir.mktmpdir do |output_dir|
        templates = {
          "taxonomy"      => "<html>{{ content }}</html>",
          "taxonomy_term" => "<html>{{ content }}</html>",
        }

        Hwaro::Content::Taxonomies.generate(site, output_dir, templates)

        File.exists?(File.join(output_dir, "authors", "index.html")).should be_true
        File.exists?(File.join(output_dir, "authors", "alice", "index.html")).should be_true
        File.exists?(File.join(output_dir, "authors", "bob", "index.html")).should be_true
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
