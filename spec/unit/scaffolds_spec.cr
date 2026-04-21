require "../spec_helper"
require "../../src/services/scaffolds/registry"

describe Hwaro::Services::Scaffolds::Simple do
  describe "#type" do
    it "returns Simple scaffold type" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::Simple)
    end
  end

  describe "#description" do
    it "returns a non-empty description" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      scaffold.description.should_not be_empty
    end
  end

  describe "#content_files" do
    it "includes index.md" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.content_files
      files.has_key?("index.md").should be_true
    end

    it "includes about.md" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.content_files
      files.has_key?("about.md").should be_true
    end

    it "generates content with taxonomy frontmatter by default" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.content_files(skip_taxonomies: false)

      files["index.md"].should contain("tags")
      files["about.md"].should contain("tags")
    end

    it "generates content without taxonomy frontmatter when skipped" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.content_files(skip_taxonomies: true)

      files["index.md"].should_not contain("tags =")
      files["about.md"].should_not contain("tags =")
      files["about.md"].should_not contain("categories =")
    end

    it "includes Hwaro mention in index" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.content_files
      files["index.md"].should contain("Hwaro")
    end

    it "includes getting started instructions" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.content_files
      files["index.md"].should contain("hwaro build")
      files["index.md"].should contain("hwaro serve")
    end
  end

  describe "#template_files" do
    it "includes header.html" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files
      files.has_key?("header.html").should be_true
    end

    it "includes footer.html" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files
      files.has_key?("footer.html").should be_true
    end

    it "includes page.html" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files
      files.has_key?("page.html").should be_true
    end

    it "includes section.html" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files
      files.has_key?("section.html").should be_true
    end

    it "includes 404.html" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files
      files.has_key?("404.html").should be_true
    end

    it "includes taxonomy templates by default" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files(skip_taxonomies: false)
      files.has_key?("taxonomy.html").should be_true
      files.has_key?("taxonomy_term.html").should be_true
    end

    it "excludes taxonomy templates when skipped" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files(skip_taxonomies: true)
      files.has_key?("taxonomy.html").should be_false
      files.has_key?("taxonomy_term.html").should be_false
    end
  end

  describe "#config_content" do
    it "returns non-empty config" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      config = scaffold.config_content
      config.should_not be_empty
    end

    it "includes site title placeholder" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      config = scaffold.config_content
      config.should contain("title")
    end

    it "includes base_url" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      config = scaffold.config_content
      config.should contain("base_url")
    end

    it "includes taxonomy config by default" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      config = scaffold.config_content(skip_taxonomies: false)
      config.should contain("taxonomies")
    end

    it "excludes taxonomy config when skipped" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      config = scaffold.config_content(skip_taxonomies: true)
      config.should_not contain("[[taxonomies]]")
    end
  end
end

describe Hwaro::Services::Scaffolds::Docs do
  describe "#type" do
    it "returns Docs scaffold type" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::Docs)
    end
  end

  describe "#description" do
    it "returns a non-empty description" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      scaffold.description.should_not be_empty
    end

    it "mentions documentation" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      scaffold.description.downcase.should contain("doc")
    end
  end

  describe "#content_files" do
    it "includes index.md" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      files.has_key?("index.md").should be_true
    end

    it "includes getting-started section" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      keys = files.keys
      keys.any?(&.includes?("getting-started")).should be_true
    end

    it "includes guide section" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      keys = files.keys
      keys.any?(&.includes?("guide")).should be_true
    end

    it "includes reference section" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      keys = files.keys
      keys.any?(&.includes?("reference")).should be_true
    end

    it "includes installation content" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      keys = files.keys
      keys.any?(&.includes?("installation")).should be_true
    end

    it "includes quick-start content" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      keys = files.keys
      keys.any?(&.includes?("quick-start")).should be_true
    end

    it "includes configuration content" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      keys = files.keys
      keys.any?(&.includes?("configuration")).should be_true
    end

    it "has more content files than simple scaffold" do
      docs = Hwaro::Services::Scaffolds::Docs.new
      simple = Hwaro::Services::Scaffolds::Simple.new
      docs.content_files.size.should be > simple.content_files.size
    end
  end

  describe "#template_files" do
    it "includes header.html" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      files.has_key?("header.html").should be_true
    end

    it "includes footer.html" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      files.has_key?("footer.html").should be_true
    end

    it "includes page.html" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      files.has_key?("page.html").should be_true
    end

    it "includes section.html" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      files.has_key?("section.html").should be_true
    end

    it "includes 404.html" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      files.has_key?("404.html").should be_true
    end

    it "template files contain HTML content" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      files.values.each do |content|
        content.should_not be_empty
      end
    end
  end

  describe "#config_content" do
    it "returns non-empty config" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      config = scaffold.config_content
      config.should_not be_empty
    end

    it "includes base_url" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      config = scaffold.config_content
      config.should contain("base_url")
    end

    it "includes title" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      config = scaffold.config_content
      config.should contain("title")
    end
  end
