require "../spec_helper"
require "../../src/models/config"
require "../../src/services/creator"

describe Hwaro::Services::Creator do
  describe "#run" do
    it "creates a file from a direct path with inferred title (honours user's path)" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          options = Hwaro::Config::Options::NewOptions.new(path: "my-first-post.md")
          creator = Hwaro::Services::Creator.new

          result = creator.run(options)

          # `hwaro new foo.md` now lands at `content/foo.md` — the previous
          # behaviour silently rerouted to `content/drafts/foo.md`, which
          # surprised users who didn't ask for drafts.
          expected_path = "content/my-first-post.md"
          File.exists?(expected_path).should be_true
          result.should eq(expected_path)

          content = File.read(expected_path)
          content.should contain("title = \"My First Post\"")
          # And since it no longer lives under drafts/, draft defaults to false.
          content.should_not contain("draft = true")
        end
      end
    end

    it "creates a file from a direct path with explicit title (honours user's path)" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          options = Hwaro::Config::Options::NewOptions.new(path: "custom.md", title: "My Custom Title")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/custom.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("title = \"My Custom Title\"")
        end
      end
    end

    it "places explicit drafts/ paths under drafts and marks them draft" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")

          options = Hwaro::Config::Options::NewOptions.new(path: "drafts/wip.md")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/drafts/wip.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("draft = true")
        end
      end
    end

    it "does not mark content draft just because the path contains 'drafts' as a substring" do
      # Regression: `base_dir.includes?("drafts")` matched a path SEGMENT only
      # by accident — `content/draftsmanship/...` was silently published as a
      # draft. Match a real path segment instead.
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/draftsmanship")

          options = Hwaro::Config::Options::NewOptions.new(path: "draftsmanship/post.md")
          creator = Hwaro::Services::Creator.new
          creator.run(options)

          content = File.read("content/draftsmanship/post.md")
          content.should_not contain("draft = true")
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

    it "treats a bare path without .md as the page stem (title only populates front matter, not the filename on disk)" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          options = Hwaro::Config::Options::NewOptions.new(path: "contact", title: "Get In Touch")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          # Bare path "contact" (no .md, no --section, default no-bundle) becomes the stem:
          # content/contact.md (URL /contact/), title is only for front matter.
          expected_path = "content/contact.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("title = \"Get In Touch\"")
        end
      end
    end

    it "uses an explicit archetype if provided" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("archetypes")

          File.write("archetypes/custom.md", "+++\ntitle = \"{{ title }}\"\ncustom = true\n+++\n\n# Custom Content")

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Archetype Test", archetype: "custom")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/post.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("title = \"Archetype Test\"")
          content.should contain("custom = true")
          content.should contain("# Custom Content")
        end
      end
    end

    # Regression: archetype substitution injected the raw title/date, so a
    # title containing a double quote (`My "Quoted" Post`) produced invalid
    # TOML (`title = "My "Quoted" Post"`) and the generated file failed to
    # build. The values must be escaped like `tags` already is.
    it "escapes a quoted title/tags in archetype front matter (valid TOML)" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("archetypes")
          File.write("archetypes/custom.md", "+++\ntitle = \"{{ title }}\"\ndate = \"{{ date }}\"\ntags = {{ tags }}\n+++\n")

          options = Hwaro::Config::Options::NewOptions.new(
            path: "post.md", title: %(My "Quoted" Post), archetype: "custom", tags: [%(a "b"), "c"])
          Hwaro::Services::Creator.new.run(options)

          content = File.read("content/post.md")
          content.should contain(%(title = "My \\"Quoted\\" Post"))
          # Front matter must parse as valid TOML.
          fm = content.lines.reject { |l| l.strip == "+++" }.join("\n")
          parsed = TOML.parse(fm)
          parsed["title"].as_s.should eq(%(My "Quoted" Post))
          parsed["tags"].as_a.map(&.as_s).should eq([%(a "b"), "c"])
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
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("archetypes")

          File.write("archetypes/default.md", "---\ntitle: {{ title }}\ndefault: true\n---\n")

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Default Test")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/post.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("default: true")
        end
      end
    end

    it "falls back to built-in generation if no archetype exists" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          # No archetypes directory

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Fallback Test")
          creator = Hwaro::Services::Creator.new

          creator.run(options)

          expected_path = "content/post.md"
          File.exists?(expected_path).should be_true

          content = File.read(expected_path)
          content.should contain("title = \"Fallback Test\"")
          content.should contain("date = ")
        end
      end
    end

    # Regression for https://github.com/hahwul/hwaro/issues/525
    # When no archetype is found, the built-in fallback used to append
    # `# <title>` after the front matter, producing two `<h1>`s once a
    # template rendered `{{ page.title }}` as well. Body must now be empty.
    it "fallback front matter omits the markdown H1 (gh#525)" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "No Dup H1")
          Hwaro::Services::Creator.new.run(options)

          content = File.read("content/post.md")
          content.should contain("title = \"No Dup H1\"")
          content.should_not contain("# No Dup H1")
          # Front matter terminator is the last non-empty line.
          content.lines.reject(&.blank?).last.should eq("+++")
        end
      end
    end

    # We intentionally default to a simple date-only value (YYYY-MM-DD) for
    # new content because that's what most authors actually want. It is still
    # a valid unquoted TOML date. Users who need time precision can pass --date.
    it "writes the default date as a simple unquoted YYYY-MM-DD value" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Date Form")
          Hwaro::Services::Creator.new.run(options)

          content = File.read("content/post.md")
          # No quoted form anywhere on the date line.
          content.should_not match(/^date = "[^"]*"$/m)
          # Simple date (e.g. 2026-05-29). Full ISO is still accepted via --date.
          content.should match(/^date = \d{4}-\d{2}-\d{2}$/m)
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

    it "raises HwaroError(HWARO_E_IO) when the file already exists" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          File.write("content/existing.md", "content")

          options = Hwaro::Config::Options::NewOptions.new(path: "existing.md", title: "Existing Post")
          creator = Hwaro::Services::Creator.new

          err = expect_raises(Hwaro::HwaroError) do
            creator.run(options)
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_IO)
          err.exit_code.should eq(Hwaro::Errors::EXIT_IO)
          (err.message || "").should contain("File already exists: content/existing.md")
        end
      end
    end

    it "raises HwaroError(HWARO_E_USAGE) when an explicit archetype is missing" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")
          FileUtils.mkdir_p("archetypes")

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Post", archetype: "missing")
          creator = Hwaro::Services::Creator.new

          err = expect_raises(Hwaro::HwaroError) do
            creator.run(options)
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
          err.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
          (err.message || "").should contain("Archetype not found: archetypes/missing.md")
        end
      end
    end

    it "fails fast with HwaroError(HWARO_E_USAGE) when title cannot be inferred (flag-only, no prompt)" do
      # `hwaro new` is flag-only: the Creator must raise a clear usage error
      # rather than falling back to an interactive `gets` prompt. This holds
      # in both TTY and non-TTY environments.
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")

          options = Hwaro::Config::Options::NewOptions.new
          creator = Hwaro::Services::Creator.new

          err = expect_raises(Hwaro::HwaroError) do
            creator.run(options)
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
          (err.message || "").should match(/missing --title/)
        end
      end
    end

    it "fails fast with HwaroError(HWARO_E_USAGE) when path is a directory and title is missing" do
      # Regression: `hwaro new posts/` (directory, no --title) should raise
      # the same usage error since no title can be inferred from a directory.
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/blog")

          options = Hwaro::Config::Options::NewOptions.new(path: "blog")
          creator = Hwaro::Services::Creator.new

          err = expect_raises(Hwaro::HwaroError) do
            creator.run(options)
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
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
          FileUtils.mkdir_p("content")

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello")
          Hwaro::Services::Creator.new.run(options)

          content = File.read("content/post.md")
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
          FileUtils.mkdir_p("content")

          config = Hwaro::Models::Config.new
          config.content_new.front_matter_format = "yaml"

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello")
          Hwaro::Services::Creator.new.run(options, config)

          content = File.read("content/post.md")
          content.should contain("---\n")
          content.should contain("title: \"Hello\"")
          content.should contain("description: \"\"")
          content.should_not contain("+++\n")
        end
      end
    end

    it "emits JSON front matter when config selects json" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          config = Hwaro::Models::Config.new
          config.content_new.front_matter_format = "json"

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello")
          Hwaro::Services::Creator.new.run(options, config)

          content = File.read("content/post.md")
          content.should start_with("{")
          # The JSON block must be parseable and contain the expected fields.
          end_idx = content.index!("}\n") + 1
          parsed = JSON.parse(content[0, end_idx])
          parsed["title"].as_s.should eq("Hello")
          parsed["description"].as_s.should eq("")
          # Default location no longer routes to drafts/, so draft is omitted.
          parsed.as_h.has_key?("draft").should be_false
          content.should_not contain("+++\n")
          content.should_not contain("---\n")
        end
      end
    end

    # An explicit `description` (supplied by the interactive `hwaro new` wizard)
    # must be written as the field's value instead of the empty placeholder the
    # flag form leaves behind, across every front-matter format.
    it "writes the supplied description value into TOML front matter" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello", description: "A short intro")
          Hwaro::Services::Creator.new.run(options)

          File.read("content/post.md").should contain(%(description = "A short intro"))
        end
      end
    end

    it "writes the supplied description value into YAML front matter" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          config = Hwaro::Models::Config.new
          config.content_new.front_matter_format = "yaml"

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello", description: "A short intro")
          Hwaro::Services::Creator.new.run(options, config)

          File.read("content/post.md").should contain(%(description: "A short intro"))
        end
      end
    end

    it "writes the supplied description value into JSON front matter" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          config = Hwaro::Models::Config.new
          config.content_new.front_matter_format = "json"

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello", description: "A short intro")
          Hwaro::Services::Creator.new.run(options, config)

          content = File.read("content/post.md")
          parsed = JSON.parse(content[0, content.index!("}\n") + 1])
          parsed["description"].as_s.should eq("A short intro")
        end
      end
    end

    it "force-includes description even when default_fields omitted it" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          config = Hwaro::Models::Config.new
          config.content_new.default_fields = [] of String

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello", description: "Forced in")
          Hwaro::Services::Creator.new.run(options, config)

          File.read("content/post.md").should contain(%(description = "Forced in"))
        end
      end
    end

    it "substitutes {{ description }} in an archetype, escaping the value" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("archetypes")
          File.write("archetypes/default.md", %(+++\ntitle = "{{ title }}"\ndescription = "{{ description }}"\n+++\n\n))

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello", description: %(My "Quoted" intro))
          Hwaro::Services::Creator.new.run(options)

          File.read("content/post.md").should contain(%(description = "My \\"Quoted\\" intro"))
        end
      end
    end

    it "leaves an archetype's {{ description }} empty when none is supplied" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("archetypes")
          File.write("archetypes/default.md", %(+++\ntitle = "{{ title }}"\ndescription = "{{ description }}"\n+++\n\n))

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello")
          Hwaro::Services::Creator.new.run(options)

          File.read("content/post.md").should contain(%(description = ""))
        end
      end
    end

    describe "stability guards" do
      it "raises HWARO_E_USAGE for a --date the build cannot parse, writing nothing" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")
            options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "T", date: "2026-13-45")
            err = expect_raises(Hwaro::HwaroError) { Hwaro::Services::Creator.new.run(options) }
            err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
            File.exists?("content/post.md").should be_false
          end
        end
      end

      it "derives the title from the filename when --title is whitespace-only" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")
            options = Hwaro::Config::Options::NewOptions.new(path: "my-post.md", title: "   ")
            Hwaro::Services::Creator.new.run(options)
            File.read("content/my-post.md").should contain(%(title = "My Post"))
          end
        end
      end

      it "derives the bundle title from the path's last segment when --bundle has no --title" do
        # Parity: the config-driven `bundle = true` derived the title from the
        # path, but the explicit `--bundle` flag demanded --title and errored.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")
            options = Hwaro::Config::Options::NewOptions.new(path: "posts/my-bundle", bundle: true)
            result = Hwaro::Services::Creator.new.run(options)
            result.should eq("content/posts/my-bundle/index.md")
            File.read(result).should contain(%(title = "My Bundle"))
          end
        end
      end

      it "refuses a flat page whose URL collides with an existing bundle" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts/foo")
            File.write("content/posts/foo/index.md", "+++\ntitle = \"F\"\n+++\n")
            options = Hwaro::Config::Options::NewOptions.new(path: "posts/foo.md", title: "F2")
            err = expect_raises(Hwaro::HwaroError) { Hwaro::Services::Creator.new.run(options) }
            err.code.should eq(Hwaro::Errors::HWARO_E_IO)
            File.exists?("content/posts/foo.md").should be_false
          end
        end
      end

      it "refuses a flat page whose URL collides with an existing section index" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/sec")
            File.write("content/sec/_index.md", "+++\ntitle = \"S\"\n+++\n")
            options = Hwaro::Config::Options::NewOptions.new(path: "sec.md", title: "S2")
            err = expect_raises(Hwaro::HwaroError) { Hwaro::Services::Creator.new.run(options) }
            err.code.should eq(Hwaro::Errors::HWARO_E_IO)
            File.exists?("content/sec.md").should be_false
          end
        end
      end

      it "classifies a file squatting on a parent directory segment as HWARO_E_IO" do
        # Previously this unwound as a bare File::AlreadyExistsError — no
        # error code, no exit taxonomy, and an empty stdout in --json mode.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")
            File.write("content/blocker.md", "+++\ntitle = \"B\"\n+++\n")
            options = Hwaro::Config::Options::NewOptions.new(path: "blocker.md/child.md", title: "C")
            err = expect_raises(Hwaro::HwaroError) { Hwaro::Services::Creator.new.run(options) }
            err.code.should eq(Hwaro::Errors::HWARO_E_IO)
          end
        end
      end
    end

    describe ".slugify" do
      it "lowercases and hyphenates a title" do
        Hwaro::Services::Creator.slugify("My First Post!").should eq("my-first-post")
      end

      it "collapses punctuation runs and trims edge hyphens" do
        Hwaro::Services::Creator.slugify("  Breaking News! (2024)  ").should eq("breaking-news-2024")
      end

      it "preserves CJK letters" do
        Hwaro::Services::Creator.slugify("안녕 세계").should eq("안녕-세계")
      end

      it "returns an empty string when nothing is slug-able" do
        Hwaro::Services::Creator.slugify("!!!").should eq("")
      end
    end

    # The default generators (no archetype) hand-roll escape_string for
    # backslash-before-quote ordering. An adversarial title (`C:\` style
    # backslash + embedded quote) must still produce front matter that
    # round-trips through a real parser back to the original string —
    # otherwise the next `hwaro build` chokes on unparseable TOML/YAML.
    it "round-trips an adversarial title through the default TOML generator" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          adversarial = %(My "Quoted" \\ Post)
          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: adversarial)
          Hwaro::Services::Creator.new.run(options)

          content = File.read("content/post.md")
          fm = content.lines.reject { |l| l.strip == "+++" }.join("\n")
          parsed = TOML.parse(fm)
          parsed["title"].as_s.should eq(adversarial)
        end
      end
    end

    it "round-trips an adversarial title through the default YAML generator" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          config = Hwaro::Models::Config.new
          config.content_new.front_matter_format = "yaml"

          adversarial = %(My "Quoted" \\ Post)
          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: adversarial)
          Hwaro::Services::Creator.new.run(options, config)

          content = File.read("content/post.md")
          fm = content.lines.reject { |l| l.strip == "---" }.join("\n")
          parsed = YAML.parse(fm)
          parsed["title"].as_s.should eq(adversarial)
        end
      end
    end

    # JSON is correct by construction (JSON::Any.to_pretty_json), but keep a
    # cheap round-trip as an extra guard.
    it "round-trips an adversarial title through the default JSON generator" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          config = Hwaro::Models::Config.new
          config.content_new.front_matter_format = "json"

          adversarial = %(My "Quoted" \\ Post)
          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: adversarial)
          Hwaro::Services::Creator.new.run(options, config)

          content = File.read("content/post.md")
          end_idx = content.index!("}\n") + 1
          parsed = JSON.parse(content[0, end_idx])
          parsed["title"].as_s.should eq(adversarial)
        end
      end
    end

    # When no <path> is given and the title slugifies to empty (all
    # punctuation/emoji), the slug-empty guard must raise a classified usage
    # error rather than writing a stray hidden `content/.md` file.
    it "fails fast with HwaroError(HWARO_E_USAGE) when title slugifies to empty (no path)" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/drafts")

          options = Hwaro::Config::Options::NewOptions.new(title: "!!!")
          creator = Hwaro::Services::Creator.new

          err = expect_raises(Hwaro::HwaroError) do
            creator.run(options)
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
          (err.message || "").should match(/filename-safe/)

          # No stray hidden file written.
          File.exists?("content/.md").should be_false
          File.exists?("content/drafts/.md").should be_false
        end
      end
    end

    it "honours custom default_fields from config" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          config = Hwaro::Models::Config.new
          config.content_new.default_fields = ["description", "author", "summary"]

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello")
          Hwaro::Services::Creator.new.run(options, config)

          content = File.read("content/post.md")
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
          FileUtils.mkdir_p("content")

          config = Hwaro::Models::Config.new
          config.content_new.default_fields = ["title", "date", "draft", "tags", "description"]

          options = Hwaro::Config::Options::NewOptions.new(path: "post.md", title: "Hello")
          Hwaro::Services::Creator.new.run(options, config)

          content = File.read("content/post.md")
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

      it "treats a multi-segment dir-ish path as the bundle directory itself" do
        # Regression for the double-wrap: `posts/bundled --bundle` used to
        # produce `posts/bundled/bundled/index.md` because the directory
        # fallback appended a `<title-slug>.md` to the path first, then
        # bundle-wrapped the result. The path IS the bundle dir when
        # --bundle is active, so land at `<path>/index.md` directly.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            options = Hwaro::Config::Options::NewOptions.new(
              path: "posts/bundled", title: "Bundled", bundle: true)
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/posts/bundled/index.md").should be_true
            File.exists?("content/posts/bundled/bundled/index.md").should be_false
            File.exists?("content/posts/bundled/bundled.md").should be_false
          end
        end
      end

      it "keeps the custom title in front matter without leaking it into the bundle path" do
        # The title slug must not become a directory layer when the user
        # explicitly picked the bundle dir via the path argument.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            options = Hwaro::Config::Options::NewOptions.new(
              path: "posts/deep", title: "Something Else", bundle: true)
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/posts/deep/index.md").should be_true
            File.exists?("content/posts/deep/something-else/index.md").should be_false

            content = File.read("content/posts/deep/index.md")
            content.should contain("title = \"Something Else\"")
          end
        end
      end

      it "leaves `-s section` + dir-ish path behavior unchanged" do
        # The -s branch handles path-without-.md differently (appends .md
        # to the path rather than using it as a directory), so the double-
        # wrap collapse must not apply here. `foo -s docs --bundle` should
        # still produce `docs/foo/index.md`, not `docs/index.md`.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")
            options = Hwaro::Config::Options::NewOptions.new(
              path: "foo", title: "Foo", section: "docs", bundle: true)
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/docs/foo/index.md").should be_true
            File.exists?("content/docs/index.md").should be_false
          end
        end
      end

      it "treats a single-segment dir-ish path as the bundle directory itself" do
        # `hwaro new mysection --bundle --title Intro` — the path IS the
        # bundle directory when --bundle is active, even for a bare slug.
        # Previously this produced `mysection/intro/index.md` because the
        # double-wrap fix required a `/` in the path; issue #458 tightens
        # the behavior so single-segment paths collapse the slug layer too.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")
            options = Hwaro::Config::Options::NewOptions.new(
              path: "mysection", title: "Intro", bundle: true)
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/mysection/index.md").should be_true
            File.exists?("content/mysection/intro/index.md").should be_false

            content = File.read("content/mysection/index.md")
            content.should contain("title = \"Intro\"")
          end
        end
      end

      it "collapses the slug layer when path slug and title slug collide (issue #458)" do
        # Regression guard for the reported case: `bundle-post` as path +
        # title "Bundle Post" (same slug) must not produce
        # `bundle-post/bundle-post/index.md`.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")
            options = Hwaro::Config::Options::NewOptions.new(
              path: "bundle-post", title: "Bundle Post", bundle: true)
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/bundle-post/index.md").should be_true
            File.exists?("content/bundle-post/bundle-post/index.md").should be_false
            File.exists?("content/bundle-post/bundle-post.md").should be_false
          end
        end
      end

      it "treats --no-bundle dir-ish paths as a flat file slug (issue #459)" do
        # `--no-bundle` must produce a single flat file. The earlier
        # directory-fallback used to append the title slug as a filename
        # inside `<path>/`, defeating the flag. With --no-bundle the path
        # is authoritative and becomes `<path>.md` directly.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            options = Hwaro::Config::Options::NewOptions.new(
              path: "posts/nobund", title: "NoBund", bundle: false)
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/posts/nobund.md").should be_true
            Dir.exists?("content/posts/nobund").should be_false

            content = File.read("content/posts/nobund.md")
            content.should contain("title = \"NoBund\"")
          end
        end
      end

      it "treats --no-bundle single-segment paths as a top-level flat file (issue #459)" do
        # Regression guard for the reported case: `no-bundle-post` as path
        # with --no-bundle must produce `content/no-bundle-post.md`, not
        # `content/no-bundle-post/<title-slug>.md`.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")
            options = Hwaro::Config::Options::NewOptions.new(
              path: "no-bundle-post", title: "No Bundle", bundle: false)
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/no-bundle-post.md").should be_true
            Dir.exists?("content/no-bundle-post").should be_false

            content = File.read("content/no-bundle-post.md")
            content.should contain("title = \"No Bundle\"")
          end
        end
      end

      it "refuses bundle creation with HwaroError(HWARO_E_IO) when a single-file sibling already exists" do
        # Both `posts/hello.md` (sibling) and `posts/hello/index.md`
        # (bundle) would render to the same URL — we'd rather fail loudly
        # than silently duplicate the page.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            File.write("content/posts/hello.md", "+++\ntitle = \"Existing\"\n+++\n")

            options = Hwaro::Config::Options::NewOptions.new(
              path: "posts/hello.md", title: "Hello", bundle: true)
            err = expect_raises(Hwaro::HwaroError) do
              Hwaro::Services::Creator.new.run(options)
            end
            err.code.should eq(Hwaro::Errors::HWARO_E_IO)
            (err.message || "").should contain("single-file sibling")

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

      it "respects [content.new] bundle = true for bare paths (does not collapse to content/index.md)" do
        # Regression: when bundle default comes from config (not CLI --bundle),
        # bare paths like `new mypage -t "..."` used to go through the flat
        # heuristic then the path_is_dir_bundle collapse, producing
        # content/index.md instead of content/mypage/index.md.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")
            config = Hwaro::Models::Config.new
            config.content_new.bundle = true

            options = Hwaro::Config::Options::NewOptions.new(
              path: "my-bare-bundle", title: "Bare Bundle Via Config")
            Hwaro::Services::Creator.new.run(options, config)

            File.exists?("content/my-bare-bundle/index.md").should be_true
            File.exists?("content/index.md").should be_false

            content = File.read("content/my-bare-bundle/index.md")
            content.should contain("title = \"Bare Bundle Via Config\"")
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

    describe "--section vs path directory conflict" do
      # Regression: `hwaro new posts/foo.md -s docs` used to silently drop
      # the path's leading directory and create the file under the section
      # instead. The path is authoritative now (the user wrote the dir),
      # and --section is ignored after a one-line warning.

      it "prefers the path and warns when the leading directory and --section disagree" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")

            buffer = IO::Memory.new
            previous_io = Hwaro::Logger.io
            Hwaro::Logger.io = buffer
            begin
              options = Hwaro::Config::Options::NewOptions.new(
                path: "posts/conflict.md", title: "C", section: "docs")
              Hwaro::Services::Creator.new.run(options)
            ensure
              Hwaro::Logger.io = previous_io
            end

            # Path wins.
            File.exists?("content/posts/conflict.md").should be_true
            File.exists?("content/docs/conflict.md").should be_false

            log = buffer.to_s
            log.should contain("--section 'docs'")
            log.should contain("posts/")
            log.should contain("ignoring --section")
          end
        end
      end

      it "warns when the path is dir-ish and leading-segment differs from --section" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")

            buffer = IO::Memory.new
            previous_io = Hwaro::Logger.io
            Hwaro::Logger.io = buffer
            begin
              options = Hwaro::Config::Options::NewOptions.new(
                path: "posts/nope", title: "Nope", section: "docs")
              Hwaro::Services::Creator.new.run(options)
            ensure
              Hwaro::Logger.io = previous_io
            end

            # Section branch discarded due to conflict; we still honor the
            # directory part of the path the user typed and place a flat file
            # using the last segment as stem (better UX than falling back to
            # title-slug-inside-dir).
            File.exists?("content/posts/nope.md").should be_true
            File.exists?("content/posts/nope/nope.md").should be_false
            File.exists?("content/docs/nope.md").should be_false

            buffer.to_s.should contain("ignoring --section")
          end
        end
      end

      it "preserves deeper nesting in the path when dropping --section" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")
            options = Hwaro::Config::Options::NewOptions.new(
              path: "tools/deep/note.md", title: "Note", section: "docs")
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/tools/deep/note.md").should be_true
            File.exists?("content/docs/tools/deep/note.md").should be_false
            File.exists?("content/docs/note.md").should be_false
          end
        end
      end

      it "does not warn when --section matches the path's leading directory" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")

            buffer = IO::Memory.new
            previous_io = Hwaro::Logger.io
            Hwaro::Logger.io = buffer
            begin
              options = Hwaro::Config::Options::NewOptions.new(
                path: "posts/post.md", title: "P", section: "posts")
              Hwaro::Services::Creator.new.run(options)
            ensure
              Hwaro::Logger.io = previous_io
            end

            File.exists?("content/posts/post.md").should be_true
            buffer.to_s.should_not contain("--section")
          end
        end
      end

      it "does not double the dir when a slash-path's leading segment matches --section" do
        # Regression: `hwaro new posts/foo -s posts` (no .md extension) used to
        # join the section onto a path that already carried it, producing
        # content/posts/posts/foo.md.
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")
            options = Hwaro::Config::Options::NewOptions.new(
              path: "posts/foo", title: "Foo", section: "posts")
            Hwaro::Services::Creator.new.run(options)

            File.exists?("content/posts/foo.md").should be_true
            Dir.exists?("content/posts/posts").should be_false
          end
        end
      end

      it "does not warn when the path has no leading directory (section provides it)" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")

            buffer = IO::Memory.new
            previous_io = Hwaro::Logger.io
            Hwaro::Logger.io = buffer
            begin
              options = Hwaro::Config::Options::NewOptions.new(
                path: "intro.md", title: "Intro", section: "docs")
              Hwaro::Services::Creator.new.run(options)
            ensure
              Hwaro::Logger.io = previous_io
            end

            File.exists?("content/docs/intro.md").should be_true
            buffer.to_s.should_not contain("--section")
          end
        end
      end
    end
  end

  describe ".validate_and_normalize_path!" do
    it "accepts a plain relative path unchanged" do
      Hwaro::Services::Creator.validate_and_normalize_path!("posts/hello.md").should eq("posts/hello.md")
      Hwaro::Services::Creator.validate_and_normalize_path!("index.md").should eq("index.md")
    end

    it "collapses double slashes" do
      Hwaro::Services::Creator.validate_and_normalize_path!("posts//foo.md").should eq("posts/foo.md")
      Hwaro::Services::Creator.validate_and_normalize_path!("a//b///c.md").should eq("a/b/c.md")
    end

    it "strips leading ./ segments" do
      Hwaro::Services::Creator.validate_and_normalize_path!("./posts/foo.md").should eq("posts/foo.md")
    end

    it "accepts non-markdown-extension paths" do
      # The validator is about path shape, not extension — Creator decides
      # bundle vs single-file downstream.
      Hwaro::Services::Creator.validate_and_normalize_path!("posts/foo").should eq("posts/foo")
    end

    it "rejects an empty or whitespace-only path" do
      expect_raises(ArgumentError, /missing <path>/) do
        Hwaro::Services::Creator.validate_and_normalize_path!("")
      end
      expect_raises(ArgumentError, /missing <path>/) do
        Hwaro::Services::Creator.validate_and_normalize_path!("   ")
      end
    end

    it "rejects an absolute path" do
      expect_raises(ArgumentError, /Absolute path/) do
        Hwaro::Services::Creator.validate_and_normalize_path!("/tmp/evil.md")
      end
      expect_raises(ArgumentError, /Absolute path/) do
        Hwaro::Services::Creator.validate_and_normalize_path!("/etc/passwd")
      end
    end

    it "rejects paths that escape content/ via ..;" do
      expect_raises(ArgumentError, /escapes the content\/ directory/) do
        Hwaro::Services::Creator.validate_and_normalize_path!("../escaped.md")
      end
      expect_raises(ArgumentError, /escapes the content\/ directory/) do
        Hwaro::Services::Creator.validate_and_normalize_path!("../../../etc/passwd")
      end
    end

    it "rejects paths that reduce to content/ itself (no filename)" do
      expect_raises(ArgumentError, /escapes/) do
        Hwaro::Services::Creator.validate_and_normalize_path!(".")
      end
    end

    it "accepts paths that reference .. internally but stay under content/" do
      # foo/../bar.md resolves to bar.md which is still inside content/.
      Hwaro::Services::Creator.validate_and_normalize_path!("foo/../bar.md").should eq("bar.md")
    end

    it "rejects hidden (dot-leading) segments the build would ignore" do
      # Content discovery globs `content/**/*`, which skips hidden entries —
      # a scaffolded `.md` / `.hidden/foo.md` would never render.
      expect_raises(ArgumentError, /hidden segment/) do
        Hwaro::Services::Creator.validate_and_normalize_path!(".md")
      end
      expect_raises(ArgumentError, /hidden segment/) do
        Hwaro::Services::Creator.validate_and_normalize_path!(".hidden/foo.md")
      end
      expect_raises(ArgumentError, /hidden segment/) do
        Hwaro::Services::Creator.validate_and_normalize_path!("posts/.hidden/foo.md")
      end
      expect_raises(ArgumentError, /hidden segment/) do
        Hwaro::Services::Creator.validate_and_normalize_path!("...")
      end
    end
  end

  describe ".parseable_content_date?" do
    it "accepts the formats the build's front-matter parser accepts" do
      Hwaro::Services::Creator.parseable_content_date?("2026-03-22").should be_true
      Hwaro::Services::Creator.parseable_content_date?("2026-03-22 10:30:00").should be_true
      Hwaro::Services::Creator.parseable_content_date?("2026-03-22T10:30:00").should be_true
      Hwaro::Services::Creator.parseable_content_date?("2026-03-22T10:30:00Z").should be_true
      Hwaro::Services::Creator.parseable_content_date?("2026-03-22T10:30:00+09:00").should be_true
    end

    it "rejects out-of-range and garbage dates" do
      # `2026-13-45` matches the TOML datetime *pattern* and used to be
      # emitted unquoted — invalid TOML that broke the whole generated file.
      Hwaro::Services::Creator.parseable_content_date?("2026-13-45").should be_false
      Hwaro::Services::Creator.parseable_content_date?("2026-02-30").should be_false
      Hwaro::Services::Creator.parseable_content_date?("not-a-date").should be_false
      Hwaro::Services::Creator.parseable_content_date?("").should be_false
      Hwaro::Services::Creator.parseable_content_date?("   ").should be_false
    end
  end

  describe ".url_safe_path?" do
    it "returns true for plain ASCII paths" do
      Hwaro::Services::Creator.url_safe_path?("posts/hello-world.md").should be_true
      Hwaro::Services::Creator.url_safe_path?("my_post.md").should be_true
      Hwaro::Services::Creator.url_safe_path?("docs/v1.2/intro.md").should be_true
    end

    it "returns true for CJK / Unicode letter paths" do
      Hwaro::Services::Creator.url_safe_path?("한글/포스트.md").should be_true
      Hwaro::Services::Creator.url_safe_path?("café/résumé.md").should be_true
    end

    it "returns false for paths with spaces or reserved punctuation" do
      Hwaro::Services::Creator.url_safe_path?("special chars!@#").should be_false
      Hwaro::Services::Creator.url_safe_path?("posts/hello world.md").should be_false
      Hwaro::Services::Creator.url_safe_path?("a?b.md").should be_false
    end
  end

  describe ".sanitize_url_path" do
    it "is a no-op for already-safe paths" do
      Hwaro::Services::Creator.sanitize_url_path("posts/hello.md").should eq("posts/hello.md")
      Hwaro::Services::Creator.sanitize_url_path("한글/포스트.md").should eq("한글/포스트.md")
    end

    it "collapses unsafe characters to a single hyphen per run" do
      Hwaro::Services::Creator.sanitize_url_path("special chars!@#").should eq("special-chars")
      Hwaro::Services::Creator.sanitize_url_path("a!!!b").should eq("a-b")
    end

    it "trims leading and trailing hyphens per segment" do
      Hwaro::Services::Creator.sanitize_url_path("!foo!/!bar!").should eq("foo/bar")
    end

    it "does not leave a hyphen dangling against an extension dot" do
      # Punctuation right before the extension used to leave `foo-.md`
      # because strip('-') can't reach a hyphen that sits before `.md`.
      Hwaro::Services::Creator.sanitize_url_path("posts/my post!.md").should eq("posts/my-post.md")
      Hwaro::Services::Creator.sanitize_url_path("a!.b").should eq("a.b")
    end

    it "preserves path separators and the RFC 3986 unreserved set" do
      Hwaro::Services::Creator.sanitize_url_path("posts/my_post.v2.md").should eq("posts/my_post.v2.md")
      Hwaro::Services::Creator.sanitize_url_path("a/b/c~d.md").should eq("a/b/c~d.md")
    end

    it "preserves original casing" do
      # Filesystem case-sensitivity varies; silently lowercasing could
      # clobber an existing sibling file.
      Hwaro::Services::Creator.sanitize_url_path("Posts/MyPost.md").should eq("Posts/MyPost.md")
    end

    it "handles mixed CJK and unsafe characters" do
      Hwaro::Services::Creator.sanitize_url_path("한글 테스트/포스트").should eq("한글-테스트/포스트")
    end

    it "drops segments that sanitize to empty so no leading slash appears" do
      # "!!!" sanitizes to an empty segment — the overall path must not
      # turn into "/foo.md" (which would look absolute to File.join).
      Hwaro::Services::Creator.sanitize_url_path("!!!/foo.md").should eq("foo.md")
      Hwaro::Services::Creator.sanitize_url_path("posts/!!!/bar").should eq("posts/bar")
    end

    it "raises ArgumentError when every segment sanitizes away" do
      expect_raises(ArgumentError, /no URL-safe characters/) do
        Hwaro::Services::Creator.sanitize_url_path("!!!")
      end
      expect_raises(ArgumentError, /no URL-safe characters/) do
        Hwaro::Services::Creator.sanitize_url_path("!!!/???")
      end
    end

    it "drops segments that sanitize to pure dots instead of synthesizing `..`" do
      # `>.>.` → `-.-.` → hyphen/dot collapse → `..` — a traversal segment
      # fabricated AFTER validate_and_normalize_path! already ran. It must
      # vanish like any empty segment, never join the on-disk path.
      Hwaro::Services::Creator.sanitize_url_path("posts/>.>./foo.md").should eq("posts/foo.md")
      Hwaro::Services::Creator.sanitize_url_path("a/>.>./>.>./b.md").should eq("a/b.md")
    end
  end
end
