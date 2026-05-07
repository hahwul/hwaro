require "../spec_helper"
require "../../src/services/scaffolds/registry"

# =============================================================================
# Unit specs for the Book / BookDark scaffolds and the abstract Base class.
#
# Existing scaffolds_spec.cr (600 lines) covers Simple, Docs, BlogDark,
# DocsDark, and Registry. scaffolds_blog_spec.cr / scaffolds_bare_spec.cr
# / scaffolds_docs_spec.cr cover the remaining named scaffolds. Book and
# BookDark were referenced only in scaffold_registry_spec.cr (lookup) and
# had no functional coverage; Base (abstract class) likewise had no spec.
# =============================================================================

describe Hwaro::Services::Scaffolds::Book do
  describe "#type" do
    it "returns Book scaffold type" do
      Hwaro::Services::Scaffolds::Book.new.type
        .should eq(Hwaro::Config::Options::ScaffoldType::Book)
    end
  end

  describe "#description" do
    it "is a non-empty string mentioning Book-style structure" do
      desc = Hwaro::Services::Scaffolds::Book.new.description
      desc.should_not be_empty
      desc.should contain("Book-style")
    end
  end

  describe "#content_files" do
    it "includes the root index" do
      files = Hwaro::Services::Scaffolds::Book.new.content_files
      files.has_key?("index.md").should be_true
    end

    it "includes 3 chapter sections with their pages" do
      files = Hwaro::Services::Scaffolds::Book.new.content_files
      files.has_key?("chapter-1/_index.md").should be_true
      files.has_key?("chapter-1/getting-started.md").should be_true
      files.has_key?("chapter-1/installation.md").should be_true
      files.has_key?("chapter-2/_index.md").should be_true
      files.has_key?("chapter-2/basic-usage.md").should be_true
      files.has_key?("chapter-2/configuration.md").should be_true
      files.has_key?("chapter-3/_index.md").should be_true
      files.has_key?("chapter-3/advanced-topics.md").should be_true
    end

    it "produces non-empty content for every file" do
      files = Hwaro::Services::Scaffolds::Book.new.content_files
      files.each do |path, content|
        # Custom failure message names the offending file so a regression
        # is immediately localized.
        fail "content for #{path} was empty" if content.empty?
      end
    end
  end

  describe "#template_files" do
    it "includes the standard 5 templates" do
      files = Hwaro::Services::Scaffolds::Book.new.template_files
      files.has_key?("header.html").should be_true
      files.has_key?("footer.html").should be_true
      files.has_key?("page.html").should be_true
      files.has_key?("section.html").should be_true
      files.has_key?("404.html").should be_true
    end

    it "includes taxonomy templates by default" do
      files = Hwaro::Services::Scaffolds::Book.new.template_files
      files.has_key?("taxonomy.html").should be_true
      files.has_key?("taxonomy_term.html").should be_true
    end

    it "excludes taxonomy templates when skip_taxonomies is true" do
      files = Hwaro::Services::Scaffolds::Book.new.template_files(skip_taxonomies: true)
      files.has_key?("taxonomy.html").should be_false
      files.has_key?("taxonomy_term.html").should be_false
    end

    # Regression for gh#523: the book TOC sidebar used to bake the
    # original three chapters with hand-numbered "1.", "1.1" links
    # into the template. Adding a chapter via `hwaro new` left the
    # sidebar stale. Now the template iterates `site.sections`.
    it "renders the chapter sidebar dynamically via site.sections (gh#523)" do
      files = Hwaro::Services::Scaffolds::Book.new.template_files
      page = files["page.html"]
      page.should contain("{% for sec in site.sections")
      page.should contain("{% for p in sec.pages")
      page.should_not contain("/chapter-1/installation/")
      page.should_not contain("/chapter-2/configuration/")
      page.should_not contain("/chapter-3/advanced-topics/")
    end
  end

  describe "#static_files" do
    it "ships the book CSS and JS assets" do
      files = Hwaro::Services::Scaffolds::Book.new.static_files
      files.has_key?("css/style.css").should be_true
      files.has_key?("js/book.js").should be_true
    end

    it "ships real CSS and JS payloads (not just placeholders)" do
      files = Hwaro::Services::Scaffolds::Book.new.static_files
      # Structural fingerprints catch a wider class of regression than an
      # arbitrary byte-count threshold (e.g., truncation to a stub).
      files["css/style.css"].should contain(":root")
      files["js/book.js"].should contain("function")
    end
  end

  describe "#config_content" do
    it "returns non-empty TOML config" do
      config = Hwaro::Services::Scaffolds::Book.new.config_content
      config.should_not be_empty
    end

    it "uses the Book scaffold's title and description" do
      config = Hwaro::Services::Scaffolds::Book.new.config_content
      config.should contain(%(title = "My Book"))
      config.should contain("A book powered by Hwaro.")
    end

    it "uses the light highlight.js theme by default" do
      config = Hwaro::Services::Scaffolds::Book.new.config_content
      # `theme = "github"` is a prefix of `theme = "github-dark"`, so a
      # negative-lookahead regex disambiguates the two values. (The line
      # has a trailing comment, so a simple newline guard would miss.)
      config.should match(/theme = "github"(?!-)/)
      config.should_not contain(%(theme = "github-dark"))
    end

    it "includes taxonomies block by default" do
      config = Hwaro::Services::Scaffolds::Book.new.config_content
      config.should contain("[[taxonomies]]")
    end

    it "omits taxonomies block when skip_taxonomies is true" do
      config = Hwaro::Services::Scaffolds::Book.new.config_content(skip_taxonomies: true)
      config.should_not contain("[[taxonomies]]")
    end
  end
