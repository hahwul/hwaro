require "../spec_helper"
require "../../src/config/options/init_options"

describe Hwaro::Config::Options::ScaffoldType do
  describe ".from_string" do
    it "parses 'simple'" do
      Hwaro::Config::Options::ScaffoldType.from_string("simple").should eq(Hwaro::Config::Options::ScaffoldType::Simple)
    end

    it "parses 'blog'" do
      Hwaro::Config::Options::ScaffoldType.from_string("blog").should eq(Hwaro::Config::Options::ScaffoldType::Blog)
    end

    it "parses 'docs'" do
      Hwaro::Config::Options::ScaffoldType.from_string("docs").should eq(Hwaro::Config::Options::ScaffoldType::Docs)
    end

    it "parses 'blog-dark'" do
      Hwaro::Config::Options::ScaffoldType.from_string("blog-dark").should eq(Hwaro::Config::Options::ScaffoldType::BlogDark)
    end

    it "parses 'docs-dark'" do
      Hwaro::Config::Options::ScaffoldType.from_string("docs-dark").should eq(Hwaro::Config::Options::ScaffoldType::DocsDark)
    end

    it "parses 'book'" do
      Hwaro::Config::Options::ScaffoldType.from_string("book").should eq(Hwaro::Config::Options::ScaffoldType::Book)
    end

    it "parses 'book-dark'" do
      Hwaro::Config::Options::ScaffoldType.from_string("book-dark").should eq(Hwaro::Config::Options::ScaffoldType::BookDark)
    end

    it "is case insensitive" do
      Hwaro::Config::Options::ScaffoldType.from_string("BLOG").should eq(Hwaro::Config::Options::ScaffoldType::Blog)
      Hwaro::Config::Options::ScaffoldType.from_string("Docs").should eq(Hwaro::Config::Options::ScaffoldType::Docs)
    end

    it "raises on unknown type" do
      expect_raises(ArgumentError, /Unknown scaffold type/) do
        Hwaro::Config::Options::ScaffoldType.from_string("unknown")
      end
    end
  end

  describe "#to_s" do
    it "converts Simple to 'simple'" do
      Hwaro::Config::Options::ScaffoldType::Simple.to_s.should eq("simple")
    end

    it "converts Blog to 'blog'" do
      Hwaro::Config::Options::ScaffoldType::Blog.to_s.should eq("blog")
    end

    it "converts Docs to 'docs'" do
      Hwaro::Config::Options::ScaffoldType::Docs.to_s.should eq("docs")
    end

    it "converts BlogDark to 'blog-dark'" do
      Hwaro::Config::Options::ScaffoldType::BlogDark.to_s.should eq("blog-dark")
    end

    it "converts DocsDark to 'docs-dark'" do
      Hwaro::Config::Options::ScaffoldType::DocsDark.to_s.should eq("docs-dark")
    end

    it "converts Book to 'book'" do
      Hwaro::Config::Options::ScaffoldType::Book.to_s.should eq("book")
    end

    it "converts BookDark to 'book-dark'" do
      Hwaro::Config::Options::ScaffoldType::BookDark.to_s.should eq("book-dark")
    end

    it "round-trips through from_string and to_s" do
      ["simple", "blog", "docs", "blog-dark", "docs-dark", "book", "book-dark"].each do |name|
        Hwaro::Config::Options::ScaffoldType.from_string(name).to_s.should eq(name)
      end
    end
  end
end

describe Hwaro::Config::Options::AgentsMode do
  describe ".from_string" do
    it "parses 'remote'" do
      Hwaro::Config::Options::AgentsMode.from_string("remote").should eq(Hwaro::Config::Options::AgentsMode::Remote)
    end

    it "parses 'local'" do
      Hwaro::Config::Options::AgentsMode.from_string("local").should eq(Hwaro::Config::Options::AgentsMode::Local)
    end

    it "is case insensitive" do
      Hwaro::Config::Options::AgentsMode.from_string("REMOTE").should eq(Hwaro::Config::Options::AgentsMode::Remote)
      Hwaro::Config::Options::AgentsMode.from_string("Local").should eq(Hwaro::Config::Options::AgentsMode::Local)
    end

    it "raises on unknown mode" do
      expect_raises(ArgumentError, /Unknown agents mode/) do
        Hwaro::Config::Options::AgentsMode.from_string("unknown")
      end
    end
  end

  describe "#to_s" do
    it "converts Remote to 'remote'" do
      Hwaro::Config::Options::AgentsMode::Remote.to_s.should eq("remote")
    end

    it "converts Local to 'local'" do
      Hwaro::Config::Options::AgentsMode::Local.to_s.should eq("local")
    end

    it "round-trips through from_string and to_s" do
      ["remote", "local"].each do |name|
        Hwaro::Config::Options::AgentsMode.from_string(name).to_s.should eq(name)
      end
    end
  end
end

describe Hwaro::Config::Options::InitOptions do
  describe "#initialize" do
    it "has sensible defaults" do
      opts = Hwaro::Config::Options::InitOptions.new
      opts.path.should eq(".")
      opts.force.should be_false
      opts.skip_agents_md.should be_false
      opts.skip_sample_content.should be_false
      opts.skip_taxonomies.should be_false
      opts.multilingual_languages.should be_empty
      opts.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Simple)
      opts.scaffold_remote.should be_nil
      opts.agents_mode.should eq(Hwaro::Config::Options::AgentsMode::Remote)
    end
  end

  describe "#multilingual?" do
    it "returns false when no languages set" do
      opts = Hwaro::Config::Options::InitOptions.new
      opts.multilingual?.should be_false
    end

    it "returns false when only one language" do
      opts = Hwaro::Config::Options::InitOptions.new(multilingual_languages: ["en"])
      opts.multilingual?.should be_false
    end

    it "returns true when two or more languages" do
      opts = Hwaro::Config::Options::InitOptions.new(multilingual_languages: ["en", "ko"])
      opts.multilingual?.should be_true
    end
  end
end
