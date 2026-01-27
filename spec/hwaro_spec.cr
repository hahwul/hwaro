require "./spec_helper"

describe Hwaro do
  describe "VERSION" do
    it "has a version number" do
      Hwaro::VERSION.should_not be_nil
      Hwaro::VERSION.should eq("0.0.6")
    end
  end

  describe Hwaro::Config::Options::BuildOptions do
    it "has default values" do
      options = Hwaro::Config::Options::BuildOptions.new
      options.output_dir.should eq("public")
      options.drafts.should eq(false)
      options.minify.should eq(false)
      options.parallel.should eq(true)
      options.cache.should eq(false)
    end

    it "accepts custom values" do
      options = Hwaro::Config::Options::BuildOptions.new(
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

  describe Hwaro::Config::Options::ServeOptions do
    it "has default values" do
      options = Hwaro::Config::Options::ServeOptions.new
      options.host.should eq("0.0.0.0")
      options.port.should eq(3000)
      options.drafts.should eq(false)
      options.open_browser.should eq(false)
    end

    it "converts to build options" do
      options = Hwaro::Config::Options::ServeOptions.new(drafts: true)
      build_options = options.to_build_options
      build_options.drafts.should eq(true)
      build_options.output_dir.should eq("public")
    end
  end

  describe Hwaro::Config::Options::InitOptions do
    it "has default values" do
      options = Hwaro::Config::Options::InitOptions.new
      options.path.should eq(".")
      options.force.should eq(false)
    end
  end

  describe Hwaro::Models::Config do
    it "has default values" do
      config = Hwaro::Models::Config.new
      config.title.should eq("Hwaro Site")
      config.description.should eq("")
      config.base_url.should eq("")
      config.sitemap.enabled.should eq(false)
      config.feeds.enabled.should eq(false)
      config.search.enabled.should eq(false)
      config.taxonomies.should eq([] of Hwaro::Models::TaxonomyConfig)
    end

    it "has default search configuration" do
      config = Hwaro::Models::Config.new
      config.search.enabled.should eq(false)
      config.search.format.should eq("fuse_json")
      config.search.fields.should eq(["title", "content"])
      config.search.filename.should eq("search.json")
    end

    it "has default plugin configuration" do
      config = Hwaro::Models::Config.new
      config.plugins.processors.should eq(["markdown"])
    end

    it "has default pagination configuration" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled.should eq(false)
      config.pagination.per_page.should eq(10)
    end
  end

  describe Hwaro::Models::Section do
    it "has pagination properties" do
      section = Hwaro::Models::Section.new("wiki/index.md")
      section.paginate.should be_nil
      section.pagination_enabled.should be_nil
    end

    it "can set pagination properties" do
      section = Hwaro::Models::Section.new("wiki/index.md")
      section.paginate = 5
      section.pagination_enabled = true
      section.paginate.should eq(5)
      section.pagination_enabled.should eq(true)
    end
  end

  describe Hwaro::Content::Pagination::Paginator do
    it "creates a paginator with config" do
      config = Hwaro::Models::Config.new
      paginator = Hwaro::Content::Pagination::Paginator.new(config)
      paginator.should_not be_nil
    end

    it "paginates pages when enabled" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled = true
      config.pagination.per_page = 2

      section = Hwaro::Models::Section.new("wiki/index.md")
      section.section = "wiki"

      pages = [
        Hwaro::Models::Page.new("wiki/1.md"),
        Hwaro::Models::Page.new("wiki/2.md"),
        Hwaro::Models::Page.new("wiki/3.md"),
      ]
      pages.each { |p| p.section = "wiki"; p.title = p.path }

      paginator = Hwaro::Content::Pagination::Paginator.new(config)
      result = paginator.paginate(section, pages)

      result.enabled.should eq(true)
      result.per_page.should eq(2)
      result.paginated_pages.size.should eq(2)
      result.paginated_pages[0].page_number.should eq(1)
      result.paginated_pages[0].pages.size.should eq(2)
      result.paginated_pages[1].page_number.should eq(2)
      result.paginated_pages[1].pages.size.should eq(1)
    end

    it "returns single page when pagination is disabled" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled = false

      section = Hwaro::Models::Section.new("wiki/index.md")
      section.section = "wiki"

      pages = [
        Hwaro::Models::Page.new("wiki/1.md"),
        Hwaro::Models::Page.new("wiki/2.md"),
      ]
      pages.each { |p| p.section = "wiki"; p.title = p.path }

      paginator = Hwaro::Content::Pagination::Paginator.new(config)
      result = paginator.paginate(section, pages)

      result.enabled.should eq(false)
      result.paginated_pages.size.should eq(1)
      result.paginated_pages[0].pages.size.should eq(2)
    end

    it "respects section-level pagination override" do
      config = Hwaro::Models::Config.new
      config.pagination.enabled = false # Globally disabled
      config.pagination.per_page = 10

      section = Hwaro::Models::Section.new("wiki/index.md")
      section.section = "wiki"
      section.pagination_enabled = true # Section-level override
      section.paginate = 1              # Section-level per_page

      pages = [
        Hwaro::Models::Page.new("wiki/1.md"),
        Hwaro::Models::Page.new("wiki/2.md"),
      ]
      pages.each { |p| p.section = "wiki"; p.title = p.path }

      paginator = Hwaro::Content::Pagination::Paginator.new(config)
      result = paginator.paginate(section, pages)

      result.enabled.should eq(true)
      result.per_page.should eq(1)
      result.paginated_pages.size.should eq(2)
    end
  end

  describe Hwaro::Content::Pagination::Renderer do
    it "renders section list" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("wiki/1.md")
      page.title = "Test Page"
      page.url = "/wiki/1/"

      paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
        pages: [page],
        page_number: 1,
        total_pages: 1,
        per_page: 10,
        total_items: 1,
        has_prev: false,
        has_next: false,
        prev_url: nil,
        next_url: nil,
        first_url: "/wiki/",
        last_url: "/wiki/"
      )

      renderer = Hwaro::Content::Pagination::Renderer.new(config)
      html = renderer.render_section_list(paginated_page)

      html.should contain("<li>")
      html.should contain("<a href=\"https://example.com/wiki/1/\">Test Page</a>")
    end

    it "renders pagination nav when multiple pages" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
        pages: [] of Hwaro::Models::Page,
        page_number: 1,
        total_pages: 3,
        per_page: 10,
        total_items: 25,
        has_prev: false,
        has_next: true,
        prev_url: nil,
        next_url: "/wiki/page/2/",
        first_url: "/wiki/",
        last_url: "/wiki/page/3/"
      )

      renderer = Hwaro::Content::Pagination::Renderer.new(config)
      html = renderer.render_pagination_nav(paginated_page)

      html.should contain("<nav class=\"pagination\"")
      html.should contain("Next")
      html.should contain("pagination-disabled") # Previous is disabled on page 1
    end

    it "returns empty string for single page" do
      config = Hwaro::Models::Config.new

      paginated_page = Hwaro::Content::Pagination::PaginatedPage.new(
        pages: [] of Hwaro::Models::Page,
        page_number: 1,
        total_pages: 1,
        per_page: 10,
        total_items: 5,
        has_prev: false,
        has_next: false,
        prev_url: nil,
        next_url: nil,
        first_url: "/wiki/",
        last_url: "/wiki/"
      )

      renderer = Hwaro::Content::Pagination::Renderer.new(config)
      html = renderer.render_pagination_nav(paginated_page)

      html.should eq("")
    end
  end

  describe Hwaro::Content::Processors::Registry do
    it "has markdown processor registered by default" do
      Hwaro::Content::Processors::Registry.has?("markdown").should be_true
    end

    it "has html processor registered" do
      Hwaro::Content::Processors::Registry.has?("html").should be_true
    end

    it "can list all processor names" do
      names = Hwaro::Content::Processors::Registry.names
      names.should contain("markdown")
      names.should contain("html")
    end
  end

  describe Hwaro::CLI::CommandRegistry do
    # Initialize runner to register commands
    Hwaro::CLI::Runner.new

    it "has init command registered" do
      Hwaro::CLI::CommandRegistry.has?("init").should be_true
    end

    it "has build command registered" do
      Hwaro::CLI::CommandRegistry.has?("build").should be_true
    end

    it "has serve command registered" do
      Hwaro::CLI::CommandRegistry.has?("serve").should be_true
    end

    it "has deploy command registered" do
      Hwaro::CLI::CommandRegistry.has?("deploy").should be_true
    end
  end

  describe Hwaro::Processor::Markdown do
    describe "parse" do
      it "captures front matter keys for taxonomy detection" do
        content = <<-MARKDOWN
        +++
        title = "Post"
        tags = ["a"]
        categories = []
        +++

        # Content
        MARKDOWN

        result = Hwaro::Processor::Markdown.parse(content)
        result[:front_matter_keys].should contain("tags")
        result[:front_matter_keys].should contain("categories")
      end

      it "keeps empty taxonomy arrays for configured keys" do
        content = <<-MARKDOWN
        ---
        title: Post
        categories: []
        ---

        # Content
        MARKDOWN

        result = Hwaro::Processor::Markdown.parse(content)
        result[:taxonomies].has_key?("categories").should be_true
        result[:taxonomies]["categories"].should eq([] of String)
      end
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
        result[:title].should eq("Test Page")
        result[:draft].should eq(false)
        result[:in_sitemap].should eq(false)
      end

      it "defaults in_sitemap to true when not specified in TOML" do
        content = <<-MARKDOWN
        +++
        title = "Test Page"
        +++

        # Content
        MARKDOWN

        result = Hwaro::Processor::Markdown.parse(content)
        result[:in_sitemap].should eq(true)
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
        result[:title].should eq("Test Page")
        result[:draft].should eq(false)
        result[:in_sitemap].should eq(false)
      end

      it "defaults in_sitemap to true when not specified in YAML" do
        content = <<-MARKDOWN
        ---
        title: Test Page
        ---

        # Content
        MARKDOWN

        result = Hwaro::Processor::Markdown.parse(content)
        result[:in_sitemap].should eq(true)
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
        result[:in_sitemap].should eq(true)
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
        result[:in_sitemap].should eq(true)
      end

      it "parses pagination settings from TOML frontmatter" do
        content = <<-MARKDOWN
        +++
        title = "Wiki"
        paginate = 5
        pagination_enabled = true
        +++

        # Wiki Section
        MARKDOWN

        result = Hwaro::Processor::Markdown.parse(content)
        result[:paginate].should eq(5)
        result[:pagination_enabled].should eq(true)
      end

      it "parses pagination settings from YAML frontmatter" do
        content = <<-MARKDOWN
        ---
        title: Wiki
        paginate: 10
        pagination_enabled: false
        ---

        # Wiki Section
        MARKDOWN

        result = Hwaro::Processor::Markdown.parse(content)
        result[:paginate].should eq(10)
        result[:pagination_enabled].should eq(false)
      end

      it "defaults pagination settings to nil when not specified" do
        content = <<-MARKDOWN
        +++
        title = "Test Page"
        +++

        # Content
        MARKDOWN

        result = Hwaro::Processor::Markdown.parse(content)
        result[:paginate].should be_nil
        result[:pagination_enabled].should be_nil
      end
    end
  end
end
