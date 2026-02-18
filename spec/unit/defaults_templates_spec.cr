require "../spec_helper"
require "../../src/services/defaults/templates"

describe Hwaro::Services::Defaults::TemplateSamples do
  describe ".header" do
    it "returns a string containing expected tags" do
      header = Hwaro::Services::Defaults::TemplateSamples.header
      header.should contain("{{ site.description }}")
      header.should contain("{{ page.title }}")
      header.should contain("{{ site.title }}")
      header.should contain("{{ page.section }}")
      header.should contain("{{ base_url }}")
    end
  end

  describe ".footer" do
    it "returns a string containing Powered by Hwaro" do
      footer = Hwaro::Services::Defaults::TemplateSamples.footer
      footer.should contain("Powered by Hwaro")
    end
  end

  describe ".page" do
    it "returns a string containing expected tags" do
      page = Hwaro::Services::Defaults::TemplateSamples.page
      page.should contain("{% include \"header.html\" %}")
      page.should contain("{{ content }}")
      page.should contain("{% include \"footer.html\" %}")
    end
  end

  describe ".section" do
    it "returns a string containing expected tags" do
      section = Hwaro::Services::Defaults::TemplateSamples.section
      section.should contain("{{ page.title }}")
      section.should contain("{{ section.list }}")
      section.should contain("{{ pagination }}")
    end
  end

  describe ".not_found" do
    it "returns a string containing expected content" do
      not_found = Hwaro::Services::Defaults::TemplateSamples.not_found
      not_found.should contain("404 Not Found")
      not_found.should contain("{{ base_url }}")
    end
  end

  describe ".alert" do
    it "returns a string containing expected tags" do
      alert = Hwaro::Services::Defaults::TemplateSamples.alert
      alert.should contain("{{ type | upper }}")
      alert.should contain("{{ message }}")
    end
  end

  describe ".taxonomy" do
    it "returns a string containing expected tags" do
      taxonomy = Hwaro::Services::Defaults::TemplateSamples.taxonomy
      taxonomy.should contain("Browse all terms in this taxonomy")
      taxonomy.should contain("{{ page.title }}")
    end
  end

  describe ".taxonomy_term" do
    it "returns a string containing expected tags" do
      taxonomy_term = Hwaro::Services::Defaults::TemplateSamples.taxonomy_term
      taxonomy_term.should contain("Posts tagged with this term")
      taxonomy_term.should contain("{{ page.title }}")
    end
  end
end
