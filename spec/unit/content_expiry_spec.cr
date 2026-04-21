require "../spec_helper"
require "../../src/models/config"
require "../../src/models/page"
require "../../src/content/processors/markdown"

describe "Content expiry" do
  describe "front matter parsing" do
    it "parses expires field from TOML front matter" do
      processor = Hwaro::Content::Processors::Markdown.new
      content = <<-MD
        +++
        title = "Expiring Post"
        expires = 2025-12-31
        +++

        Content here
        MD

      result = processor.parse(content)
      result[:expires].should_not be_nil
      result[:expires].not_nil!.year.should eq(2025)
      result[:expires].not_nil!.month.should eq(12)
      result[:expires].not_nil!.day.should eq(31)
    end

    it "returns nil expires when not set" do
      processor = Hwaro::Content::Processors::Markdown.new
      content = <<-MD
        +++
        title = "Normal Post"
        +++

        Content here
        MD

      result = processor.parse(content)
      result[:expires].should be_nil
    end

    it "does not put expires into extra" do
      processor = Hwaro::Content::Processors::Markdown.new
      content = <<-MD
        +++
        title = "Expiring Post"
        expires = 2025-06-15
        +++

        Content here
        MD

      result = processor.parse(content)
      result[:extra].has_key?("expires").should be_false
    end
  end

  describe "Page model" do
    it "has expires property defaulting to nil" do
      page = Hwaro::Models::Page.new("test.md")
      page.expires.should be_nil
    end

    it "can set expires" do
      page = Hwaro::Models::Page.new("test.md")
      page.expires = Time.utc(2025, 6, 15)
      page.expires.not_nil!.year.should eq(2025)
    end
  end

  describe "BuildOptions" do
    it "has include_expired defaulting to false" do
      options = Hwaro::Config::Options::BuildOptions.new
      options.include_expired.should be_false
    end
  end

  describe "ServeOptions" do
    it "has include_expired defaulting to false" do
      options = Hwaro::Config::Options::ServeOptions.new
      options.include_expired.should be_false
    end

    it "passes include_expired to BuildOptions" do
      options = Hwaro::Config::Options::ServeOptions.new(include_expired: true)
      build_options = options.to_build_options
      build_options.include_expired.should be_true
    end
  end
end