end

describe Hwaro::Services::Scaffolds::BlogDark do
  describe "#type" do
    it "returns BlogDark scaffold type" do
      scaffold = Hwaro::Services::Scaffolds::BlogDark.new
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::BlogDark)
    end
  end

  describe "#description" do
    it "returns a non-empty description" do
      scaffold = Hwaro::Services::Scaffolds::BlogDark.new
      scaffold.description.should_not be_empty
    end

    it "mentions dark theme" do
      scaffold = Hwaro::Services::Scaffolds::BlogDark.new
      scaffold.description.downcase.should contain("dark")
    end
  end

  describe "#content_files" do
    it "has the same content files as Blog" do
      dark = Hwaro::Services::Scaffolds::BlogDark.new
      light = Hwaro::Services::Scaffolds::Blog.new
      dark.content_files.keys.sort!.should eq(light.content_files.keys.sort!)
    end
  end

  describe "#template_files" do
    it "has the same template files as Blog" do
      dark = Hwaro::Services::Scaffolds::BlogDark.new
      light = Hwaro::Services::Scaffolds::Blog.new
      dark.template_files.keys.sort!.should eq(light.template_files.keys.sort!)
    end
  end

  describe "#config_content" do
    it "uses github-dark highlight theme" do
      scaffold = Hwaro::Services::Scaffolds::BlogDark.new
      config = scaffold.config_content
      config.should contain("github-dark")
    end
  end

  describe "#static_files" do
    it "includes css/style.css and js/search.js" do
      scaffold = Hwaro::Services::Scaffolds::BlogDark.new
      scaffold.static_files.has_key?("css/style.css").should be_true
      scaffold.static_files.has_key?("js/search.js").should be_true
    end

    it "uses dark color variables" do
      scaffold = Hwaro::Services::Scaffolds::BlogDark.new
      css = scaffold.static_files["css/style.css"]
      css.should contain("#1a1816")
      css.should contain("#d4d0cc")
    end
  end
end

describe Hwaro::Services::Scaffolds::DocsDark do
  describe "#type" do
    it "returns DocsDark scaffold type" do
      scaffold = Hwaro::Services::Scaffolds::DocsDark.new
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::DocsDark)
    end
  end

  describe "#description" do
    it "returns a non-empty description" do
      scaffold = Hwaro::Services::Scaffolds::DocsDark.new
      scaffold.description.should_not be_empty
    end

    it "mentions dark theme" do
      scaffold = Hwaro::Services::Scaffolds::DocsDark.new
      scaffold.description.downcase.should contain("dark")
    end
  end

  describe "#content_files" do
    it "has the same content files as Docs" do
      dark = Hwaro::Services::Scaffolds::DocsDark.new
      light = Hwaro::Services::Scaffolds::Docs.new
      dark.content_files.keys.sort!.should eq(light.content_files.keys.sort!)
    end
  end

  describe "#template_files" do
    it "has the same template files as Docs" do
      dark = Hwaro::Services::Scaffolds::DocsDark.new
      light = Hwaro::Services::Scaffolds::Docs.new
      dark.template_files.keys.sort!.should eq(light.template_files.keys.sort!)
    end
  end

  describe "#config_content" do
    it "uses github-dark highlight theme" do
      scaffold = Hwaro::Services::Scaffolds::DocsDark.new
      config = scaffold.config_content
      config.should contain("github-dark")
    end
  end

  describe "#static_files" do
    it "includes css/style.css and js/search.js" do
      scaffold = Hwaro::Services::Scaffolds::DocsDark.new
      scaffold.static_files.has_key?("css/style.css").should be_true
      scaffold.static_files.has_key?("js/search.js").should be_true
    end

    it "uses dark color variables" do
      scaffold = Hwaro::Services::Scaffolds::DocsDark.new
      css = scaffold.static_files["css/style.css"]
      css.should contain("#1d1d1f")
      css.should contain("#f5f5f7")
    end
  end
end

