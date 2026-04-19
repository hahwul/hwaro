require "../spec_helper"
require "../../src/models/config"
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
          content.should contain("title = \"My First Post\"")
          content.should contain("draft = true")
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
          content.should contain("title = \"My Custom Title\"")
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
          content.should contain("title = \"My Blog Post\"")
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
          content.should contain("title = \"Fallback Test\"")
          content.should contain("date = ")
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
          content.should contain("title = \"My Draft Post\"")
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

    it "fails fast when title cannot be inferred (flag-only, no prompt)" do
      # `hwaro new` is flag-only: the Creator must raise a clear usage error
      # rather than falling back to an interactive `gets` prompt. This holds
      # in both TTY and non-TTY environments.
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")

          options = Hwaro::Config::Options::NewOptions.new
          creator = Hwaro::Services::Creator.new

          expect_raises(Exception, /missing --title/) do
            creator.run(options)
          end
        end
      end
    end

    it "fails fast when path is a directory and title is missing" do
      # Regression: `hwaro new posts/` (directory, no --title) should raise
      # the same usage error since no title can be inferred from a directory.
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/blog")

          options = Hwaro::Config::Options::NewOptions.new(path: "blog")
          creator = Hwaro::Services::Creator.new

          expect_raises(Exception, /missing --title/) do
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
          content.should contain("title = \"Breaking News! (2024)\"")
        end
      end
    end

    it "defaults to TOML front matter with a description field" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello")
          Hwaro::Services::Creator.new.run(options)

          content = File.read("content/drafts/post.md")
          content.should contain("+++\n")
          content.should contain("title = \"Hello\"")
          content.should contain("description = \"\"")
          content.should_not contain("---\n")
        end
      end
    end

    it "emits YAML front matter when config selects yaml" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")

          config = Hwaro::Models::Config.new
          config.content_new.front_matter_format = "yaml"

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello")
          Hwaro::Services::Creator.new.run(options, config)

          content = File.read("content/drafts/post.md")
          content.should contain("---\n")
          content.should contain("title: \"Hello\"")
          content.should contain("description: \"\"")
          content.should_not contain("+++\n")
        end
      end
    end

    it "honours custom default_fields from config" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")

          config = Hwaro::Models::Config.new
          config.content_new.default_fields = ["description", "author", "summary"]

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello")
          Hwaro::Services::Creator.new.run(options, config)

          content = File.read("content/drafts/post.md")
          content.should contain("description = \"\"")
          content.should contain("author = \"\"")
          content.should contain("summary = \"\"")
        end
      end
    end

    it "ignores built-in fields listed in default_fields" do
      # Built-ins (title/date/draft/tags) have dedicated rendering. Listing
      # them in default_fields must not duplicate them with empty values.
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")

          config = Hwaro::Models::Config.new
          config.content_new.default_fields = ["title", "date", "draft", "tags", "description"]

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello")
          Hwaro::Services::Creator.new.run(options, config)

          content = File.read("content/drafts/post.md")
          content.scan("title = ").size.should eq(1)
          content.scan("date = ").size.should eq(1)
          content.should_not contain("title = \"\"")
          content.should_not contain("date = \"\"")
          content.should contain("description = \"\"")
        end
      end
    end

    # Precedence: CLI --bundle > archetype directive > config > single.
    # These tests each isolate a single layer so regressions in the
    # resolver show up independently.
    describe "bundle (leaf-bundle) layout" do
      it "creates foo/index.md when --bundle is passed on the CLI" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            options = Hwaro::Config::Options::NewOptions.new(
              path: "posts/hello.md", title: "Hello", bundle: true)
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/posts/hello/index.md").should be_true
            File.exists?("content/posts/hello.md").should be_false
          end
        end
      end

      it "--no-bundle (bundle=false) forces a single file even when config defaults to bundle" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            config = Hwaro::Models::Config.new
            config.content_new.bundle = true

            options = Hwaro::Config::Options::NewOptions.new(
              path: "posts/solo.md", title: "Solo", bundle: false)
            Hwaro::Services::Creator.new.run(options, config)

            File.exists?("content/posts/solo.md").should be_true
            Dir.exists?("content/posts/solo").should be_false
          end
        end
      end

      it "falls back to the config default when --bundle is unspecified" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            config = Hwaro::Models::Config.new
            config.content_new.bundle = true

            options = Hwaro::Config::Options::NewOptions.new(
              path: "posts/defaulted.md", title: "Defaulted")
            Hwaro::Services::Creator.new.run(options, config)

            File.exists?("content/posts/defaulted/index.md").should be_true
          end
        end
      end

      it "honours `<!-- hwaro: bundle -->` directive in an archetype and strips it" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/tools")
            FileUtils.mkdir_p("archetypes")
            File.write(
              "archetypes/tools.md",
              "<!-- hwaro: bundle -->\n+++\ntitle = \"{{ title }}\"\nkind = \"tool\"\n+++\n\n# {{ title }}\n"
            )

            options = Hwaro::Config::Options::NewOptions.new(
              path: "tools/drill.md", title: "Drill")
            Hwaro::Services::Creator.new.run(options)

            bundle_path = "content/tools/drill/index.md"
            File.exists?(bundle_path).should be_true
            content = File.read(bundle_path)
            # Directive must not leak into generated content.
            content.should_not contain("hwaro:")
            content.should contain("title = \"Drill\"")
            content.should contain("kind = \"tool\"")
          end
        end
      end

      it "lets CLI --no-bundle override an archetype directive" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/tools")
            FileUtils.mkdir_p("archetypes")
            File.write(
              "archetypes/tools.md",
              "<!-- hwaro: bundle=true -->\n+++\ntitle = \"{{ title }}\"\n+++\n"
            )

            options = Hwaro::Config::Options::NewOptions.new(
              path: "tools/saw.md", title: "Saw", bundle: false)
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/tools/saw.md").should be_true
            Dir.exists?("content/tools/saw").should be_false
          end
        end
      end

      it "is idempotent when the path already ends in index.md" do
        # Guards against double-wrapping: `hwaro new foo/index.md --bundle`
        # must not produce `foo/index/index.md`.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/foo")
            options = Hwaro::Config::Options::NewOptions.new(
              path: "foo/index.md", title: "Foo", bundle: true)
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/foo/index.md").should be_true
            File.exists?("content/foo/index/index.md").should be_false
          end
        end
      end

      it "does not wrap `_index.md` section indices" do
        # Section indices look like bundles shape-wise but mean something
        # different; wrapping to `_index/index.md` would create a phantom
        # section.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            options = Hwaro::Config::Options::NewOptions.new(
              path: "posts/_index.md", title: "Posts", bundle: true)
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/posts/_index.md").should be_true
            File.exists?("content/posts/_index/index.md").should be_false
          end
        end
      end

      it "refuses bundle creation when a single-file sibling already exists" do
        # Both `posts/hello.md` (sibling) and `posts/hello/index.md`
        # (bundle) would render to the same URL — we'd rather fail loudly
        # than silently duplicate the page.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            File.write("content/posts/hello.md", "+++\ntitle = \"Existing\"\n+++\n")

            options = Hwaro::Config::Options::NewOptions.new(
              path: "posts/hello.md", title: "Hello", bundle: true)
            expect_raises(Exception, /sibling already exists/) do
              Hwaro::Services::Creator.new.run(options)
            end

            # Existing file left untouched, bundle not created.
            File.read("content/posts/hello.md").should contain("Existing")
            File.exists?("content/posts/hello/index.md").should be_false
          end
        end
      end

      it "warns and ignores unknown hwaro directives" do
        # Typos like `<!-- hwaro: bundlr=true -->` used to silently no-op.
        # Now they warn and bundle mode is not activated (behaviour check
        # substitutes for asserting on Logger output).
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/tools")
            FileUtils.mkdir_p("archetypes")
            File.write(
              "archetypes/tools.md",
              "<!-- hwaro: bundlr=true -->\n+++\ntitle = \"{{ title }}\"\n+++\n"
            )

            options = Hwaro::Config::Options::NewOptions.new(
              path: "tools/saw.md", title: "Saw")
            Hwaro::Services::Creator.new.run(options)

            # Unknown key → no bundle reshape; single file wins.
            File.exists?("content/tools/saw.md").should be_true
            Dir.exists?("content/tools/saw").should be_false
          end
        end
      end

      it "works with --section + --bundle together" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            options = Hwaro::Config::Options::NewOptions.new(
              path: "hello.md", title: "Hello", section: "blog", bundle: true)
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/blog/hello/index.md").should be_true
            File.exists?("content/blog/hello.md").should be_false
          end
        end
      end
    end
  end
end
