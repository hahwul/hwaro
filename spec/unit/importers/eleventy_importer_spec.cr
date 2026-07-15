require "../../spec_helper"
require "../../../src/services/importers/eleventy_importer"

describe Hwaro::Services::Importers::EleventyImporter do
  describe "#run" do
    it "imports a basic Eleventy post" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-ELEVENTY
          ---
          title: "My 11ty Post"
          date: 2024-05-01
          tags:
            - post
            - eleventy
            - ssg
          description: "A post about 11ty"
          ---
          Welcome to Eleventy.
          ELEVENTY

        File.write(File.join(posts_dir, "my-11ty-post.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "eleventy",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::EleventyImporter.new
        result = importer.run(options)

        result.success.should be_true
        result.imported_count.should eq(1)

        output_file = File.join(output_dir, "posts", "my-11ty-post.md")
        File.exists?(output_file).should be_true

        content = File.read(output_file)
        content.should contain("+++")
        content.should contain("title = \"My 11ty Post\"")
        content.should contain("description = \"A post about 11ty\"")
        # "post" collection tag should be filtered out
        content.should contain("tags = [\"eleventy\", \"ssg\"]")
        content.should contain("Welcome to Eleventy.")
      end
    end

    it "filters out collection tags (post, posts, all)" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "blog")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-ELEVENTY
          ---
          title: "Tag Filter Test"
          tags:
            - posts
            - all
            - javascript
          ---
          Content.
          ELEVENTY

        File.write(File.join(posts_dir, "tag-filter.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "eleventy",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::EleventyImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "blog", "tag-filter.md"))
        content.should contain("tags = [\"javascript\"]")
        content.should_not contain("\"posts\"")
        content.should_not contain("\"all\"")
      end
    end

    it "skips drafts when options.drafts is false" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-ELEVENTY
          ---
          title: "Draft Post"
          draft: true
          ---
          Draft content.
          ELEVENTY

        File.write(File.join(posts_dir, "draft.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "eleventy",
          path: dir,
          output_dir: output_dir,
          drafts: false,
        )

        importer = Hwaro::Services::Importers::EleventyImporter.new
        result = importer.run(options)

        result.imported_count.should eq(0)
        result.skipped_count.should eq(1)
      end
    end

    it "skips eleventyExcludeFromCollections as draft" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-ELEVENTY
          ---
          title: "Excluded Post"
          eleventyExcludeFromCollections: true
          ---
          Hidden content.
          ELEVENTY

        File.write(File.join(posts_dir, "excluded.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "eleventy",
          path: dir,
          output_dir: output_dir,
          drafts: false,
        )

        importer = Hwaro::Services::Importers::EleventyImporter.new
        result = importer.run(options)

        result.imported_count.should eq(0)
        result.skipped_count.should eq(1)
      end
    end

    it "maps layout to template" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "posts")
        FileUtils.mkdir_p(posts_dir)

        post_content = <<-ELEVENTY
          ---
          title: "Layout Test"
          layout: post.njk
          ---
          Content.
          ELEVENTY

        File.write(File.join(posts_dir, "layout-test.md"), post_content)

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "eleventy",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::EleventyImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "layout-test.md"))
        content.should contain("template = \"post.njk\"")
      end
    end

    it "skips node_modules and _site directories" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "posts")
        node_modules = File.join(dir, "node_modules", "some-pkg")
        site_dir = File.join(dir, "_site", "posts")
        FileUtils.mkdir_p(posts_dir)
        FileUtils.mkdir_p(node_modules)
        FileUtils.mkdir_p(site_dir)

        File.write(File.join(posts_dir, "real-post.md"), <<-ELEVENTY
          ---
          title: "Real Post"
          ---
          Content.
          ELEVENTY
        )

        File.write(File.join(node_modules, "readme.md"), "# Package readme")
        File.write(File.join(site_dir, "built.md"), "# Built output")

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "eleventy",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::EleventyImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)
      end
    end

    it "merges directory data defaults into posts" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "posts")
        FileUtils.mkdir_p(posts_dir)

        # Create directory data file (posts.json)
        File.write(File.join(posts_dir, "posts.json"), %({"layout": "post.njk", "tags": ["post"]}))

        # Create post without layout
        File.write(File.join(posts_dir, "data-merge.md"), <<-ELEVENTY
          ---
          title: "Data Merge Test"
          ---
          Content.
          ELEVENTY
        )

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "eleventy",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::EleventyImporter.new
        importer.run(options)

        content = File.read(File.join(output_dir, "posts", "data-merge.md"))
        content.should contain("template = \"post.njk\"")
        content.should contain("title = \"Data Merge Test\"")
      end
    end

    it "round-trips nested .11tydata.json directory data through YAML dump/reparse" do
      # Regression guard for json_any_to_yaml_any's recursive Array/Hash
      # branches and the .11tydata.json precedence path: nested objects/arrays
      # in dir-data must survive YAML.dump/reparse so the merged tags appear.
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "posts")
        FileUtils.mkdir_p(posts_dir)

        # .11tydata.json takes precedence over posts.json (untested before).
        File.write(
          File.join(posts_dir, "posts.11tydata.json"),
          %({"tags": ["a", "b"], "meta": {"k": "v"}})
        )

        File.write(File.join(posts_dir, "nested-merge.md"), <<-ELEVENTY
          ---
          title: "Nested Merge"
          ---
          Content.
          ELEVENTY
        )

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "eleventy",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::EleventyImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)
        content = File.read(File.join(output_dir, "posts", "nested-merge.md"))
        content.should contain("title = \"Nested Merge\"")
        # The nested array tags survive the dump/reparse round trip.
        content.should contain("tags = [\"a\", \"b\"]")
      end
    end

    it "lets file frontmatter win over directory data on a type conflict" do
      # dir-data provides tags as an array, the file provides a scalar string.
      # File overrides win; the merge must not error.
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "posts")
        FileUtils.mkdir_p(posts_dir)

        File.write(
          File.join(posts_dir, "posts.json"),
          %({"tags": ["a", "b"]})
        )

        File.write(File.join(posts_dir, "type-conflict.md"), <<-ELEVENTY
          ---
          title: "Type Conflict"
          tags: solo
          ---
          Content.
          ELEVENTY
        )

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "eleventy",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::EleventyImporter.new
        result = importer.run(options)

        result.imported_count.should eq(1)
        result.error_count.should eq(0)
        content = File.read(File.join(output_dir, "posts", "type-conflict.md"))
        # File's scalar value wins over the dir-data array.
        content.should contain("tags = [\"solo\"]")
        content.should_not contain("\"a\"")
        content.should_not contain("\"b\"")
      end
    end

    it "returns error result for non-existent directory" do
      options = Hwaro::Config::Options::ImportOptions.new(
        source_type: "eleventy",
        path: "/non/existent/path",
        output_dir: "/tmp/output",
      )

      importer = Hwaro::Services::Importers::EleventyImporter.new
      result = importer.run(options)

      result.success.should be_false
      result.message.should contain("not found")
    end

    it "handles bundle-index files (index.md layout) correctly" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "posts")
        bundle_a = File.join(posts_dir, "post-a")
        bundle_b = File.join(posts_dir, "post-b")
        FileUtils.mkdir_p(bundle_a)
        FileUtils.mkdir_p(bundle_b)

        # File at root of collection posts/index.md (without title) should still be skipped
        File.write(File.join(posts_dir, "index.md"), "Content at root index.")

        # Files at nested folders posts/post-a/index.md should use parent dir name as slug and fallback title
        File.write(File.join(bundle_a, "index.md"), "Content A.")
        # and if title is specified, it should still use the parent dir name as slug
        File.write(File.join(bundle_b, "index.md"), "---\ntitle: \"Custom Title\"\n---\nContent B.")

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "eleventy",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::EleventyImporter.new
        result = importer.run(options)

        result.imported_count.should eq(2) # post-a/index.md and post-b/index.md
        result.skipped_count.should eq(1)  # root index.md skipped

        File.exists?(File.join(output_dir, "posts", "post-a.md")).should be_true
        content_a = File.read(File.join(output_dir, "posts", "post-a.md"))
        content_a.should contain("title = \"Post A\"")
        content_a.should contain("Content A.")

        File.exists?(File.join(output_dir, "posts", "post-b.md")).should be_true
        content_b = File.read(File.join(output_dir, "posts", "post-b.md"))
        content_b.should contain("title = \"Custom Title\"")
        content_b.should contain("Content B.")
      end
    end

    it "handles nested directory/slug collisions by appending a suffix and warning" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "blog")
        dir_2023 = File.join(blog_dir, "2023")
        dir_2024 = File.join(blog_dir, "2024")
        FileUtils.mkdir_p(dir_2023)
        FileUtils.mkdir_p(dir_2024)

        File.write(File.join(dir_2023, "foo.md"), "---\ntitle: \"Foo 2023\"\n---\nContent 2023.")
        File.write(File.join(dir_2024, "foo.md"), "---\ntitle: \"Foo 2024\"\n---\nContent 2024.")

        output_dir = File.join(dir, "output")
        options = Hwaro::Config::Options::ImportOptions.new(
          source_type: "eleventy",
          path: dir,
          output_dir: output_dir,
        )

        importer = Hwaro::Services::Importers::EleventyImporter.new
        result = importer.run(options)

        result.imported_count.should eq(2)
        File.exists?(File.join(output_dir, "blog", "foo.md")).should be_true
        File.exists?(File.join(output_dir, "blog", "foo-1.md")).should be_true

        content_foo = File.read(File.join(output_dir, "blog", "foo.md"))
        content_foo1 = File.read(File.join(output_dir, "blog", "foo-1.md"))

        if content_foo.includes?("Content 2023.")
          content_foo1.should contain("Content 2024.")
        else
          content_foo.should contain("Content 2024.")
          content_foo1.should contain("Content 2023.")
        end
      end
    end
  end
end