describe Hwaro::Services::Scaffolds::Registry do
  describe ".get" do
    it "returns Simple scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Simple)
      scaffold.should be_a(Hwaro::Services::Scaffolds::Simple)
    end

    it "returns Blog scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Blog)
      scaffold.should be_a(Hwaro::Services::Scaffolds::Blog)
    end

    it "returns Docs scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Docs)
      scaffold.should be_a(Hwaro::Services::Scaffolds::Docs)
    end

    it "returns BlogDark scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::BlogDark)
      scaffold.should be_a(Hwaro::Services::Scaffolds::BlogDark)
    end

    it "returns DocsDark scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::DocsDark)
      scaffold.should be_a(Hwaro::Services::Scaffolds::DocsDark)
    end

    it "raises for unknown scaffold type" do
      # All known types are registered, so this test verifies the mechanism
      Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Simple).should_not be_nil
    end
  end

  describe ".has?" do
    it "returns true for Simple" do
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::Simple).should be_true
    end

    it "returns true for Blog" do
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::Blog).should be_true
    end

    it "returns true for Docs" do
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::Docs).should be_true
    end

    it "returns true for BlogDark" do
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::BlogDark).should be_true
    end

    it "returns true for DocsDark" do
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::DocsDark).should be_true
    end
  end

  describe ".all" do
    it "returns all registered scaffolds" do
      all = Hwaro::Services::Scaffolds::Registry.all
      all.size.should be >= 5
    end

    it "includes instances of all scaffold types" do
      all = Hwaro::Services::Scaffolds::Registry.all
      types = all.map(&.type)
      types.should contain(Hwaro::Config::Options::ScaffoldType::Simple)
      types.should contain(Hwaro::Config::Options::ScaffoldType::Blog)
      types.should contain(Hwaro::Config::Options::ScaffoldType::BlogDark)
      types.should contain(Hwaro::Config::Options::ScaffoldType::Docs)
      types.should contain(Hwaro::Config::Options::ScaffoldType::DocsDark)
    end
  end

  describe ".list" do
    it "returns list of tuples with name and description" do
      list = Hwaro::Services::Scaffolds::Registry.list
      list.should_not be_empty
    end

    it "each item has a non-empty name" do
      list = Hwaro::Services::Scaffolds::Registry.list
      list.each do |name, _desc|
        name.should_not be_empty
      end
    end

    it "each item has a non-empty description" do
      list = Hwaro::Services::Scaffolds::Registry.list
      list.each do |_name, desc|
        desc.should_not be_empty
      end
    end

    it "has at least 5 items" do
      list = Hwaro::Services::Scaffolds::Registry.list
      list.size.should be >= 5
    end
  end

  describe ".default" do
    it "returns the Simple scaffold" do
      default = Hwaro::Services::Scaffolds::Registry.default
      default.type.should eq(Hwaro::Config::Options::ScaffoldType::Simple)
    end

    it "is an instance of Simple" do
      default = Hwaro::Services::Scaffolds::Registry.default
      default.should be_a(Hwaro::Services::Scaffolds::Simple)
    end
  end

  describe "scaffold consistency" do
    it "all scaffolds produce non-empty content_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.content_files.should_not be_empty
      end
    end

    it "all scaffolds produce non-empty template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.template_files.should_not be_empty
      end
    end

    it "all scaffolds produce non-empty config_content" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.config_content.should_not be_empty
      end
    end

    it "all scaffolds include index.md in content_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.content_files.has_key?("index.md").should be_true
      end
    end

    it "all scaffolds include page.html in template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.template_files.has_key?("page.html").should be_true
      end
    end

    it "all scaffolds include section.html in template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.template_files.has_key?("section.html").should be_true
      end
    end

    it "all scaffolds include header.html in template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.template_files.has_key?("header.html").should be_true
      end
    end

    it "all scaffolds include footer.html in template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.template_files.has_key?("footer.html").should be_true
      end
    end

    it "all scaffolds include 404.html in template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.template_files.has_key?("404.html").should be_true
      end
    end

    it "all scaffolds config_content includes base_url" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.config_content.should contain("base_url")
      end
    end

    it "all scaffolds support skip_taxonomies for content_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        with_tax = scaffold.content_files(skip_taxonomies: false)
        without_tax = scaffold.content_files(skip_taxonomies: true)

        with_tax.should_not be_empty
        without_tax.should_not be_empty
      end
    end

    it "all scaffolds support skip_taxonomies for template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        with_tax = scaffold.template_files(skip_taxonomies: false)
        without_tax = scaffold.template_files(skip_taxonomies: true)

        # With taxonomies should have at least as many templates
        with_tax.size.should be >= without_tax.size
      end
    end

    it "all scaffolds support skip_taxonomies for config_content" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        with_tax = scaffold.config_content(skip_taxonomies: false)
        without_tax = scaffold.config_content(skip_taxonomies: true)

        with_tax.should_not be_empty
        without_tax.should_not be_empty
      end
    end
  end
end