end

describe Hwaro::Services::Scaffolds::BookDark do
  describe "#type" do
    it "returns BookDark scaffold type" do
      Hwaro::Services::Scaffolds::BookDark.new.type
        .should eq(Hwaro::Config::Options::ScaffoldType::BookDark)
    end
  end

  describe "#description" do
    it "mentions both Book-style and dark theme" do
      desc = Hwaro::Services::Scaffolds::BookDark.new.description
      desc.should contain("Book-style")
      desc.should contain("dark")
    end
  end

  describe "inheritance from Book" do
    it "reuses Book's content_files (chapter structure)" do
      light = Hwaro::Services::Scaffolds::Book.new.content_files
      dark = Hwaro::Services::Scaffolds::BookDark.new.content_files
      # Guard against the both-empty trivial case before comparing key sets.
      dark.size.should be > 0
      dark.keys.sort!.should eq(light.keys.sort!)
    end

    it "reuses Book's template files structure" do
      light = Hwaro::Services::Scaffolds::Book.new.template_files
      dark = Hwaro::Services::Scaffolds::BookDark.new.template_files
      dark.size.should be > 0
      dark.keys.sort!.should eq(light.keys.sort!)
    end

    it "ships its own static assets via the inherited static_files" do
      files = Hwaro::Services::Scaffolds::BookDark.new.static_files
      files.has_key?("css/style.css").should be_true
      files.has_key?("js/book.js").should be_true
    end
  end

  describe "#config_content" do
    it "uses the github-dark highlight theme" do
      config = Hwaro::Services::Scaffolds::BookDark.new.config_content
      config.should contain(%(theme = "github-dark"))
      # Negative lookahead — see the matching Book test for rationale.
      config.should_not match(/theme = "github"(?!-)/)
    end

    it "still names the scaffold 'My Book'" do
      config = Hwaro::Services::Scaffolds::BookDark.new.config_content
      config.should contain(%(title = "My Book"))
    end

    it "omits taxonomies block when skip_taxonomies is true" do
      config = Hwaro::Services::Scaffolds::BookDark.new.config_content(skip_taxonomies: true)
      config.should_not contain("[[taxonomies]]")
    end
  end
end

# A minimal concrete subclass to exercise Base's default and protected helpers.
# Type returns Bare arbitrarily — this class is never registered with the
# scaffold registry; it exists only so the abstract Base methods can be
# instantiated and called.
private class TestBaseScaffold < Hwaro::Services::Scaffolds::Base
  def type : Hwaro::Config::Options::ScaffoldType
    Hwaro::Config::Options::ScaffoldType::Bare
  end

  def description : String
    "test scaffold"
  end

  def content_files(skip_taxonomies : Bool = false) : Hash(String, String)
    {} of String => String
  end

  def template_files(skip_taxonomies : Bool = false) : Hash(String, String)
    {} of String => String
  end

  def config_content(skip_taxonomies : Bool = false) : String
    minimal_config_content(skip_taxonomies)
  end
end

describe Hwaro::Services::Scaffolds::Base do
  describe "#static_files (default)" do
    it "is empty unless the subclass overrides it" do
      TestBaseScaffold.new.static_files.should be_empty
    end
  end

  describe "#shortcode_files (default)" do
    it "ships the shared alert shortcode" do
      files = TestBaseScaffold.new.shortcode_files
      files.has_key?("shortcodes/alert.html").should be_true
      # Alert shortcode references body and type via Jinja. The `{{ type`
      # substring is intentionally truncated — the source uses
      # `{{ type | upper }}`, and the partial form matches both the filtered
      # and unfiltered forms.
      files["shortcodes/alert.html"].should contain("{{ body }}")
      files["shortcodes/alert.html"].should contain("{{ type")
    end
  end

  describe "#minimal_config_content" do
    it "renders title, base_url, and processors plugin entries" do
      out = TestBaseScaffold.new.config_content
      out.should contain(%(title = "My Hwaro Site"))
      out.should contain("base_url")
      out.should contain("[plugins]")
      out.should contain(%(processors = ["markdown"]))
    end

    it "includes taxonomies block by default" do
      out = TestBaseScaffold.new.config_content(skip_taxonomies: false)
      out.should contain("[[taxonomies]]")
      out.should contain(%(name = "tags"))
    end

    it "omits taxonomies block when skip_taxonomies is true" do
      out = TestBaseScaffold.new.config_content(skip_taxonomies: true)
      out.should_not contain("[[taxonomies]]")
    end

    it "uses the light highlight theme via the default config_highlight_theme" do
      out = TestBaseScaffold.new.config_content
      # Negative lookahead disambiguates "github" from "github-dark".
      out.should match(/theme = "github"(?!-)/)
      out.should_not contain(%(theme = "github-dark"))
    end
  end
end
