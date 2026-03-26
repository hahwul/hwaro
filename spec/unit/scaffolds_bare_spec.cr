require "../spec_helper"
require "../../src/services/scaffolds/bare"

describe Hwaro::Services::Scaffolds::Bare do
  describe "#type" do
    it "returns Bare scaffold type" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::Bare)
    end
  end

  describe "#description" do
    it "returns a non-empty description" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      scaffold.description.should_not be_empty
      scaffold.description.should contain("Minimal")
    end
  end

  describe "#content_files" do
    it "generates index.md and about.md" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      files = scaffold.content_files

      files.has_key?("index.md").should be_true
      files.has_key?("about.md").should be_true
    end

    it "generates index.md with title" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      files = scaffold.content_files

      files["index.md"].should contain("title")
      files["index.md"].should contain("Welcome to Hwaro")
    end

    it "generates about.md with title" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      files = scaffold.content_files

      files["about.md"].should contain("title")
      files["about.md"].should contain("About")
    end

    it "returns same files regardless of skip_taxonomies" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      with_tax = scaffold.content_files(skip_taxonomies: false)
      without_tax = scaffold.content_files(skip_taxonomies: true)

      with_tax.keys.sort.should eq(without_tax.keys.sort)
    end
  end

  describe "#template_files" do
    it "generates core template files" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      files = scaffold.template_files

      files.has_key?("header.html").should be_true
      files.has_key?("footer.html").should be_true
      files.has_key?("page.html").should be_true
      files.has_key?("section.html").should be_true
      files.has_key?("404.html").should be_true
    end

    it "includes taxonomy templates by default" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      files = scaffold.template_files

      files.has_key?("taxonomy.html").should be_true
      files.has_key?("taxonomy_term.html").should be_true
    end

    it "excludes taxonomy templates when skip_taxonomies is true" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      files = scaffold.template_files(skip_taxonomies: true)

      files.has_key?("taxonomy.html").should be_false
      files.has_key?("taxonomy_term.html").should be_false
    end

    it "generates semantic HTML templates without styles" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      files = scaffold.template_files

      # Header should have semantic HTML
      files["header.html"].should contain("<!DOCTYPE html>")
      files["header.html"].should contain("<header>")
      files["header.html"].should contain("<nav>")

      # Footer should have semantic HTML
      files["footer.html"].should contain("<footer>")
      files["footer.html"].should contain("</html>")
    end

    it "generates 404 template" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      files = scaffold.template_files

      files["404.html"].should contain("404")
      files["404.html"].should contain("Not Found")
    end
  end

  describe "#static_files" do
    it "returns empty hash" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      scaffold.static_files.should be_empty
    end
  end

  describe "#shortcode_files" do
    it "returns empty hash" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      scaffold.shortcode_files.should be_empty
    end
  end

  describe "#config_content" do
    it "generates valid config" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      config = scaffold.config_content

      config.should_not be_empty
      config.should contain("title")
    end

    it "includes taxonomies config by default" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      config = scaffold.config_content(skip_taxonomies: false)

      config.should contain("taxonomies")
    end

    it "excludes taxonomies config when skip_taxonomies is true" do
      scaffold = Hwaro::Services::Scaffolds::Bare.new
      config_with = scaffold.config_content(skip_taxonomies: false)
      config_without = scaffold.config_content(skip_taxonomies: true)

      # Without taxonomies should be shorter
      config_without.size.should be < config_with.size
    end
  end
end
