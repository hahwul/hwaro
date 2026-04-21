require "../spec_helper"
require "../../src/services/initializer"
require "../../src/services/creator"
require "file_utils"

describe Hwaro::Services::Initializer do
  describe "#run" do
    it "creates basic project structure" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "mysite")
        initializer = Hwaro::Services::Initializer.new
        initializer.run(target)

        Dir.exists?(File.join(target, "content")).should be_true
        Dir.exists?(File.join(target, "templates")).should be_true
        Dir.exists?(File.join(target, "static")).should be_true
        File.exists?(File.join(target, "config.toml")).should be_true
        File.exists?(File.join(target, "AGENTS.md")).should be_true
      end
    end

    it "creates target directory if it does not exist" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "new", "nested", "site")
        initializer = Hwaro::Services::Initializer.new
        initializer.run(target)

        Dir.exists?(target).should be_true
        File.exists?(File.join(target, "config.toml")).should be_true
      end
    end

    describe "--force option" do
      it "overwrites non-empty directory with force=true" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "existing")
          Dir.mkdir_p(target)
          File.write(File.join(target, "existing_file.txt"), "hello")

          initializer = Hwaro::Services::Initializer.new
          initializer.run(target, force: true)

          File.exists?(File.join(target, "config.toml")).should be_true
          File.exists?(File.join(target, "existing_file.txt")).should be_true
        end
      end
    end

    describe "--skip-agents-md option" do
      it "does not create AGENTS.md when skip_agents_md=true" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          initializer = Hwaro::Services::Initializer.new
          initializer.run(target, skip_agents_md: true)

          File.exists?(File.join(target, "AGENTS.md")).should be_false
          File.exists?(File.join(target, "config.toml")).should be_true
        end
      end

      it "creates AGENTS.md by default" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          initializer = Hwaro::Services::Initializer.new
          initializer.run(target)

          File.exists?(File.join(target, "AGENTS.md")).should be_true
        end
      end
    end

    describe "--skip-sample-content option" do
      it "creates content dir but no sample files when skip_sample_content=true" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          initializer = Hwaro::Services::Initializer.new
          initializer.run(target, skip_sample_content: true)

          Dir.exists?(File.join(target, "content")).should be_true
          # Templates should still be created
          Dir.exists?(File.join(target, "templates")).should be_true
        end
      end
    end

    describe "--skip-taxonomies option" do
      it "creates project without taxonomy content when skip_taxonomies=true" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          initializer = Hwaro::Services::Initializer.new
          initializer.run(target, skip_taxonomies: true)

          File.exists?(File.join(target, "config.toml")).should be_true
          Dir.exists?(File.join(target, "content")).should be_true
        end
      end
    end

    describe "scaffold types" do
      it "initializes with simple scaffold" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          initializer = Hwaro::Services::Initializer.new
          initializer.run(target, scaffold_type: Hwaro::Config::Options::ScaffoldType::Simple)

          File.exists?(File.join(target, "config.toml")).should be_true
          Dir.exists?(File.join(target, "content")).should be_true
        end
      end

      it "initializes with blog scaffold" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          initializer = Hwaro::Services::Initializer.new
          initializer.run(target, scaffold_type: Hwaro::Config::Options::ScaffoldType::Blog)

          File.exists?(File.join(target, "config.toml")).should be_true
          Dir.exists?(File.join(target, "content")).should be_true
          Dir.exists?(File.join(target, "templates")).should be_true
        end
      end

      it "initializes with docs scaffold" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          initializer = Hwaro::Services::Initializer.new
          initializer.run(target, scaffold_type: Hwaro::Config::Options::ScaffoldType::Docs)

          File.exists?(File.join(target, "config.toml")).should be_true
          Dir.exists?(File.join(target, "content")).should be_true
          Dir.exists?(File.join(target, "templates")).should be_true
        end
      end
    end

    describe "archetypes" do
      it "creates archetypes/default.md for built-in scaffolds" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          Hwaro::Services::Initializer.new.run(target)

          archetype_path = File.join(target, "archetypes", "default.md")
          File.exists?(archetype_path).should be_true

          content = File.read(archetype_path)
          content.should contain("+++")
          content.should contain("title = \"{{ title }}\"")
          content.should contain("description = \"\"")
        end
      end

      it "ships a posts archetype with the blog scaffold" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          Hwaro::Services::Initializer.new.run(
            target,
            scaffold_type: Hwaro::Config::Options::ScaffoldType::Blog,
          )

          posts_path = File.join(target, "archetypes", "posts.md")
          File.exists?(posts_path).should be_true

          content = File.read(posts_path)
          content.should contain("authors = []")
          content.should contain("categories = []")
        end
      end

      it "ships section archetypes with the docs scaffold" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          Hwaro::Services::Initializer.new.run(
            target,
            scaffold_type: Hwaro::Config::Options::ScaffoldType::Docs,
          )

          %w[getting-started guide reference].each do |name|
            File.exists?(File.join(target, "archetypes", "#{name}.md")).should be_true
          end
          content = File.read(File.join(target, "archetypes", "guide.md"))
          # `weight` is commented out so every new docs page doesn't
          # default to the same weight and collide on ordering.
          content.should contain("# weight = 10")
          content.should_not match(/^weight = /m)
          content.should contain("toc = true")
        end
      end

      it "makes `hwaro new` pick up the scaffolded default archetype" do
        # Regression: the whole point of shipping `archetypes/default.md`
        # is that `Services::Creator#find_archetype` should match it for
        # fresh sites, producing TOML front matter with `description`
        # instead of the hardcoded built-in template.
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          Hwaro::Services::Initializer.new.run(target)

          Dir.cd(target) do
            FileUtils.mkdir_p("content/drafts")
            options = Hwaro::Config::Options::NewOptions.new(path: "hello.md", title: "Hello")
            Hwaro::Services::Creator.new.run(options)

            content = File.read("content/drafts/hello.md")
            content.should contain("+++")
            content.should contain("title = \"Hello\"")
            content.should contain("description = \"\"")
          end
        end
      end
    end

    describe "multilingual initialization" do
      it "creates multilingual project with multiple languages" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          initializer = Hwaro::Services::Initializer.new
          initializer.run(target, multilingual_languages: ["en", "ko"])

          File.exists?(File.join(target, "config.toml")).should be_true
          config_content = File.read(File.join(target, "config.toml"))
          config_content.should contain("default_language = \"en\"")
          config_content.should contain("[languages.en]")
          config_content.should contain("[languages.ko]")

          # Default language content (no suffix)
          File.exists?(File.join(target, "content", "index.md")).should be_true
          # Second language content (with lang suffix)
          File.exists?(File.join(target, "content", "index.ko.md")).should be_true
        end
      end

      it "treats single language as non-multilingual" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          initializer = Hwaro::Services::Initializer.new
          initializer.run(target, multilingual_languages: ["en"])

          File.exists?(File.join(target, "config.toml")).should be_true
          config_content = File.read(File.join(target, "config.toml"))
          # Single language should use standard (non-multilingual) config
          config_content.should_not contain("[languages]")
        end
      end

      it "creates multilingual blog content" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          initializer = Hwaro::Services::Initializer.new
          initializer.run(target, multilingual_languages: ["en", "ja"])

          # Default language blog
          File.exists?(File.join(target, "content", "blog", "_index.md")).should be_true
          File.exists?(File.join(target, "content", "blog", "hello-world.md")).should be_true
          # Second language blog
          File.exists?(File.join(target, "content", "blog", "_index.ja.md")).should be_true
          File.exists?(File.join(target, "content", "blog", "hello-world.ja.md")).should be_true
        end
      end

      it "skips blog content in multilingual mode with skip_taxonomies" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          initializer = Hwaro::Services::Initializer.new
          initializer.run(target, multilingual_languages: ["en", "ko"], skip_taxonomies: true)

          File.exists?(File.join(target, "content", "index.md")).should be_true
          Dir.exists?(File.join(target, "content", "blog")).should be_false
        end
      end
    end

    describe "agents mode" do
      it "creates remote AGENTS.md by default" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          initializer = Hwaro::Services::Initializer.new
          initializer.run(target)

          agents_content = File.read(File.join(target, "AGENTS.md"))
          agents_content.should contain "hwaro.hahwul.com"
          agents_content.should contain "llms-full.txt"
        end
      end

      it "creates local AGENTS.md when agents_mode is local" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          initializer = Hwaro::Services::Initializer.new
          initializer.run(target, agents_mode: Hwaro::Config::Options::AgentsMode::Local)

          agents_content = File.read(File.join(target, "AGENTS.md"))
          agents_content.should contain "## Content"
          agents_content.should contain "## Templates"
        end
      end
    end

    describe "InitOptions struct" do
      it "accepts InitOptions for run" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          options = Hwaro::Config::Options::InitOptions.new(
            path: target,
            force: false,
            skip_agents_md: true,
            skip_sample_content: false,
            skip_taxonomies: false,
          )

          initializer = Hwaro::Services::Initializer.new
          initializer.run(options)

          File.exists?(File.join(target, "config.toml")).should be_true
          File.exists?(File.join(target, "AGENTS.md")).should be_false
        end
      end

      it "respects agents_mode in InitOptions" do
        Dir.mktmpdir do |dir|
          target = File.join(dir, "site")
          options = Hwaro::Config::Options::InitOptions.new(
            path: target,
            agents_mode: Hwaro::Config::Options::AgentsMode::Local,
          )

          initializer = Hwaro::Services::Initializer.new
          initializer.run(options)

          agents_content = File.read(File.join(target, "AGENTS.md"))
          agents_content.should contain "## Templates"
        end
      end
    end
  end
end
