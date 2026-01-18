require "./spec_helper"

describe Hwaro do
  describe "VERSION" do
    it "has a version number" do
      Hwaro::VERSION.should_not be_nil
      Hwaro::VERSION.should eq("0.1.0")
    end
  end

  describe Hwaro::Options::BuildOptions do
    it "has default values" do
      options = Hwaro::Options::BuildOptions.new
      options.output_dir.should eq("public")
      options.drafts.should eq(false)
      options.minify.should eq(false)
      options.parallel.should eq(true)
      options.cache.should eq(false)
    end

    it "accepts custom values" do
      options = Hwaro::Options::BuildOptions.new(
        output_dir: "dist",
        drafts: true,
        minify: true,
        parallel: false,
        cache: true
      )
      options.output_dir.should eq("dist")
      options.drafts.should eq(true)
      options.minify.should eq(true)
      options.parallel.should eq(false)
      options.cache.should eq(true)
    end
  end

  describe Hwaro::Options::ServeOptions do
    it "has default values" do
      options = Hwaro::Options::ServeOptions.new
      options.host.should eq("0.0.0.0")
      options.port.should eq(3000)
      options.drafts.should eq(false)
      options.open_browser.should eq(false)
    end

    it "converts to build options" do
      options = Hwaro::Options::ServeOptions.new(drafts: true)
      build_options = options.to_build_options
      build_options.drafts.should eq(true)
      build_options.output_dir.should eq("public")
    end
  end

  describe Hwaro::Options::InitOptions do
    it "has default values" do
      options = Hwaro::Options::InitOptions.new
      options.path.should eq(".")
      options.force.should eq(false)
    end
  end

  describe Hwaro::Schemas::Config do
    it "has default values" do
      config = Hwaro::Schemas::Config.new
      config.title.should eq("Hwaro Site")
      config.description.should eq("")
      config.base_url.should eq("")
      config.sitemap.should eq(false)
    end

    it "has default plugin configuration" do
      config = Hwaro::Schemas::Config.new
      config.plugins.processors.should eq(["markdown"])
    end
  end

  describe Hwaro::Plugins::Processors::Registry do
    it "has markdown processor registered by default" do
      Hwaro::Plugins::Processors::Registry.has?("markdown").should be_true
    end

    it "has html processor registered" do
      Hwaro::Plugins::Processors::Registry.has?("html").should be_true
    end

    it "can list all processor names" do
      names = Hwaro::Plugins::Processors::Registry.names
      names.should contain("markdown")
      names.should contain("html")
    end
  end

  describe Hwaro::CLI::CommandRegistry do
    it "has init command registered" do
      Hwaro::CLI::CommandRegistry.has?("init").should be_true
    end

    it "has build command registered" do
      Hwaro::CLI::CommandRegistry.has?("build").should be_true
    end

    it "has serve command registered" do
      Hwaro::CLI::CommandRegistry.has?("serve").should be_true
    end
  end

  describe Hwaro::Processor::Markdown do
    describe "parse" do
      it "parses TOML frontmatter with in_sitemap" do
        content = <<-MARKDOWN
        +++
        title = "Test Page"
        draft = false
        in_sitemap = false
        +++

        # Content
        MARKDOWN

        result = Hwaro::Processor::Markdown.parse(content)
        result.should_not be_nil
        if result
          title, markdown, draft, layout, in_sitemap = result
          title.should eq("Test Page")
          draft.should eq(false)
          in_sitemap.should eq(false)
        end
      end

      it "defaults in_sitemap to true when not specified in TOML" do
        content = <<-MARKDOWN
        +++
        title = "Test Page"
        +++

        # Content
        MARKDOWN

        result = Hwaro::Processor::Markdown.parse(content)
        result.should_not be_nil
        if result
          title, markdown, draft, layout, in_sitemap = result
          in_sitemap.should eq(true)
        end
      end

      it "parses YAML frontmatter with in_sitemap" do
        content = <<-MARKDOWN
        ---
        title: Test Page
        draft: false
        in_sitemap: false
        ---

        # Content
        MARKDOWN

        result = Hwaro::Processor::Markdown.parse(content)
        result.should_not be_nil
        if result
          title, markdown, draft, layout, in_sitemap = result
          title.should eq("Test Page")
          draft.should eq(false)
          in_sitemap.should eq(false)
        end
      end

      it "defaults in_sitemap to true when not specified in YAML" do
        content = <<-MARKDOWN
        ---
        title: Test Page
        ---

        # Content
        MARKDOWN

        result = Hwaro::Processor::Markdown.parse(content)
        result.should_not be_nil
        if result
          title, markdown, draft, layout, in_sitemap = result
          in_sitemap.should eq(true)
        end
      end

      it "handles in_sitemap explicitly set to true in TOML" do
        content = <<-MARKDOWN
        +++
        title = "Test Page"
        in_sitemap = true
        +++

        # Content
        MARKDOWN

        result = Hwaro::Processor::Markdown.parse(content)
        result.should_not be_nil
        if result
          title, markdown, draft, layout, in_sitemap = result
          in_sitemap.should eq(true)
        end
      end

      it "handles in_sitemap explicitly set to true in YAML" do
        content = <<-MARKDOWN
        ---
        title: Test Page
        in_sitemap: true
        ---

        # Content
        MARKDOWN

        result = Hwaro::Processor::Markdown.parse(content)
        result.should_not be_nil
        if result
          title, markdown, draft, layout, in_sitemap = result
          in_sitemap.should eq(true)
        end
      end
    end
  end
end
