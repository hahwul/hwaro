require "../spec_helper"
require "../../src/services/creator"

describe Hwaro::Services::Creator do
  describe "#run" do
    it "creates a file from a direct path with inferred title" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          # Create necessary directories
          FileUtils.mkdir_p("content/drafts")

          options = Hwaro::Config::Options::NewOptions.new(path: "my-first-post.md")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/drafts/my-first-post.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("title: My First Post")
          content.should contain("draft: true")
        end
      end
    end

    it "creates a file from a direct path with explicit title" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")

          options = Hwaro::Config::Options::NewOptions.new(path: "custom.md", title: "My Custom Title")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/drafts/custom.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("title: My Custom Title")
        end
      end
    end

    it "creates a file in a subdirectory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/blog")

          options = Hwaro::Config::Options::NewOptions.new(path: "blog/post.md", title: "Blog Post")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/blog/post.md"
          File.exists?(expected_path).should be_true
        end
      end
    end

    it "creates a file when path is a directory and title is provided" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/blog")

          options = Hwaro::Config::Options::NewOptions.new(path: "blog", title: "My Blog Post")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          # "My Blog Post" -> "my-blog-post.md"
          expected_path = "content/blog/my-blog-post.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("title: My Blog Post")
        end
      end
    end

    it "uses an explicit archetype if provided" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")
          FileUtils.mkdir_p("archetypes")

          File.write("archetypes/custom.md", "+++\ntitle = \"{{ title }}\"\ncustom = true\n+++\n\n# Custom Content")

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Archetype Test", archetype: "custom")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/drafts/post.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("title = \"Archetype Test\"")
          content.should contain("custom = true")
          content.should contain("# Custom Content")
        end
      end
    end

    it "uses an implicit archetype based on directory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/blog")
          FileUtils.mkdir_p("archetypes")

          # Create archetype for 'blog' section
          File.write("archetypes/blog.md", "---\ntitle: {{ title }}\ntype: blog\n---\n")

          options = Hwaro::Config::Options::NewOptions.new(path: "blog/post.md", title: "Blog Item")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/blog/post.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("type: blog")
        end
      end
    end

    it "uses the default archetype if no specific archetype matches" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")
          FileUtils.mkdir_p("archetypes")

          File.write("archetypes/default.md", "---\ntitle: {{ title }}\ndefault: true\n---\n")

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Default Test")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/drafts/post.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("default: true")
        end
      end
    end

    it "falls back to built-in generation if no archetype exists" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")
          # No archetypes directory

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Fallback Test")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/drafts/post.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("title: Fallback Test")
          content.should contain("date: ")
        end
      end
    end

    it "creates a file when path starts with content/" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/blog")

          options = Hwaro::Config::Options::NewOptions.new(path: "content/blog/post.md", title: "Blog Post")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/blog/post.md"
          File.exists?(expected_path).should be_true
        end
      end
    end

    it "creates a file in drafts when path is nil but title is provided" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")

          options = Hwaro::Config::Options::NewOptions.new(title: "My Draft Post")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/drafts/my-draft-post.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("title: My Draft Post")
        end
      end
    end

    it "raises an error if file already exists" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")
          File.write("content/drafts/existing.md", "content")

          options = Hwaro::Config::Options::NewOptions.new(path: "existing.md", title: "Existing Post")
          creator = Hwaro::Services::Creator.new

          expect_raises(Exception, "File already exists: content/drafts/existing.md") do
            creator.run(options)
          end
        end
      end
    end

    it "raises an error if explicit archetype is missing" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")
          FileUtils.mkdir_p("archetypes")

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Post", archetype: "missing")
          creator = Hwaro::Services::Creator.new

          expect_raises(Exception, "Archetype not found: archetypes/missing.md") do
            creator.run(options)
          end
        end
      end
    end

    it "creates a file from a directory path using title slug" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/news")

          # Test with special characters in title
          options = Hwaro::Config::Options::NewOptions.new(path: "news", title: "Breaking News! (2024)")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          # "Breaking News! (2024)" -> "breaking-news-2024.md"
          expected_path = "content/news/breaking-news-2024.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("title: Breaking News! (2024)")
        end
      end
    end
  end
end
