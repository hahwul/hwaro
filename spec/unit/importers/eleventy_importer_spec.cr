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
  end
end
